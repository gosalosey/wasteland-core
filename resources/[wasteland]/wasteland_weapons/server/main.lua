-- wasteland_weapons :: server/main.lua
-- Module "weapons": weapon items are held by using them (hotbar or Use)
-- and put away by using them again. The server decides what a player holds,
-- takes ammo from the inventory for every shot the client reports, wears
-- the weapon, and repairs it with repair kits. GTA's own weapons are not
-- used: the client only ever has the weapon the server handed it.

local M
local held = {}  -- source -> { uid, item }
local extra = {} -- item -> { def, owner }: weapons other resources added with RegisterWeapon

local function inv() return exports.wasteland_inventory end
local function inventoryRunning() return GetResourceState('wasteland_inventory') == 'started' end

local function notice(src, message)
    TriggerClientEvent('wasteland:weapons:client:notice', src, message)
end

local function label(item)
    local d = inv():GetItemDefinition(item)
    return d and d.label or item
end

local function ammoCount(src, w)
    if not w.ammo then return 0 end
    return inv():GetItemCount(src, w.ammo) or 0
end

--- What the client needs to hold the weapon.
local function state(src, h, stack)
    local w = M.config.weapons[h.item]
    local d = inv():GetItemDefinition(h.item)
    local durability = stack.metadata.durability or (d and d.durability) or 0
    -- fitted attachments -> GTA components
    local components = {}
    local fitted = stack.metadata.attachments or {}
    local scripted = {}   -- slots with no game part (custom guns): the client does the effect
    for slot in pairs(fitted) do
        local comp = d and d.attachments and d.attachments[slot]
        if comp == 'SCRIPTED' then scripted[slot] = true
        elseif comp then components[#components + 1] = comp end
    end
    table.sort(components)
    return {
        components = components, scripted = scripted,
        uid = h.uid, item = h.item, label = d and d.label or h.item, hash = w.hash,
        melee = w.ammo == nil, ammo = ammoCount(src, w),
        durability = durability, maxDurability = d and d.durability or 0,
        broken = d and d.durability > 0 and durability <= 0 or false,
    }
end

local function holster(src, quiet)
    if not held[src] then return end
    held[src] = nil
    TriggerClientEvent('wasteland:weapons:client:holster', src)
    if not quiet then TriggerEvent('wasteland:weapons:holstered', src) end
end

-- Throwables (molotovs, grenades, sticky bombs) are their own ammo: when
-- the stack in hand is used up, keep holding the next stack of them.
local function nextStack(src, h)
    local w = M.config.weapons[h.item]
    if not w or w.ammo ~= h.item then return nil end
    local list = inv():FindItems(src, h.item) or {}
    if not list[1] then return nil end
    h.uid = list[1].uid
    return inv():FindItem(src, h.uid)
end

local function sendState(src)
    local h = held[src]
    if not h then return end
    local stack = inv():FindItem(src, h.uid) or nextStack(src, h)
    if not stack then
        holster(src)
        return
    end
    h.lastAmmo = ammoCount(src, M.config.weapons[h.item])
    TriggerClientEvent('wasteland:weapons:client:state', src, state(src, h, stack))
end

-------------------------------------------------------------------------------
-- Using items
-------------------------------------------------------------------------------

-- Only weapons the player carries (not ones in a drop or stash they have
-- open) can be held.
local function useWeapon(src, stack)
    if not M.config.weapons[stack.name] then return false, 'This weapon cannot be used right now.' end
    local found = inv():FindItem(src, stack.uid)
    if not found then return false, 'Put it in your inventory first.' end
    if held[src] and held[src].uid == stack.uid then
        holster(src)
        return 0
    end
    held[src] = { uid = stack.uid, item = stack.name }
    local s = state(src, held[src], found)
    held[src].lastAmmo = s.ammo
    TriggerClientEvent('wasteland:weapons:client:hold', src, s)
    TriggerEvent('wasteland:weapons:held', src, stack.name)
    if s.broken then return 0, string.format('Your %s is broken. Repair it with a repair kit.', s.label) end
    if not s.melee and s.ammo == 0 then return 0, string.format('You have no %s.', label(M.config.weapons[stack.name].ammo)) end
    return 0
end

local function useRepair(src, stack)
    local h = held[src]
    if not h then return false, 'Hold the weapon you want to repair.' end
    local found = inv():FindItem(src, h.uid)
    if not found then holster(src); return false, 'Hold the weapon you want to repair.' end
    local d = inv():GetItemDefinition(h.item)
    local max = d and d.durability or 0
    local current = found.metadata.durability or max
    if max <= 0 or current >= max then return false, string.format('Your %s is not damaged.', d and d.label or h.item) end
    local amount = math.ceil(max * M.config.repairItems[stack.name].percent / 100)
    local ok, err = inv():SetItemMetadata(src, h.uid, { durability = math.min(max, current + amount) })
    if not ok then return false, err end
    M.log:info('player %d repaired %s (%d -> %d)', src, h.item, current, math.min(max, current + amount))
    sendState(src)
    return 1, string.format('Repaired your %s.', d.label)
end

-- An attachment on a gun: the one picked in the inventory (targetUid), or
-- the gun in your hands. -> consumed, message
local function useAttachment(src, stack, _, targetUid)
    local ad = inv():GetItemDefinition(stack.name)
    local slot = ad and ad.attachment
    if not slot then return false, 'That is not an attachment.' end
    local uid = targetUid or (held[src] and held[src].uid)
    if not uid then return false, 'Right-click a gun and choose Attach, or hold the gun first.' end
    local gun = inv():FindItem(src, uid)
    if not gun then return false, 'Keep the gun in your inventory.' end
    local gd = inv():GetItemDefinition(gun.name)
    if not gd or not gd.attachments or not gd.attachments[slot] then
        return false, string.format('A %s does not fit the %s.', ad.label:lower(), gd and gd.label or gun.name)
    end
    local fitted = {}
    for k, v in pairs(gun.metadata.attachments or {}) do fitted[k] = v end
    if fitted[slot] then return false, string.format('Your %s already has a %s.', gd.label, ad.label:lower()) end
    fitted[slot] = stack.name
    local ok, err = inv():SetItemMetadata(src, uid, { attachments = fitted })
    if not ok then return false, err end
    if held[src] and held[src].uid == uid then sendState(src) end
    return 1, string.format('%s fitted to your %s.', ad.label, gd.label)
end

-- Take every attachment off a gun: back into the inventory (what does not fit stays on).
local function detach(src, uid)
    local gun = inv():FindItem(src, uid)
    if not gun then return end
    local gd = inv():GetItemDefinition(gun.name)
    local fitted = gun.metadata.attachments or {}
    local left, taken = {}, 0
    for slot, item in pairs(fitted) do
        if type(item) == 'string' and inv():AddItem(src, item, 1) then taken = taken + 1 else left[slot] = item end
    end
    inv():SetItemMetadata(src, uid, { attachments = left })
    if held[src] and held[src].uid == uid then sendState(src) end
    if taken > 0 then notice(src, string.format('Took %d attachment%s off your %s.', taken, taken == 1 and '' or 's', gd and gd.label or 'gun')) end
    if next(left) then notice(src, 'No room for the rest: they stay on the gun.') end
end

-- Weapons from RegisterWeapon join the config's (the config wins on a clash).
local function applyExtra()
    for item, e in pairs(extra) do
        if not M.config.weapons[item] then M.config.weapons[item] = e.def; e.applied = true end
    end
end

local function registerUsables()
    if not inventoryRunning() then return end
    for item in pairs(M.config.weapons) do
        local ok, err = inv():RegisterUsable(item, useWeapon)
        if not ok then M.log:warn('weapon "%s": %s (add it to inventory.lua items)', item, tostring(err)) end
    end
    for _, item in ipairs(M.config.attachmentItems or {}) do
        local ok, err = inv():RegisterUsable(item, useAttachment)
        if not ok then M.log:warn('attachment "%s": %s (add it to inventory.lua items)', item, tostring(err)) end
    end
    for item in pairs(M.config.repairItems) do
        local ok, err = inv():RegisterUsable(item, useRepair)
        if not ok then M.log:warn('repair item "%s": %s (add it to inventory.lua items)', item, tostring(err)) end
    end
end

AddEventHandler('wasteland:core:moduleState', function(name, st)
    if name == 'inventory' and st == 'running' and M and M.active then registerUsables() end
end)

-------------------------------------------------------------------------------
-- Shots and hits reported by the client
-------------------------------------------------------------------------------

local function used(src, count, coords)
    local h = held[src]
    if not h then return end
    local w = M.config.weapons[h.item]
    local stack = inv():FindItem(src, h.uid) or nextStack(src, h)
    if not stack then holster(src); return end
    local d = inv():GetItemDefinition(h.item)
    local max = d and d.durability or 0
    local durability = stack.metadata.durability or max
    if max > 0 and durability <= 0 then
        M.log:warn('player %d reported %d uses of a broken %s', src, count, h.item)
        sendState(src)
        return
    end
    local n = count
    if w.ammo then
        local have = ammoCount(src, w)
        n = math.min(count, have)
        if count > have + 2 then
            M.log:warn('player %d reported %d shots with %s but had %d %s', src, count, h.item, have, w.ammo)
        end
        if n > 0 then
            local ok, err = inv():RemoveItem(src, w.ammo, n)
            if not ok then M.log:warn('ammo for player %d: %s', src, tostring(err)); n = 0 end
        end
    end
    if n > 0 and max > 0 then
        -- a skilled fighter wears weapons slower (wasteland_skills)
        local care = 0
        if GetResourceState('wasteland_skills') == 'started' then
            local ok, b = pcall(function() return exports.wasteland_skills:GetBonus(src, 'combat', 'weaponWear') end)
            care = ok and tonumber(b) or 0
        end
        local after = math.max(0, durability - n * w.wear * (1 - care))
        inv():SetItemMetadata(src, h.uid, { durability = after })
        if after == 0 then notice(src, string.format('Your %s broke. Repair it with a repair kit.', d.label)) end
    end
    if n > 0 then
        -- Zombies (and anything else) listen for noise here; a suppressor
        -- halves how far a shot carries.
        local noiseRange = w.noise
        if w.ammo and stack.metadata.attachments and stack.metadata.attachments.suppressor then
            noiseRange = noiseRange * (M.config.suppressorNoise or 0.5)
        end
        TriggerEvent('wasteland:weapons:used', src, h.item, n, noiseRange, coords)
    end
    sendState(src)
end

-------------------------------------------------------------------------------
-- Keeping the held weapon honest
-------------------------------------------------------------------------------

-- Any change to the player's inventory: is the weapon still carried, and
-- how much ammo is left?
AddEventHandler('wasteland:inventory:playerUpdated', function(src)
    local h = held[src]
    if not h or not (M and M.active) then return end
    local stack = inv():FindItem(src, h.uid) or nextStack(src, h)
    if not stack then
        holster(src)
        return
    end
    local ammo = ammoCount(src, M.config.weapons[h.item])
    if ammo ~= h.lastAmmo then sendState(src) end
end)

AddEventHandler('wasteland:survival:died', function(src) holster(src, true) end)
AddEventHandler('wasteland:players:characterUnloading', function(src) held[src] = nil end)
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then held[src] = nil end
end)

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local WEAPON_SCHEMA = { type = 'table', fields = {
    hash = { type = 'string', required = true, pattern = '^WEAPON_[%w_]+$' },
    ammo = { type = 'string', pattern = '^[%w_]+$' },
    wear = { type = 'integer', default = 1, min = 0, max = 1000 },
    noise = { type = 'number', default = 0, min = 0, max = 2000 },
} }

