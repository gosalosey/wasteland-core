-- wasteland_world: clock and weather rules, sync to clients, exports, and
-- the empty-world switch on the server.

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_world/shared/clock.lua', 't', env))()
local Clock = env.WLW.Clock

describe('clock rules', function()
    it('advances one game minute per msPerMinute and wraps at midnight', function()
        local c = { hour = 23, minute = 58, carry = 0 }
        expect(Clock.advance(c, 1999, 2000)).toBe(0)
        expect(Clock.advance(c, 1, 2000)).toBe(1)
        expect(c.minute).toBe(59)
        Clock.advance(c, 4000, 2000)
        expect(c.hour).toBe(0); expect(c.minute).toBe(1)
    end)
    it('does not move while frozen', function()
        local c = { hour = 6, minute = 0, carry = 0, frozen = true }
        Clock.advance(c, 60000, 2000)
        expect(c.hour).toBe(6); expect(c.minute).toBe(0)
    end)
    it('picks weighted weather and never repeats the current one', function()
        local pool = { CLEAR = 1, RAIN = 1 }
        expect(Clock.nextWeather(pool, 'CLEAR', 0.99)).toBe('RAIN')
        expect(Clock.nextWeather(pool, 'RAIN', 0.0)).toBe('CLEAR')
        expect(Clock.nextWeather({ CLEAR = 5 }, 'CLEAR', 0.5)).toBe('CLEAR')
        expect(Clock.nextWeather({ CLEAR = 1, RAIN = 0, FOGGY = 3 }, 'EXTRASUNNY', 0.5)).toBe('FOGGY')
    end)
end)

describe('world module', function()
    local server = newServer({ config = { ['world.lua'] = [[return {
        time = { startHour = 8, msPerMinute = 1000 },
        weather = { start = 'CLEAR', changeMinutes = 2, transitionSeconds = 5, pool = { RAIN = 1 } },
    }]] } })
    server:start('wasteland_world')
    server:advance(100)
    local id = server:connectAndJoin({ name = 'W', license = 'w' })

    it('runs and switches ambient population off for the main bucket', function()
        expect(states(server).world).toBe('running')
        expect(server.population[0]).toBe(false)
    end)

    it('sends the clock, weather and world settings to clients', function()
        server:clientEvent(id, 'wasteland:world:server:request')
        local ev = server:clientEventsFor(id, 'wasteland:world:client:sync')
        local p = ev[#ev].args[1]
        expect(p.hour).toBe(8)
        expect(p.weather).toBe('CLEAR')
        expect(p.population.peds).toBe(false)
        expect(p.audio.music).toBe(false)
    end)

    it('advances time on the server', function()
        server:advance(60000)
        local h, m = server:export('wasteland_world', 'GetTime')
        expect(h).toBe(9); expect(m).toBe(0)
    end)

    it('changes weather by itself after changeMinutes', function()
        server:advance(70000)
        expect((server:export('wasteland_world', 'GetWeather'))).toBe('RAIN')
    end)

    it('admins can set time and weather; setting weather stops the cycle', function()
        expect(server:export('wasteland_world', 'SetTime', 22, 30)).toBe(true)
        expect(server:export('wasteland_world', 'SetWeather', 'THUNDER')).toBe(true)
        local w, dynamic = server:export('wasteland_world', 'GetWeather')
        expect(w).toBe('THUNDER'); expect(dynamic).toBe(false)
        local ok, err = server:export('wasteland_world', 'SetWeather', 'LAVA')
        expect(ok).toBe(false); expect(err).toContain('unknown weather')
        local ev = server:clientEventsFor(-1, 'wasteland:world:client:sync')
        expect(ev[#ev].args[1].hour).toBe(22)
        expect(#server.scriptErrors).toBe(0)
    end)

    it('puts the population back when it stops', function()
        server:stop('wasteland_world')
        expect(server.population[0]).toBe(true)
    end)
end)
