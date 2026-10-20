-- wasteland_farming :: shared/rules.lua
-- Pure rules (no natives; unit-tested): growth stages, time left, one
-- growing tick (water used, plants grow only while watered).

WLF = WLF or {}
local Rules = {}
WLF.Rules = Rules

--- The stage of a plant: sprout (to 25%), young (to 60%), grown (to 100%), ripe.
function Rules.stage(growth, minutes)
    local p = (minutes or 0) > 0 and (growth or 0) / minutes or 1
    if p >= 1 then return 'ripe' end
    if p >= 0.6 then return 'grown' end
    if p >= 0.25 then return 'young' end
    return 'sprout'
end

--- Minutes of watered growing left until ripe (0 = ripe).
function Rules.minutesLeft(growth, minutes)
    return math.max(0, math.ceil((minutes or 0) - (growth or 0)))
end

--- Spot positions of a plot with `size` spots per side, in the plot's own
--- space (metres from its middle), the soil at 0.3 m.
function Rules.spots(size)
    local out = {}
    for i = 0, size - 1 do
        for j = 0, size - 1 do
            out[#out + 1] = { x = -size / 2 + 0.5 + i, y = -size / 2 + 0.5 + j, z = 0.3 }
        end
    end
    return out
end

--- One tick of `dtMinutes` for a plot { water, slots = { [i] = { crop, growth } | false } }.
--- rained: the plot is outdoors and it rains (water topped up to maxWater).
--- Returns true when a stage changed or water ran out / filled up (worth telling clients).
function Rules.tick(plot, crops, dtMinutes, rained, maxWater)
    local changed = false
    if rained and (plot.water or 0) < maxWater then
        plot.water = maxWater
        changed = true
    end
    local growing = false
    for _, s in pairs(plot.slots) do
        if s and crops[s.crop] and (s.growth or 0) < crops[s.crop].minutes then growing = true end
    end
    if not growing or (plot.water or 0) <= 0 then return changed end
    local dt = math.min(dtMinutes, plot.water)
    for _, s in pairs(plot.slots) do
        local c = s and crops[s.crop]
        if c and (s.growth or 0) < c.minutes then
            local before = Rules.stage(s.growth, c.minutes)
            s.growth = math.min(c.minutes, (s.growth or 0) + dt)
            if Rules.stage(s.growth, c.minutes) ~= before then changed = true end
        end
    end
    if not rained then
        plot.water = math.max(0, plot.water - dt)
        if plot.water <= 0 then changed = true end
    end
    return changed
end

return Rules
