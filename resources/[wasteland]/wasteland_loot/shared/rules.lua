-- wasteland_loot :: shared/rules.lua
-- Pure rules (no natives): container keys, loot rolls, refills. Unit-tested.

WLL = WLL or {}
local Rules = {}
WLL.Rules = Rules

--- A world container is the same for everyone: its type and its position
--- rounded to a metre. Used as the stash name (letters, digits, _ and -).
function Rules.key(typeName, coords)
    local r = function(v) return math.floor(v + 0.5) end
    return string.format('loot_%s_%d_%d_%d', typeName, r(coords.x), r(coords.y), r(coords.z))
end

--- Stash name for a zombie body.
function Rules.bodyKey(uid)
    return 'loot_body_' .. tostring(uid):gsub('[^%w]', '')
end

--- Roll a loot table: list of { name, count } (empty = found nothing).
--- t = { emptyChance, rolls = { min, max }, items = { { name, min, max, weight } } }
--- rng(a, b) -> integer in [a, b]; roll() -> number in [0, 1).
function Rules.roll(t, rng, roll)
    if roll() < t.emptyChance or #t.items == 0 then return {} end
    local total = 0
    for _, it in ipairs(t.items) do total = total + it.weight end
    local out, byName = {}, {}
    for _ = 1, rng(t.rolls[1], t.rolls[2]) do
        local pick = rng(1, total)
        for _, it in ipairs(t.items) do
            pick = pick - it.weight
            if pick <= 0 then
                local count = rng(it.min, it.max)
                if byName[it.name] then
                    byName[it.name].count = byName[it.name].count + count
                else
                    byName[it.name] = { name = it.name, count = count }
                    out[#out + 1] = byName[it.name]
                end
                break
            end
        end
    end
    return out
end

--- Should a container get new loot now? Never filled: yes. Otherwise only
--- once it is empty and the refill time has passed since the last fill.
function Rules.needsFill(state, isEmpty, nowMs, refillMinutes)
    if not state or not state.filledAt then return true end
    return isEmpty and nowMs - state.filledAt >= refillMinutes * 60000
end

--- Minutes until a container refills (0 when it could refill now).
function Rules.minutesLeft(state, nowMs, refillMinutes)
    if not state or not state.filledAt then return 0 end
    return math.max(0, math.ceil((state.filledAt + refillMinutes * 60000 - nowMs) / 60000))
end

--- Model hash -> container type, for every type that has models.
--- hash(name) turns a model name into a hash.
function Rules.modelIndex(containers, hash)
    local out = {}
    for typeName, c in pairs(containers) do
        for _, m in ipairs(c.models or {}) do out[hash(m)] = typeName end
    end
    return out
end

--- How many trees a tree zone has: its own `trees`, or one per 2 m of radius.
function Rules.zoneTreeCount(zone)
    if zone.trees and zone.trees > 0 then return math.floor(zone.trees) end
    return math.max(10, math.floor(zone.radius / 2))
end

--- Where the trees of a zone stand: a list of { x, y, m } (m = which model,
--- 1..models). The same zone always gets the same trees (seeded from its
--- middle), at least `spacing` metres apart, inside the radius. Ground
--- height is found by the client.
function Rules.zoneTrees(zone, spacing, models)
    local seed = ((math.floor(zone.coords.x * 10) * 73856093) ~ (math.floor(zone.coords.y * 10) * 19349663)) & 0x7fffffff
    local function rand() -- LCG: does not touch math.random
        seed = (seed * 1103515245 + 12345) & 0x7fffffff
        return seed / 0x80000000
    end
    local want, out = Rules.zoneTreeCount(zone), {}
    local min2 = spacing * spacing
    for _ = 1, want * 40 do
        if #out >= want then break end
        local a, r = rand() * 2 * math.pi, zone.radius * math.sqrt(rand())
        local x, y = zone.coords.x + r * math.cos(a), zone.coords.y + r * math.sin(a)
        local free = true
        for _, t in ipairs(out) do
            if (t.x - x) ^ 2 + (t.y - y) ^ 2 < min2 then free = false; break end
        end
        if free then out[#out + 1] = { x = x, y = y, m = 1 + math.floor(rand() * math.max(1, models)) } end
    end
    return out
end

return Rules
