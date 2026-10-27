-- Vehicle rules (wasteland_vehicles/shared/rules.lua).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_vehicles/shared/rules.lua', 't', env))()
local Rules = env.WLVE.Rules

local cfg = { tankLitres = 50 }
local full = { fuel = 20, engine = 800, body = 800, parts = { battery = true, engine = true, wheels = 4 } }

describe('vehicle rules', function()
    it('a vehicle runs only with every part, fuel and a working engine', function()
        expect(Rules.canRun(full)).toBe(true)
        expect(select(2, Rules.canRun({ fuel = 20, engine = 800, parts = { battery = false, engine = true, wheels = 4 } }))).toBe('There is no battery.')
        expect(select(2, Rules.canRun({ fuel = 0, engine = 800, parts = full.parts }))).toBe('The tank is empty.')
        expect(select(2, Rules.canRun({ fuel = 5, engine = 50, parts = full.parts }))).toContain('wrecked')
        expect(select(2, Rules.canRun({ fuel = 5, engine = 800, parts = { battery = true, engine = true, wheels = 3 } }))).toBe('It has 3 of 4 wheels.')
    end)
    it('wrecks miss parts by chance', function()
        local w = { batteryMissing = 0.6, engineMissing = 0.5, wheelsMissingChance = 0.4, wheelsMissingMax = 2,
            fuel = { 0, 8 }, engine = { 250, 700 }, body = { 300, 800 } }
        local seq = { 0.1, 0.7, 0.3 } -- wheels missing, battery there, engine missing
        local i = 0
        local v = Rules.wreck(w, function(a, b) return b end, function() i = i + 1; return seq[i] end)
        expect(v.parts.wheels).toBe(2); expect(v.parts.battery).toBe(true); expect(v.parts.engine).toBe(false)
        expect(v.fuel).toBe(8); expect(v.engine).toBe(700)
    end)
    it('fuel: idle use plus distance', function()
        local f = { idlePerMinute = 0.06, per100km = 14 }
        expect(math.abs(Rules.fuelUsed(f, 0, 60) - 0.06) < 1e-9).toBe(true)
        expect(math.abs(Rules.fuelUsed(f, 100, 3600) - (3.6 + 14)) < 1e-9).toBe(true)
    end)
    it('actions need the right item, and only when it makes sense', function()
        local wreck = { fuel = 0, engine = 500, body = 500, parts = { battery = false, engine = true, wheels = 3 } }
        local carry = { car_battery = true }
        local has = function(i) return carry[i] == true end
        expect(Rules.check('battery', wreck, has, false, cfg)).toBe('car_battery')
        expect(select(2, Rules.check('engine', wreck, has, false, cfg))).toBe('The engine parts are already there.')
        expect(select(2, Rules.check('wheel', wreck, has, false, cfg))).toBe('You need a wheel.')
        expect(select(2, Rules.check('repair', full, has, false, cfg))).toBe('You need a toolkit.')
        expect(select(2, Rules.check('refuel', { fuel = 50, parts = full.parts }, has, false, cfg))).toBe('The tank is full.')
    end)
    it('siphoning needs fuel, a hose and a jerry can with room', function()
        local carry = {}
        local has = function(i) return carry[i] == true end
        local v = { fuel = 10, engine = 900, body = 900, parts = full.parts }
        expect(select(2, Rules.check('siphon', { fuel = 0.2, parts = full.parts }, has, false, cfg))).toBe('The tank is empty.')
        expect(select(2, Rules.check('siphon', v, has, false, cfg))).toBe('You need a siphon hose.')
        carry.siphon_hose = true
        expect(select(2, Rules.check('siphon', v, has, false, cfg))).toBe('You need a jerry can that is not full.')
        carry.jerry_can_space = true
        expect(Rules.check('siphon', v, has, false, cfg)).toBe('siphon_hose')
    end)
    it('locks: fit, key, pick, trunk', function()
        local carry = { vehicle_lock = true, lockpick = true }
        local has = function(i) return carry[i] == true end
        local v = { fuel = 5, engine = 900, body = 900, parts = full.parts }
        expect(Rules.check('fitLock', v, has, false, cfg)).toBe('vehicle_lock')
        expect(select(2, Rules.check('toggleLock', v, has, false, cfg))).toBe('It has no lock.')
        v.lockCode, v.locked = 'abc', true
        expect(select(2, Rules.check('fitLock', v, has, false, cfg))).toBe('It already has a lock.')
        expect(Rules.check('toggleLock', v, has, true, cfg)).toBe(true)
        expect(select(2, Rules.check('toggleLock', v, has, false, cfg))).toBe('You do not have the key.')
        expect(Rules.check('pickLock', v, has, false, cfg)).toBe('lockpick')
        expect(select(2, Rules.check('pickLock', v, has, true, cfg))).toBe('You have the key.')
        expect(Rules.check('removeLock', v, has, true, cfg, true)).toBe(true)
        expect(select(2, Rules.check('removeLock', v, has, true, cfg, false))).toBe('Only the survivor who fitted this lock can take it off.')
        expect(select(2, Rules.check('removeLock', { parts = full.parts }, has, false, cfg, true))).toBe('It has no lock.')
        expect(select(2, Rules.check('trunk', v, has, false, cfg))).toBe('It is locked.')
        expect(Rules.check('trunk', v, has, true, cfg)).toBe(true)
    end)
    it('parts survive a round trip through the database column', function()
        local p = Rules.decodeParts(Rules.encodeParts({ battery = true, engine = false, wheels = 3 }))
        expect(p.battery).toBe(true); expect(p.engine).toBe(false); expect(p.wheels).toBe(3)
        expect(Rules.decodeParts(nil).wheels).toBe(0)
    end)
    it('pumps: same key for everyone; full again 2 hours after fuel was first taken', function()
        expect(Rules.pumpKey({ x = 10.4, y = -3.6, z = 29.5 })).toBe('10_-4_30')
        local p = { litres = 80, refillMinutes = 120 }
        local pump = { litres = 80 }
        expect(Rules.pumpWait(pump, p, 0)).toBe(0) -- full
        expect(Rules.pumpTake(pump, p, 50, 0)).toBe(50)
        expect(pump.litres).toBe(30); expect(Rules.pumpWait(pump, p, 0)).toBe(120)
        expect(Rules.pumpTake(pump, p, 50, 60 * 60000)).toBe(30) -- only what is left; the clock is not restarted
        expect(Rules.pumpWait(pump, p, 60 * 60000)).toBe(60)
        expect(Rules.pumpTake(pump, p, 5, 90 * 60000)).toBe(0)
        Rules.pumpLevel(pump, p, 120 * 60000)
        expect(pump.litres).toBe(80); expect(Rules.pumpWait(pump, p, 120 * 60000)).toBe(0)
        expect(Rules.duration(84)).toBe('1 h 24 min'); expect(Rules.duration(120)).toBe('2 h'); expect(Rules.duration(45)).toBe('45 min')
    end)
end)

