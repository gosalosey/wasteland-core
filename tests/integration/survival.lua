-- wasteland_survival (server): stats per character, tick and damage,
-- consumables through the inventory, bleeding reports, environment,
-- death (body bag) and respawn, persistence and exports.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { saveIntervalSeconds = 10, restoreDelayMs = 200 }',
    ['survival.lua'] = [[return {
        tickSeconds = 10,
        respawn = { delaySeconds = 15, points = { { x = 1.0, y = 2.0, z = 3.0, heading = 90.0 } } },
        consumables = {
            canned_beans = { hunger = 35, animation = 'eat' },
            bandage = { stopBleeding = 3, health = 10, animation = 'treat', message = 'Bandaged.' },
            water_bottle = { thirst = 45, animation = 'drink' },
        },
    }]],
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function world()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival' })
    return server
end

local function player(server, license)
    local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
    server:advance(200)
    server.players[id].coords = { x = 100.0, y = 100.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    return id
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end
local function stats(server, id) return last(events(server, id, 'wasteland:survival:client:stats')).args[1] end
local function S(server, fn, ...) return server:export('wasteland_survival', fn, ...) end

local function invSnap(server, id) return last(events(server, id, 'wasteland:inventory:client:sync')).args[1] end
local function find(snapshot, name)
    for _, i in ipairs(snapshot.inventories) do
        for _, s in ipairs(i.items) do if s.name == name then return s, i.id end end
    end
end

describe('survival stats', function()
    local server = world()
    local id = player(server, 'amy')

    it('runs and sends fresh stats to a new character', function()
        expect(states(server).survival).toBe('running')
        local s = stats(server, id)
        expect(s.hunger).toBe(100); expect(s.thirst).toBe(100); expect(s.dead).toBe(false)
    end)

    it('drains on every tick and is stored as character data', function()
        server:advance(60000)
        local s = stats(server, id)
        expect(s.hunger < 100).toBe(true)
        expect(s.thirst < s.hunger).toBe(true)
        local stored = server:export('wasteland_players', 'GetCharacterData', 1, 'survival')
        expect(stored.hunger).toBe(s.hunger)
    end)

    it('starving sends whole points of damage to the client', function()
        server:export('wasteland_survival', 'ModifyStats', id, { hunger = -100 })
        local before = #events(server, id, 'wasteland:survival:client:damage')
        server:advance(60000)
        local dmg = events(server, id, 'wasteland:survival:client:damage')
        expect(#dmg > before).toBe(true)
        local total = 0
        for i = before + 1, #dmg do total = total + dmg[i].args[1] end
        expect(total >= 2).toBe(true)
    end)

    it('uses the reported surroundings and worn clothing for temperature', function()
        server:clientEvent(id, 'wasteland:survival:server:environment', -30, true)
        server:advance(120000)
        expect(stats(server, id).temperature < 37).toBe(true)
        expect(stats(server, id).ambient).toBe(-30)
    end)
end)

describe('food, drink and medicine through the inventory', function()
    local server = world()
    local id = player(server, 'ben')
    server:export('wasteland_survival', 'ModifyStats', id, { hunger = -50 })

    it('eating restores hunger and uses up one item', function()
        local beans = find(invSnap(server, id), 'canned_beans')
        server:clientEvent(id, 'wasteland:inventory:server:use', beans.uid, 'player:1')
        server:advance(200)
        expect(stats(server, id).hunger >= 84).toBe(true)
        expect(find(invSnap(server, id), 'canned_beans').count).toBe(1)
        expect(last(events(server, id, 'wasteland:survival:client:consumed')).args[1]).toBe('eat')
    end)

    it('refuses items that would do nothing (and keeps them)', function()
        server:export('wasteland_survival', 'ModifyStats', id, { thirst = 100 })
        local bottle = find(invSnap(server, id), 'water_bottle')
        server:clientEvent(id, 'wasteland:inventory:server:use', bottle.uid, 'player:1')
        server:advance(200)
        local errs = events(server, id, 'wasteland:inventory:client:error')
        expect(last(errs).args[1]).toBe('You do not need that right now.')
        expect(find(invSnap(server, id), 'water_bottle') ~= nil).toBe(true)
    end)

    it('a hard hit can start bleeding; a bandage stops it and heals', function()
        for _ = 1, 20 do
            server:clientEvent(id, 'wasteland:survival:server:damaged', 60)
            server:advance(300)
            if stats(server, id).bleeding > 0 then break end
        end
        expect(stats(server, id).bleeding > 0).toBe(true)
        local bandage = find(invSnap(server, id), 'bandage')
        server:clientEvent(id, 'wasteland:inventory:server:use', bandage.uid, 'player:1')
        server:advance(200)
        expect(stats(server, id).bleeding).toBe(0)
        expect(last(events(server, id, 'wasteland:survival:client:heal')).args[1]).toBe(10)
        local notes = events(server, id, 'wasteland:inventory:client:notice')
        expect(last(notes).args[1]).toBe('Bandaged.')
    end)
end)

describe('death and respawn', function()
    local server = world()
    local id = player(server, 'cleo')
    local bandage = find(invSnap(server, id), 'bandage')
    server:clientEvent(id, 'wasteland:inventory:server:setHotbar', 1, bandage.uid)
    server:advance(200)
    server:clientEvent(id, 'wasteland:survival:server:died')
    server:advance(300)

    it('drops everything but hotbar items into a body bag named after the character', function()
        local dead = last(events(server, id, 'wasteland:survival:client:dead'))
        expect(dead.args[1].respawnSeconds).toBe(15)
        local snap = invSnap(server, id)
        local pockets
        for _, i in ipairs(snap.inventories) do if i.id == snap.pockets then pockets = i end end
        expect(#pockets.items).toBe(1)
        expect(pockets.items[1].name).toBe('bandage')
        local drops = last(events(server, id, 'wasteland:inventory:client:drops')).args[1]
        expect(drops[1].label).toBe('Body of John Doe')
        expect(drops[1].owner).toBe(1)
        expect(S(server, 'IsDead', id)).toBe(true)
    end)

    it('a second death report does nothing', function()
        server:advance(5000)
        server:clientEvent(id, 'wasteland:survival:server:died')
        server:advance(200)
        expect(#events(server, id, 'wasteland:survival:client:dead')).toBe(1)
    end)

    it('respawn waits for the delay, then resets stats at a respawn point', function()
        server:clientEvent(id, 'wasteland:survival:server:respawn')
        server:advance(200)
        expect(last(events(server, id, 'wasteland:survival:client:notice')).args[1]).toContain('Wait')
        server:advance(10000)
        server:clientEvent(id, 'wasteland:survival:server:respawn')
        server:advance(200)
        local r = last(events(server, id, 'wasteland:survival:client:respawn'))
        expect(r.args[1].x).toBe(1.0)
        expect(r.args[1].heading).toBe(90.0)
        local s = stats(server, id)
        expect(s.dead).toBe(false); expect(s.hunger).toBe(70); expect(s.bleeding).toBe(0)
        expect(S(server, 'IsDead', id)).toBe(false)
    end)

    it('a player who leaves while dead can respawn at once when back', function()
        server:clientEvent(id, 'wasteland:survival:server:died')
        server:advance(300)
        server:dropPlayer(id)
        server:advance(1000)
        local id2 = server:connectAndJoin({ name = 'P-cleo', license = 'cleo' })
        server:advance(200)
        server.players[id2].coords = { x = 100.0, y = 100.0, z = 30.0 }
        server:command(id2, 'character select 1'); server:advance(500)
        local dead = last(events(server, id2, 'wasteland:survival:client:dead'))
        expect(dead.args[1].respawnSeconds).toBe(0)
        server:clientEvent(id2, 'wasteland:survival:server:respawn')
        server:advance(200)
        expect(#events(server, id2, 'wasteland:survival:client:respawn')).toBe(1)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('exports and guarded events', function()
    local server = world()
    local id = player(server, 'dan')

    it('AddInfection and AddBleeding change the stats (zombie hits use these)', function()
        expect(S(server, 'AddInfection', id, 30)).toBe(true)
        expect(S(server, 'AddBleeding', id, 1)).toBe(true)
        local s = S(server, 'GetStats', id)
        expect(s.infection).toBe(30); expect(s.bleeding).toBe(1)
    end)

    it('the admin command sets stats (ACE required)', function()
        server:clearOutput()
        server:command(0, 'survival ' .. id .. ' thirst 5'); server:advance(100)
        expect(S(server, 'GetStats', id).thirst).toBe(5)
        server:command(0, 'survival ' .. id .. ' bleeding 9'); server:advance(100)
        expect(S(server, 'GetStats', id).bleeding).toBe(3)
        server:command(id, 'survival ' .. id .. ' hunger 100'); server:advance(100)
        expect(#server:lines('tried "survival" without the wasteland.admin ACE')).toBe(1)
        server:command(0, 'survival ' .. id .. ' charisma 5'); server:advance(100)
        expect(#server:lines('usage: survival <server id>')).toBe(1)
    end)

    it('rejects out-of-range reports', function()
        server:clientEvent(id, 'wasteland:survival:server:environment', 500, false)
        server:clientEvent(id, 'wasteland:survival:server:damaged', -5)
        expect(#server:lines('rejected "wasteland:survival:server:environment" from player 1 (payload)')).toBe(1)
        expect(#server:lines('rejected "wasteland:survival:server:damaged" from player 1 (payload)')).toBe(1)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
