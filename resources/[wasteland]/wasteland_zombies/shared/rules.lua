-- wasteland_zombies :: shared/rules.lua
-- Pure rules (no natives): how many zombies a player gets, walker or
-- runner, whether a spawn point is acceptable, what a hit does, who hears a
-- noise, what a zombie drops. Unit-tested.

WLZ = WLZ or {}
local Rules = {}
WLZ.Rules = Rules

local function dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
Rules.dist2d = dist2d

local function dist3d(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
Rules.dist3d = dist3d

--- Night: 21:00 - 05:59.
function Rules.isNight(hour)
    return hour ~= nil and (hour >= 21 or hour < 6)
end

--- Zombies wanted around one player.
function Rules.target(pop, night)
    local n = pop.perPlayer * (night and pop.nightMultiplier or 1)
    return math.floor(n + 0.5)
end

--- How many to spawn for a player who has `near` zombies around, with
--- `total` alive in the world. Never more than `pop.spawnBatch` at once.
function Rules.toSpawn(pop, night, near, total)
    local want = Rules.target(pop, night) - near
    local room = pop.maxTotal - total
    return math.max(0, math.min(want, room, pop.spawnBatch))
end

--- A kind name from a roll in [0, 1). Every kind but 'walker' has a chance
--- (percent; nightChance at night); kinds are tried in name order and
--- whatever is left is a walker.
function Rules.pickKind(kinds, night, roll)
    local names = {}
    for name in pairs(kinds) do if name ~= 'walker' then names[#names + 1] = name end end
    table.sort(names)
    local acc = 0
    for _, name in ipairs(names) do
        local k = kinds[name]
        acc = acc + ((night and k.nightChance or k.chance) or 0) / 100
        if roll < acc then return name end
    end
    return 'walker'
end

--- Sync check: which zombies the server has near a player that the
--- player's game does not show (missing), and which the game shows that the
--- server does not have (ghosts). expected, seen: lists of network ids.
function Rules.compareSync(expected, seen, known)
    local seenSet, missing, ghosts = {}, {}, {}
    for _, id in ipairs(seen) do seenSet[id] = true end
    for _, id in ipairs(expected) do if not seenSet[id] then missing[#missing + 1] = id end end
    for _, id in ipairs(seen) do if not known[id] then ghosts[#ghosts + 1] = id end end
    return missing, ghosts
end

--- The models a new zombie of `kind` may use: the kind's own list, else the
--- general list; without the ones no player's game has (missing).
function Rules.modelPool(kind, general, missing)
    local function usable(list)
        local out = {}
        for _, m in ipairs(list or {}) do if not missing[m] then out[#out + 1] = m end end
        return out
    end
    local own = usable(kind and kind.models)
    if #own > 0 then return own end
    return usable(general)
end

--- Is `point` a good place for a zombie for player `requester`? Not too
--- close to (or too far from) them, and not right next to anyone else.
--- players: list of { source, coords }
function Rules.validSpawn(pop, point, requester, players)
    if type(point) ~= 'table' or type(point.x) ~= 'number' or type(point.y) ~= 'number' or type(point.z) ~= 'number' then
        return false, 'not a point'
    end
    local d = dist2d(point, requester)
    if d < pop.spawnMin * 0.8 or d > pop.spawnMax * 1.2 then return false, 'outside the spawn ring' end
    for _, p in ipairs(players) do
        if p.coords and dist2d(point, p.coords) < pop.spawnMin * 0.8 then return false, 'too close to a player' end
    end
    return true
end

--- What a zombie hit does. rolls = { damage, infection, infectionAmount, bleeding } each in [0, 1).
function Rules.hit(kind, rolls)
    local lo, hi = kind.damage[1], kind.damage[2]
    local out = { damage = math.floor(lo + (hi - lo + 1) * rolls.damage), infection = 0, bleeding = 0 }
    if rolls.infection < kind.infectionChance then
        local ilo, ihi = kind.infection[1], kind.infection[2]
        out.infection = math.floor(ilo + (ihi - ilo + 1) * rolls.infectionAmount)
    end
    if rolls.bleeding < kind.bleedingChance then out.bleeding = 1 end
    return out
end

--- Zombies (list of { id, coords, dead }) within `radius` of `coords`.
function Rules.hearers(zombies, coords, radius)
    local out = {}
    if not coords or not radius or radius <= 0 then return out end
    for _, z in ipairs(zombies) do
        if not z.dead and z.coords and dist3d(z.coords, coords) <= radius then out[#out + 1] = z.id end
    end
    return out
end

--- Loot a dead zombie drops: list of { name, count }, or nil (nothing).
--- rng(a, b) -> integer in [a, b]; chanceRoll in [0, 1).
function Rules.loot(loot, chanceRoll, rng)
    if chanceRoll >= loot.chance or #loot.items == 0 then return nil end
    local total = 0
    for _, it in ipairs(loot.items) do total = total + it.weight end
    local pick = rng(1, total)
    for _, it in ipairs(loot.items) do
        pick = pick - it.weight
        if pick <= 0 then return { { name = it.name, count = rng(it.min, it.max) } } end
    end
    return nil
end

return Rules
