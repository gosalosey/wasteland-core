-- Survivor rules (wasteland_survivors/shared/rules.lua).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_survivors/shared/rules.lua', 't', env))()
local Rules = env.WLSV.Rules

local function seq(...)
    local list, i = { ... }, 0
    return function() i = i + 1; return list[(i - 1) % #list + 1] end
end

describe('survivor rules', function()
    it('picks by weight, numbers in a range', function()
        local list = { { n = 'a', weight = 3 }, { n = 'b', weight = 1 } }
        expect(Rules.pick(list, 0.7).n).toBe('a')
        expect(Rules.pick(list, 0.8).n).toBe('b')
        expect(Rules.between(2, 4, 0.0)).toBe(2)
        expect(Rules.between(2, 4, 0.999)).toBe(4)
        expect(Rules.between(3, 1, 0.5)).toBe(3)
    end)

    it('picks different entries, never more than there are', function()
        local list = { { n = 'a' }, { n = 'b' }, { n = 'c' } }
        local got = Rules.pickSome(list, 5, seq(0.0))
        expect(#got).toBe(3)
        expect(got[1].n .. got[2].n .. got[3].n).toBe('abc')
    end)

    it('own copies of trade offers, with how many times', function()
        local pool = { { give = { name = 'scrap_metal', count = 10 }, get = { name = 'ammo_12g', count = 6 }, times = 3 } }
        local o = Rules.offers(pool, 2, seq(0.0))
        expect(#o).toBe(1)
        expect(o[1].left).toBe(3)
        o[1].give.count = 1
        expect(pool[1].give.count).toBe(10)
    end)

    it('rewards and when help is enough', function()
        local r = Rules.reward({ { name = 'bandage', min = 1, max = 3 } }, 2, seq(0.0, 0.999))
        expect(#r).toBe(1); expect(r[1].name).toBe('bandage'); expect(r[1].count).toBe(3)
        expect(Rules.helped(1, 2)).toBe(false)
        expect(Rules.helped(2, 2)).toBe(true)
        expect(Rules.helped(nil, 1)).toBe(false)
    end)
end)
