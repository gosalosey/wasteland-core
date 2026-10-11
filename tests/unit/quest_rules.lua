-- Quest rules (wasteland_quests/shared/rules.lua).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_quests/shared/rules.lua', 't', env))()
local Rules = env.WLQ.Rules

local q = { cooldownMinutes = 60, objectives = {
    { type = 'bring', item = 'scrap_metal', count = 5 },
    { type = 'kill', count = 3, near = { x = 0, y = 0, z = 0, radius = 100 } },
    { type = 'visit', coords = { x = 500, y = 0, z = 0 }, radius = 20, label = 'the tower' },
    { type = 'search', container = 'crate', count = 2 },
    { type = 'craft', recipe = 'bandage', count = 2 },
} }

describe('quest objectives', function()
    it('count kills near the place, searches of the right container, crafts and visits', function()
        local p = Rules.fresh(q)
        expect(Rules.apply(q, p, { type = 'kill', coords = { x = 50, y = 0, z = 0 } })).toBe(true)
        expect(Rules.apply(q, p, { type = 'kill', coords = { x = 500, y = 0, z = 0 } })).toBe(false) -- too far
        expect(Rules.apply(q, p, { type = 'search', container = 'bin' })).toBe(false)
        Rules.apply(q, p, { type = 'search', container = 'crate' })
        Rules.apply(q, p, { type = 'craft', recipe = 'bandage', count = 5 })
        expect(Rules.apply(q, p, { type = 'visit', coords = { x = 0, y = 0, z = 0 } })).toBe(false)
        Rules.apply(q, p, { type = 'visit', coords = { x = 510, y = 0, z = 0 } })
        expect(p[2]).toBe(1); expect(p[3]).toBe(1); expect(p[4]).toBe(1); expect(p[5]).toBe(2) -- capped
    end)
    it('bring counts what you carry; complete needs every line', function()
        local p = { 0, 3, 1, 2, 2 }
        local carry = { scrap_metal = 4 }
        expect(Rules.complete(q, p, function(n) return carry[n] end)).toBe(false)
        carry.scrap_metal = 9
        local have, n = Rules.objective(q, p, 1, function(x) return carry[x] end)
        expect(have).toBe(5); expect(n).toBe(5)
        expect(Rules.complete(q, p, function(x) return carry[x] end)).toBe(true)
    end)
    it('texts for the tracker', function()
        expect(Rules.text(q.objectives[1], 3, 5, 'Scrap metal')).toBe('Bring Scrap metal 3/5')
        expect(Rules.text(q.objectives[3], 0, 1)).toBe('Go to the tower')
        expect(Rules.text(q.objectives[3], 1, 1)).toBe('Go to the tower (done)')
        expect(Rules.text({ type = 'kill', count = 10 }, 7, 10)).toBe('Kill zombies 7/10')
    end)
end)

describe('quest status', function()
    local none = function() return 0 end
    it('available, active, ready, and cooldown after it was done', function()
        expect(Rules.status('a', q, { active = {}, done = {} }, 1000, none)).toBe('available')
        expect(Rules.status('a', q, { active = { a = { progress = Rules.fresh(q) } }, done = {} }, 1000, none)).toBe('active')
        local s, m = Rules.status('a', q, { active = {}, done = { a = 1000 } }, 1000 + 30 * 60, none)
        expect(s).toBe('cooldown'); expect(m).toBe(30)
        expect(Rules.status('a', q, { active = {}, done = { a = 1000 } }, 1000 + 61 * 60, none)).toBe('available')
    end)
end)