M = Wasteland.DefineModule({
    name = 'weapons',
    version = '0.1.0',
    description = 'Weapon items: hold, ammo from the inventory, durability, repairs',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', inventory = '^0.1.0' },
    config = {
        file = 'weapons.lua',
        optional = true,
        schema = { type = 'table', fields = {
            weapons = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%w_]+$' },
                values = WEAPON_SCHEMA },
            attachmentItems = { type = 'array', default = {}, items = { type = 'string', pattern = '^[%w_]+$' } },
            suppressorNoise = { type = 'number', default = 0.5, min = 0, max = 1, description = 'Noise of a suppressed shot (share of the gun\'s)' },
            repairItems = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%w_]+$' },
                values = { type = 'table', fields = { percent = { type = 'number', required = true, min = 1, max = 100 } } } },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        held = {}
        for _, e in pairs(extra) do e.applied = nil end
        applyExtra()
        if inventoryRunning() then
            for item, w in pairs(M.config.weapons) do
                if w.ammo and not inv():GetItemDefinition(w.ammo) then
                    return false, string.format('weapons.lua: %s uses ammo "%s", which is not in inventory.lua items', item, w.ammo)
                end
            end
        end
        registerUsables()
        return true
    end,
    onShutdown = function()
        for src in pairs(held) do TriggerClientEvent('wasteland:weapons:client:holster', src) end
        held = {}
    end,
})

