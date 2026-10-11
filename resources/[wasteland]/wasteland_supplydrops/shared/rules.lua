-- wasteland_supplydrops :: shared/rules.lua
-- Pure rules: no natives, no globals but the WLSD table, the random
-- function passed in. That keeps them easy to unit-test
-- (tests/unit/supplydrop_rules.lua).

WLSD = WLSD or {}
local Rules = {}
WLSD.Rules = Rules

local function dist2(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy
end

--- A spawn point at least `minGap` metres from every active drop, or nil.
--- points: list of { x, y, z, label }; active: list of { coords }; rnd(n) -> 1..n
function Rules.pickPoint(points, active, minGap, rnd)
    local free = {}
    for _, p in ipairs(points) do
        local ok = true
        for _, d in ipairs(active) do
            if dist2(p, d.coords) < minGap * minGap then ok = false; break end
        end
        if ok then free[#free + 1] = p end
    end
    if #free == 0 then return nil end
    return free[rnd(#free)]
end

--- Roll the crate contents from a weighted list (used when wasteland_loot
--- is not running). items: { { name, min, max, weight } }; rolls: { min, max }
--- rnd(a, b) -> integer a..b. Returns a list of { name, count } (merged).
function Rules.rollItems(items, rolls, rnd)
    local total = 0
    for _, it in ipairs(items) do total = total + it.weight end
    if total <= 0 then return {} end
    local counts, order = {}, {}
    for _ = 1, rnd(rolls[1], rolls[2]) do
        local pick, acc = rnd(1, total), 0
        for _, it in ipairs(items) do
            acc = acc + it.weight
            if pick <= acc then
                if not counts[it.name] then order[#order + 1] = it.name; counts[it.name] = 0 end
                counts[it.name] = counts[it.name] + rnd(it.min, it.max)
                break
            end
        end
    end
    local out = {}
    for _, name in ipairs(order) do out[#out + 1] = { name = name, count = counts[name] } end
    return out
end

--- Is it time for a new drop? (minutes since the last one, how many are out)
function Rules.due(sinceLastMs, intervalMinutes, active, maxActive, playersOnline, minPlayers)
    return sinceLastMs >= intervalMinutes * 60000 and active < maxActive and playersOnline >= minPlayers
end

return Rules
