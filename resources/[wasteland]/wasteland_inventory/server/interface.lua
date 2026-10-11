-- wasteland_inventory :: server/interface.lua
-- Guarded net events (the inventory screen), exports for other modules and
-- the admin /give command.

local Inv = WLI.Inv
local Drops = WLI.Drops
local Sync = WLI.Sync
local Interface = {}
WLI.Interface = Interface

local UID = { type = 'string', required = true, pattern = '^%x+$', minLength = 16, maxLength = 16 }
local INV_ID = { type = 'string', required = true, pattern = '^%a+:[%w_%-:%.]+$', maxLength = 64 }
local CELL = { type = 'integer', required = true, min = 0, max = 31 }
local SLOT = { type = 'enum', required = true, values = WLI.EQUIP_SLOTS }
local COUNT = { type = 'integer', min = 1, max = 100000 }
local BOOL = { type = 'boolean', default = false }
local OPS_RATE = { burst = 20, perSecond = 8 }

-- Answer an operation: on failure tell the player why and resend the
-- truth (the screen may have moved the item optimistically).
local function answer(src, ok, err)
    if not ok then
        Sync.error(src, err or 'that did not work')
        Sync.player(src)
    end
end

--- Send the item definitions (with usability) to one player or everyone.
function Interface.sendDefinitions(target)
    local defs = {}
    for name, d in pairs(WLI.defs) do
        defs[name] = {
            name = name, label = d.label, description = d.description, category = d.category,
            width = d.width, height = d.height, weight = d.weight, stack = d.stack,
            durability = d.durability, equip = d.equip, container = d.container, color = d.color, warmth = d.warmth,
            usable = WLI.usable[name] ~= nil,
        }
    end
    TriggerClientEvent('wasteland:inventory:client:definitions', target or -1, {
        items = defs, slots = WLI.EQUIP_SLOTS, slotLabels = WLI.EQUIP_SLOT_LABELS,
        clothingParts = WLI.CLOTHING_PARTS, naked = WLI.cfg.naked, plain = WLI.cfg.plain,
    })
end

function Interface.registerNetEvents(M)
    M.netEvent('wasteland:inventory:server:request', { rateLimit = { burst = 5, perSecond = 1 } }, function(src)
        Interface.sendDefinitions(src)
        Drops.broadcast(src)
        Sync.player(src)
    end)
    M.netEvent('wasteland:inventory:server:move', { args = { UID, INV_ID, INV_ID, CELL, CELL, BOOL }, rateLimit = OPS_RATE },
        function(src, uid, fromId, toId, x, y, rotated) answer(src, Inv.move(src, uid, fromId, toId, x, y, rotated)) end)
    M.netEvent('wasteland:inventory:server:merge', { args = { UID, INV_ID, UID, INV_ID, COUNT }, rateLimit = OPS_RATE },
        function(src, uid, fromId, targetUid, toId, count) answer(src, Inv.merge(src, uid, fromId, targetUid, toId, count)) end)
    M.netEvent('wasteland:inventory:server:split', { args = { UID, INV_ID, { type = 'integer', required = true, min = 1, max = 100000 } }, rateLimit = OPS_RATE },
        function(src, uid, invId, count) answer(src, Inv.split(src, uid, invId, count)) end)
    M.netEvent('wasteland:inventory:server:equip', { args = { UID, INV_ID, SLOT }, rateLimit = OPS_RATE },
        function(src, uid, fromId, slot) answer(src, Inv.equip(src, uid, fromId, slot)) end)
    M.netEvent('wasteland:inventory:server:unequip', {
        args = { SLOT, INV_ID, { type = 'integer', min = 0, max = 31 }, { type = 'integer', min = 0, max = 31 }, BOOL },
        rateLimit = OPS_RATE,
    }, function(src, slot, toId, x, y, rotated) answer(src, Inv.unequip(src, slot, toId, x, y, rotated)) end)
    M.netEvent('wasteland:inventory:server:drop', { args = { UID, INV_ID, COUNT }, rateLimit = OPS_RATE },
        function(src, uid, fromId, count) answer(src, Inv.drop(src, uid, fromId, count)) end)
    M.netEvent('wasteland:inventory:server:use', { args = { UID, INV_ID }, rateLimit = { burst = 5, perSecond = 2 } },
        function(src, uid, invId)
            local ok, msg = Inv.use(src, uid, invId)
            answer(src, ok, msg)
            if ok and msg then TriggerClientEvent('wasteland:inventory:client:notice', src, msg) end
        end)
    M.netEvent('wasteland:inventory:server:setHotbar', {
        args = { { type = 'integer', required = true, min = 1, max = 5 }, { type = 'string', pattern = '^%x+$', maxLength = 16 } },
        rateLimit = OPS_RATE,
    }, function(src, index, uid) answer(src, Inv.setHotbar(src, index, uid)) end)
    M.netEvent('wasteland:inventory:server:useHotbar', { args = { { type = 'integer', required = true, min = 1, max = 5 } }, rateLimit = { burst = 5, perSecond = 2 } },
        function(src, index)
            local ok, msg = Inv.useHotbar(src, index)
            if not ok then Sync.error(src, msg) elseif msg then TriggerClientEvent('wasteland:inventory:client:notice', src, msg) end
        end)
    M.netEvent('wasteland:inventory:server:openDrop', { args = { { type = 'string', required = true, pattern = '^%x+$', maxLength = 16 } }, rateLimit = { burst = 5, perSecond = 2 } },
        function(src, id) answer(src, Drops.open(src, id)) end)
    M.netEvent('wasteland:inventory:server:close', { args = { INV_ID }, rateLimit = OPS_RATE },
        function(src, id) Drops.close(src, id) end)
