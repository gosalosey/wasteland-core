-- wasteland_inventory :: server/inventory.lua
-- Inventories in memory, access rules and every operation.
--
-- Inventory IDs (ARCHITECTURE §4):
--   player:<characterId>   pockets grid
--   equip:<characterId>    worn items (slots, no grid)
--   item:<uid>             the grid of a backpack (one level: bags never go inside bags)
--   stash:<name>           stashes opened for a player by a module
--   drop:<id>              items on the ground
--
-- Every operation: validate everything first, then change memory without
-- yielding (atomic: no other request can run in between), then queue one
-- transaction with all changed rows (Store) and send fresh snapshots.

local Grid = WLI.Grid
local Store = WLI.Store
local Inv = {}
WLI.Inv = Inv

WLI.defs = WLI.defs or {}   -- name -> validated definition
WLI.invs = {}               -- id -> inventory
WLI.chars = {}              -- characterId -> { source, id, pockets, equip, loaded, model, hotbar }
WLI.views = {}              -- source -> { [inventoryId] = true } (opened by the server)
WLI.usable = {}             -- item name -> handler

local function log() return WLI.M.log end

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local uidCounter = 0
function Inv.newUid()
    uidCounter = (uidCounter + 1) % 0x10000
    return string.format('%08x%04x%04x', os.time() & 0xffffffff, uidCounter, math.random(0, 0xffff))
end

local function copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end
Inv.copy = copy

function Inv.create(id, kind, opts)
    local inv = {
        id = id, kind = kind, label = opts.label or id,
        width = opts.width or 0, height = opts.height or 0, maxWeight = opts.maxWeight or 0,
        items = opts.items or {}, coords = opts.coords,
    }
    WLI.invs[id] = inv
    return inv
end

--- Total weight including the contents of bags (kg).
function Inv.stackWeight(s)
    local d = WLI.defs[s.name]
    local w = d and d.weight * s.count or 0
    if d and d.container then
        local c = WLI.invs['item:' .. s.uid]
        if c then w = w + Inv.weight(c) end
    end
    return w
end

function Inv.weight(inv, ignoreUid)
    local total = 0
    for uid, s in pairs(inv.items) do
        if uid ~= ignoreUid then total = total + Inv.stackWeight(s) end
    end
    return total
end

function Inv.characterOf(src)
    local ok, cid = pcall(function() return exports.wasteland_players:GetCharacterId(src) end)
    if not ok or not cid then return nil end
    return WLI.chars[cid]
end

function Inv.backpack(c)
    local equip = WLI.invs[c.equip]
    if not equip then return nil end
    for _, s in pairs(equip.items) do
        if s.slot == 'back' then return s end
    end
    return nil
end

--- The worn armor vest that holds plates (armor slot, container), or nil.
function Inv.vest(c)
    local equip = WLI.invs[c.equip]
    if not equip then return nil end
    for _, s in pairs(equip.items) do
        local d = WLI.defs[s.name]
        if s.slot == 'armor' and d and d.container then return s end
    end
    return nil
end

