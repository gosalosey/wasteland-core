-- wasteland_vehicles :: shared/rules.lua
-- Pure rules (no natives): wrecks, what a vehicle needs to run, fuel use,
-- and what each action needs. Unit-tested.
--
-- Vehicle state: { fuel (litres), engine, body (GTA health 0-1000),
--   parts = { battery = bool, engine = bool, wheels = 0-4 }, lockCode, locked }

WLVE = WLVE or {}
local Rules = {}
WLVE.Rules = Rules

--- A new wreck: parts randomly missing, little fuel, damaged.
--- w = config.wreck; rng(a, b) integer; roll() in [0, 1).
function Rules.wreck(w, rng, roll)
    local wheels = 4
    if roll() < w.wheelsMissingChance then wheels = 4 - rng(1, w.wheelsMissingMax) end
    return {
        fuel = rng(w.fuel[1], w.fuel[2]),
        engine = rng(w.engine[1], w.engine[2]),
        body = rng(w.body[1], w.body[2]),
        parts = { battery = roll() >= w.batteryMissing, engine = roll() >= w.engineMissing, wheels = wheels },
        locked = false,
    }
end

--- Can the engine start? Returns true or false, reason.
function Rules.canRun(v)
    local p = v.parts or {}
    if not p.engine then return false, 'The engine parts are missing.' end
    if not p.battery then return false, 'There is no battery.' end
    if (v.engine or 0) <= 100 then return false, 'The engine is wrecked. Repair it with a toolkit.' end
    if (v.fuel or 0) <= 0 then return false, 'The tank is empty.' end
    if (p.wheels or 0) < 4 then return false, string.format('It has %d of 4 wheels.', p.wheels or 0) end
    return true
end

--- Fuel used (litres) over `seconds` at `kmh` with the engine running.
--- f = { idlePerMinute, per100km }
function Rules.fuelUsed(f, kmh, seconds)
    return f.idlePerMinute * seconds / 60 + f.per100km * (kmh * seconds / 3600) / 100
end

--- What an action needs and whether it can be done now.
--- action: battery | engine | wheel | refuel | repair | fitLock | toggleLock | pickLock | trunk
--- has(item) -> true if the player carries it; key = player holds this vehicle's key.
--- Returns item to use (or true) or nil, reason.
function Rules.check(action, v, has, key, cfg)
    local p = v.parts
    if action == 'battery' then
        if p.battery then return nil, 'It already has a battery.' end
        return has('car_battery') and 'car_battery' or nil, 'You need a car battery.'
    elseif action == 'engine' then
        if p.engine then return nil, 'The engine parts are already there.' end
        return has('engine_parts') and 'engine_parts' or nil, 'You need engine parts.'
    elseif action == 'wheel' then
        if p.wheels >= 4 then return nil, 'All four wheels are on.' end
        return has('car_wheel') and 'car_wheel' or nil, 'You need a wheel.'
    elseif action == 'refuel' then
        if v.fuel >= cfg.tankLitres - 0.5 then return nil, 'The tank is full.' end
        return has('jerry_can') and 'jerry_can' or nil, 'You need a jerry can with fuel.'
    elseif action == 'repair' then
        if v.engine >= 990 and v.body >= 990 then return nil, 'It does not need repairs.' end
        return has('vehicle_repair_kit') and 'vehicle_repair_kit' or nil, 'You need a toolkit.'
    elseif action == 'fitLock' then
        if v.lockCode then return nil, 'It already has a lock.' end
        return has('vehicle_lock') and 'vehicle_lock' or nil, 'You need a car lock.'
    elseif action == 'toggleLock' then
        if not v.lockCode then return nil, 'It has no lock.' end
        return key and true or nil, 'You do not have the key.'
    elseif action == 'pickLock' then
        if not v.lockCode or not v.locked then return nil, 'It is not locked.' end
        if key then return nil, 'You have the key.' end
        return has('lockpick') and 'lockpick' or nil, 'You need a lockpick.'
    elseif action == 'trunk' then
        if v.locked and not key then return nil, 'It is locked.' end
        return true
    end
    return nil, 'Unknown action.'
end

--- A gas pump is the same for everyone: its position rounded to a metre.
function Rules.pumpKey(coords)
    local r = function(v) return math.floor(v + 0.5) end
    return string.format('%d_%d_%d', r(coords.x), r(coords.y), r(coords.z))
end

--- A pump's fuel now: refills `refillLitres` every `refillMinutes` since
--- it was last topped up, up to `litres`. Mutates and returns the pump.
--- pump = { litres, since }   p = config.pump
function Rules.pumpLevel(pump, p, nowMs)
    local step = p.refillMinutes * 60000
    if pump.litres >= p.litres then
        pump.litres, pump.since = p.litres, nowMs
        return pump
    end
    local steps = math.floor((nowMs - pump.since) / step)
    if steps > 0 then
        pump.litres = math.min(p.litres, pump.litres + steps * p.refillLitres)
        pump.since = pump.since + steps * step
    end
    return pump
end

--- Minutes until a dry pump has fuel again.
function Rules.pumpWait(pump, p, nowMs)
    return math.max(1, math.ceil((pump.since + p.refillMinutes * 60000 - nowMs) / 60000))
end

--- Encode / decode the parts column.
function Rules.encodeParts(p)
    return string.format('{"battery":%s,"engine":%s,"wheels":%d}', p.battery and 'true' or 'false', p.engine and 'true' or 'false', p.wheels or 0)
end

function Rules.decodeParts(s)
    local out = { battery = false, engine = false, wheels = 0 }
    if type(s) ~= 'string' then return out end
    out.battery = s:find('"battery":true', 1, true) ~= nil
    out.engine = s:find('"engine":true', 1, true) ~= nil
    out.wheels = tonumber(s:match('"wheels":(%d+)')) or 0
    return out
end

return Rules
