-- wasteland_inventory :: server/drops.lua
-- Items on the ground ('drop:<id>' grids with coordinates), stashes opened
-- by modules ('stash:<name>'), and the distance rules for both.
-- Drops are stored (wl_drops + wl_items) so they survive restarts, and
-- expire after inventory.dropLifetimeMinutes.

local Inv = WLI.Inv
local Store = WLI.Store
local Grid = WLI.Grid
local SQL = WLI.SQL
local Drops = {}
WLI.Drops = Drops

WLI.dropList = {} -- id -> { id, x, y, z, created, expires, owner, label }

local function log() return WLI.M.log end

function Drops.playerCoords(src)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    if not c then return nil end
    return { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0 }
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Is the player close enough to an inventory that has a position?
function Drops.inRange(src, inv)
    if not inv.coords then return true end
    local p = Drops.playerCoords(src)
    if not p then return false, 'your position is unknown to the server (OneSync is required)' end
    if distance(p, inv.coords) > WLI.cfg.reachDistance then return false, 'you are too far away' end
    return true
end

function Drops.list()
    local out = {}
    for _, d in pairs(WLI.dropList) do
        out[#out + 1] = { id = d.id, x = d.x, y = d.y, z = d.z, owner = d.owner, label = d.label }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Drops.broadcast(target)
    TriggerClientEvent('wasteland:inventory:client:drops', target or -1, Drops.list())
end

-- opts (body bags): { label, owner = characterId, grid = { width, height }, lifetimeMinutes }
local function createDrop(coords, opts)
    opts = opts or {}
    local id = Inv.newUid()
    local g = opts.grid or WLI.cfg.dropGrid
    local now = os.time()
    local expires = now + (opts.lifetimeMinutes or WLI.cfg.dropLifetimeMinutes) * 60
    local inv = Inv.create('drop:' .. id, 'grid', {
        label = opts.label or 'Ground', width = g.width, height = g.height, maxWeight = 100000, coords = coords,
    })
    WLI.dropList[id] = { id = id, x = coords.x, y = coords.y, z = coords.z, created = now, expires = expires,
        owner = opts.owner, label = opts.label }
    return inv, { SQL.insertDrop, { id, coords.x, coords.y, coords.z, now, opts.owner, opts.label, expires } }
end
Drops.create = createDrop

--- Plan placing `count` units of stack `s` on the ground near `src`.
--- Does not touch the source inventory (the caller does).
--- Returns { statements, inventoryId } or nil, err.
function Drops.place(src, s, count)
    local p = Drops.playerCoords(src)
    if not p then return nil, 'your position is unknown to the server (OneSync is required)' end
    local d = WLI.defs[s.name]
    local target, x, y, rotated
    for id, info in pairs(WLI.dropList) do
        local inv = WLI.invs['drop:' .. id]
        if inv and not info.owner and distance(p, info) <= WLI.cfg.dropMergeDistance then
            x, y, rotated = Grid.findSpot(inv, WLI.defs, d)
            if x then target = inv; break end
        end
    end
    local statements = {}
    if not target then
        local g = WLI.cfg.dropGrid
        if not ((d.width <= g.width and d.height <= g.height) or (d.height <= g.width and d.width <= g.height)) then
            return nil, 'that item is too big to drop'
        end
        local insert
        target, insert = createDrop({ x = p.x, y = p.y, z = p.z - 0.95 })
        statements[#statements + 1] = insert
        x, y, rotated = Grid.findSpot(target, WLI.defs, d)
        if not x then return nil, 'that item is too big to drop' end
    end
    local placed
    if count == s.count then
        placed = s
        s.x, s.y, s.rotated, s.slot = x, y, rotated, nil
    else
        placed = { uid = Inv.newUid(), name = s.name, count = count, x = x, y = y, rotated = rotated, metadata = Inv.copy(s.metadata) }
    end
    target.items[placed.uid] = placed
    statements[#statements + 1] = Store.upsert(placed, target.id)
    return { statements = statements, inventoryId = target.id }
end

local function removeDrop(id, statements)
    local inv = WLI.invs['drop:' .. id]
    statements[#statements + 1] = { SQL.deleteDrop, { id } }
    if inv then
        statements[#statements + 1] = { SQL.deleteInventoryItems, { inv.id } }
        for _, s in pairs(inv.items) do
            if WLI.defs[s.name] and WLI.defs[s.name].container then
                statements[#statements + 1] = { SQL.deleteInventoryItems, { 'item:' .. s.uid } }
                WLI.invs['item:' .. s.uid] = nil
            end
        end
    end
    WLI.invs['drop:' .. id] = nil
    WLI.dropList[id] = nil
    for _, v in pairs(WLI.views) do v['drop:' .. id] = nil end
end

--- After a change: a drop that became empty disappears.
function Drops.onChanged(inventoryId)
    local id = inventoryId:sub(6)
    local inv = WLI.invs[inventoryId]
    if inv and WLI.dropList[id] and next(inv.items) == nil then
        local statements = {}
        removeDrop(id, statements)
        Store.enqueue(statements, 'remove empty drop ' .. id)
        Drops.broadcast()
    end
end

--- Remove drops older than the lifetime (items are deleted).
function Drops.expire()
    local now = os.time()
    local statements, n = {}, 0
    for id, info in pairs(WLI.dropList) do
        if info.expires <= now then
            removeDrop(id, statements)
            n = n + 1
        end
    end
    if n > 0 then
        Store.enqueue(statements, string.format('expire %d drop(s)', n))
        log():info('removed %d expired drop(s)', n)
        Drops.broadcast()
    end
    return n
end

--- Load stored drops (thread only).
function Drops.loadAll()
    local rows, err = WDB.query(SQL.selectDrops, {})
    if err then return false, err end
    for _, r in ipairs(rows) do
        local items, ierr = Store.loadItems('drop:' .. r.id)
        if not items then return false, ierr end
        local owner = tonumber(r.owner_character)
        local g = owner and WLI.cfg.deathBagGrid or WLI.cfg.dropGrid
        local coords = { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z) }
        local created = tonumber(r.created_unix) or os.time()
        Inv.create('drop:' .. r.id, 'grid', { label = r.label or 'Ground', width = g.width, height = g.height,
            maxWeight = 100000, coords = coords, items = items })
        WLI.dropList[r.id] = { id = r.id, x = coords.x, y = coords.y, z = coords.z, created = created,
            expires = tonumber(r.expires_unix) or (created + WLI.cfg.dropLifetimeMinutes * 60),
            owner = owner, label = r.label }
        for _, s in pairs(items) do
            if WLI.defs[s.name].container then
                local contents = Store.loadItems('item:' .. s.uid)
                Inv.containerFor(s).items = contents or {}
            end
        end
        if next(items) == nil then Drops.onChanged('drop:' .. r.id) end
    end
    return true
end

--- A player asks to open a drop near them.
function Drops.open(src, id)
    local inv = WLI.invs['drop:' .. tostring(id)]
    if not inv then return false, 'there is nothing there any more' end
    local ok, why = Drops.inRange(src, inv)
    if not ok then return false, why end
    WLI.views[src] = WLI.views[src] or {}
    WLI.views[src][inv.id] = true
    WLI.Sync.player(src)
    return true
end

--- Open a stash for a player (modules decide when; thread only, it may load).
--- opts = { label, width, height, maxWeight, coords }
function Drops.openStash(src, name, opts)
    if type(name) ~= 'string' or not name:match('^[%w_%-:%.]+$') or #name > 56 then
        return false, 'stash names may use letters, digits and _ - : .'
    end
    local id = 'stash:' .. name
    local inv = WLI.invs[id]
    if not inv then
        opts = opts or {}
        local items, err = Store.loadItems(id)
        if not items then return false, err end
        inv = WLI.invs[id] or Inv.create(id, 'grid', {
            label = opts.label or 'Stash', width = math.floor(tonumber(opts.width) or 10),
            height = math.floor(tonumber(opts.height) or 6), maxWeight = tonumber(opts.maxWeight) or 100,
            coords = opts.coords, items = items,
        })
        for _, s in pairs(items) do
            if WLI.defs[s.name].container then
                Inv.containerFor(s).items = Store.loadItems('item:' .. s.uid) or {}
            end
        end
    end
    local ok, why = Drops.inRange(src, inv)
    if not ok then return false, why end
    WLI.views[src] = WLI.views[src] or {}
    WLI.views[src][id] = true
    WLI.Sync.player(src)
    return true
end

function Drops.close(src, id)
    if WLI.views[src] then WLI.views[src][id] = nil end
    WLI.Sync.player(src)
end

return Drops
