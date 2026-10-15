-- Skill rules (wasteland_skills/shared/rules.lua) with the shipped config.

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_skills/shared/rules.lua', 't', env))()
local Rules = env.WLSK.Rules
local f = assert(io.open(RESOURCES .. '/wasteland_config/config/skills.lua', 'rb'))
local cfg = assert(load(f:read('a'), '@skills.lua', 't', {}))()
f:close()
local curve, max = cfg.xpCurve, cfg.maxLevel

describe('skill levels', function()
    it('100 XP to level 2, then each level needs more', function()
        expect(Rules.xpToNext(curve, 1)).toBe(100)
        expect(Rules.xpToNext(curve, 2)).toBe(283)
        expect(Rules.xpToNext(curve, 9) > Rules.xpToNext(curve, 8)).toBe(true)
    end)

    it('level and progress from total XP', function()
        local l, into, need = Rules.level(curve, max, 0)
        expect(l).toBe(1); expect(into).toBe(0); expect(need).toBe(100)
        l, into = Rules.level(curve, max, 150)
        expect(l).toBe(2); expect(into).toBe(50)
        l, into, need = Rules.level(curve, max, 1e9)
        expect(l).toBe(10); expect(need).toBe(0)
        expect(Rules.xpForLevel(curve, 10) > 10000 and Rules.xpForLevel(curve, 10) < 12000).toBe(true)
    end)

    it('bonuses: nothing at level 1, the full bonus at the top, even steps between', function()
        expect(Rules.bonus(0.3, 1, max)).toBe(0)
        expect(Rules.bonus(0.3, 10, max)).toBe(0.3)
        expect(math.abs(Rules.bonus(0.3, 4, max) - 0.1) < 1e-9).toBe(true)
        expect(Rules.bonus(nil, 10, max)).toBe(0)
    end)
end)

describe('skill death penalty', function()
    it('some: loses 10 % of the progress into the level, never the level itself', function()
        local start = Rules.xpForLevel(curve, 3)
        expect(Rules.afterDeath(curve, max, start + 200, { mode = 'some', percent = 10 })).toBe(start + 180)
        expect(Rules.afterDeath(curve, max, start, { mode = 'some', percent = 10 })).toBe(start)
        local all = Rules.afterDeath(curve, max, start + 1, { mode = 'some', percent = 100 })
        expect((Rules.level(curve, max, all))).toBe(3)
    end)

    it('none keeps everything; all starts over', function()
        expect(Rules.afterDeath(curve, max, 5000, { mode = 'none' })).toBe(5000)
        expect(Rules.afterDeath(curve, max, 5000, { mode = 'all' })).toBe(0)
    end)
end)
