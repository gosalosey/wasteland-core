-- wasteland_events (server): a whole event: announced, the danger appears
-- when a player comes near, bandits drop bags, the loot stays locked until
-- every bandit and event zombie is dead, then opens; admin command; ending.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['zombies.lua'] = 'return { population = { perPlayer = 0, maxTotal = 60 } }',
    ['events.lua'] = [[return {
        intervalMinutes = 0, activateDistance = 150, lootMinutes = 1,
        banditDrop = { { name = 'ammo_9mm', min = 5, max = 5, chance = 1 } },
        types = {
            test = { label = 'Test crash', minutes = 30, message = 'Crash near %s.', clearedMessage = 'Clear near %s.',
                lootLabel = 'Wreckage', lootTable = 'helicrash', lootRolls = 1,
                zombies = { count = 2, runnerShare = 0 }, bandits = { count = 2 },
                props = { { model = 'prop_crashed_heli', loot = true } } },
        },
        points = { { x = 500.0, y = 500.0, z = 30.0, label = 'the test field' } },
    }]],
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end

describe('world events', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival', 'wasteland_zombies',
        'wasteland_loot', 'wasteland_events' })
    local id = server:connectAndJoin({ name = 'P-ev', license = 'ev' })
    server:advance(200)
    server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
    server:command(id, 'character create Event Test'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
    local function EV(fn, ...) return server:export('wasteland_events', fn, ...) end
    local function note() return last(events(server, id, 'wasteland:events:client:notice')).args[1] end
    local eventId

    it('starts: everyone gets the message and the marker; nothing spawns while nobody is near', function()
        expect(states(server).events).toBe('running')
        server:command(0, 'event test'); server:advance(100)
        local list = EV('GetEvents')
        expect(#list).toBe(1)
        eventId = list[1].id
        expect(list[1].state).toBe('waiting')
        expect(last(events(server, -1, 'wasteland:events:client:notice')).args[1]).toBe('Crash near the test field.')
        expect(last(events(server, -1, 'wasteland:events:client:event')).args[1].props[1].model).toBe('prop_crashed_heli')
        server:advance(4000)
        expect(#server:entityList('wlBandit')).toBe(0)
    end)

    it('a player coming near: asked for ground spots, then bandits and zombies appear', function()
        server.players[id].coords = { x = 450.0, y = 500.0, z = 30.0 }
        server:advance(2500)
        local ask = last(events(server, id, 'wasteland:events:client:findSpots')).args
        expect(ask[1]).toBe(eventId)
        local spots = {}
        for i = 1, 4 do spots[i] = { x = 500.0 + i * 3, y = 505.0, z = 30.0 } end
        server:clientEvent(id, 'wasteland:events:server:spots', eventId, spots); server:advance(200)
        expect(#server:entityList('wlBandit')).toBe(2)
        local e = EV('GetEvents')[1]
        expect(e.state).toBe('active'); expect(e.bandits).toBe(2); expect(e.zombies).toBe(2)
    end)

    it('the loot stays locked while anyone is left', function()
        server.players[id].coords = { x = 502.0, y = 500.0, z = 30.0 }
        server:clientEvent(id, 'wasteland:events:server:open', eventId); server:advance(300)
        expect(note()).toBe('Too dangerous: 2 bandits and 2 zombies are still here.')
    end)

    it('killed bandits drop a bag; once everything is dead the loot opens and the marker clears', function()
        local drops = #events(server, -1, 'wasteland:inventory:client:drops')
        for _, b in ipairs(server:entityList('wlBandit')) do b.health = 0 end
        server:advance(2200)
        expect(#events(server, -1, 'wasteland:inventory:client:drops') > drops).toBe(true)
        expect(EV('GetEvents')[1].bandits).toBe(0)
        for _, z in ipairs(server:entityList('wlZombie')) do z.health = 0 end
        server:advance(4500)
        expect(EV('GetEvents')[1].state).toBe('cleared')
        expect(last(events(server, -1, 'wasteland:events:client:notice')).args[1]).toBe('Clear near the test field.')
        server:advance(1100)
        server:clientEvent(id, 'wasteland:events:server:open', eventId); server:advance(300)
        expect(#events(server, id, 'wasteland:inventory:client:open')).toBe(1)
        local snap = server:export('wasteland_inventory', 'GetInventory', 'stash:event_' .. eventId)
        expect(#snap.items > 0).toBe(true)
    end)

    it('ends after the loot time; bandits are removed', function()
        server:advance(62000)
        expect(#EV('GetEvents')).toBe(0)
        expect(#events(server, -1, 'wasteland:events:client:remove') >= 1).toBe(true)
        expect(#server:entityList('wlBandit')).toBe(0)
        expect(#server:lines('raised:')).toBe(0)
    end)

    it('admins can start one next to them and end them all', function()
        server.aces[id .. '|wasteland.admin'] = true
        server:command(id, 'event test here'); server:advance(100)
        expect(#EV('GetEvents')).toBe(1)
        expect(EV('GetEvents')[1].place).toBe('an admin')
        server:command(id, 'event end'); server:advance(100)
        expect(#EV('GetEvents')).toBe(0)
    end)
end)