M.netEvent('wasteland:weapons:server:used', {
    args = {
        { type = 'integer', required = true, min = 1, max = 200 },
        { type = 'table', fields = { x = { type = 'number' }, y = { type = 'number' }, z = { type = 'number' } } },
    },
    rateLimit = { burst = 6, perSecond = 3 },
}, function(src, count, coords)
    used(src, count, coords)
end)

M.netEvent('wasteland:weapons:server:holster', { rateLimit = { burst = 5, perSecond = 2 } }, function(src)
    holster(src)
end)

-------------------------------------------------------------------------------
-- Exports (weapons api 0.1)
-------------------------------------------------------------------------------

--- GetHeldWeapon(source) -> { uid, item } | nil
exports('GetHeldWeapon', function(src)
    local h = held[tonumber(src)]
    return h and { uid = h.uid, item = h.item } or nil
end)

--- GetWeaponConfig(item) -> { hash, ammo, wear, noise } | nil
exports('GetWeaponConfig', function(item)
    local w = M and M.config.weapons[item]
    return w and { hash = w.hash, ammo = w.ammo, wear = w.wear, noise = w.noise } or nil
end)

M.netEvent('wasteland:weapons:server:detach', { args = { { type = 'string', required = true, pattern = '^[%w_%-]+$', maxLength = 64 } },
    rateLimit = { burst = 3, perSecond = 1 } }, function(src, uid) detach(src, uid) end)

