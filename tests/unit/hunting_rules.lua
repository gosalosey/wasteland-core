-- Hunting rules (wasteland_hunting/shared/rules.lua).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_hunting/shared/rules.lua', 't', env))()
local Rules = env.WLH.Rules

describe('hunting rules', function()
    it('picks animals by weight', function()
        local list = { { label = 'Deer', weight = 3 }, { label = 'Rabbit', weight = 1 } }
        expect(Rules.pick(list, 0.0).label).toBe('Deer')
        expect(Rules.pick(list, 0.74).label).toBe('Deer')
        expect(Rules.pick(list, 0.76).label).toBe('Rabbit')
        expect(Rules.pick({}, 0.5) == nil).toBe(true)
    end)

    it('meat and pelts from an animal, or from any other animal', function()
        local deer = { meat = { 2, 4 }, pelt = 1 }
        local lo, pelt = Rules.yield(deer, { 1, 2 }, 0.0)
        expect(lo).toBe(2); expect(pelt).toBe(1)
        expect((Rules.yield(deer, { 1, 2 }, 0.999))).toBe(4)
        local m, p = Rules.yield(nil, { 1, 2 }, 0.6)
        expect(m).toBe(2); expect(p).toBe(0)
    end)

    it('how many to cook', function()
        expect(Rules.cookCount(5, 3, 50)).toBe(3)
        expect(Rules.cookCount(0, 3, 50)).toBe(1)
        expect(Rules.cookCount(10, 20, 4)).toBe(4)
        expect(Rules.cookCount(2, 0, 50)).toBe(0)
    end)

    it('in front of the player', function()
        local x, y = Rules.inFront(0, 0, 0, 2)
        expect(math.abs(x) < 1e-9 and math.abs(y - 2) < 1e-9).toBe(true)
        x, y = Rules.inFront(0, 0, 90, 2) -- GTA: 90 faces west
        expect(math.abs(x + 2) < 1e-9 and math.abs(y) < 1e-9).toBe(true)
    end)
end)
