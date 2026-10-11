-- wasteland_tailor (server): restyling worn clothes at a tailor for cash.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['tailor.lua'] = [[return { price = 25, shops = { { label = 'Test Tailor', coords = { x = 10.0, y = 10.0, z = 30.0, heading = 0.0 } } } }]],
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end

describe('tailor', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_tailor' })
    local id = server:connectAndJoin({ name = 'P-t', license = 'tail' })
    server:advance(200)
    server.players[id].coords = { x = 11.0, y = 10.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local function worn(slot) for _, w in ipairs(I('GetWornItems', id)) do if w.slot == slot then return w end end end
    local function buy(changes) server:clientEvent(id, 'wasteland:tailor:server:buy', 1, 'mp_m_freemode_01', changes); server:advance(1100) end
    local function note() return last(events(server, id, 'wasteland:tailor:client:notice')).args[1] end

    it('runs and sends the tailors to clients', function()
        expect(states(server).tailor).toBe('running')
        expect(last(events(server, -1, 'wasteland:tailor:client:config')).args[1].shops[1].label).toBe('Test Tailor')
    end)

    it('needs cash: $25 a piece', function()
        buy({ { slot = 'legs', look = { legs = { 5, 2 } } } })
        expect(note()).toBe('That costs $25. You do not have enough cash.')
        expect(worn('legs').metadata.legs[1] ~= 5 or worn('legs').metadata.legs[2] ~= 2).toBe(true)
    end)

    it('restyles worn pieces and takes the cash', function()
        I('AddCash', id, 100); server:advance(100)
        buy({ { slot = 'legs', look = { legs = { 5, 2 } } }, { slot = 'torso', look = { top = { 7, 1 }, undershirt = { 15, 0 }, arms = { 4, 0 } } } })
        expect(#events(server, id, 'wasteland:tailor:client:done')).toBe(1)
        expect(I('GetCash', id)).toBe(50)
        local legs = worn('legs').metadata
        expect(legs.legs[1]).toBe(5); expect(legs.legs[2]).toBe(2); expect(legs.model).toBe('mp_m_freemode_01')
        expect(worn('torso').metadata.top[1]).toBe(7)
    end)

    it('only what is worn, sane values, at the tailor', function()
        buy({ { slot = 'back', look = { bag = { 1, 0 } } } })
        expect(note()).toBe('You are not wearing anything there.')
        buy({ { slot = 'legs', look = { legs = { 5000, 0 } } } })
        expect(note()).toBe('That look is not possible.')
        server.players[id].coords = { x = 50.0, y = 10.0, z = 30.0 }
        buy({ { slot = 'legs', look = { legs = { 1, 0 } } } })
        expect(note()).toBe('You are too far from the tailor.')
        expect(I('GetCash', id)).toBe(50)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)