end

-------------------------------------------------------------------------------
-- Admin: /give <player> <item> [count]
-------------------------------------------------------------------------------

function Interface.registerCommand(cfg)
    RegisterCommand(cfg.giveCommand, function(source, args)
        local src = tonumber(source) or 0
        local reply = function(msg)
            if src == 0 then print(msg) else TriggerClientEvent('wasteland:core:client:consoleOutput', src, { msg }) end
        end
        if src ~= 0 and not IsPlayerAceAllowed(tostring(src), cfg.adminAce) then
            WLI.M.log:warn('player %d tried "%s" without the %s ACE', src, cfg.giveCommand, cfg.adminAce)
            return
        end
        local target, name, count = tonumber(args[1]), args[2], math.tointeger(tonumber(args[3] or '1'))
        if not target or not name or not count then
            reply(string.format('usage: %s <server id> <item> [count]', cfg.giveCommand))
            return
        end
        local ok, err = Inv.addItem(target, name, count)
        if ok then
            WLI.M.log:info('%s gave %d x %s to player %d', src == 0 and 'console' or ('player ' .. src), count, name, target)
            reply(string.format('Gave %d x %s to player %d.', count, name, target))
        else
            reply('Could not give: ' .. tostring(err))
        end
    end, false)
end

-------------------------------------------------------------------------------
-- Exports (inventory api 0.1)
-------------------------------------------------------------------------------

local function inactive() return not (WLI.M and WLI.M.active) end

--- AddItem(target, name, count, metadata?) -> ok, err   (target: server id or inventory id)
exports('AddItem', function(target, name, count, metadata)
    if inactive() then return false, 'inventory module is not running' end
    return Inv.addItem(target, name, math.tointeger(tonumber(count)) or count, metadata)
end)

--- RemoveItem(target, name, count) -> ok, err   (all or nothing)
exports('RemoveItem', function(target, name, count)
    if inactive() then return false, 'inventory module is not running' end
    return Inv.removeItem(target, name, math.tointeger(tonumber(count)) or count)
end)

--- GetItemCount(target, name) -> number
exports('GetItemCount', function(target, name)
    if inactive() then return 0 end
    return Inv.countItem(target, name)
end)

