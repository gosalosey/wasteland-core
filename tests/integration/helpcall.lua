-- Calls for help (wasteland_groups): /help tells everyone, /accepthelp gives a
-- route that follows the caller, /cancelhelp ends it; one call per cooldown.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('calls for help', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_groups' })
    local function join(license, first, x)
        local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
        server:advance(200)
        server.players[id].coords = { x = x, y = 0.0, z = 30.0 }
        server:command(id, 'character create ' .. first .. ' Help'); server:advance(300)
        server:command(id, 'character select 1'); server:advance(500)
        server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
        return id
    end
    local caller = join('hc1', 'Cal', 100.0)
    local helper = join('hc2', 'Hal', 900.0)
    local function last(id, ev) local l = server:clientEventsFor(id, 'wasteland:groups:client:' .. ev); return l[#l], #l end
    local function send(id, ev, ...) server:clientEvent(id, 'wasteland:groups:server:' .. ev, ...); server:advance(100) end

    it('/help tells everyone who needs help and where', function()
        send(caller, 'help', 'surrounded at the gas station')
        local call = last(helper, 'helpCall').args[1]
        expect(call.name).toBe('Cal Help')
        expect(call.coords.x).toBe(100.0)
        expect(call.message).toBe('surrounded at the gas station')
        expect(call.from).toBe(caller)
    end)

    it('not again straight away (cooldown)', function()
        send(caller, 'help', 'again')
        local _, n = last(helper, 'helpCall')
        expect(n).toBe(1)
    end)

    it('/accepthelp: a route to the caller, who is told someone is coming; it follows them', function()
        send(helper, 'acceptHelp')
        local r = last(helper, 'helpRoute').args[1]
        expect(r.name).toBe('Cal Help'); expect(r.coords.x).toBe(100.0)
        local n = last(caller, 'notice').args[1]
        expect(n).toBe('Hal Help is coming to help you.')
        server.players[caller].coords = { x = 150.0, y = 10.0, z = 30.0 }
        server:advance(10100)
        r = last(helper, 'helpRoute').args[1]
        expect(r.coords.x).toBe(150.0); expect(r.update).toBe(true)
    end)

    it('the caller cannot accept their own call; /cancelhelp ends it for the helpers', function()
        send(caller, 'acceptHelp')
        expect(last(caller, 'notice').args[1]).toBe('Nobody is calling for help right now.')
        send(caller, 'cancelHelp')
        local e = last(helper, 'helpEnded')
        expect(e.args[2]).toBe('cancelled')
        send(helper, 'acceptHelp')
        expect(last(helper, 'notice').args[1]).toBe('Nobody is calling for help right now.')
        expect(#server.scriptErrors).toBe(0)
    end)
end)
