-- Where a returning character wakes up: its last known position; with none
-- that can be used, a safe camp (new characters are left to the creator).

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200, positionSampleSeconds = 1 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('where a returning character spawns', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_camps' })
    local function loadedPos(id)
        local l = server:clientEventsFor(id, 'wasteland:players:client:characterLoaded')
        return l[#l].args[1].position
    end
    local id = server:connectAndJoin({ name = 'P-spawn', license = 'spawn' })
    server:advance(200)
    server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
    server:command(id, 'character create Sid Spawn'); server:advance(300)

    it('a brand-new character gets the default spawn (the creator and camp choice come next)', function()
        server:command(id, 'character select 1'); server:advance(500)
        expect(loadedPos(id).x).toBe(1734.0)
        server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
    end)

    it('a returning character goes back to where it logged out', function()
        server:clientEvent(id, 'wasteland:players:server:placed'); server:advance(100)
        server.players[id].coords = { x = 1850.0, y = 3600.0, z = 34.0 }
        server:advance(1100) -- position sample
        server:dropPlayer(id, 'Exiting'); server:advance(500)
        id = server:connectAndJoin({ name = 'P-spawn', license = 'spawn' }); server:advance(200)
        server:command(id, 'character select 1'); server:advance(500)
        local p = loadedPos(id)
        expect(p.x).toBe(1850.0); expect(p.y).toBe(3600.0)
    end)

    it('with no usable last position (here: the map origin), a safe camp', function()
        server:clientEvent(id, 'wasteland:players:server:placed'); server:advance(100)
        server.players[id].coords = { x = 0.0, y = 0.0, z = 0.5 }
        server:advance(1100)
        server:dropPlayer(id, 'Exiting'); server:advance(500)
        id = server:connectAndJoin({ name = 'P-spawn', license = 'spawn' }); server:advance(200)
        server:command(id, 'character select 1'); server:advance(500)
        local p = loadedPos(id)
        expect(p ~= nil).toBe(true)
        local camp = server:export('wasteland_camps', 'GetCampAt', p)
        expect(camp ~= nil).toBe(true)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
