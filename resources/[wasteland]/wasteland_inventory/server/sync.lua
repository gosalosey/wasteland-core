-- wasteland_inventory :: server/sync.lua
-- Sends players full snapshots of the inventories they can see. Snapshots
-- are small (a few dozen stacks), so every change resends them instead of
-- diffs; the client never has to reconcile.

local Inv = WLI.Inv
local Sync = {}
WLI.Sync = Sync

function Sync.snapshot(inv)
    local items = {}
    for _, s in pairs(inv.items) do
        items[#items + 1] = {
            uid = s.uid, name = s.name, count = s.count, x = s.x, y = s.y,
            rotated = s.rotated == true, slot = s.slot, metadata = Inv.copy(s.metadata or {}),
        }
    end
    table.sort(items, function(a, b) return a.uid < b.uid end)
    return {
        id = inv.id, label = inv.label, kind = inv.kind,
        width = inv.width, height = inv.height, maxWeight = inv.maxWeight,
        weight = math.floor(Inv.weight(inv) * 100 + 0.5) / 100,
        items = items,
    }
end

--- Send a player everything they can see.
function Sync.player(src)
    local c = Inv.characterOf(src)
    if not c or not c.loaded then return end
    local bag = Inv.backpack(c)
    local payload = {
        pockets = c.pockets, equip = c.equip,
        backpack = bag and ('item:' .. bag.uid) or nil,
        secondary = {}, hotbar = c.hotbar, inventories = {},
    }
    local function add(id)
        local inv = WLI.invs[id]
        if inv then payload.inventories[#payload.inventories + 1] = Sync.snapshot(inv) end
    end
    add(c.pockets)
    add(c.equip)
    if payload.backpack then add(payload.backpack) end
    for id in pairs(WLI.views[src] or {}) do
        if WLI.invs[id] then
            payload.secondary[#payload.secondary + 1] = id
            add(id)
        end
    end
    table.sort(payload.secondary)
    TriggerClientEvent('wasteland:inventory:client:sync', src, payload)
    -- Server modules (weapons: is the held weapon still carried?) react here.
    TriggerEvent('wasteland:inventory:playerUpdated', src)
end

--- Who can see inventory `id`: its owner and players viewing it.
local function watchers(id, out)
    local kind, rest = id:match('^(%a+):(.+)$')
    if kind == 'player' or kind == 'equip' then
        local c = WLI.chars[tonumber(rest)]
        if c and c.source then out[c.source] = true end
    elseif kind == 'item' then
        for _, c in pairs(WLI.chars) do
            local bag = c.loaded and Inv.backpack(c)
            if bag and bag.uid == rest and c.source then out[c.source] = true end
        end
    end
    for src, v in pairs(WLI.views) do
        if v[id] then out[src] = true end
    end
end

--- Inventories changed: resync everyone who sees them (and the actor).
function Sync.changed(changedIds, actor)
    local targets = {}
    if actor then targets[actor] = true end
    for id in pairs(changedIds or {}) do
        watchers(id, targets)
        if id:sub(1, 5) == 'drop:' then WLI.Drops.onChanged(id) end
    end
    for src in pairs(targets) do Sync.player(src) end
end

--- Worn items changed (clothing is derived by the client from the equip
--- snapshot, which Sync.player already sent). Kept as a named hook.
function Sync.clothing(src) end

function Sync.error(src, message)
    TriggerClientEvent('wasteland:inventory:client:error', src, message)
end

return Sync
