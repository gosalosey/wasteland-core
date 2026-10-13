-- wasteland_inventory :: shared/grid.lua
-- Pure grid logic (no natives, no state): footprints, collision, finding
-- free space, weights and stack compatibility. Used by the server (which
-- decides) and mirrored by the UI (which only previews).
--
-- Coordinates are 0-based cells: x = column, y = row. An item of width w
-- and height h at (x, y) covers columns x..x+w-1 and rows y..y+h-1;
-- `rotated` swaps w and h.
--
-- inventory = { width, height, maxWeight, items = { [uid] = stack } }
-- stack     = { uid, name, count, x, y, rotated, metadata }

WLI = WLI or {}
WLI.Grid = WLI.Grid or {}
local Grid = WLI.Grid

function Grid.footprint(def, rotated)
    if rotated then return def.height, def.width end
    return def.width, def.height
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

--- Can `def` be placed at (x, y)? ignoreUid: the stack being moved.
--- Returns true or false, reason ('outside' | 'overlap'), blockingUid.
function Grid.fits(inv, defs, def, x, y, rotated, ignoreUid)
    local w, h = Grid.footprint(def, rotated)
    if math.type(x) ~= 'integer' or math.type(y) ~= 'integer' then return false, 'outside' end
    if x < 0 or y < 0 or x + w > inv.width or y + h > inv.height then return false, 'outside' end
    for uid, s in pairs(inv.items) do
        if uid ~= ignoreUid and s.x ~= nil then
            local sd = defs[s.name]
            local sw, sh = Grid.footprint(sd or { width = 1, height = 1 }, s.rotated)
            if overlaps(x, y, w, h, s.x, s.y, sw, sh) then return false, 'overlap', uid end
        end
    end
    return true
end

--- First free position, row by row; tries unrotated, then rotated.
--- Returns x, y, rotated or nil.
function Grid.findSpot(inv, defs, def, ignoreUid)
    for _, rotated in ipairs({ false, true }) do
        if not rotated or def.width ~= def.height then
            local w, h = Grid.footprint(def, rotated)
            for y = 0, inv.height - h do
                for x = 0, inv.width - w do
                    if Grid.fits(inv, defs, def, x, y, rotated, ignoreUid) then return x, y, rotated end
                end
            end
        end
    end
    return nil
end

--- Weight of the stacks themselves (kg). Container contents are added by
--- the caller (Grid has no access to other inventories).
function Grid.weight(inv, defs, ignoreUid)
    local total = 0
    for uid, s in pairs(inv.items) do
        if uid ~= ignoreUid then
            local d = defs[s.name]
            if d then total = total + d.weight * s.count end
        end
    end
    return total
end

function Grid.deepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not Grid.deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

--- Can stack `a` merge into stack `b`?
function Grid.canMerge(a, b, defs)
    if a.uid == b.uid or a.name ~= b.name then return false end
    local d = defs[a.name]
    if not d or d.stack <= 1 then return false end
    return Grid.deepEqual(a.metadata or {}, b.metadata or {})
end

--- Pocket size from what is worn: base + the bonus of every worn slot,
--- at most max. pockets = { width, height, maxWidth, maxHeight, bonus = { [slot] = { width, height } } };
--- worn: map of stacks with .slot. -> width, height
function Grid.pocketSize(pockets, worn, ignoreUid)
    local w, h = pockets.width, pockets.height
    for uid, s in pairs(worn or {}) do
        local b = s.slot and pockets.bonus and pockets.bonus[s.slot]
        if b and (s.uid or uid) ~= ignoreUid then w, h = w + (b.width or 0), h + (b.height or 0) end
    end
    return math.min(w, pockets.maxWidth or w), math.min(h, pockets.maxHeight or h)
end

