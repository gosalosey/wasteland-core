-- wasteland_events :: shared/rules.lua
-- Pure rules for world events (no natives; the random function is passed in).

WLEV = WLEV or {}
local Rules = {}
WLEV.Rules = Rules

local function dist2(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy
end

--- An event type by weight. types: map name -> { weight }; rnd(a, b) -> integer.
--- Names are sorted so the same roll always gives the same type.
function Rules.pickType(types, rnd)
    local names, total = {}, 0
    for name, t in pairs(types) do
        if (t.weight or 0) > 0 then names[#names + 1] = name; total = total + t.weight end
    end
    if total <= 0 then return nil end
    table.sort(names)
    local roll, acc = rnd(1, total), 0
    for _, name in ipairs(names) do
        acc = acc + types[name].weight
        if roll <= acc then return name end
    end
    return names[#names]
end

--- A point at least `minGap` metres from every running event and not inside
--- a safe zone. points: { { x, y, z, label } }; active: { { center } };
--- isSafe(point) -> boolean; rnd(n) -> 1..n
function Rules.pickPoint(points, active, minGap, isSafe, rnd)
    local free = {}
    for _, p in ipairs(points) do
        local ok = not isSafe(p)
        for _, e in ipairs(active) do
            if ok and dist2(p, e.center) < minGap * minGap then ok = false end
        end
        if ok then free[#free + 1] = p end
    end
    if #free == 0 then return nil end
    return free[rnd(#free)]
end

--- Spots around a centre when no player's game can find ground (fallback):
--- n points on a ring between rMin and rMax, at the centre's height.
function Rules.ring(center, n, rMin, rMax, rnd)
    local out = {}
    for i = 1, n do
        local a = (i / n) * math.pi * 2 + rnd() * 0.5
        local r = rMin + rnd() * (rMax - rMin)
        out[#out + 1] = { x = center.x + math.cos(a) * r, y = center.y + math.sin(a) * r, z = center.z }
    end
    return out
end

--- Is the event cleared? Every bandit dead, no event zombie still alive.
--- bandits: { { dead } }; zombiesAlive: number
function Rules.cleared(bandits, zombiesAlive)
    for _, b in ipairs(bandits) do if not b.dead then return false end end
    return zombiesAlive == 0
end

--- What stops the loot: "2 bandits and 5 zombies are still here." or nil.
function Rules.blockedText(banditsLeft, zombiesLeft)
    local parts = {}
    if banditsLeft > 0 then parts[#parts + 1] = banditsLeft .. (banditsLeft == 1 and ' bandit' or ' bandits') end
    if zombiesLeft > 0 then parts[#parts + 1] = zombiesLeft .. (zombiesLeft == 1 and ' zombie' or ' zombies') end
    if #parts == 0 then return nil end
    local total = banditsLeft + zombiesLeft
    return 'Too dangerous: ' .. table.concat(parts, ' and ') .. (total == 1 and ' is' or ' are') .. ' still here.'
end

return Rules
