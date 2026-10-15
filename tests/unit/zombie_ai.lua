-- Zombie AI upgrade rules (wasteland_zombies/shared/ai.lua).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_zombies/shared/ai.lua', 't', env))()
local AI = env.WLZ.AI
local ai = AI.settings(nil)

local function uids(n)
    local out = {}
    for i = 1, n do out[i] = string.format('%08x%04x', 1700000000 + i * 7, i) end
    return out
end

describe('zombie ai: settings', function()
    it('uses the defaults for anything left out; the user\'s values on top', function()
        local s = AI.merge(AI.DEFAULTS, { personalities = { stalker = { weight = 0 } }, horde = { maxResponders = 4 } })
        expect(s.personalities.stalker.weight).toBe(0)
        expect(s.personalities.stalker.keepDistance[1]).toBe(12) -- kept
        expect(s.horde.maxResponders).toBe(4); expect(s.horde.spread).toBe(6)
        expect(s.enabled).toBe(true)
    end)

    it('a value of the wrong type keeps the default and is reported', function()
        local warnings = {}
        local s = AI.merge(AI.DEFAULTS, { horde = { maxResponders = 'lots' } }, warnings)
        expect(s.horde.maxResponders).toBe(15)
        expect(warnings[1]).toContain('horde.maxResponders')
    end)

    it('lists are replaced, not merged', function()
        local s = AI.merge(AI.DEFAULTS, { ambushPoints = { { x = 1.0, y = 2.0, z = 3.0 } } })
        expect(#s.ambushPoints).toBe(1)
    end)
end)

describe('zombie ai: who a zombie is', function()
    it('the same uid always gives the same roll, personality and special (every game agrees)', function()
        local u = '65a1b2c30001'
        expect(AI.roll(u, 'x')).toBe(AI.roll(u, 'x'))
        expect(AI.roll(u, 'x') ~= AI.roll(u, 'y')).toBe(true)
        expect(AI.personality(ai, u, 'day', 'day')).toBe(AI.personality(ai, u, 'day', 'day'))
        for _, id in ipairs(uids(50)) do
            local r = AI.roll(id, 'special')
            expect(r >= 0 and r < 1).toBe(true)
        end
    end)

    it('personalities follow their weights (and a weight of 0 is never picked)', function()
        local s = AI.merge(AI.DEFAULTS, { personalities = { sleeper = { weight = 0 } } })
        local counts = {}
        for _, id in ipairs(uids(2000)) do
            local p = AI.personality(s, id, 'day', 'day')
            counts[p] = (counts[p] or 0) + 1
        end
        expect(counts.sleeper).toBe(nil)
        -- wanderers are 45 of 90 by day: about half
        expect(counts.wanderer > 850 and counts.wanderer < 1150).toBe(true)
        expect(counts.pack > 200).toBe(true)
    end)

    it('more stalkers at night', function()
        local day, night = 0, 0
        for _, id in ipairs(uids(2000)) do
            if AI.personality(ai, id, 'day', 'day') == 'stalker' then day = day + 1 end
            if AI.personality(ai, id, 'night', 'night') == 'stalker' then night = night + 1 end
        end
        expect(night > day).toBe(true)
    end)

    it('specials are rare; bosses are off by default; specials can be switched off', function()
        local n, bosses = 0, 0
        for _, id in ipairs(uids(2000)) do
            local name, sp = AI.special(ai, id)
            if name then n = n + 1 end
            if sp and sp.boss then bosses = bosses + 1 end
        end
        expect(n > 100 and n < 400).toBe(true) -- 11 % in all
        expect(bosses).toBe(0)
        local off = AI.merge(AI.DEFAULTS, { specials = { enabled = false } })
        expect(AI.special(off, '65a1b2c30001')).toBe(nil)
        local all = AI.merge(AI.DEFAULTS, { specials = { spitter = { chance = 100 } } })
        local name = AI.special(all, '65a1b2c30002')
        expect(name ~= nil).toBe(true)
    end)
end)

describe('zombie ai: time of day', function()
    it('dawn, day, dusk and night (night wraps past midnight)', function()
        expect((AI.phase(ai, 6))).toBe('dawn')
        expect((AI.phase(ai, 12))).toBe('day')
        expect((AI.phase(ai, 20))).toBe('dusk')
        expect((AI.phase(ai, 23))).toBe('night')
        expect((AI.phase(ai, 2))).toBe('night')
        local _, night = AI.phase(ai, 2)
        expect(night.horde > 1).toBe(true)
    end)
end)

describe('zombie ai: senses', function()
    local s = ai.senses
    it('sees further in front, less to the side; runners are easier to see, still players harder', function()
        local front = AI.sightRange(s, { base = 70, inFront = true, speed = 1.5 })
        local side = AI.sightRange(s, { base = 70, inFront = false, speed = 1.5 })
        local still = AI.sightRange(s, { base = 70, inFront = true, speed = 0 })
        local run = AI.sightRange(s, { base = 70, inFront = true, speed = 6, sprinting = true })
        expect(front).toBe(70)
        expect(side < front).toBe(true); expect(still < front).toBe(true); expect(run > front).toBe(true)
    end)

    it('the view cone', function()
        local fwd = { x = 1, y = 0 }
        expect(AI.inFront(s, fwd, { x = 0, y = 0 }, { x = 10, y = 1 })).toBe(true)
        expect(AI.inFront(s, fwd, { x = 0, y = 0 }, { x = -10, y = 0 })).toBe(false)
    end)

    it('hearing: crouching is quiet, running loud, standing still silent, engines carry', function()
        local base = { walk = 18, crouch = 6, sprint = 45 }
        local function h(o) for k, v in pairs(base) do o[k] = v end; return AI.hearRange(s, o) end
        expect(h({})).toBe(18)
        expect(h({ crouching = true })).toBe(6)
        expect(h({ running = true })).toBe(45)
        expect(h({ still = true })).toBe(6)
        expect(h({ vehicle = true, vehicleMoving = true })).toBe(35) -- a moving engine (35) is louder than walking (18)
        expect(h({ still = true, vehicle = true })).toBe(21)          -- an idling engine: 60 % of 35
    end)
end)

describe('zombie ai: movement and memory', function()
    it('pack hunters take different sides of the target', function()
        local t = { x = 0, y = 0, z = 0 }
        local a, b = AI.packSlot(1, 2, t, 3.5, 0), AI.packSlot(2, 2, t, 3.5, 0)
        expect(math.floor(a.x + 0.5)).toBe(4); expect(math.floor(b.x - 0.5)).toBe(-4)
    end)

    it('stalkers keep their distance on their own side', function()
        local p = AI.stalkPoint({ x = 30, y = 0 }, { x = 0, y = 0, z = 0 }, 15, 0)
        expect(math.floor(p.x + 0.5)).toBe(15)
    end)

    it('a chase ends after too long or too far from where it began', function()
        local m = ai.memory
        local chase = { startedAt = 0, from = { x = 0, y = 0 } }
        expect(AI.giveUp(m, chase, 1000, { x = 10, y = 0 })).toBe(false)
        expect(AI.giveUp(m, chase, (m.maxChaseSeconds + 1) * 1000, { x = 10, y = 0 })).toBe(true)
        expect(AI.giveUp(m, chase, 1000, { x = m.maxChaseDistance + 5, y = 0 })).toBe(true)
    end)

    it('search points stay near the last known spot', function()
        for i = 1, 20 do
            local p = AI.searchPoint({ x = 100, y = 100, z = 0 }, 12, i / 21, (21 - i) / 21)
            local d = math.sqrt((p.x - 100) ^ 2 + (p.y - 100) ^ 2)
            expect(d <= 12.001).toBe(true)
        end
    end)

    it('isolated: nobody else near', function()
        expect(AI.isolated({ x = 0, y = 0 }, { { x = 100, y = 0 } }, 25)).toBe(true)
        expect(AI.isolated({ x = 0, y = 0 }, { { x = 10, y = 0 } }, 25)).toBe(false)
    end)
end)

describe('zombie ai: horde', function()
    it('only the nearest answer, up to the cap', function()
        local zs = {}
        for i = 1, 10 do zs[i] = { id = i, coords = { x = i * 10.0, y = 0, z = 0 } } end
        zs[11] = { id = 11, coords = { x = 1.0, y = 0, z = 0 }, dead = true }
        local ids = AI.responders(zs, { x = 0, y = 0, z = 0 }, 75, 3)
        expect(#ids).toBe(3); expect(ids[1]).toBe(1); expect(ids[3]).toBe(3)
        expect(#AI.responders(zs, { x = 0, y = 0, z = 0 }, 75)).toBe(7)
    end)

    it('the first goes to the noise, the others spread around it (no stacking)', function()
        local at = { x = 0, y = 0, z = 0 }
        local p0 = AI.spreadPoint(at, 0, 6)
        expect(p0.x).toBe(0); expect(p0.y).toBe(0)
        local seen = {}
        for slot = 1, 12 do
            local p = AI.spreadPoint(at, slot, 6)
            local key = string.format('%.1f:%.1f', p.x, p.y)
            expect(seen[key]).toBe(nil); seen[key] = true
        end
    end)

    it('repeated gunfire in one area reaches further, up to the cap, and fades', function()
        local h = ai.horde
        local history = {}
        local at = { x = 0, y = 0 }
        expect(AI.repeatScale(h, history, 0, at)).toBe(1)
        expect(AI.repeatScale(h, history, 1000, at)).toBe(1.25)
        for i = 2, 20 do AI.repeatScale(h, history, i * 100, at) end
        expect(AI.repeatScale(h, history, 3000, at)).toBe(2.5)
        expect(AI.repeatScale(h, history, 60000, at)).toBe(1) -- the window passed
        expect(AI.repeatScale(h, history, 60100, { x = 500, y = 0 })).toBe(1) -- somewhere else
    end)

    it('entry points and ambush points', function()
        local e = AI.entryFor({ { x = 0, y = 0, z = 0, radius = 15, entry = { x = 5, y = 5, z = 0 } } }, { x = 3, y = 0 })
        expect(e.x).toBe(5)
        expect(AI.entryFor({ { x = 0, y = 0, z = 0, radius = 15, entry = { x = 5, y = 5, z = 0 } } }, { x = 50, y = 0 })).toBe(nil)
        local p = AI.ambushPointFor({ { x = 0, y = 0, z = 0, radius = 40 }, { x = 30, y = 0, z = 0, radius = 40 } }, { x = 25, y = 0 })
        expect(p.x).toBe(30)
    end)

    it('a sound has a cooldown per 30 m spot', function()
        expect(AI.cooldownKey('gunshot', { x = 1, y = 1 })).toBe(AI.cooldownKey('gunshot', { x = 20, y = 20 }))
        expect(AI.cooldownKey('gunshot', { x = 1, y = 1 }) ~= AI.cooldownKey('gunshot', { x = 40, y = 1 })).toBe(true)
    end)
end)
