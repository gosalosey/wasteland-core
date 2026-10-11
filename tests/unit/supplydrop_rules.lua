-- Supply drop rules (wasteland_supplydrops/shared/rules.lua): pure
-- functions, tested with a fake random function. A good place to start
-- when you write tests for your own module.

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_supplydrops/shared/rules.lua', 't', env))()
local Rules = env.WLSD.Rules

describe('supply drop rules', function()
    local points = { { x = 0, y = 0, z = 0, label = 'A' }, { x = 1000, y = 0, z = 0, label = 'B' }, { x = 100, y = 0, z = 0, label = 'C' } }

    it('picks a point far enough from the drops that are out', function()
        local p = Rules.pickPoint(points, { { coords = { x = 0, y = 0 } } }, 300, function() return 1 end)
        expect(p.label).toBe('B') -- A and C are within 300 m of the drop
        local none = Rules.pickPoint(points, { { coords = { x = 0, y = 0 } }, { coords = { x = 1000, y = 0 } } }, 300, function() return 1 end)
        expect(none == nil).toBe(true)
    end)

    it('rolls weighted items and merges repeats', function()
        local items = { { name = 'ammo', min = 5, max = 5, weight = 3 }, { name = 'bandage', min = 1, max = 1, weight = 1 } }
        local seq = { 3, 1, 5, 2, 5, 4, 1 } -- rolls = 3, then pick / amount pairs
        local i = 0
        local rnd = function(a, b) i = i + 1; return math.max(a, math.min(b, seq[i])) end
        local out = Rules.rollItems(items, { 3, 3 }, rnd)
        expect(#out).toBe(2)
        expect(out[1].name).toBe('ammo'); expect(out[1].count).toBe(10)
        expect(out[2].name).toBe('bandage'); expect(out[2].count).toBe(1)
        expect(#Rules.rollItems({}, { 1, 1 }, rnd)).toBe(0)
    end)

    it('is due after the interval, with room and enough players', function()
        expect(Rules.due(46 * 60000, 45, 0, 1, 2, 1)).toBe(true)
        expect(Rules.due(44 * 60000, 45, 0, 1, 2, 1)).toBe(false)
        expect(Rules.due(46 * 60000, 45, 1, 1, 2, 1)).toBe(false)
        expect(Rules.due(46 * 60000, 45, 0, 1, 0, 1)).toBe(false)
    end)
end)
