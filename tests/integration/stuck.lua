-- /stuck (wasteland_camps): the nearest safe camp, after standing still for
-- waitSeconds, once every cooldownMinutes; checked by the server.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('/stuck', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_camps' })
    local id = server:connectAndJoin({ name = 'P-stuck', license = 'stuck' })
    server:advance(200)
    server:command(id, 'character create Stu Stuck'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
    server.players[id].coords = { x = 1700.0, y = 3500.0, z = 35.0 } -- near Sandy Shores
    local function ev(name) local l = server:clientEventsFor(id, 'wasteland:camps:client:' .. name); return l[#l], #l end
    local function send(name) server:clientEvent(id, 'wasteland:camps:server:' .. name); server:advance(100) end

    it('shows the nearest safe camp and how long to stand still', function()
        send('stuckInfo')
        local info = ev('stuckInfo').args[1]
        expect(info.camp).toBe('Sandy Shores Camp')
        expect(info.wait).toBe(10); expect(info.cooldown).toBe(0)
    end)

    it('finishing before the wait does nothing; moving cancels it', function()
        send('stuckStart')
        expect(ev('stuckCount').args[1]).toBe(10)
        send('stuckFinish')
        local _, n = ev('spawnAt'); expect(n).toBe(0)
        send('stuckStart')
        server.players[id].coords = { x = 1710.0, y = 3500.0, z = 35.0 }
        server:advance(10100)
        send('stuckFinish')
        _, n = ev('spawnAt'); expect(n).toBe(0)
        expect(ev('stuckFailed').args[1]).toContain('You moved')
    end)

    it('standing still for the wait: taken to the camp; then a cooldown', function()
        send('stuckStart')
        server:advance(10100)
        send('stuckFinish')
        local spawn, n = ev('spawnAt')
        expect(n).toBe(1)
        expect(spawn.args[2]).toBe('Sandy Shores Camp')
        send('stuckInfo')
        expect(ev('stuckInfo').args[1].cooldown > 0).toBe(true)
        send('stuckStart')
        server:advance(10100)
        send('stuckFinish')
        _, n = ev('spawnAt'); expect(n).toBe(1) -- not again during the cooldown
        expect(#server.scriptErrors).toBe(0)
    end)
end)
