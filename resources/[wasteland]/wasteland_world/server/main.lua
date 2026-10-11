-- wasteland_world :: server/main.lua
-- Module "world": the server's game clock and weather (one for everyone),
-- and an empty world: no ambient NPCs or traffic (OneSync population is
-- switched off for the main routing bucket; clients enforce the rest).
-- Zones, camps and traders join this module in Milestone 7.

local Clock = WLW.Clock
local M
local clock = { hour = 12, minute = 0, carry = 0, frozen = false }
local weather = { current = 'CLEAR', dynamic = true, sinceChange = 0 }
local runToken = nil

local function payload(transition)
    return {
        hour = clock.hour, minute = clock.minute, frozen = clock.frozen,
        msPerMinute = M.config.time.msPerMinute,
        weather = weather.current, transition = transition or 0,
        population = M.config.population, audio = M.config.audio,
    }
end

local function broadcast(transition, target)
    TriggerClientEvent('wasteland:world:client:sync', target or -1, payload(transition))
end

local function setWeather(name, transition)
    if weather.current == name then return end
    weather.current = name
    weather.sinceChange = 0
    M.log:info('weather is now %s', name)
    broadcast(transition or M.config.weather.transitionSeconds)
end

local function loop(token)
    local sinceBroadcast = 0
    while runToken == token do
        Citizen.Wait(1000)
        if runToken ~= token then return end
        Clock.advance(clock, 1000, M.config.time.msPerMinute)
        weather.sinceChange = weather.sinceChange + 1
        if weather.dynamic and weather.sinceChange >= M.config.weather.changeMinutes * 60 then
            setWeather(Clock.nextWeather(M.config.weather.pool, weather.current, math.random()))
        end
        sinceBroadcast = sinceBroadcast + 1
        if sinceBroadcast >= 30 then
            sinceBroadcast = 0
            broadcast()
        end
    end
end

local function applyPopulation()
    local p = M.config.population
    -- With OneSync the server decides population; off for the main bucket
    -- when neither ambient peds nor traffic are wanted.
    if SetRoutingBucketPopulationEnabled then
        SetRoutingBucketPopulationEnabled(0, p.peds or p.vehicles)
    end
end

local POOL_KEYS = {}
for _, w in ipairs(WLW.WEATHERS) do POOL_KEYS[#POOL_KEYS + 1] = w end

M = Wasteland.DefineModule({
    name = 'world',
    version = '0.1.0',
    description = 'Game clock, weather, empty world (no ambient NPCs or traffic), ambient audio off',
    core = '^1.1.0',
    config = {
        file = 'world.lua',
        optional = true,
        schema = { type = 'table', fields = {
            population = { type = 'table', fields = {
                peds = { type = 'boolean', default = false, description = 'Ambient pedestrians' },
                vehicles = { type = 'boolean', default = false, description = 'Ambient traffic' },
                parkedVehicles = { type = 'boolean', default = false, description = 'Parked cars at the roadside' },
                police = { type = 'boolean', default = false, description = 'Police, dispatch and wanted levels' },
            } },
            audio = { type = 'table', fields = {
                ambience = { type = 'boolean', default = false, description = 'City and nature background sound' },
                music = { type = 'boolean', default = false, description = 'Radio, score and flight music, music from buildings' },
                scanner = { type = 'boolean', default = false, description = 'Police scanner and distant sirens' },
                emitters = { type = 'array', default = {}, items = { type = 'string', pattern = '^[%w_]+$' },
                    description = 'Extra static emitters (music sources) to switch off' },
            } },
            time = { type = 'table', fields = {
                startHour = { type = 'integer', default = 12, min = 0, max = 23 },
                msPerMinute = { type = 'integer', default = 2000, min = 100, max = 600000,
                    description = 'Real milliseconds per game minute (2000 = a 48-minute day, like GTA online)' },
                frozen = { type = 'boolean', default = false },
            } },
            weather = { type = 'table', fields = {
                start = { type = 'enum', values = WLW.WEATHERS, default = 'CLEAR' },
                dynamic = { type = 'boolean', default = true },
                changeMinutes = { type = 'integer', default = 30, min = 1, max = 1440, description = 'Real minutes between changes' },
                transitionSeconds = { type = 'integer', default = 30, min = 0, max = 300 },
                pool = { type = 'map', keys = { type = 'enum', values = WLW.WEATHERS }, values = { type = 'number', min = 0, max = 100 },
                    default = { CLEAR = 30, EXTRASUNNY = 15, CLOUDS = 20, OVERCAST = 15, FOGGY = 8, RAIN = 8, THUNDER = 4 } },
            } },
        } },
    },
    onInit = function(mod)
        M = mod
        Clock.set(clock, M.config.time.startHour, 0)
        clock.frozen = M.config.time.frozen
        weather.current, weather.dynamic, weather.sinceChange = M.config.weather.start, M.config.weather.dynamic, 0
        applyPopulation()
        local token = {}
        runToken = token
        Citizen.CreateThread(function() loop(token) end)
        broadcast()
        return true
    end,
    onShutdown = function()
        runToken = nil
        if SetRoutingBucketPopulationEnabled then SetRoutingBucketPopulationEnabled(0, true) end
    end,
})

M.netEvent('wasteland:world:server:request', { rateLimit = { burst = 3, perSecond = 0.2 } }, function(src)
    broadcast(0, src)
end)

-------------------------------------------------------------------------------
-- Exports (world api 0.1)
-------------------------------------------------------------------------------

--- GetTime() -> hour, minute, frozen
exports('GetTime', function() return clock.hour, clock.minute, clock.frozen end)

--- SetTime(hour, minute) -> ok
exports('SetTime', function(hour, minute)
    hour, minute = tonumber(hour), tonumber(minute) or 0
    if not hour or hour < 0 or hour > 23 or minute < 0 or minute > 59 then return false, 'hour 0-23, minute 0-59' end
    Clock.set(clock, hour, minute)
    broadcast()
    return true
end)

--- FreezeTime(frozen) -> ok
exports('FreezeTime', function(frozen)
    clock.frozen = frozen == true
    broadcast()
    return true
end)

--- GetWeather() -> name, dynamic
exports('GetWeather', function() return weather.current, weather.dynamic end)

--- SetWeather(name, keepDynamic?) -> ok, err   (setting it stops the dynamic cycle unless keepDynamic)
exports('SetWeather', function(name, keepDynamic)
    local valid = false
    for _, w in ipairs(WLW.WEATHERS) do if w == name then valid = true end end
    if not valid then return false, 'unknown weather ' .. tostring(name) end
    weather.dynamic = keepDynamic == true
    setWeather(name)
    broadcast()
    return true
end)

--- SetWeatherDynamic(dynamic) -> ok
exports('SetWeatherDynamic', function(dynamic)
    weather.dynamic = dynamic == true
    weather.sinceChange = 0
    broadcast()
    return true
end)

--- GetWeatherNames() -> list
exports('GetWeatherNames', function() return POOL_KEYS end)