describe('vehicle part condition', function()
    it('old vehicles get conditions: fitted parts 100%, missing 0%', function()
        local v = { parts = { battery = true, engine = false, wheels = 3 } }
        local c = Rules.cond(v)
        expect(c.battery).toBe(100); expect(c.engine).toBe(0)
        expect(c.tyres[3]).toBe(100); expect(c.tyres[4]).toBe(0)
    end)

    it('worn out engine parts or a dead battery: no start', function()
        local v = { fuel = 10, engine = 800, parts = { battery = true, engine = true, wheels = 4, cond = { engine = 0, battery = 50, tyres = { 100, 100, 100, 100 } } } }
        expect(select(2, Rules.canRun(v))).toContain('worn out')
        v.parts.cond.engine, v.parts.cond.battery = 40, 0
        expect(select(2, Rules.canRun(v))).toContain('battery is dead')
    end)

    it('driving wears the fitted parts by distance', function()
        local v = { parts = { battery = true, engine = true, wheels = 4 } }
        local w = { enginePartsPer100km = 10, batteryPer100km = 4, tyresPer100km = 20 }
        expect(Rules.wear(v, 50, w)).toBe(false)
        expect(v.parts.cond.engine).toBe(95); expect(v.parts.cond.battery).toBe(98); expect(v.parts.cond.tyres[2]).toBe(90)
        expect(Rules.wear(v, 1000, w)).toBe(true)
        expect(v.parts.cond.engine).toBe(0)
    end)

    it('repairing one part needs a toolkit and stops at the cap', function()
        local yes = function() return true end
        local v = { parts = { battery = true, engine = true, wheels = 4, cond = { engine = 70, battery = 85, tyres = { 10, 100, 100, 100 } } } }
        local c = { partRepair = { cap = 80 } }
        expect(Rules.check('repairPart', v, yes, false, c, false, 'tyre1')).toBe('vehicle_repair_kit')
        expect(select(2, Rules.check('repairPart', v, yes, false, c, false, 'battery'))).toContain('80%')
        expect(select(2, Rules.check('repairPart', v, yes, false, c, false, 'nonsense'))).toBe('Repair what?')
        expect(Rules.check('battery', v, yes, false, c)).toBe('car_battery')
        expect(Rules.check('wheel', v, yes, false, c, false, 'tyre1')).toBe('car_wheel')
        expect(select(2, Rules.check('wheel', v, yes, false, c, false, 'tyre2'))).toBe('All four wheels are on.')
        expect(Rules.worstTyre(v)).toBe(1)
    end)

    it('conditions are saved and loaded with the parts', function()
        local p = Rules.decodeParts(Rules.encodeParts({ battery = true, engine = true, wheels = 4,
            cond = { engine = 61.25, battery = 0, tyres = { 100, 55.5, 0, 12 } } }))
        expect(p.cond.engine).toBe(61.3); expect(p.cond.battery).toBe(0); expect(p.cond.tyres[2]).toBe(55.5); expect(p.cond.tyres[4]).toBe(12)
        expect(Rules.decodeParts('{"battery":true,"engine":true,"wheels":4}').cond).toBe(nil)
    end)
end)

