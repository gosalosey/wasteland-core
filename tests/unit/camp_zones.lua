-- Camp rules (wasteland_camps/shared/zones.lua).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_camps/shared/zones.lua', 't', env))()
local Zones = env.WLC.Zones

local camps = {
    { id = 'a', coords = { x = 0, y = 0, z = 0 }, radius = 50 },
    { id = 'b', coords = { x = 500, y = 0, z = 0 }, radius = 30, safe = false },
}

describe('camp zones', function()
    it('a point is in the camp whose circle it is inside (any height)', function()
        expect(Zones.campAt(camps, { x = 30, y = 30, z = 200 }).id).toBe('a')
        expect(Zones.campAt(camps, { x = 40, y = 40, z = 0 })).toBe(nil)
        expect(Zones.isSafe(camps, { x = 0, y = 0, z = 0 })).toBe(true)
        expect(Zones.isSafe(camps, { x = 500, y = 10, z = 0 })).toBe(false) -- a camp, but not safe
    end)
end)

describe('trade checks', function()
    local entry = { name = 'bandage', buy = 25, sell = 8 }
    it('buying needs stock and cash', function()
        expect(Zones.buyCheck(entry, 2, 10, 100)).toBe(50)
        expect(select(2, Zones.buyCheck(entry, 2, 1, 100))).toBe('Only 1 left.')
        expect(select(2, Zones.buyCheck(entry, 1, 0, 100))).toBe('Sold out. Come back later.')
        expect(select(2, Zones.buyCheck(entry, 5, 10, 100))).toBe('You need $125 (you have $100).')
        expect(select(2, Zones.buyCheck({ name = 'x', sell = 3 }, 1, 10, 100))).toBe('This trader does not sell that.')
    end)
    it('selling needs the items and a trader who buys them', function()
        expect(Zones.sellCheck(entry, 3, 5)).toBe(24)
        expect(select(2, Zones.sellCheck(entry, 6, 5))).toBe('You only have 5.')
        expect(select(2, Zones.sellCheck({ name = 'x', buy = 3 }, 1, 5))).toBe('This trader does not buy that.')
    end)
    it('restock refills up to the stock limit', function()
        local entries = { { name = 'a', stock = 10, restock = 3 }, { name = 'b', sell = 1 } }
        local cur = { a = 8 }
        Zones.restock(entries, cur)
        expect(cur.a).toBe(10)
        cur.a = 2
        Zones.restock(entries, cur)
        expect(cur.a).toBe(5)
        expect(cur.b).toBe(nil)
    end)
end)