--- Fit every stack of `inv` into a width x height grid: stacks already
--- inside stay put, the others get the first free spot (biggest first).
--- fixed: optional { [uid] = stack } placed first and never moved.
--- Returns moves = { [uid] = { x, y, rotated } }, overflow = { uid... }.
function Grid.repack(inv, defs, width, height, fixed)
    local test = { width = width, height = height, items = {} }
    local moves, overflow, rest = {}, {}, {}
    for uid, s in pairs(fixed or {}) do test.items[uid] = s end
    for uid, s in pairs(inv.items) do
        if not (fixed and fixed[uid]) and s.x ~= nil then
            local d = defs[s.name] or { width = 1, height = 1 }
            local w, h = Grid.footprint(d, s.rotated)
            local inside = s.x + w <= width and s.y + h <= height
            if inside and Grid.fits(test, defs, d, s.x, s.y, s.rotated) then test.items[uid] = s
            else rest[#rest + 1] = s end
        end
    end
    table.sort(rest, function(a, b)
        local da, db = defs[a.name] or { width = 1, height = 1 }, defs[b.name] or { width = 1, height = 1 }
        if da.width * da.height ~= db.width * db.height then return da.width * da.height > db.width * db.height end
        return a.uid < b.uid
    end)
    for _, s in ipairs(rest) do
        local d = defs[s.name] or { width = 1, height = 1 }
        local x, y, rotated = Grid.findSpot(test, defs, d)
        if x then
            moves[s.uid] = { x = x, y = y, rotated = rotated }
            test.items[s.uid] = { uid = s.uid, name = s.name, x = x, y = y, rotated = rotated }
        else
            overflow[#overflow + 1] = s.uid
        end
    end
    return moves, overflow
end

-- Order of item categories when sorting (others after these, by name).
Grid.SORT_ORDER = { 'weapon', 'ammo', 'medical', 'food', 'drink', 'tool', 'material', 'clothing', 'armor', 'container', 'misc' }

--- Auto-sort: merge part stacks of the same item (same metadata), then pack
--- everything from the top left, grouped by category, biggest first.
--- -> plan = { place = { [uid] = { x, y, rotated, count } }, remove = { uid... }, into = { [removed uid] = kept uid } }
---    or nil when it would not all fit (then nothing changes).
function Grid.sortPlan(inv, defs)
    local rank = {}
    for i, c in ipairs(Grid.SORT_ORDER) do rank[c] = i end
    -- 1. merge stackable stacks
    local groups, order = {}, {}
    for _, s in pairs(inv.items) do
        if s.x ~= nil then
            local d = defs[s.name] or { stack = 1 }
            local key = nil
            if (d.stack or 1) > 1 then
                for _, g in ipairs(order) do
                    if g.name == s.name and Grid.deepEqual(g.metadata or {}, s.metadata or {}) then key = g end
                end
            end
            if key then
                key.total = key.total + s.count
                key.uids[#key.uids + 1] = s.uid
            else
                local g = { name = s.name, metadata = s.metadata, total = s.count, uids = { s.uid }, stack = d.stack or 1 }
                order[#order + 1] = g
                groups[#groups + 1] = g
            end
        end
    end
    local stacks, remove, into = {}, {}, {}
    for _, g in ipairs(groups) do
        table.sort(g.uids)
        local left = g.total
        for _, uid in ipairs(g.uids) do
            if left > 0 then
                local n = math.min(left, g.stack)
                stacks[#stacks + 1] = { uid = uid, name = g.name, count = n }
                left = left - n
            else
                remove[#remove + 1] = uid
                into[uid] = g.uids[1]
            end
        end
    end
    -- 2. order: category, then bigger first, then name
    table.sort(stacks, function(a, b)
        local da, db = defs[a.name] or { width = 1, height = 1 }, defs[b.name] or { width = 1, height = 1 }
        local ra, rb = rank[da.category] or 99, rank[db.category] or 99
        if ra ~= rb then return ra < rb end
        local aa, ab = (da.width or 1) * (da.height or 1), (db.width or 1) * (db.height or 1)
        if aa ~= ab then return aa > ab end
        if (da.label or a.name) ~= (db.label or b.name) then return (da.label or a.name) < (db.label or b.name) end
        return a.uid < b.uid
    end)
    -- 3. pack
    local test = { width = inv.width, height = inv.height, items = {} }
    local place = {}
    for _, st in ipairs(stacks) do
        local d = defs[st.name] or { width = 1, height = 1 }
        local x, y, rotated = Grid.findSpot(test, defs, d)
        if not x then return nil end
        test.items[st.uid] = { uid = st.uid, name = st.name, x = x, y = y, rotated = rotated }
        place[st.uid] = { x = x, y = y, rotated = rotated, count = st.count }
    end
    return { place = place, remove = remove, into = into }
end

function Grid.count(inv)
    local n = 0
    for _ in pairs(inv.items) do n = n + 1 end
    return n
end

return Grid
