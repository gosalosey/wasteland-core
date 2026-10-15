-- wasteland_skills :: shared/rules.lua
-- Pure rules (no natives): levels from XP, what a level is worth, the
-- death penalty. Unit-tested.

WLSK = WLSK or {}
local Rules = {}
WLSK.Rules = Rules

--- XP needed to go from `level` to `level + 1`.
function Rules.xpToNext(curve, level)
    return math.floor(curve.base * level ^ curve.growth + 0.5)
end

--- Total XP at which `level` starts (level 1 starts at 0).
function Rules.xpForLevel(curve, level)
    local total = 0
    for l = 1, level - 1 do total = total + Rules.xpToNext(curve, l) end
    return total
end

--- Level for a total XP, and the progress into it: level, into, needed.
--- At the top level, `needed` is 0.
function Rules.level(curve, maxLevel, xp)
    xp = math.max(0, xp or 0)
    local level, start = 1, 0
    while level < maxLevel do
        local step = Rules.xpToNext(curve, level)
        if xp < start + step then return level, xp - start, step end
        start = start + step
        level = level + 1
    end
    return maxLevel, xp - start, 0
end

--- What a bonus is worth at `level`: nothing at level 1, the full `max`
--- at the top level, evenly in between.
function Rules.bonus(max, level, maxLevel)
    if not max or maxLevel <= 1 then return 0 end
    local l = math.max(1, math.min(maxLevel, level))
    return max * (l - 1) / (maxLevel - 1)
end

--- XP left after dying. mode: 'none' (keep all), 'some' (lose `percent` of
--- the progress into the current level, never a level), 'all' (back to 0).
function Rules.afterDeath(curve, maxLevel, xp, penalty)
    local mode = penalty and penalty.mode or 'some'
    if mode == 'none' then return xp end
    if mode == 'all' then return 0 end
    local level, into = Rules.level(curve, maxLevel, xp)
    local start = Rules.xpForLevel(curve, level)
    local lose = math.floor(into * (penalty.percent or 10) / 100 + 0.5)
    return math.max(start, xp - lose)
end

--- A whole number of extra items from a fraction (0.5 at 1 -> sometimes 1).
--- roll in [0, 1).
function Rules.extra(base, fraction, roll)
    local want = (base or 0) * (fraction or 0)
    local whole = math.floor(want)
    if roll < want - whole then whole = whole + 1 end
    return whole
end

return Rules
