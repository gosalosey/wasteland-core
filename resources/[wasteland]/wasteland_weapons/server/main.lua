-- wasteland_weapons :: server/main.lua
-- Module "weapons": weapon items are held by using them (hotbar or Use)
-- and put away by using them again. The server decides what a player holds,
-- takes ammo from the inventory for every shot the client reports, wears
-- the weapon, and repairs it with repair kits. GTA's own weapons are not
-- used: the client only ever has the weapon the server handed it.

local M
local held = {}  -- source -> { uid, item }

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
    return {
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

local function sendState(src)
    local h = held[src]
    if not h then return end
    local stack = inv():FindItem(src, h.uid)
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

local function registerUsables()
    if not inventoryRunning() then return end
    for item in pairs(M.config.weapons) do
        local ok, err = inv():RegisterUsable(item, useWeapon)
        if not ok then M.log:warn('weapon "%s": %s (add it to inventory.lua items)', item, tostring(err)) end
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
    local stack = inv():FindItem(src, h.uid)
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
        -- Zombies (and anything else) listen for noise here.
        TriggerEvent('wasteland:weapons:used', src, h.item, n, w.noise, coords)
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
    local stack = inv():FindItem(src, h.uid)
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
                values = { type = 'table', fields = {
                    hash = { type = 'string', required = true, pattern = '^WEAPON_[%w_]+$' },
                    ammo = { type = 'string', pattern = '^[%w_]+$' },
                    wear = { type = 'integer', default = 1, min = 0, max = 1000 },
                    noise = { type = 'number', default = 0, min = 0, max = 2000 },
                } } },
            repairItems = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%w_]+$' },
                values = { type = 'table', fields = { percent = { type = 'number', required = true, min = 1, max = 100 } } } },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        held = {}
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
