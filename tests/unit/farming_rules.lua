-- Farming rules (wasteland_farming/shared/rules.lua).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_farming/shared/rules.lua', 't', env))()
local Rules = env.WLF.Rules
local CROPS = { lettuce = { minutes = 20 } }

describe('farming rules', function()
    it('stages by growth', function()
        expect(Rules.stage(0, 20)).toBe('sprout')
        expect(Rules.stage(5, 20)).toBe('young')
        expect(Rules.stage(12, 20)).toBe('grown')
        expect(Rules.stage(20, 20)).toBe('ripe')
        expect(Rules.minutesLeft(12, 20)).toBe(8)
        expect(Rules.minutesLeft(30, 20)).toBe(0)
    end)

    it('spots: 1, 4 and 9 in a grid round the middle', function()
        expect(#Rules.spots(1)).toBe(1)
        expect(#Rules.spots(2)).toBe(4)
        local s3 = Rules.spots(3)
        expect(#s3).toBe(9)
        expect(s3[1].x).toBe(-1); expect(s3[5].x).toBe(0); expect(s3[9].y).toBe(1)
    end)

    it('plants grow only while watered; water is used; rain fills it', function()
        local plot = { water = 0, slots = { { crop = 'lettuce', growth = 0 } } }
        Rules.tick(plot, CROPS, 1, false, 180)
        expect(plot.slots[1].growth).toBe(0)                -- dry: no growth
        plot.water = 3
        Rules.tick(plot, CROPS, 1, false, 180)
        expect(plot.slots[1].growth).toBe(1); expect(plot.water).toBe(2)
        local changed = Rules.tick(plot, CROPS, 5, true, 180)   -- rain
        expect(plot.water).toBe(180); expect(plot.slots[1].growth).toBe(6); expect(changed).toBe(true)
        Rules.tick(plot, CROPS, 30, false, 180)
        expect(plot.slots[1].growth).toBe(20)               -- ripe, capped
        local w = plot.water
        Rules.tick(plot, CROPS, 1, false, 180)
        expect(plot.water).toBe(w)                          -- nothing growing: no water used
    end)
end)