--- GetItemList() -> list of { name, label, category } sorted by label
exports('GetItemList', function()
    local out = {}
    for name, d in pairs(WLI.defs) do out[#out + 1] = { name = name, label = d.label, category = d.category } end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

--- GetItemDefinition(name) -> definition copy | nil
exports('GetItemDefinition', function(name)
    local d = WLI.defs[name]
    return d and Inv.copy(d) or nil
end)

--- RegisterItem(name, definition) -> ok, err   (modules adding their items)
exports('RegisterItem', function(name, def)
    local d, err = WLI.validateItem(Wasteland.Schema(), name, def)
    if not d then return false, err end
    if WLI.defs[name] then return false, string.format('item "%s" is already defined', name) end
    WLI.defs[name] = d
    Interface.sendDefinitions()
    return true
end)

--- RegisterUsable(name, handler(source, stack, inventoryId) -> consumed | false, message)
exports('RegisterUsable', function(name, handler)
    if not WLI.defs[name] then return false, string.format('unknown item "%s"', tostring(name)) end
    WLI.usable[name] = handler
    Interface.sendDefinitions()
    return true
end)

--- OpenStash(source, name, opts) -> true (started) | false, err
--- opts: label, width, height, maxWeight, coords (players must be within
--- reachDistance when coords are given). Loads in the background; errors
--- are shown to the player.
exports('OpenStash', function(src, name, opts)
    if inactive() then return false, 'inventory module is not running' end
    src = tonumber(src)
    if not src then return false, 'source must be a player server id' end
    Citizen.CreateThread(function()
        local ok, err = Drops.openStash(src, name, opts)
        if not ok then Sync.error(src, err) end
    end)
    return true
end)

--- GetInventory(id) -> snapshot | nil
exports('GetInventory', function(id)
    local inv = WLI.invs[id]
    return inv and Sync.snapshot(inv) or nil
end)

--- DeathDrop(source, label) -> { dropIds } | nil, err
--- Everything except hotbar items goes into body bag(s) at the player's
--- position, marked with the character as owner (map marker).
exports('DeathDrop', function(src, label)
    if inactive() then return nil, 'inventory module is not running' end
    return Inv.deathDrop(tonumber(src), type(label) == 'string' and label:sub(1, 64) or 'Body')
end)

--- OpenForAdmin(adminSource, targetSource) -> ok, err
--- Lets an admin see and move the target's pockets and worn bag in their
--- own inventory screen (the admin module checks permissions first).
exports('OpenForAdmin', function(adminSrc, targetSrc)
    adminSrc, targetSrc = tonumber(adminSrc), tonumber(targetSrc)
    local c = Inv.characterOf(targetSrc)
    if not c or not c.loaded then return false, 'that player has no loaded inventory' end
    WLI.views[adminSrc] = WLI.views[adminSrc] or {}
    WLI.views[adminSrc][c.pockets] = true
    local bag = Inv.backpack(c)
    if bag and WLI.invs['item:' .. bag.uid] then WLI.views[adminSrc]['item:' .. bag.uid] = true end
    Sync.player(adminSrc)
    TriggerClientEvent('wasteland:inventory:client:open', adminSrc)
    return true
end)

--- ClearInventory(source) -> ok, err   (pockets, worn items and the worn bag's contents)
exports('ClearInventory', function(src)
    if inactive() then return false, 'inventory module is not running' end
    return Inv.clear(tonumber(src))
end)

--- GetWornItems(source) -> list of { name, slot, metadata, warmth }
exports('GetWornItems', function(src)
    local c = Inv.characterOf(tonumber(src))
    if not c or not c.loaded or not WLI.invs[c.equip] then return {} end
    local out = {}
    for _, s in pairs(WLI.invs[c.equip].items) do
        local d = WLI.defs[s.name]
        out[#out + 1] = { name = s.name, slot = s.slot, metadata = Inv.copy(s.metadata), warmth = d and d.warmth or 0 }
    end
    return out
end)

--- IsLoaded(source) -> boolean
exports('IsLoaded', function(src)
    local c = Inv.characterOf(tonumber(src))
    return c ~= nil and c.loaded == true
end)

return Interface
