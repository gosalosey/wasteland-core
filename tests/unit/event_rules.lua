-- World event rules (wasteland_events/shared/rules.lua).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_events/shared/rules.lua', 't', env))()
local Rules = env.WLEV.Rules

describe('world event rules', function()
    it('picks a type by weight (zero weight never)', function()
        local types = { horde = { weight = 1 }, helicrash = { weight = 3 }, off = { weight = 0 } }
        expect(Rules.pickType(types, function() return 1 end)).toBe('helicrash')  -- helicrash 1-3, horde 4
        expect(Rules.pickType(types, function() return 4 end)).toBe('horde')
        expect(Rules.pickType({ off = { weight = 0 } }, function() return 1 end) == nil).toBe(true)
    end)

    it('picks a point away from other events and out of camps', function()
        local points = { { x = 0, y = 0, label = 'A' }, { x = 2000, y = 0, label = 'B' }, { x = 5000, y = 0, label = 'C' } }
        local safe = function(p) return p.label == 'C' end
        local p = Rules.pickPoint(points, { { center = { x = 100, y = 0 } } }, 800, safe, function() return 1 end)
        expect(p.label).toBe('B')
        expect(Rules.pickPoint(points, { { center = { x = 0, y = 0 } }, { center = { x = 2000, y = 0 } } }, 800, safe, function() return 1 end) == nil).toBe(true)
    end)

    it('spreads fallback spots on a ring', function()
        local spots = Rules.ring({ x = 0, y = 0, z = 10 }, 6, 10, 20, function() return 0.5 end)
        expect(#spots).toBe(6)
        for _, s in ipairs(spots) do
            local d = math.sqrt(s.x * s.x + s.y * s.y)
            expect(d >= 10 and d <= 20).toBe(true)
            expect(s.z).toBe(10)
        end
    end)

    it('is cleared only when every bandit is dead and no event zombie is left', function()
        expect(Rules.cleared({ { dead = true }, { dead = true } }, 0)).toBe(true)
        expect(Rules.cleared({ { dead = true }, { dead = false } }, 0)).toBe(false)
        expect(Rules.cleared({}, 2)).toBe(false)
    end)

    it('says what still blocks the loot', function()
        expect(Rules.blockedText(2, 5)).toBe('Too dangerous: 2 bandits and 5 zombies are still here.')
        expect(Rules.blockedText(1, 0)).toBe('Too dangerous: 1 bandit is still here.')
        expect(Rules.blockedText(0, 1)).toBe('Too dangerous: 1 zombie is still here.')
        expect(Rules.blockedText(0, 0) == nil).toBe(true)
    end)
end)
