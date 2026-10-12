-- Base rules (wasteland_bases/shared/rules.lua): the grid, claims, costs, upkeep.

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_bases/shared/rules.lua', 't', env))()
local Rules = env.WLB.Rules

local function near(a, b) return math.abs(a - b) < 1e-6 end

describe('base rules', function()
    local flag = { x = 100.0, y = 200.0, heading = 0.0 }

    it('local and world points go back and forth, also turned', function()
        local turned = { x = 10.0, y = -5.0, heading = 37.0 }
        local lx, ly = Rules.toLocal(turned, 14.0, 3.0)
        local x, y = Rules.toWorld(turned, lx, ly)
        expect(near(x, 14.0) and near(y, 3.0)).toBe(true)
        -- GTA headings: 90 faces west, so the flag's right is then north
        local rx, ry = Rules.toWorld({ x = 0, y = 0, heading = 90.0 }, 1.0, 0.0)
        expect(near(rx, 0.0) and near(ry, 1.0)).toBe(true)
    end)

    it('snaps to the nearest edge, or along the asked direction', function()
        local s = Rules.snapEdge(flag, 101.2, 200.3, 3.0)
        expect(s.key).toBe('0:0:0'); expect(near(s.x, 101.5) and near(s.y, 200.0)).toBe(true); expect(s.heading).toBe(0.0)
        local v = Rules.snapEdge(flag, 103.2, 201.0, 3.0)
        expect(v.key).toBe('1:0:1'); expect(near(v.x, 103.0) and near(v.y, 201.5)).toBe(true); expect(v.heading).toBe(90.0)
        local asked = Rules.snapEdge(flag, 101.2, 200.3, 3.0, 270)
        expect(asked.key).toBe('0:0:1'); expect(asked.heading).toBe(270.0)
        -- the same edge whichever way round
        expect(Rules.snapEdge(flag, 101.2, 200.3, 3.0, 180).key).toBe('0:0:0')
    end)

    it('snaps on a turned grid', function()
        local f = { x = 0.0, y = 0.0, heading = 90.0 }
        local s = Rules.snapEdge(f, -0.2, 1.4, 3.0, 0)
        expect(s.key).toBe('0:0:0'); expect(near(s.x, 0.0) and near(s.y, 1.5)).toBe(true); expect(s.heading).toBe(90.0)
    end)

    it('claims, costs, refunds', function()
        expect(Rules.inClaim(flag, 120.0, 200.0, 30.0)).toBe(true)
        expect(Rules.inClaim(flag, 131.0, 200.0, 30.0)).toBe(false)
        local have = { planks = 3, nails = 50 }
        local miss = Rules.missing({ { name = 'planks', count = 4 }, { name = 'nails', count = 10 } }, function(n) return have[n] end)
        expect(#miss).toBe(1); expect(miss[1].name).toBe('planks'); expect(miss[1].need).toBe(4)
        local back = Rules.refund({ { name = 'planks', count = 4 }, { name = 'tape', count = 1 } }, 0.5)
        expect(#back).toBe(1); expect(back[1].count).toBe(2)
    end)

    it('upkeep per day and its state', function()
        local u = { base = 1, perPieces = 10, perBlock = 1 }
        expect(Rules.upkeepPerDay(u, 0)).toBe(1)
        expect(Rules.upkeepPerDay(u, 10)).toBe(2)
        expect(Rules.upkeepPerDay(u, 11)).toBe(3)
        expect(Rules.upkeepState(1000, 999, 1)).toBe('paid')
        expect(Rules.upkeepState(1000, 1000, 1)).toBe('due')
        expect(Rules.upkeepState(1000, 4600, 1)).toBe('gone')
    end)

    it('no claims near camps or other bases', function()
        local cfg = { campDistance = 100.0, baseDistance = 150.0 }
        local ok, why = Rules.claimAllowed(0.0, 0.0, {}, { { x = 120.0, y = 0.0, radius = 30.0, label = 'Sandy camp' } }, cfg)
        expect(ok).toBe(false); expect(why).toBe('Too close to Sandy camp.')
        expect((Rules.claimAllowed(0.0, 0.0, { { x = 100.0, y = 0.0 } }, {}, cfg))).toBe(false)
        expect((Rules.claimAllowed(0.0, 0.0, { { x = 200.0, y = 0.0 } }, { { x = 200.0, y = 0.0, radius = 30.0 } }, cfg))).toBe(true)
    end)

    it('door parts swing round the hinge', function()
        local piece = { x = 10.0, y = 10.0, z = 5.0, heading = 0.0 }
        local x, y, z, h = Rules.partPosition(piece, { x = 0.0, y = 0.0, z = 1.0 }, 90.0, -0.6, 0.0)
        expect(near(x, 9.4) and near(y, 10.6) and near(z, 6.0)).toBe(true); expect(h).toBe(90.0)
        local cx = Rules.partPosition(piece, { x = 0.0 })
        expect(cx).toBe(10.0)
    end)
end)
