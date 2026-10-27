-- wasteland_vehicles :: shared/rules.lua
-- Pure rules (no natives): wrecks, what a vehicle needs to run, fuel use,
-- and what each action needs. Unit-tested.
--
-- Vehicle state: { fuel (litres), engine, body (GTA health 0-1000),
--   parts = { battery = bool, engine = bool, wheels = 0-4,
--             cond = { engine = 0-100, battery = 0-100, tyres = { 0-100 x4 } } }, lockCode, locked }
-- cond: condition of each part in %. Tyres by position (1 front left, 2 front
-- right, 3 rear left, 4 rear right; a motorbike: 1 front, 2 rear); positions
-- above `wheels` have no wheel. v.wheelsMax: 4 (cars) or 2 (motorbikes).
-- Engine parts or battery at 0: the engine will not start. A tyre at 0 is flat.

WLVE = WLVE or {}
local Rules = {}
WLVE.Rules = Rules

--- How many wheels this vehicle has when complete: 4, or 2 for a motorbike.
function Rules.wheelsMax(v) return (v and v.wheelsMax) or 4 end

--- A new wreck: parts randomly missing, little fuel, damaged.
--- w = config.wreck; rng(a, b) integer; roll() in [0, 1); max = wheels when complete (4, or 2 for a bike).
function Rules.wreck(w, rng, roll, max)
    max = max or 4
    local wheels = max
    if roll() < w.wheelsMissingChance then wheels = max - rng(1, math.min(w.wheelsMissingMax, max)) end
    local c = w.condition or { 25, 85 }
    local parts = { battery = roll() >= w.batteryMissing, engine = roll() >= w.engineMissing, wheels = wheels }
    parts.cond = { engine = parts.engine and rng(c[1], c[2]) or 0, battery = parts.battery and rng(c[1], c[2]) or 0, tyres = {} }
    for i = 1, 4 do parts.cond.tyres[i] = i <= wheels and rng(c[1], c[2]) or 0 end
    return {
        fuel = rng(w.fuel[1], w.fuel[2]),
        engine = rng(w.engine[1], w.engine[2]),
        body = rng(w.body[1], w.body[2]),
        parts = parts,
        locked = false,
    }
end

--- The condition table of a vehicle (made when missing: fitted parts 100%).
function Rules.cond(v)
    local p = v.parts
    if type(p.cond) ~= 'table' then p.cond = {} end
    local c = p.cond
    if c.engine == nil then c.engine = p.engine and 100 or 0 end
    if c.battery == nil then c.battery = p.battery and 100 or 0 end
    if type(c.tyres) ~= 'table' then c.tyres = {} end
    for i = 1, 4 do
        if c.tyres[i] == nil then c.tyres[i] = i <= (p.wheels or 0) and 100 or 0 end
        if i > (p.wheels or 0) then c.tyres[i] = 0 end
    end
    return c
end

Rules.TYRE_NAMES = { 'front left', 'front right', 'rear left', 'rear right' }
Rules.BIKE_TYRE_NAMES = { 'front', 'rear' }

--- The name of tyre position i on this vehicle ("front left", or "front" on a bike).
function Rules.tyreName(v, i)
    return (Rules.wheelsMax(v) == 2 and Rules.BIKE_TYRE_NAMES or Rules.TYRE_NAMES)[i] or ''
end

--- Driving wears parts: `km` driven. w = { enginePartsPer100km, batteryPer100km, tyresPer100km }.
--- Returns true when a part just reached 0.
function Rules.wear(v, km, w)
    local max = Rules.wheelsMax(v)
    local c = Rules.cond(v)
    local before = { c.engine, c.battery, c.tyres[1], c.tyres[2], c.tyres[3], c.tyres[4] }
    local f = math.max(0, km) / 100
    if v.parts.engine then c.engine = math.max(0, c.engine - w.enginePartsPer100km * f) end
    if v.parts.battery then c.battery = math.max(0, c.battery - w.batteryPer100km * f) end
    for i = 1, math.min(max, v.parts.wheels or 0) do c.tyres[i] = math.max(0, c.tyres[i] - w.tyresPer100km * f) end
    local now = { c.engine, c.battery, c.tyres[1], c.tyres[2], c.tyres[3], c.tyres[4] }
    for i = 1, 6 do if before[i] > 0 and now[i] <= 0 then return true end end
    return false
