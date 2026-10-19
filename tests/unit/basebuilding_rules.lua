-- Base building rules (wasteland_basebuilding/shared/rules.lua).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_basebuilding/shared/rules.lua', 't', env))()
local Rules = env.WLBB.Rules

describe('base building rules', function()
    it('snap rules: walls on foundations and next to each other, doors in doorways, ceilings on top', function()
        local r = Rules.snapRules()
        expect(r.wall[1].anchor).toBe('foundation'); expect(r.wall[1].mode).toBe('edge')
        local chains = 0
        for _, rule in ipairs(r.wall) do if rule.mode == 'chain' then chains = chains + 1 end end
        expect(chains).toBe(4)
        expect(r.door[1].anchor).toBe('doorway'); expect(r.door[1].mode).toBe('exact')
        expect(r.ceiling[1].mode).toBe('top')
    end)

    it('more floors: a ladder hatch snaps like a ceiling; stairs stand on foundations and ceilings', function()
        local r = Rules.snapRules()
        expect(#r.hatch).toBe(#r.ceiling)
        expect(r.hatch[1].anchor).toBe(r.ceiling[1].anchor)
        expect(r.stairs[1].anchor).toBe('foundation'); expect(r.stairs[1].mode).toBe('top')
        expect(r.stairs[2].anchor).toBe('ceiling'); expect(r.stairs[2].mode).toBe('top')
    end)

    it('the nearest cupboard covering a point', function()
        local list = { { id = 1, coords = { x = 0, y = 0, z = 0 }, radius = 40 }, { id = 2, coords = { x = 60, y = 0, z = 0 }, radius = 40 } }
        expect(Rules.covering(list, { x = 35, y = 0, z = 0 }).id).toBe(2)
        expect(Rules.covering(list, { x = 10, y = 0, z = 0 }).id).toBe(1)
        expect(Rules.covering(list, { x = 200, y = 0, z = 0 }) == nil).toBe(true)
    end)

    it('missing materials and refunds', function()
        local have = { wood_planks = 3 }
        local miss = Rules.missing({ wood_planks = 6, stone = 2 }, function(i) return have[i] end)
        expect(#miss).toBe(2); expect(miss[2].item).toBe('wood_planks'); expect(miss[2].have).toBe(3)
        local back = Rules.refund({ wood_planks = 5, scrap_metal = 1 }, 0.5)
        expect(back.wood_planks).toBe(2); expect(back.scrap_metal == nil).toBe(true)
    end)

    it('upkeep carries the part of a unit over (one piece costs 1 a day, not 1 a tick)', function()
        local carry, paid = nil, 0
        for _ = 1, 288 do -- a day of 5-minute ticks
            local owed
            owed, carry = Rules.upkeepTick({ wood = 1 }, { wood = 1 }, 5 / 1440, carry)
            paid = paid + owed.wood
        end
        expect(paid).toBe(1)
        expect(Rules.hoursLeft(12, 6)).toBe(48.0)
        expect(Rules.hoursLeft(5, 0) == nil).toBe(true)
    end)
end)