--- RegisterWeapon(item, { hash, ammo?, wear?, noise? }) -> ok, err
--- For resources that bring their own weapons (an addon weapon streamed by
--- that resource). The item must already exist (inventory RegisterItem).
--- Kept until the registering resource stops; a weapon of the same name in
--- weapons.lua wins.
exports('RegisterWeapon', function(item, def)
    if type(item) ~= 'string' or not item:match('^[%w_]+$') then return false, 'item name must be letters, digits and _' end
    local w, errs = Wasteland.Schema().validate(WEAPON_SCHEMA, def)
    if #errs > 0 then
        local m = {}
        for _, e in ipairs(errs) do m[#m + 1] = (e.path ~= '' and e.path .. ': ' or '') .. e.message end
        return false, string.format('weapon "%s": %s', item, table.concat(m, '; '))
    end
    local owner = GetInvokingResource() or GetCurrentResourceName()
    if extra[item] and extra[item].owner ~= owner then return false, string.format('weapon "%s" was already registered by %s', item, extra[item].owner) end
    if M and M.active and inventoryRunning() then
        if not inv():GetItemDefinition(item) then return false, string.format('unknown item "%s" (register the item first)', item) end
        if w.ammo and not inv():GetItemDefinition(w.ammo) then return false, string.format('weapon "%s" uses unknown ammo "%s"', item, w.ammo) end
    end
    local was = extra[item]
    extra[item] = { def = w, owner = owner }
    if M and M.active then
        -- a weapons.lua entry of the same name stays; ours replaces only our own
        if not M.config.weapons[item] or (was and was.applied) then
            M.config.weapons[item] = w; extra[item].applied = true
        end
        if inventoryRunning() then
            local ok, err = inv():RegisterUsable(item, useWeapon)
            if not ok then return false, err end
        end
    end
    return true
end)

AddEventHandler('onResourceStop', function(res)
    for item, e in pairs(extra) do
        if e.owner == res then
            if M and e.applied then
                M.config.weapons[item] = nil
                for src, h in pairs(held) do if h.item == item then holster(src) end end
            end
            extra[item] = nil
        end
    end
end)