end

--- A part name from the client: 'engine', 'battery' or 'tyre1'..'tyre4'. Returns kind, tyre position.
function Rules.part(name)
    if name == 'engine' or name == 'battery' then return name end
    local i = type(name) == 'string' and tonumber(name:match('^tyre([1-4])$'))
    if i then return 'tyre', i end
    return nil
end

--- The most worn fitted tyre (position), or nil with no wheels.
function Rules.worstTyre(v)
    local c = Rules.cond(v)
    local best
    for i = 1, math.min(Rules.wheelsMax(v), v.parts.wheels or 0) do
        if not best or c.tyres[i] < c.tyres[best] then best = i end
    end
    return best
end

--- Can the engine start? Returns true or false, reason.
function Rules.canRun(v)
    local p = v.parts or {}
    if not p.engine then return false, 'The engine parts are missing.' end
    if not p.battery then return false, 'There is no battery.' end
    local c = p.cond
    if c and c.engine and c.engine <= 0 then return false, 'The engine parts are worn out. Repair them (toolkit) or fit new ones.' end
    if c and c.battery and c.battery <= 0 then return false, 'The battery is dead. Recondition it (toolkit) or fit a new one.' end
    if (v.engine or 0) <= 100 then return false, 'The engine is wrecked. Repair it with a toolkit.' end
    if (v.fuel or 0) <= 0 then return false, 'The tank is empty.' end
    local max = Rules.wheelsMax(v)
    if (p.wheels or 0) < max then return false, string.format('It has %d of %d wheels.', p.wheels or 0, max) end
    return true
end

--- Fuel used (litres) over `seconds` at `kmh` with the engine running.
--- f = { idlePerMinute, per100km }
function Rules.fuelUsed(f, kmh, seconds)
    return f.idlePerMinute * seconds / 60 + f.per100km * (kmh * seconds / 3600) / 100
end

--- What an action needs and whether it can be done now.
--- action: fullRepair | battery | engine | wheel | refuel | repair | siphon | fitLock | toggleLock | pickLock | removeLock | trunk
--- has(item) -> true if the player carries it; key = player holds this vehicle's key;
--- mine = the player fitted this lock (removeLock).
--- Returns item to use (or true) or nil, reason.
function Rules.check(action, v, has, key, cfg, mine, part)
    local p = v.parts
    local c = Rules.cond(v)
    if action == 'battery' then   -- fit a missing battery, or replace a worn one
        if p.battery and c.battery >= 100 then return nil, 'It already has a battery.' end
        return has('car_battery') and 'car_battery' or nil, 'You need a car battery.'
    elseif action == 'engine' then
        if p.engine and c.engine >= 100 then return nil, 'The engine parts are already there.' end
        return has('engine_parts') and 'engine_parts' or nil, 'You need engine parts.'
    elseif action == 'wheel' then  -- mount a missing wheel, or replace tyre `part` (or the worst one)
        local max = Rules.wheelsMax(v)
        if p.wheels >= max then
            local _, i = Rules.part(part)
            i = i or Rules.worstTyre(v)
            if i and i > max then return nil, 'There is no wheel there.' end
            if not i or c.tyres[i] >= 100 then return nil, max == 2 and 'Both wheels are on.' or 'All four wheels are on.' end
        end
        return has('car_wheel') and 'car_wheel' or nil, 'You need a wheel.'
    elseif action == 'repairPart' then   -- toolkit on one part, up to partRepair.cap %
        local kind, i = Rules.part(part)
        local cap = (cfg.partRepair and cfg.partRepair.cap) or 80
        if kind == 'engine' and not p.engine then return nil, 'There are no engine parts to repair.' end
        if kind == 'battery' and not p.battery then return nil, 'There is no battery to recondition.' end
        if kind == 'tyre' and (i > (p.wheels or 0) or i > Rules.wheelsMax(v)) then return nil, 'There is no wheel there.' end
        if not kind then return nil, 'Repair what?' end
        local now = kind == 'tyre' and c.tyres[i] or c[kind]
        if now >= cap then return nil, string.format('A toolkit cannot do better than %d%%. Fit a new one.', cap) end
        return has('vehicle_repair_kit') and 'vehicle_repair_kit' or nil, 'You need a toolkit.'
    elseif action == 'refuel' then
        if v.fuel >= cfg.tankLitres - 0.5 then return nil, 'The tank is full.' end
        return has('jerry_can') and 'jerry_can' or nil, 'You need a jerry can with fuel.'
    elseif action == 'siphon' then
        -- has('jerry_can_space'): a jerry can that is not full.
        if v.fuel < 0.5 then return nil, 'The tank is empty.' end
        if not has('siphon_hose') then return nil, 'You need a siphon hose.' end
        return has('jerry_can_space') and 'siphon_hose' or nil, 'You need a jerry can that is not full.'
    elseif action == 'fullRepair' then
        local whole = p.battery and p.engine and p.wheels >= Rules.wheelsMax(v) and v.engine >= 990 and v.body >= 990
            and v.fuel >= cfg.tankLitres * 0.5 - 0.5
        if whole then return nil, 'This vehicle is already in good shape.' end
        return has('full_vehicle_repair') and 'full_vehicle_repair' or nil, 'You need a Full vehicle repair.'
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
    elseif action == 'removeLock' then
        if not v.lockCode then return nil, 'It has no lock.' end
        return mine and true or nil, 'Only the survivor who fitted this lock can take it off.'
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

