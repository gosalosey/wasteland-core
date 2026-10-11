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
        expect(select(2, Rules.check('trunk', v, has, false, cfg))).toBe('It is locked.')
        expect(Rules.check('trunk', v, has, true, cfg)).toBe(true)
    end)
    it('parts survive a round trip through the database column', function()
        local p = Rules.decodeParts(Rules.encodeParts({ battery = true, engine = false, wheels = 3 }))
        expect(p.battery).toBe(true); expect(p.engine).toBe(false); expect(p.wheels).toBe(3)
        expect(Rules.decodeParts(nil).wheels).toBe(0)
    end)
    it('pumps: same key for everyone, refill on a timer up to full', function()
        expect(Rules.pumpKey({ x = 10.4, y = -3.6, z = 29.5 })).toBe('10_-4_30')
        local p = { litres = 80, refillLitres = 20, refillMinutes = 15, litresPerSecond = 4, vehicleDistance = 8 }
        local pump = { litres = 5, since = 0 }
        Rules.pumpLevel(pump, p, 14 * 60000)
        expect(pump.litres).toBe(5)
        expect(Rules.pumpWait(pump, p, 14 * 60000)).toBe(1)
        Rules.pumpLevel(pump, p, 31 * 60000)
        expect(pump.litres).toBe(45); expect(pump.since).toBe(30 * 60000)
        Rules.pumpLevel(pump, p, 200 * 60000)
        expect(pump.litres).toBe(80)
    end)
end)