--- Container inventory for a bag stack (created empty if new).
function Inv.containerFor(stack)
    local d = WLI.defs[stack.name]
    if not d or not d.container then return nil end
    local id = 'item:' .. stack.uid
    local inv = WLI.invs[id]
    if inv then
        -- the bag's size in the settings changed while it was loaded: follow it
        -- (only when everything in it still fits)
        if inv.width ~= d.container.width or inv.height ~= d.container.height then
            local moves, over = Grid.repack(inv, WLI.defs, d.container.width, d.container.height)
            if #over == 0 then
                local statements = {}
                for uid, m in pairs(moves) do
                    local s = inv.items[uid]
                    s.x, s.y, s.rotated = m.x, m.y, m.rotated
                    statements[#statements + 1] = Store.upsert(s, id)
                end
                if #statements > 0 then Store.enqueue(statements, 'fit bag ' .. id .. ' to its size') end
                inv.width, inv.height = d.container.width, d.container.height
            end
        end
        inv.maxWeight = d.container.maxWeight
        inv.accepts = d.container.accepts
        return inv
    end
    local inv = Inv.create(id, 'grid', {
        label = d.label, width = d.container.width, height = d.container.height, maxWeight = d.container.maxWeight,
    })
    if inv then inv.accepts = d.container.accepts end
    return inv
end

--- A bag's grid with its stored items. If the bag got smaller in the
--- settings, stacks outside the grid move inside; if they cannot all fit,
--- the grid stays just big enough for them (nothing is lost).
function Inv.loadContainer(stack, items)
    local inv = Inv.containerFor(stack)
    if not inv then return nil end
    inv.items = items or {}
    local moves, over = Grid.repack(inv, WLI.defs, inv.width, inv.height)
    if #over > 0 then
        local w, h = inv.width, inv.height
        for _, s in pairs(inv.items) do
            if s.x ~= nil then
                local fw, fh = Grid.footprint(WLI.defs[s.name] or { width = 1, height = 1 }, s.rotated)
                w, h = math.max(w, s.x + fw), math.max(h, s.y + fh)
            end
        end
        inv.width, inv.height = w, h
    elseif next(moves) then
        local statements = {}
        for uid, m in pairs(moves) do
            local s = inv.items[uid]
            s.x, s.y, s.rotated = m.x, m.y, m.rotated
            statements[#statements + 1] = Store.upsert(s, inv.id)
        end
        Store.enqueue(statements, 'fit bag ' .. inv.id .. ' to its size')
    end
    return inv
end

-------------------------------------------------------------------------------
-- Access
-------------------------------------------------------------------------------

--- May player `src` act on inventory `id`? Returns inventory or nil, reason.
function Inv.access(src, id)
    if type(id) ~= 'string' then return nil, 'unknown inventory' end
    local c = Inv.characterOf(src)
    if not c then return nil, 'you have no character loaded' end
    if not c.loaded then return nil, 'your inventory is still loading' end
    local inv = WLI.invs[id]
    if not inv then return nil, 'that inventory is not available' end
    if id == c.pockets or id == c.equip then return inv end
    local bag = Inv.backpack(c)
    if bag and id == 'item:' .. bag.uid then return inv end
    local vest = Inv.vest(c)
    if vest and id == 'item:' .. vest.uid then return inv end
    if WLI.views[src] and WLI.views[src][id] then
        local okRange, why = WLI.Drops.inRange(src, inv)
        if not okRange then return nil, why end
        return inv
    end
    return nil, 'you cannot reach that'
end

-------------------------------------------------------------------------------
-- Operation plumbing
-------------------------------------------------------------------------------

-- Run an operation for a player: checks the database is accepting, runs
-- `fn` (which validates, mutates and returns statements + changed ids),
-- queues the write and syncs. Returns ok, err.
function Inv.run(src, label, fn)
    local accepting, why = Store.accepting()
    if not accepting then return false, 'Inventory changes are paused: ' .. why .. '.' end
    local result, err = fn()
    if not result then return false, err end
    Store.enqueue(result.statements, string.format('%s by player %s', label, tostring(src)))
    WLI.Sync.changed(result.changed, src)
    if result.after then result.after() end
    return true
end

local function changedSet(...)
    local out = {}
    for i = 1, select('#', ...) do
        local id = select(i, ...)
        if id then out[id] = true end
    end
    return out
end

local function needsGrid(inv)
    if inv.kind ~= 'grid' then return 'items can only be placed in a grid' end
    return nil
end

local function bagCheck(def, to, uid)
    if to.id == 'item:' .. tostring(uid) then return 'a bag cannot go inside itself' end
    -- plate slots of an armor vest: plates only
    if to.accepts then
        for _, n in ipairs(to.accepts) do if n == def.name then return nil end end
        return 'only armor plates go in there'
    end
    -- a vest (with its plates) may go in a bag; a bag may not
    if def.container and not def.container.accepts and to.id:sub(1, 5) == 'item:' then return 'a bag cannot go inside another bag' end
    return nil
end

local function weightCheck(to, addKg, ignoreUid)
    if Inv.weight(to, ignoreUid) + addKg > to.maxWeight + 1e-9 then
        return string.format('too heavy (%s holds %.1f kg)', to.label, to.maxWeight)
    end
    return nil
end

-------------------------------------------------------------------------------
-- Pockets grow with what is worn (inventory.lua pockets.bonus)
-------------------------------------------------------------------------------

-- The character an inventory id belongs to ('player:<id>' / 'equip:<id>').
local function ownerOf(invId)
    local cid = tonumber(tostring(invId):match('^%a+:(%d+)$'))
    local c = cid and WLI.chars[cid]
    if c and (invId == c.pockets or invId == c.equip) then return c end
    return nil
end

local function givesPockets(slot)
    local b = slot and WLI.cfg.pockets.bonus and WLI.cfg.pockets.bonus[slot]
    return b ~= nil and ((b.width or 0) > 0 or (b.height or 0) > 0)
end

--- Would taking off worn stack `s` leave the pockets too small for what is in
--- them? landing: { x, y, rotated } when it goes into the pockets itself.
--- -> nil (fine) or an error message.
local function shrinkProblem(c, s, landing)
    if not givesPockets(s.slot) then return nil end
    local pockets, equip = WLI.invs[c.pockets], WLI.invs[c.equip]
    local w, h = Grid.pocketSize(WLI.cfg.pockets, equip.items, s.uid)
    if w >= pockets.width and h >= pockets.height then return nil end
    local fixed = nil
    if landing then
        local fw, fh = Grid.footprint(WLI.defs[s.name], landing.rotated == true)
        if landing.x + fw > w or landing.y + fh > h then return 'there is no room there' end
        fixed = { [s.uid] = { uid = s.uid, name = s.name, x = landing.x, y = landing.y, rotated = landing.rotated == true } }
    end
    local _, over = Grid.repack(pockets, WLI.defs, w, h, fixed)
    if #over > 0 then
        return string.format('your pockets get smaller without the %s: make room in them first', WLI.defs[s.name].label:lower())
    end
    return nil
end

--- Size the pockets to what is worn. Stacks outside the new size move
--- inside. What cannot fit goes to overflow(stack) when given; otherwise the
--- pockets stay just big enough to hold it (nothing is ever lost).
--- With statements/changed the caller enqueues and syncs.
function Inv.fitPockets(c, statements, changed, overflow)
    local pockets, equip = WLI.invs[c.pockets], WLI.invs[c.equip]
    if not pockets or not equip then return end
    local w, h = Grid.pocketSize(WLI.cfg.pockets, equip.items)
    local own = statements == nil
    statements, changed = statements or {}, changed or {}
    local moves, over = Grid.repack(pockets, WLI.defs, w, h)
    if #over > 0 and overflow then
        for _, uid in ipairs(over) do
            local st = pockets.items[uid]
            pockets.items[uid] = nil
            overflow(st)
        end
    elseif #over > 0 then
        -- keep everything where it is; grow just enough to cover it
        moves = {}
        for _, st in pairs(pockets.items) do
            if st.x ~= nil then
                local fw, fh = Grid.footprint(WLI.defs[st.name] or { width = 1, height = 1 }, st.rotated)
                w, h = math.max(w, st.x + fw), math.max(h, st.y + fh)
            end
        end
    end
    local touched = next(moves) ~= nil or w ~= pockets.width or h ~= pockets.height
    for uid, m in pairs(moves) do
        local st = pockets.items[uid]
        if st then
            st.x, st.y, st.rotated = m.x, m.y, m.rotated
            statements[#statements + 1] = Store.upsert(st, pockets.id)
        end
    end
    pockets.width, pockets.height = w, h
    if touched then changed[pockets.id] = true end
    if own and touched then
        if #statements > 0 then Store.enqueue(statements, string.format('pockets of character %d', c.id)) end
        if c.source then WLI.Sync.changed(changed, c.source) end
    end
end

-------------------------------------------------------------------------------
-- Operations (validate -> mutate -> statements)
-------------------------------------------------------------------------------

--- Move a stack (from a grid or a worn slot) to a grid position.
-- Items with a `limit`: how many more of `name` this character may carry
-- (math.huge when the item has no limit).
function Inv.limitLeft(c, name)
    local d = WLI.defs[name]
    if not d or not d.limit then return math.huge end
    local n = 0
    for _, id in ipairs(Inv.ownInventories(c)) do
        local inv = WLI.invs[id]
        if inv then for _, s in pairs(inv.items) do if s.name == name then n = n + s.count end end end
    end
    return d.limit - n
end

local function limitText(name)
    local d = WLI.defs[name]
    return string.format('you can only carry %d %s', d.limit, d.label)
end

-- Is `id` one of this character's own inventories?
local function isOwn(c, id)
    for _, own in ipairs(Inv.ownInventories(c)) do if own == id then return true end end
    return false
end

function Inv.move(src, uid, fromId, toId, x, y, rotated)
    return Inv.run(src, 'move', function()
        local from, e1 = Inv.access(src, fromId); if not from then return nil, e1 end
        local to, e2 = Inv.access(src, toId); if not to then return nil, e2 end
        local s = from.items[uid]
        if not s then return nil, 'that item is no longer there' end
        local d = WLI.defs[s.name]
        local mc = Inv.characterOf(src)
        if d and d.limit and mc and isOwn(mc, toId) and not isOwn(mc, fromId) and Inv.limitLeft(mc, s.name) < s.count then
            return nil, limitText(s.name)
        end
        local bad = needsGrid(to) or bagCheck(d, to, uid)
        if bad then return nil, bad end
        local ok = Grid.fits(to, WLI.defs, d, x, y, rotated == true, from == to and uid or nil)
        if not ok then return nil, 'there is no room there' end
        if from ~= to then
            local heavy = weightCheck(to, Inv.stackWeight(s))
            if heavy then return nil, heavy end
        end
        local wearer = s.slot and ownerOf(from.id)
        if wearer then
            local landing = (to.id == wearer.pockets) and { x = x, y = y, rotated = rotated == true } or nil
            local problem = shrinkProblem(wearer, s, landing)
            if problem then return nil, problem end
        end
        local wasWorn = s.slot
        from.items[uid] = nil
        s.x, s.y, s.rotated, s.slot = x, y, rotated == true, nil
        to.items[uid] = s
        local statements, changed = { Store.upsert(s, to.id) }, changedSet(from.id, to.id)
        if wearer then Inv.fitPockets(wearer, statements, changed) end
        return {
            statements = statements,
            changed = changed,
            after = wasWorn and function() WLI.Sync.clothing(src) end or nil,
        }
    end)
end

--- Move up to `count` units from stack `uid` onto stack `targetUid`.
function Inv.merge(src, uid, fromId, targetUid, toId, count)
    return Inv.run(src, 'merge', function()
        local from, e1 = Inv.access(src, fromId); if not from then return nil, e1 end
        local to, e2 = Inv.access(src, toId); if not to then return nil, e2 end
        local s, t = from.items[uid], to.items[targetUid]
        if not s or not t then return nil, 'that item is no longer there' end
        if not Grid.canMerge(s, t, WLI.defs) then return nil, 'those items do not stack' end
        local d = WLI.defs[s.name]
        local n = math.min(count or s.count, s.count, d.stack - t.count)
        if n < 1 then return nil, 'that stack is full' end
        if from ~= to then
            local heavy = weightCheck(to, d.weight * n)
            if heavy then return nil, heavy end
        end
        t.count = t.count + n
        s.count = s.count - n
        local statements = { Store.upsert(t, to.id) }
        if s.count == 0 then
            from.items[uid] = nil
            statements[#statements + 1] = Store.delete(uid)
        else
            statements[#statements + 1] = Store.upsert(s, from.id)
        end
        return { statements = statements, changed = changedSet(from.id, to.id) }
    end)
end

--- Split `count` units off a stack into a new stack in the same grid.
function Inv.split(src, uid, invId, count)
    return Inv.run(src, 'split', function()
        local inv, e = Inv.access(src, invId); if not inv then return nil, e end
        local s = inv.items[uid]
        if not s then return nil, 'that item is no longer there' end
        if inv.kind ~= 'grid' then return nil, 'items can only be split in a grid' end
        if math.type(count) ~= 'integer' or count < 1 or count >= s.count then
            return nil, string.format('you can split 1 to %d from this stack', s.count - 1)
        end
        local d = WLI.defs[s.name]
        local x, y, rotated = Grid.findSpot(inv, WLI.defs, d)
        if not x then return nil, 'there is no free space for the new stack' end
        local new = { uid = Inv.newUid(), name = s.name, count = count, x = x, y = y, rotated = rotated, metadata = copy(s.metadata) }
        s.count = s.count - count
        inv.items[new.uid] = new
        return { statements = { Store.upsert(s, inv.id), Store.upsert(new, inv.id) }, changed = changedSet(inv.id) }
    end)
end

--- Wear an item. If the slot is taken, the worn item swaps into the
--- place the new one came from (or any free space there).
function Inv.equip(src, uid, fromId, slot)
    return Inv.run(src, 'equip', function()
        local c = Inv.characterOf(src)
        local from, e1 = Inv.access(src, fromId); if not from then return nil, e1 end
        if from.kind ~= 'grid' then return nil, 'that item is already worn' end
        local equip = WLI.invs[c.equip]
        local s = from.items[uid]
        if not s then return nil, 'that item is no longer there' end
        local d = WLI.defs[s.name]
        if d.equip ~= slot then return nil, string.format('%s cannot be worn there', d.label) end
        if WLI.CLOTHING_PARTS[slot] and s.metadata and s.metadata.model and c.model and s.metadata.model ~= c.model then
            return nil, string.format('%s does not fit this character', d.label)
        end
        local old
        for _, w in pairs(equip.items) do if w.slot == slot then old = w end end
        local statements = {}
        local changed = changedSet(from.id, equip.id)
        from.items[uid] = nil -- free its cells for the swap
        if old then
            local od = WLI.defs[old.name]
            local badBag = bagCheck(od, from, old.uid)
            local ox, oy, orot
            if not badBag then
                if Grid.fits(from, WLI.defs, od, s.x, s.y, s.rotated) then
                    ox, oy, orot = s.x, s.y, s.rotated
                else
                    ox, oy, orot = Grid.findSpot(from, WLI.defs, od)
                end
            end
            -- `s` is already out of `from`, so only the old item is added
            local heavy = (not badBag) and ox and weightCheck(from, Inv.stackWeight(old))
            if badBag or not ox or heavy then
                from.items[uid] = s -- undo: nothing has changed yet
                return nil, badBag or heavy or string.format('take off the %s first (no room for it)', od.label)
            end
            equip.items[old.uid] = nil
            old.slot, old.x, old.y, old.rotated = nil, ox, oy, orot
            from.items[old.uid] = old
            statements[#statements + 1] = Store.upsert(old, from.id)
            if od.container then changed['item:' .. old.uid] = true end
        end
        s.x, s.y, s.rotated, s.slot = nil, nil, false, slot
        equip.items[uid] = s
        statements[#statements + 1] = Store.upsert(s, equip.id)
        if d.container then Inv.containerFor(s); changed['item:' .. uid] = true end
        Inv.fitPockets(c, statements, changed)
        return { statements = statements, changed = changed, after = function() WLI.Sync.clothing(src) end }
    end)
end

--- Take off a worn item into a grid (position optional: first free spot).
function Inv.unequip(src, slot, toId, x, y, rotated)
    local c = Inv.characterOf(src)
    if not c or not c.loaded then return false, 'your inventory is still loading' end
    local equip = WLI.invs[c.equip]
    local worn
    for _, w in pairs(equip.items) do if w.slot == slot then worn = w end end
    if not worn then return false, 'nothing is worn there' end
    if x == nil then
        local to = WLI.invs[toId]
        if not to then return false, 'that inventory is not available' end
        local area = to
        if toId == c.pockets and givesPockets(worn.slot) then
            local w, h = Grid.pocketSize(WLI.cfg.pockets, equip.items, worn.uid)
            area = { width = math.min(w, to.width), height = math.min(h, to.height), items = to.items }
        end
        x, y, rotated = Grid.findSpot(area, WLI.defs, WLI.defs[worn.name])
        if not x and area ~= to then
            return false, string.format('your pockets get smaller without the %s: make room in them first', WLI.defs[worn.name].label:lower())
        end
        if not x then return false, 'there is no room for it' end
    end
    return Inv.move(src, worn.uid, c.equip, toId, x, y, rotated)
end

--- Drop a stack (or part of it) on the ground at the player's feet.
function Inv.drop(src, uid, fromId, count)
    return Inv.run(src, 'drop', function()
        local from, e1 = Inv.access(src, fromId); if not from then return nil, e1 end
        local s = from.items[uid]
        if not s then return nil, 'that item is no longer there' end
        count = count or s.count
        if math.type(count) ~= 'integer' or count < 1 or count > s.count then
            return nil, string.format('you can drop 1 to %d', s.count)
        end
        local wasWorn = from.kind == 'equip'
        local wearer = wasWorn and ownerOf(from.id)
        if wearer then
            local problem = shrinkProblem(wearer, s, nil)
            if problem then return nil, problem end
        end
        local placed, err = WLI.Drops.place(src, s, count)
        if not placed then return nil, err end
        local statements = placed.statements
        local changed = changedSet(from.id, placed.inventoryId)
        if count == s.count then
            from.items[uid] = nil
            -- the stack row itself moves (placed.statements upserts it)
        else
            s.count = s.count - count
            statements[#statements + 1] = Store.upsert(s, from.id)
        end
        if wearer then Inv.fitPockets(wearer, statements, changed) end
        return {
            statements = statements, changed = changed,
            after = function()
                if wasWorn then WLI.Sync.clothing(src) end
                -- The screen is open: the pile it went to shows in the vicinity.
                if WLI.vicinity and WLI.vicinity[src] then
                    WLI.views[src] = WLI.views[src] or {}
                    if not WLI.views[src][placed.inventoryId] then
                        WLI.views[src][placed.inventoryId] = true
                        WLI.Sync.player(src)
                    end
                end
                WLI.Drops.broadcast()
            end,
        }
    end)
end

--- Use an item through the handler a module registered for it.
function Inv.use(src, uid, invId, targetUid)
    local inv, e = Inv.access(src, invId)
    if not inv then return false, e end
    local s = inv.items[uid]
    if not s then return false, 'that item is no longer there' end
    local handler = WLI.usable[s.name]
    if not handler then return false, string.format('%s cannot be used', WLI.defs[s.name].label) end
    local accepting, why = Store.accepting()
    if not accepting then return false, 'Inventory changes are paused: ' .. why .. '.' end
    local ok, consumed, message = pcall(handler, src, copy(s), invId, targetUid)
    if not ok then
        log():error('use handler for "%s" failed: %s', s.name, tostring(consumed))
        return false, 'that did not work'
    end
    if consumed == false then return false, message or 'you cannot use that now' end
    consumed = math.tointeger(tonumber(consumed) or 0) or 0
    if consumed > 0 then
        -- The stack may have changed while the handler ran; re-check.
        s = inv.items[uid]
        if not s or s.count < consumed then
            log():warn('use of "%s" by player %d: stack changed during the handler; nothing consumed', tostring(uid), src)
            return true
        end
        s.count = s.count - consumed
        local statements = {}
        if s.count == 0 then
            inv.items[uid] = nil
            statements[1] = Store.delete(uid)
        else
            statements[1] = Store.upsert(s, inv.id)
        end
        Store.enqueue(statements, string.format('use %s by player %d', s.name, src))
        WLI.Sync.changed(changedSet(inv.id), src)
    end
    return true, message
end

-------------------------------------------------------------------------------
-- Adding and removing items (server API, all-or-nothing)
-------------------------------------------------------------------------------

-- Inventories items for a player are added to: pockets, then worn bag.
function Inv.targetsFor(target)
    if type(target) == 'string' then
        local inv = WLI.invs[target]
        return inv and { inv } or nil
    end
    local c = Inv.characterOf(target)
    if not c or not c.loaded then return nil end
    local out = { WLI.invs[c.pockets] }
    local bag = Inv.backpack(c)
    if bag and WLI.invs['item:' .. bag.uid] then out[#out + 1] = WLI.invs['item:' .. bag.uid] end
    return out
end

--- Plan adding `count` of `name`. Returns plan or nil, err. No changes yet.
local function planAdd(targets, name, count, metadata)
    local d = WLI.defs[name]
    if not d then return nil, string.format('unknown item "%s"', tostring(name)) end
    if math.type(count) ~= 'integer' or count < 1 then return nil, 'count must be a whole number of 1 or more' end
    local meta = copy(metadata or {})
    if d.durability > 0 and meta.durability == nil then meta.durability = d.durability end
    local remaining = count
    local plan = { merges = {}, creates = {} }
    local addedKg = {}
    local function room(inv, kg)
        return Inv.weight(inv) + (addedKg[inv.id] or 0) + kg <= inv.maxWeight + 1e-9
    end
    -- 1. top up existing stacks
    if d.stack > 1 then
        for _, inv in ipairs(targets) do
            for _, s in pairs(inv.items) do
                if remaining == 0 then break end
                if s.name == name and Grid.deepEqual(s.metadata or {}, meta) and s.count < d.stack then
                    local n = math.min(remaining, d.stack - s.count)
                    while n > 0 and not room(inv, d.weight * n) do n = n - 1 end
                    if n > 0 then
                        plan.merges[#plan.merges + 1] = { inv = inv, stack = s, n = n }
                        addedKg[inv.id] = (addedKg[inv.id] or 0) + d.weight * n
                        remaining = remaining - n
                    end
                end
            end
        end
    end
    -- 2. new stacks in free space (a scratch copy tracks planned cells)
    for _, inv in ipairs(targets) do
        if inv.kind == 'grid' and not (d.container and inv.id:sub(1, 5) == 'item:') then
            local scratch = { width = inv.width, height = inv.height, items = {} }
            for uid, s in pairs(inv.items) do scratch.items[uid] = s end
            while remaining > 0 do
                local n = math.min(remaining, d.stack)
                while n > 0 and not room(inv, d.weight * n) do n = n - 1 end
                if n == 0 then break end
                local x, y, rotated = Grid.findSpot(scratch, WLI.defs, d)
                if not x then break end
                local s = { uid = Inv.newUid(), name = name, count = n, x = x, y = y, rotated = rotated, metadata = copy(meta) }
                scratch.items[s.uid] = s
                plan.creates[#plan.creates + 1] = { inv = inv, stack = s }
                addedKg[inv.id] = (addedKg[inv.id] or 0) + d.weight * n
                remaining = remaining - n
            end
        end
    end
    if remaining > 0 then return nil, string.format('not enough room for %d x %s', count, d.label) end
    return plan
end

--- AddItem(target, name, count, metadata) -> true | false, err
--- target: player server id (pockets, then worn bag) or inventory id.
function Inv.addItem(target, name, count, metadata)
    local accepting, why = Store.accepting()
    if not accepting then return false, 'inventory changes are paused: ' .. why end
    local targets = Inv.targetsFor(target)
    if not targets then return false, 'that inventory is not loaded' end
    if type(target) ~= 'string' then
        local lc = Inv.characterOf(target)
        if lc and Inv.limitLeft(lc, name) < count then return false, limitText(name) end
    end
    local plan, err = planAdd(targets, name, count, metadata)
    if not plan then return false, err end
    local statements, changed = {}, {}
    for _, m in ipairs(plan.merges) do
        m.stack.count = m.stack.count + m.n
        statements[#statements + 1] = Store.upsert(m.stack, m.inv.id)
        changed[m.inv.id] = true
    end
    for _, c in ipairs(plan.creates) do
        c.inv.items[c.stack.uid] = c.stack
        statements[#statements + 1] = Store.upsert(c.stack, c.inv.id)
        changed[c.inv.id] = true
        Inv.containerFor(c.stack)
    end
    Store.enqueue(statements, string.format('add %d x %s', count, name))
    WLI.Sync.changed(changed)
    return true
end

--- Count of `name` the target holds (pockets + worn bag, or one inventory).
function Inv.countItem(target, name)
    local targets = Inv.targetsFor(target)
    if not targets then return 0 end
    local n = 0
    for _, inv in ipairs(targets) do
        for _, s in pairs(inv.items) do if s.name == name then n = n + s.count end end
    end
    return n
end

--- RemoveItem(target, name, count) -> true | false, err (all or nothing)
function Inv.removeItem(target, name, count)
    local accepting, why = Store.accepting()
    if not accepting then return false, 'inventory changes are paused: ' .. why end
    if math.type(count) ~= 'integer' or count < 1 then return false, 'count must be a whole number of 1 or more' end
    local targets = Inv.targetsFor(target)
    if not targets then return false, 'that inventory is not loaded' end
    if Inv.countItem(target, name) < count then return false, 'not enough items' end
    local remaining = count
    local statements, changed = {}, {}
    for _, inv in ipairs(targets) do
        local stacks = {}
        for _, s in pairs(inv.items) do if s.name == name then stacks[#stacks + 1] = s end end
        table.sort(stacks, function(a, b) return a.count < b.count end) -- empty small stacks first
        for _, s in ipairs(stacks) do
            if remaining == 0 then break end
            local n = math.min(remaining, s.count)
            s.count = s.count - n
            remaining = remaining - n
            if s.count == 0 then
                inv.items[s.uid] = nil
                statements[#statements + 1] = Store.delete(s.uid)
            else
                statements[#statements + 1] = Store.upsert(s, inv.id)
            end
            changed[inv.id] = true
        end
    end
    Store.enqueue(statements, string.format('remove %d x %s', count, name))
    WLI.Sync.changed(changed)
    return true
end

-------------------------------------------------------------------------------
-- Death: everything except hotbar items goes into a body bag
-------------------------------------------------------------------------------

--- Put a dead player's items into body bag(s) at their position.
--- Kept: stacks on the hotbar (worn ones stay worn; ones inside the worn
--- bag move to the pockets if they fit). Everything else drops; a bag keeps
--- its contents. Returns { dropIds } or nil, err. One transaction.
function Inv.deathDrop(src, label)
    local c = Inv.characterOf(src)
    if not c or not c.loaded then return nil, 'inventory not loaded' end
    local accepting, why = Store.accepting()
    if not accepting then return nil, why end
    local p = WLI.Drops.playerCoords(src)
    if not p then return nil, 'position unknown (OneSync is required)' end
    local keep = {}
    for i = 1, 8 do if c.hotbar[i] then keep[c.hotbar[i]] = true end end

    local pockets, equip = WLI.invs[c.pockets], WLI.invs[c.equip]
    local bag = Inv.backpack(c)
    local bagGrid = bag and WLI.invs['item:' .. bag.uid]
    local statements, changed = {}, changedSet(c.pockets, c.equip)

    -- 1. hotbar items inside the worn bag try to move to the pockets
    if bagGrid and not keep[bag.uid] then
        for uid, s in pairs(bagGrid.items) do
            if keep[uid] then
                local x, y, rotated = Grid.findSpot(pockets, WLI.defs, WLI.defs[s.name])
                if x then
                    bagGrid.items[uid] = nil
                    s.x, s.y, s.rotated = x, y, rotated
                    pockets.items[uid] = s
                    statements[#statements + 1] = Store.upsert(s, pockets.id)
                end
            end
        end
    end

    -- 2. everything else into body bags (more than one if it does not fit)
    local toDrop = {}
    for _, inv in ipairs({ pockets, equip }) do
        for uid, s in pairs(inv.items) do
            if not keep[uid] then toDrop[#toDrop + 1] = { inv = inv, stack = s } end
        end
    end
    -- what stays worn decides the pocket size; kept stacks that no longer
    -- fit go into the body bag too
    local stillWorn = {}
    for uid, s in pairs(equip.items) do if keep[uid] then stillWorn[uid] = s end end
    local pw, ph = Grid.pocketSize(WLI.cfg.pockets, stillWorn)
    local keptPockets = { items = {} }
    for uid, s in pairs(pockets.items) do if keep[uid] then keptPockets.items[uid] = s end end
    local pocketMoves, pocketOver = Grid.repack(keptPockets, WLI.defs, pw, ph)
    for _, uid in ipairs(pocketOver) do toDrop[#toDrop + 1] = { inv = pockets, stack = pockets.items[uid] } end
    -- big items first so they find room
    table.sort(toDrop, function(a, b)
        local da, db = WLI.defs[a.stack.name], WLI.defs[b.stack.name]
        return da.width * da.height > db.width * db.height
    end)
    local bags, current = {}, nil
    local function newBag()
        local n = #bags
        local coords = { x = p.x + 0.4 * n, y = p.y, z = p.z - 0.95 }
        local inv, insert = WLI.Drops.create(coords, {
            label = label, owner = c.id, grid = WLI.cfg.deathBagGrid, lifetimeMinutes = WLI.cfg.deathBagLifetimeMinutes,
        })
        statements[#statements + 1] = insert
        bags[#bags + 1] = inv
        changed[inv.id] = true
        return inv
    end
    for _, entry in ipairs(toDrop) do
        local s, d = entry.stack, WLI.defs[entry.stack.name]
        current = current or newBag()
        local x, y, rotated = Grid.findSpot(current, WLI.defs, d)
        if not x then
            current = newBag()
            x, y, rotated = Grid.findSpot(current, WLI.defs, d)
        end
        if x then
            entry.inv.items[s.uid] = nil
            s.x, s.y, s.rotated, s.slot = x, y, rotated, nil
            current.items[s.uid] = s
            statements[#statements + 1] = Store.upsert(s, current.id)
        else
            log():error('death of player %d: %s does not fit in a body bag; it stays with the character', src, s.name)
        end
    end
    for uid, m in pairs(pocketMoves) do
        local s = pockets.items[uid]
        if s then
            s.x, s.y, s.rotated = m.x, m.y, m.rotated
            statements[#statements + 1] = Store.upsert(s, pockets.id)
        end
    end
    Inv.fitPockets(c, statements, changed)
    WLI.views[src] = nil
    if WLI.vicinity then WLI.vicinity[src] = nil end
    Store.enqueue(statements, string.format('death of character %d', c.id))
    WLI.Sync.changed(changed, src)
    WLI.Drops.broadcast()
    local ids = {}
    for _, b in ipairs(bags) do ids[#ids + 1] = b.id:sub(6) end
    return { dropIds = ids }
end

--- Delete everything a character carries and wears (admin). One transaction.
function Inv.clear(src)
    local c = Inv.characterOf(src)
    if not c or not c.loaded then return false, 'that player has no loaded inventory' end
    local accepting, why = Store.accepting()
    if not accepting then return false, why end
    local statements, changed = {}, changedSet(c.pockets, c.equip)
    for _, id in ipairs({ c.pockets, c.equip }) do
        local inv = WLI.invs[id]
        for uid, s in pairs(inv.items) do
            local d = WLI.defs[s.name]
            if d and d.container then
                statements[#statements + 1] = { WLI.SQL.deleteInventoryItems, { 'item:' .. uid } }
                WLI.invs['item:' .. uid] = nil
            end
            statements[#statements + 1] = Store.delete(uid)
            inv.items[uid] = nil
        end
    end
    Inv.fitPockets(c, statements, changed)
    for i = 1, 8 do c.hotbar[i] = false end
    exports.wasteland_players:SetCharacterData(c.id, 'hotbar', c.hotbar)
    Store.enqueue(statements, string.format('clear inventory of character %d', c.id))
    WLI.Sync.changed(changed, src)
    return true
end

-------------------------------------------------------------------------------
-- Hotbar (5 references to stacks, stored as character data "hotbar")
-------------------------------------------------------------------------------

function Inv.setHotbar(src, index, uid)
    local c = Inv.characterOf(src)
    if not c or not c.loaded then return false, 'your inventory is still loading' end
    if uid ~= nil then
        local found = false
        for _, id in ipairs(Inv.ownInventories(c)) do
            if WLI.invs[id] and WLI.invs[id].items[uid] then found = true end
        end
        if not found then return false, 'that item is not in your inventory' end
        for i = 1, 8 do if c.hotbar[i] == uid then c.hotbar[i] = false end end
    end
    c.hotbar[index] = uid or false
    exports.wasteland_players:SetCharacterData(c.id, 'hotbar', c.hotbar)
    WLI.Sync.player(src)
    return true
end

function Inv.ownInventories(c)
    local out = { c.pockets, c.equip }
    local bag = Inv.backpack(c)
    if bag then out[#out + 1] = 'item:' .. bag.uid end
    local vest = Inv.vest(c)
    if vest then out[#out + 1] = 'item:' .. vest.uid end
    return out
end

-------------------------------------------------------------------------------
-- Trading between two players: both sides at once, all or nothing
-------------------------------------------------------------------------------

--- Stacks a player can trade: pockets and worn bag (not worn items).
--- -> list of { stack, inventoryId }
function Inv.tradeable(src)
    local c = Inv.characterOf(src)
    if not c or not c.loaded then return {} end
    local out = {}
    for _, inv in ipairs(Inv.targetsFor(src) or {}) do
        for _, s in pairs(inv.items) do out[#out + 1] = { stack = s, inventoryId = inv.id } end
    end
    return out
end

--- Swap: offerA (list of { uid, count }) goes from player a to b, offerB
--- from b to a. Checks every stack is still there, then places everything;
--- if anything does not fit (room or weight) nothing changes.
--- Whole stacks keep their uid (a bag keeps its contents); part of a stack
--- becomes a new stack. One transaction. -> true | false, err
function Inv.trade(a, offerA, b, offerB)
    local accepting, why = Store.accepting()
    if not accepting then return false, 'inventory changes are paused: ' .. why end
    local ca, cb = Inv.characterOf(a), Inv.characterOf(b)
    if not ca or not ca.loaded or not cb or not cb.loaded then return false, 'an inventory is not loaded' end
    local ta, tb = Inv.targetsFor(a), Inv.targetsFor(b)
    local involved = {}
    for _, inv in ipairs(ta) do involved[#involved + 1] = inv end
    for _, inv in ipairs(tb) do involved[#involved + 1] = inv end

    -- find every offered stack where it is now
    local function locate(targets, offer, who)
        local out, seen = {}, {}
        for _, o in ipairs(offer or {}) do
            if type(o.uid) ~= 'string' or seen[o.uid] then return nil, 'the offer is not valid' end
            seen[o.uid] = true
            local found, from
            for _, inv in ipairs(targets) do if inv.items[o.uid] then found, from = inv.items[o.uid], inv end end
            if not found then return nil, who .. ' no longer has an offered item' end
            local n = math.tointeger(o.count)
            if not n or n < 1 or n > found.count then return nil, who .. ' no longer has that many ' .. WLI.defs[found.name].label end
            out[#out + 1] = { stack = found, from = from, count = n }
        end
        return out
    end
    local la, e1 = locate(ta, offerA, 'the other player'); if not la then return false, e1 end
    local lb, e2 = locate(tb, offerB, 'the other player'); if not lb then return false, e2 end
    -- items with a limit: nobody ends up carrying more than allowed
    local function overLimit(receiver, giving, getting)
        local net = {}
        for _, x in ipairs(getting) do net[x.stack.name] = (net[x.stack.name] or 0) + x.count end
        for _, x in ipairs(giving) do net[x.stack.name] = (net[x.stack.name] or 0) - x.count end
        for name, n in pairs(net) do
            if n > 0 and Inv.limitLeft(receiver, name) < n then return limitText(name) end
        end
    end
    local over = overLimit(ca, la, lb) or overLimit(cb, lb, la)
    if over then return false, over end

    -- remember everything so a failed placement can be undone
    local before, beforeSize = {}, {}
    for _, inv in ipairs(involved) do
        local m = {}
        for uid, s in pairs(inv.items) do m[uid] = copy(s) end
        before[inv.id] = m
    end
    local function undo()
        for _, inv in ipairs(involved) do
            local m = {}
            for uid, s in pairs(before[inv.id]) do m[uid] = copy(s) end
            inv.items = m
        end
    end

    -- 1. take everything offered out
    local moving = {}   -- { to = targets, whole = stack } | { to = targets, name, count, metadata }
    local function take(list, to)
        for _, l in ipairs(list) do
            if l.count == l.stack.count then
                l.from.items[l.stack.uid] = nil
                moving[#moving + 1] = { to = to, whole = l.stack }
            else
                l.stack.count = l.stack.count - l.count
                moving[#moving + 1] = { to = to, name = l.stack.name, count = l.count, metadata = copy(l.stack.metadata or {}) }
            end
        end
    end
    take(la, tb)
    take(lb, ta)

    -- 2. put it in (big things first so they find room)
    table.sort(moving, function(x, y)
        local dx = WLI.defs[x.whole and x.whole.name or x.name]
        local dy = WLI.defs[y.whole and y.whole.name or y.name]
        return dx.width * dx.height > dy.width * dy.height
    end)
    for _, m in ipairs(moving) do
        if m.whole then
            local s, d = m.whole, WLI.defs[m.whole.name]
            local placed = false
            for _, inv in ipairs(m.to) do
                if inv.kind == 'grid' and not bagCheck(d, inv, s.uid) and not weightCheck(inv, Inv.stackWeight(s)) then
                    local x, y, rotated = Grid.findSpot(inv, WLI.defs, d)
                    if x then
                        s.x, s.y, s.rotated, s.slot = x, y, rotated, nil
                        inv.items[s.uid] = s
                        placed = true
                        break
                    end
                end
            end
            if not placed then undo(); return false, string.format('not enough room for %s', d.label) end
        else
            local plan, err = planAdd(m.to, m.name, m.count, m.metadata)
            if not plan then undo(); return false, err end
            for _, mg in ipairs(plan.merges) do mg.stack.count = mg.stack.count + mg.n end
            for _, cr in ipairs(plan.creates) do cr.inv.items[cr.stack.uid] = cr.stack end
        end
    end

    -- 3. write the result: rows that changed or moved, rows that are gone
    local statements, changed = {}, {}
    local after = {}
    for _, inv in ipairs(involved) do
        for uid, s in pairs(inv.items) do
            after[uid] = true
            local old = before[inv.id][uid]
            if not old or not Grid.deepEqual(old, s) then
                statements[#statements + 1] = Store.upsert(s, inv.id)
                changed[inv.id] = true
            end
        end
    end
    for _, inv in ipairs(involved) do
        for uid in pairs(before[inv.id]) do
            if not after[uid] then
                statements[#statements + 1] = Store.delete(uid)
                changed[inv.id] = true
            end
        end
    end
    -- traded stacks leave the giver's hotbar
    for _, c in ipairs({ ca, cb }) do
        local cleared = false
        for i = 1, 8 do
            local uid = c.hotbar[i]
            if uid and not Inv.findOwn(c.source, uid) then c.hotbar[i] = false; cleared = true end
        end
        if cleared then exports.wasteland_players:SetCharacterData(c.id, 'hotbar', c.hotbar) end
    end
    Store.enqueue(statements, string.format('trade between characters %d and %d', ca.id, cb.id))
    WLI.Sync.changed(changed, a)
    WLI.Sync.player(b)
    return true
end

--- Auto-sort a grid the player can use (pockets, worn bag, an open stash,
--- trunk or drop): part stacks merge, then everything is packed by category.
function Inv.sort(src, invId)
    return Inv.run(src, 'sort', function()
        local inv, e = Inv.access(src, invId); if not inv then return nil, e end
        if inv.kind ~= 'grid' then return nil, 'only a grid can be sorted' end
        local plan = Grid.sortPlan(inv, WLI.defs)
        if not plan then return nil, 'there is not enough room to sort it' end
        local statements = {}
        for _, uid in ipairs(plan.remove) do
            inv.items[uid] = nil
            statements[#statements + 1] = Store.delete(uid)
        end
        for uid, p in pairs(plan.place) do
            local s = inv.items[uid]
            if s and (s.x ~= p.x or s.y ~= p.y or (s.rotated == true) ~= (p.rotated == true) or s.count ~= p.count) then
                s.x, s.y, s.rotated, s.count = p.x, p.y, p.rotated == true, p.count
                statements[#statements + 1] = Store.upsert(s, inv.id)
            end
        end
        -- hotbar slots of merged stacks follow the stack they went into
        local c = Inv.characterOf(src)
        if c and #plan.remove > 0 then
            local moved = false
            for i = 1, 8 do
                local to = c.hotbar[i] and plan.into[c.hotbar[i]]
                if to then c.hotbar[i] = to; moved = true end
            end
            if moved then exports.wasteland_players:SetCharacterData(c.id, 'hotbar', c.hotbar) end
        end
        return { statements = statements, changed = changedSet(inv.id) }
    end)
end

--- Take everything from a container (stash, trunk, body, drop) into the
--- pockets, then the worn bag: stackable items top up stacks, the rest
--- keep their condition. What does not fit stays. -> ok, err, taken, left
function Inv.takeAll(src, fromId)
    local taken, left = 0, 0
    local ok, err = Inv.run(src, 'take all', function()
        local from, e = Inv.access(src, fromId); if not from then return nil, e end
        local c = Inv.characterOf(src)
        local bag, vest = Inv.backpack(c), Inv.vest(c)
        if fromId == c.pockets or fromId == c.equip or (bag and fromId == 'item:' .. bag.uid) or (vest and fromId == 'item:' .. vest.uid) then
            return nil, 'that is already yours'
        end
        if from.kind ~= 'grid' then return nil, 'there is nothing to take' end
        local targets = Inv.targetsFor(src)
        if not targets then return nil, 'your inventory is still loading' end
        local list = {}
        for _, s in pairs(from.items) do if s.x ~= nil then list[#list + 1] = s end end
        -- biggest first, so they find room before small things fill it
        table.sort(list, function(a, b)
            local da, db = WLI.defs[a.name] or {}, WLI.defs[b.name] or {}
            local aa, ab = (da.width or 1) * (da.height or 1), (db.width or 1) * (db.height or 1)
            if aa ~= ab then return aa > ab end
            return a.uid < b.uid
        end)
        local statements, changed = {}, changedSet(from.id)
        for _, s in ipairs(list) do
            local d = WLI.defs[s.name]
            local plan = d and Inv.limitLeft(c, s.name) >= s.count and planAdd(targets, s.name, s.count, s.metadata) or nil
            if plan and d.stack <= 1 then
                -- one of a kind: the same stack moves (condition, bag contents)
                local cr = plan.creates[1]
                from.items[s.uid] = nil
                s.x, s.y, s.rotated, s.slot = cr.stack.x, cr.stack.y, cr.stack.rotated, nil
                cr.inv.items[s.uid] = s
                statements[#statements + 1] = Store.upsert(s, cr.inv.id)
                changed[cr.inv.id] = true
                taken = taken + 1
            elseif plan then
                for _, m in ipairs(plan.merges) do
                    m.stack.count = m.stack.count + m.n
                    statements[#statements + 1] = Store.upsert(m.stack, m.inv.id)
                    changed[m.inv.id] = true
                end
                for _, cr in ipairs(plan.creates) do
                    cr.inv.items[cr.stack.uid] = cr.stack
                    statements[#statements + 1] = Store.upsert(cr.stack, cr.inv.id)
                    changed[cr.inv.id] = true
                end
                from.items[s.uid] = nil
                statements[#statements + 1] = Store.delete(s.uid)
                taken = taken + 1
            else
                left = left + 1
            end
        end
        if taken == 0 then return nil, left > 0 and 'there is no room for any of it' or 'there is nothing to take' end
        return { statements = statements, changed = changed }
    end)
    return ok, err, taken, left
end

--- A stack the player carries (pockets, worn, worn bag): stack, inventoryId | nil
function Inv.findOwn(src, uid)
    local c = Inv.characterOf(src)
    if not c or not c.loaded or type(uid) ~= 'string' then return nil end
    for _, id in ipairs(Inv.ownInventories(c)) do
        local inv = WLI.invs[id]
        if inv and inv.items[uid] then return inv.items[uid], id end
    end
    return nil
end

--- Destroy one stack the player carries (an armor plate that broke).
function Inv.destroyOwn(src, uid)
    return Inv.run(src, 'destroy', function()
        local s, invId = Inv.findOwn(src, uid)
        if not s then return nil, 'that item is no longer in your inventory' end
        WLI.invs[invId].items[uid] = nil
        local c = Inv.characterOf(src)
        if c then for i = 1, 8 do if c.hotbar[i] == uid then c.hotbar[i] = nil end end end
        return { statements = { Store.delete(uid) }, changed = changedSet(invId) }
    end)
end

--- Merge `patch` into the metadata of a stack the player carries.
function Inv.setMetadata(src, uid, patch)
    if type(patch) ~= 'table' then return false, 'metadata patch must be a table' end
    return Inv.run(src, 'metadata', function()
        local s, invId = Inv.findOwn(src, uid)
        if not s then return nil, 'that item is no longer in your inventory' end
        s.metadata = s.metadata or {}
        for k, v in pairs(patch) do
            if type(k) ~= 'string' then return nil, 'metadata keys must be strings' end
            s.metadata[k] = v
        end
        return { statements = { Store.upsert(s, invId) }, changed = changedSet(invId) }
    end)
end

function Inv.useHotbar(src, index)
    local c = Inv.characterOf(src)
    if not c or not c.loaded then return false, 'your inventory is still loading' end
    local uid = c.hotbar[index]
    if not uid then return false, 'nothing is on that key' end
    for _, id in ipairs(Inv.ownInventories(c)) do
        local inv = WLI.invs[id]
        if inv and inv.items[uid] then
            -- A repair item asks what to repair: the inventory opens with a list.
            local d = WLI.defs[inv.items[uid].name]
            if d and d.repairs and WLI.usable[inv.items[uid].name] then
                TriggerClientEvent('wasteland:inventory:client:pickRepair', src, uid)
                return true
            end
            return Inv.use(src, uid, id)
        end
    end
    return false, 'that item is no longer in your inventory'
end

return Inv
