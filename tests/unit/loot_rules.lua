-- Loot rules (wasteland_loot/shared/rules.lua) with the shipped config.

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_loot/shared/rules.lua', 't', env))()
local Rules = env.WLL.Rules

local function shippedConfig()
    local f = assert(io.open(RESOURCES .. '/wasteland_config/config/loot.lua', 'rb'))
    local src = f:read('a'); f:close()
    return assert(load(src, '@loot.lua', 't', { math = math, vector3 = function(x, y, z) return { x = x, y = y, z = z } end }))()
end
local cfg = shippedConfig()

describe('loot containers', function()
    it('are the same for everyone: type and position rounded to a metre', function()
        expect(Rules.key('dumpster', { x = 100.4, y = -20.6, z = 30.49 })).toBe('loot_dumpster_100_-21_30')
        expect(Rules.key('dumpster', { x = 100.2, y = -21.1, z = 30.1 })).toBe('loot_dumpster_100_-21_30')
        expect(Rules.bodyKey('6a1f-00ff')).toBe('loot_body_6a1f00ff')
        expect(#Rules.key('vending', { x = -12345.5, y = -12345.5, z = -123.5 }) <= 56).toBe(true)
    end)
    it('fill when new; refill only when empty and the time has passed', function()
        expect(Rules.needsFill(nil, true, 0, 45)).toBe(true)
        local s = { filledAt = 1000 }
        expect(Rules.needsFill(s, false, 1000 + 46 * 60000, 45)).toBe(false) -- still has items
        expect(Rules.needsFill(s, true, 1000 + 44 * 60000, 45)).toBe(false)
        expect(Rules.needsFill(s, true, 1000 + 45 * 60000, 45)).toBe(true)
        expect(Rules.minutesLeft(s, 1000 + 30 * 60000, 45)).toBe(15)
    end)
    it('map every model to its container type', function()
        local idx = Rules.modelIndex(cfg.containers, function(n) return n end)
        expect(idx.prop_dumpster_01a).toBe('dumpster')
        expect(idx.prop_vend_soda_01).toBe('vending')
        expect(idx.prop_postbox_01a).toBe('mailbox')
    end)
end)

describe('loot tables', function()
    local seq = function(list) local i = 0; return function() i = i + 1; return list[i] end end
    it('sometimes give nothing (scarce)', function()
        expect(#Rules.roll(cfg.tables.trash, function(a) return a end, function() return 0.1 end)).toBe(0)
    end)
    it('pick weighted items; repeated picks of one item add up', function()
        local items = Rules.roll(cfg.tables.trash, function(a, b) return a end, function() return 0.9 end)
        expect(#items).toBe(1); expect(items[1].name).toBe('scrap_metal'); expect(items[1].count).toBe(1)
        local both = Rules.roll({ emptyChance = 0, rolls = { 2, 2 }, items = { { name = 'a', min = 2, max = 2, weight = 1 } } },
            function(a, b) return b end, function() return 0.5 end)
        expect(#both).toBe(1); expect(both[1].count).toBe(4)
    end)
    it('rare items are rare: guns about 1 in 100 picks from crates', function()
        local guns, n = 0, 4000
        math.randomseed(42)
        for _ = 1, n do
            for _, it in ipairs(Rules.roll(cfg.tables.crate, math.random, math.random)) do
                if it.name == 'weapon_pistol' then guns = guns + 1 end
            end
        end
        expect(guns > 0 and guns < n * 0.03).toBe(true)
    end)
end)

describe('tree zones', function()
    local zone = { coords = { x = 1385.98, y = 3406.79, z = 45.9 }, radius = 75 }

    it('one tree per 2 m of radius unless the zone says how many', function()
        expect(Rules.zoneTreeCount(zone)).toBe(37)
        expect(Rules.zoneTreeCount({ radius = 50, trees = 12 })).toBe(12)
    end)

    it('trees stand inside the zone, apart from each other, the same every time', function()
        local a, b = Rules.zoneTrees(zone, 6, 4), Rules.zoneTrees(zone, 6, 4)
        expect(#a).toBe(37)
        for i, t in ipairs(a) do
            expect(t.x).toBe(b[i].x); expect(t.m).toBe(b[i].m)
            expect((t.x - zone.coords.x) ^ 2 + (t.y - zone.coords.y) ^ 2 <= 75 * 75).toBe(true)
            expect(t.m >= 1 and t.m <= 4).toBe(true)
            for j = i + 1, #a do expect((t.x - a[j].x) ^ 2 + (t.y - a[j].y) ^ 2 >= 36).toBe(true) end
        end
    end)

    it('shipped zones: 50-100 m, enough trees, models and a wood table', function()
        local tz = cfg.treeZones
        expect(#tz.zones >= 7).toBe(true)
        for _, z in ipairs(tz.zones) do
            expect(z.radius >= 50 and z.radius <= 100).toBe(true)
            expect(#Rules.zoneTrees(z, tz.spacing, #tz.models) >= 25).toBe(true)
        end
        expect(tz.respawnMinutes).toBe(60)
        expect(cfg.tables[tz.table] ~= nil).toBe(true)
    end)

    it('shipped rock zones: 50-100 m, enough rocks, a pickaxe, stone', function()
        local rz = cfg.rockZones
        expect(#rz.zones >= 4).toBe(true)
        for _, z in ipairs(rz.zones) do
            expect(z.radius >= 50 and z.radius <= 100).toBe(true)
            expect(#Rules.zoneTrees(z, rz.spacing, #rz.models) >= 25).toBe(true)
        end
        expect(rz.tools[1]).toBe('pickaxe')
        expect(cfg.tables[rz.table].items[1].name).toBe('stone')
    end)
end)
