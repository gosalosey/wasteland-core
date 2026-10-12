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

function Grid.count(inv)
    local n = 0
    for _ in pairs(inv.items) do n = n + 1 end
    return n
end

return Grid