--- A pump's fuel now. A pump is full again `refillMinutes` after fuel was
--- first taken from it (taking more meanwhile does not restart the clock).
--- Mutates and returns the pump.   pump = { litres, refillAt? }   p = config.pump
function Rules.pumpLevel(pump, p, nowMs)
    if pump.refillAt and nowMs >= pump.refillAt then pump.litres, pump.refillAt = p.litres, nil end
    return pump
end

--- Take up to `wanted` litres; starts the refill clock. Returns litres taken.
function Rules.pumpTake(pump, p, wanted, nowMs)
    Rules.pumpLevel(pump, p, nowMs)
    local take = math.max(0, math.min(wanted, pump.litres))
    if take > 0 then
        pump.litres = pump.litres - take
        pump.refillAt = pump.refillAt or (nowMs + p.refillMinutes * 60000)
    end
    return take
end

--- Minutes until the pump is full again (0 = full).
function Rules.pumpWait(pump, p, nowMs)
    if not pump.refillAt then return 0 end
    return math.max(1, math.ceil((pump.refillAt - nowMs) / 60000))
end

--- "1 h 24 min", "45 min".
function Rules.duration(minutes)
    local h, m = math.floor(minutes / 60), minutes % 60
    if h > 0 then return m > 0 and string.format('%d h %d min', h, m) or string.format('%d h', h) end
    return string.format('%d min', m)
end

--- Encode / decode the parts column.
function Rules.encodeParts(p)
    local c = p.cond
    local cs = ''
    if type(c) == 'table' and type(c.tyres) == 'table' then
        local r = function(x) return math.floor((tonumber(x) or 0) * 10 + 0.5) / 10 end
        cs = string.format(',"c":[%s,%s,%s,%s,%s,%s]', r(c.engine), r(c.battery), r(c.tyres[1]), r(c.tyres[2]), r(c.tyres[3]), r(c.tyres[4]))
    end
    return string.format('{"battery":%s,"engine":%s,"wheels":%d%s}', p.battery and 'true' or 'false', p.engine and 'true' or 'false', p.wheels or 0, cs)
end

function Rules.decodeParts(s)
    local out = { battery = false, engine = false, wheels = 0 }
    if type(s) ~= 'string' then return out end
    out.battery = s:find('"battery":true', 1, true) ~= nil
    out.engine = s:find('"engine":true', 1, true) ~= nil
    out.wheels = tonumber(s:match('"wheels":(%d+)')) or 0
    local list = s:match('"c":%[([^%]]*)%]')
    if list then
        local n = {}
        for x in list:gmatch('[%d%.%-]+') do n[#n + 1] = tonumber(x) end
        if #n == 6 then out.cond = { engine = n[1], battery = n[2], tyres = { n[3], n[4], n[5], n[6] } } end
    end
    return out
end

return Rules
