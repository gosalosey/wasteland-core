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

function Grid.count(inv)
    local n = 0
    for _ in pairs(inv.items) do n = n + 1 end
    return n
end

return Grid