describe('motorbikes (two wheels)', function()
    local bike = { wheelsMax = 2, fuel = 10, engine = 800, body = 800, parts = { battery = true, engine = true, wheels = 2 } }
    it('runs on two wheels; one missing stops it', function()
        expect(Rules.canRun(bike)).toBe(true)
        local one = { wheelsMax = 2, fuel = 10, engine = 800, parts = { battery = true, engine = true, wheels = 1 } }
        expect(select(2, Rules.canRun(one))).toBe('It has 1 of 2 wheels.')
    end)
    it('a bike wreck never has more than two wheels', function()
        local w = { batteryMissing = 0, engineMissing = 0, wheelsMissingChance = 1, wheelsMissingMax = 2,
            fuel = { 0, 8 }, engine = { 250, 700 }, body = { 300, 800 } }
        for _ = 1, 20 do
            local v = Rules.wreck(w, math.random, math.random, 2)
            expect(v.parts.wheels <= 1).toBe(true)
        end
        local whole = Rules.wreck({ batteryMissing = 0, engineMissing = 0, wheelsMissingChance = 0, wheelsMissingMax = 2,
            fuel = { 0, 8 }, engine = { 250, 700 }, body = { 300, 800 } }, math.random, math.random, 2)
        expect(whole.parts.wheels).toBe(2)
    end)
    it('wheels: "both are on", no third wheel, tyres named front and rear', function()
        local has = function() return true end
        local v = { wheelsMax = 2, fuel = 10, engine = 800, body = 800, parts = { battery = true, engine = true, wheels = 2 } }
        expect(select(2, Rules.check('wheel', v, has, false, cfg))).toBe('Both wheels are on.')
        expect(select(2, Rules.check('repairPart', v, has, false, cfg, false, 'tyre3'))).toBe('There is no wheel there.')
        expect(Rules.tyreName(v, 2)).toBe('rear')
        expect(Rules.tyreName({}, 2)).toBe('front right')
        Rules.wear(v, 100, { enginePartsPer100km = 0, batteryPer100km = 0, tyresPer100km = 15 })
        expect(v.parts.cond.tyres[1]).toBe(85); expect(v.parts.cond.tyres[3]).toBe(0)
    end)
end)
