-- wasteland_basebuilding :: shared/rules.lua
-- Pure rules (no game calls, unit-tested), loaded on server and client.

WLBB = WLBB or {}
local Rules = {}
WLBB.Rules = Rules

local WALL_LIKE = { 'wall', 'doorway', 'windowframe', 'halfwall' }

--- Which existing pieces a new piece snaps onto, and how:
---   edge  - around a foundation (or ceiling-to-ceiling), facing out
---   chain - left/right of another wall-type piece
---   top   - on top of an anchor (ceilings onto walls/frames)
---   exact - in the anchor's place (doors in doorways)
function Rules.snapRules()
    local r = {}
    for _, piece in ipairs(WALL_LIKE) do
        local rules = { { anchor = 'foundation', mode = 'edge' } }
        for _, other in ipairs(WALL_LIKE) do rules[#rules + 1] = { anchor = other, mode = 'chain' } end
        r[piece] = rules
    end
    r.foundation = { { anchor = 'foundation', mode = 'edge' } }
    r.frame = { { anchor = 'foundation', mode = 'edge' } }
    r.gateframe = { { anchor = 'foundation', mode = 'edge' } }
    r.ramp = { { anchor = 'foundation', mode = 'edge' } }
    r.ceiling = { { anchor = 'frame', mode = 'top' }, { anchor = 'ceiling', mode = 'edge' } }
    for _, piece in ipairs(WALL_LIKE) do r.ceiling[#r.ceiling + 1] = { anchor = piece, mode = 'top' } end
    r.door = { { anchor = 'doorway', mode = 'exact' } }
    r.gatedoor = { { anchor = 'gateframe', mode = 'exact' } }
    r.garagedoor = { { anchor = 'frame', mode = 'exact' } }
    return r
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end
Rules.dist = dist

--- The nearest cupboard whose radius covers `p` (list or map of { coords, radius }).
function Rules.covering(cupboards, p)
    local best, bestD = nil, nil
    for _, c in pairs(cupboards) do
        local d = dist(p, c.coords)
        if d <= c.radius and (not bestD or d < bestD) then best, bestD = c, d end
    end
    return best
end

--- What is missing to pay `cost` ({ item = count }): list of { item, need, have }.
function Rules.missing(cost, countOf)
    local out = {}
    local names = {}
    for item in pairs(cost or {}) do names[#names + 1] = item end
    table.sort(names)
    for _, item in ipairs(names) do
        local need, have = cost[item], countOf(item) or 0
        if have < need then out[#out + 1] = { item = item, need = need, have = have } end
    end
    return out
end

--- Refund of `cost` at `share` (rounded down, none of 0).
function Rules.refund(cost, share)
    local out = {}
    for item, n in pairs(cost or {}) do
        local r = math.floor(n * share)
        if r > 0 then out[item] = r end
    end
    return out
end

--- Upkeep for one tick. counts: { material = pieces }, perDay: { material = per piece per day },
--- fraction: share of a day this tick is, carry: { material = owed but not yet whole }.
--- -> owed { material = whole units now }, newCarry
--- (The fraction carries over, so a base pays what it owes per day, not a
--- whole unit every tick.)
function Rules.upkeepTick(counts, perDay, fraction, carry)
    local owed, out = {}, {}
    for material, n in pairs(counts) do
        local amount = n * (perDay[material] or 0) * fraction + ((carry or {})[material] or 0)
        local whole = math.floor(amount + 1e-9)
        owed[material] = whole
        out[material] = amount - whole
    end
    return owed, out
end

--- Hours of upkeep `have` covers at `daily` per day (nil: nothing to pay).
function Rules.hoursLeft(have, daily)
    if not daily or daily <= 0 then return nil end
    return have / daily * 24.0
end

--- "8x Wood planks, 1x Metal sheet" (labels via labelOf).
function Rules.costText(cost, labelOf)
    local names = {}
    for item in pairs(cost or {}) do names[#names + 1] = item end
    table.sort(names)
    local parts = {}
    for _, item in ipairs(names) do parts[#parts + 1] = cost[item] .. 'x ' .. (labelOf and labelOf(item) or item) end
    return table.concat(parts, ', ')
end

return Rules
