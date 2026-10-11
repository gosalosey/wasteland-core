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

--- 'walker' or 'runner' from a roll in [0, 1).
function Rules.pickKind(kinds, night, roll)
    local runner = (night and kinds.runner.nightChance or kinds.runner.chance) / 100
    return roll < runner and 'runner' or 'walker'
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
