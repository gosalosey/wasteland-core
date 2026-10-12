-- wasteland_bases :: shared/rules.lua
-- Pure rules (no game calls, unit-tested): the base grid, claims, costs and
-- upkeep. Loaded on the server and the client, so the placement preview
-- snaps exactly like the server checks.
--
-- Every base has a flag at (x, y) with a heading. Wall pieces sit on the
-- edges of a square grid laid out from the flag and turned with it. An edge
-- is named "i:j:o": o = 0 for an edge along the grid's x axis (from cell
-- corner (i, j) to (i + 1, j)), o = 1 for one along y ((i, j) to (i, j + 1)).

WLB = WLB or {}
local Rules = {}
WLB.Rules = Rules

local function round(v) return math.floor(v + 0.5) end

local function rad(heading) return math.rad(heading or 0.0) end

--- World point -> the flag's grid (metres along the flag's right and forward).
function Rules.toLocal(flag, x, y)
    local dx, dy = x - flag.x, y - flag.y
    local a = rad(flag.heading)
    local c, s = math.cos(a), math.sin(a)
    return dx * c + dy * s, -dx * s + dy * c
end

--- The flag's grid -> world point.
function Rules.toWorld(flag, lx, ly)
    local a = rad(flag.heading)
    local c, s = math.cos(a), math.sin(a)
    return flag.x + lx * c - ly * s, flag.y + lx * s + ly * c
end

--- A heading in [0, 360).
function Rules.heading(h)
    h = (tonumber(h) or 0.0) % 360.0
    if h < 0 then h = h + 360.0 end
    return h
end

--- The edge nearest to a world point.
--- turn: 0 / 90 / 180 / 270, the piece's turn on the grid (90 / 270 put it
--- along y; 180 / 270 turn it round, e.g. which way a door opens). nil picks
--- the nearer of the two directions.
--- -> { key, lx, ly, x, y, heading, turn }
function Rules.snapEdge(flag, x, y, grid, turn)
    local lx, ly = Rules.toLocal(flag, x, y)
    -- along x: corner row j = round(ly / grid), cell i = floor(lx / grid)
    local ax = { i = math.floor(lx / grid), j = round(ly / grid), o = 0 }
    ax.lx, ax.ly = (ax.i + 0.5) * grid, ax.j * grid
    -- along y
    local ay = { i = round(lx / grid), j = math.floor(ly / grid), o = 1 }
    ay.lx, ay.ly = ay.i * grid, (ay.j + 0.5) * grid
    local pick
    if turn ~= nil then
        turn = round(Rules.heading(turn) / 90) % 4 * 90
        pick = (turn == 90 or turn == 270) and ay or ax
    else
        local dx = (lx - ax.lx) ^ 2 + (ly - ax.ly) ^ 2
        local dy = (lx - ay.lx) ^ 2 + (ly - ay.ly) ^ 2
        pick = dx <= dy and ax or ay
        turn = pick.o == 1 and 90 or 0
    end
    local wx, wy = Rules.toWorld(flag, pick.lx, pick.ly)
    return { key = string.format('%d:%d:%d', pick.i, pick.j, pick.o), lx = pick.lx, ly = pick.ly, x = wx, y = wy,
        heading = Rules.heading((flag.heading or 0.0) + turn), turn = turn }
end

--- Is a world point inside the flag's claim?
function Rules.inClaim(flag, x, y, radius)
    return (x - flag.x) ^ 2 + (y - flag.y) ^ 2 <= radius * radius
end

--- What is missing to pay a cost: list of { name, need, have } (empty = can pay).
--- cost: list of { name, count }; times: how many (default 1).
function Rules.missing(cost, countOf, times)
    local out = {}
    for _, c in ipairs(cost or {}) do
        local need = c.count * (times or 1)
        local have = countOf(c.name) or 0
        if have < need then out[#out + 1] = { name = c.name, need = need, have = have } end
    end
    return out
end

--- What demolishing gives back: list of { name, count } (rounded down, none of 0).
function Rules.refund(cost, fraction)
    local out = {}
    for _, c in ipairs(cost or {}) do
        local n = math.floor(c.count * (fraction or 0))
        if n > 0 then out[#out + 1] = { name = c.name, count = n } end
    end
    return out
end

--- Upkeep for one day: base + per started block of `perPieces` pieces.
function Rules.upkeepPerDay(upkeep, pieces)
    return upkeep.base + math.ceil((pieces or 0) / upkeep.perPieces) * upkeep.perBlock
end

--- Upkeep state at time `now` (seconds):
--- 'paid' (nothing due), 'due' (take a day's upkeep now), 'decaying'
--- (unpaid for less than decayHours) or 'gone' (remove the base).
function Rules.upkeepState(paidUntil, now, decayHours)
    if now < paidUntil then return 'paid' end
    if now >= paidUntil + decayHours * 3600 then return 'gone' end
    return 'due'
end

--- Is a claim allowed here? others: list of { x, y } flags; camps: list of
--- { x, y, radius }. -> true | false, reason
function Rules.claimAllowed(x, y, others, camps, cfg)
    for _, c in ipairs(camps or {}) do
        local keep = (c.radius or 0) + cfg.campDistance
        if (x - c.x) ^ 2 + (y - c.y) ^ 2 < keep * keep then
            return false, 'Too close to ' .. (c.label or 'a camp') .. '.'
        end
    end
    for _, o in ipairs(others or {}) do
        if (x - o.x) ^ 2 + (y - o.y) ^ 2 < cfg.baseDistance * cfg.baseDistance then
            return false, 'Too close to another base.'
        end
    end
    return true
end

--- Where a part sits for a piece at (x, y, z, heading): part offsets are in
--- the piece's own frame (x right, y forward, z up). angle: extra turn of
--- the part about (hingeX, hingeY) (open doors). -> x, y, z, heading
function Rules.partPosition(piece, part, angle, hingeX, hingeY)
    local px, py, rz = part.x or 0.0, part.y or 0.0, part.rz or 0.0
    if angle and angle ~= 0 then
        local a = math.rad(angle)
        local hx, hy = hingeX or 0.0, hingeY or 0.0
        local dx, dy = px - hx, py - hy
        px = hx + dx * math.cos(a) - dy * math.sin(a)
        py = hy + dx * math.sin(a) + dy * math.cos(a)
        rz = rz + angle
    end
    local a = math.rad(piece.heading or 0.0)
    local c, s = math.cos(a), math.sin(a)
    return piece.x + px * c - py * s, piece.y + px * s + py * c, piece.z + (part.z or 0.0), Rules.heading((piece.heading or 0.0) + rz)
end

return Rules
