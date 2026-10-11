-- wasteland_zombies (server): population around players (spawn points
-- found by the client, checked by the server), hits through survival,
-- noise from weapons, deaths with loot, despawning, admin command, abuse.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['zombies.lua'] = [[return {
        population = { perPlayer = 4, nightMultiplier = 1, maxTotal = 6, spawnBatch = 3, spawnIntervalSeconds = 2,
            despawnDistance = 230, despawnAfterSeconds = 5, corpseSeconds = 10 },
        loot = { chance = 1, lifetimeMinutes = 5, items = { { name = 'cash', min = 10, max = 10, weight = 1 } } },
    }]],
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function world()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival',
        'wasteland_weapons', 'wasteland_zombies' })
    return server
end

local function player(server, license, coords)
    local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
    server:advance(200)
    server.players[id].coords = coords or { x = 0.0, y = 0.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    return id
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end

-- Answer the latest spawn request like the client would: points in a ring.
local function answerSpawns(server, id, radius)
    local req = last(events(server, id, 'wasteland:zombies:client:findSpawns'))
    local n = req.args[1]
    local c = server.players[id].coords
    local points = {}
    for i = 1, n do
        local a = i * 2 * math.pi / n
        points[i] = { x = c.x + math.cos(a) * (radius or 100), y = c.y + math.sin(a) * (radius or 100), z = c.z }
    end
    server:clientEvent(id, 'wasteland:zombies:server:spawns', points)
    server:advance(100)
    return n
end

describe('zombie population', function()
    local server = world()
    local id = player(server, 'pop')

    it('runs and asks the player for spawn points', function()
        expect(states(server).zombies).toBe('running')
        server:advance(2500)
        local req = last(events(server, id, 'wasteland:zombies:client:findSpawns'))
        expect(req.args[1]).toBe(3)
        expect(req.args[2]).toBe(70); expect(req.args[3]).toBe(140)
    end)

    it('spawns zombies only on acceptable points, marked with their kind', function()
        local c = server.players[id].coords
        server:clientEvent(id, 'wasteland:zombies:server:spawns', {
            { x = c.x + 100, y = c.y, z = 30 }, { x = c.x + 5, y = c.y, z = 30 }, { x = c.x + 900, y = c.y, z = 30 },
        })
        server:advance(100)
        local zs = server:entityList('wlZombie')
        expect(#zs).toBe(1)
        local kind = zs[1].state.wlZombie.kind
        expect(kind == 'walker' or kind == 'runner').toBe(true)
        expect(zs[1].owner).toBe(id)
    end)

    it('ignores spawn points nobody asked for', function()
        server:clientEvent(id, 'wasteland:zombies:server:spawns', { { x = 100, y = 0, z = 30 } })
        server:advance(100)
        expect(#server:entityList('wlZombie')).toBe(1)
    end)

    it('tops up to the target, never past the world cap', function()
        for _ = 1, 4 do
            server:advance(2100)
            answerSpawns(server, id, 110)
        end
        expect(#server:entityList('wlZombie')).toBe(4) -- perPlayer 4
        local id2 = player(server, 'pop2', { x = 1000.0, y = 0.0, z = 30.0 })
        for _ = 1, 3 do
            server:advance(2100)
            if #events(server, id2, 'wasteland:zombies:client:findSpawns') > 0 then answerSpawns(server, id2, 100) end
        end
        expect(#server:entityList('wlZombie')).toBe(6) -- maxTotal 6
        expect(server:export('wasteland_zombies', 'GetZombieCount')).toBe(6)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('zombie hits', function()
    local server = world()
    local id = player(server, 'bite')
    local netId = server:export('wasteland_zombies', 'SpawnZombie', { x = 1.0, y = 0.0, z = 30.0 }, 'walker')
    local z = server:entityList('wlZombie')[1]

    it('the client running the zombie reports a hit: damage, through survival', function()
        server:clientEvent(id, 'wasteland:zombies:server:hit', netId, id)
        server:advance(100)
        local dmg = last(events(server, id, 'wasteland:survival:client:damage'))
        expect(dmg.args[1] >= 6 and dmg.args[1] <= 10).toBe(true)
    end)

    it('respects the cooldown', function()
        server:clientEvent(id, 'wasteland:zombies:server:hit', netId, id)
        server:advance(100)
        expect(#events(server, id, 'wasteland:survival:client:damage')).toBe(1)
        server:advance(1500)
        server:clientEvent(id, 'wasteland:zombies:server:hit', netId, id)
        server:advance(100)
        expect(#events(server, id, 'wasteland:survival:client:damage')).toBe(2)
    end)

    it('refuses hits from far away or from a client that does not run the zombie', function()
        server:advance(1600)
        z.coords = { x = 50.0, y = 0.0, z = 30.0 }
        server:clientEvent(id, 'wasteland:zombies:server:hit', netId, id)
        server:advance(100)
        expect(#events(server, id, 'wasteland:survival:client:damage')).toBe(2)
        z.coords = { x = 1.0, y = 0.0, z = 30.0 }
        z.owner = 99
        server:clientEvent(id, 'wasteland:zombies:server:hit', netId, id)
        server:advance(100)
        expect(#events(server, id, 'wasteland:survival:client:damage')).toBe(2)
        expect(#server:lines('reported a hit by zombie')).toBe(1)
        z.owner = id
    end)

    it('many hits infect and cause bleeding sometimes', function()
        local infected, bled = false, false
        for _ = 1, 40 do
            server:advance(1600)
            server:clientEvent(id, 'wasteland:zombies:server:hit', netId, id)
            server:advance(50)
            local s = server:export('wasteland_survival', 'GetStats', id)
            if s.infection > 0 then infected = true end
            if s.bleeding > 0 then bled = true end
            server:export('wasteland_survival', 'Heal', id)
        end
        expect(infected).toBe(true); expect(bled).toBe(true)
        expect(#server.scriptErrors).toBe(0)
    end)

    it('an armor plate takes the hits: no damage, no bleeding', function()
        local inv = function(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        inv('AddItem', id, 'armor_plate', 1); server:advance(100)
        local plate = inv('FindItems', id, 'armor_plate')[1]
        server:clientEvent(id, 'wasteland:inventory:server:equip', plate.uid, plate.inventoryId, 'armor'); server:advance(300)
        local damage = #events(server, id, 'wasteland:survival:client:damage')
        local bled = false
        for _ = 1, 20 do
            server:advance(1600)
            server:clientEvent(id, 'wasteland:zombies:server:hit', netId, id)
            server:advance(50)
            if server:export('wasteland_survival', 'GetStats', id).bleeding > 0 then bled = true end
        end
        expect(#events(server, id, 'wasteland:survival:client:damage')).toBe(damage)
        expect(bled).toBe(false)
        local worn
        for _, w in ipairs(inv('GetWornItems', id)) do if w.slot == 'armor' then worn = w end end
        expect(worn.metadata.durability < 100).toBe(true)
    end)
end)

describe('noise, deaths, loot and despawning', function()
    local server = world()
    local id = player(server, 'noise')
    local near = server:export('wasteland_zombies', 'SpawnZombie', { x = 60.0, y = 0.0, z = 30.0 })
    local far = server:export('wasteland_zombies', 'SpawnZombie', { x = 200.0, y = 0.0, z = 30.0 })
    local zs = server:entityList('wlZombie')

    it('gunshots send zombies that hear them to the shot', function()
        server:triggerEvent('wasteland_weapons', 'wasteland:weapons:used', id, 'weapon_pistol', 2, 120, { x = 0.0, y = 0.0, z = 30.0 })
        local inv = zs[1].state.wlInvestigate
        expect(inv.x).toBe(0.0)
        expect(zs[2].state.wlInvestigate).toBe(nil)
    end)

    it('a dead zombie (reported by its client, really hurt) drops loot and is removed later', function()
        zs[1].health = 0
        server:clientEvent(id, 'wasteland:zombies:server:died', near)
        server:advance(300)
        local drops = last(events(server, -1, 'wasteland:inventory:client:drops')).args[1]
        local loot
        for _, d in ipairs(drops) do if d.label == 'Zombie remains' then loot = d end end
        expect(loot ~= nil).toBe(true)
        local stack = server:export('wasteland_inventory', 'GetInventory', 'drop:' .. loot.id).items[1]
        expect(stack.name).toBe('cash'); expect(stack.count).toBe(10)
        expect(select(2, server:export('wasteland_zombies', 'GetZombieCount'))).toBe(1)
        server:advance(11000)
        expect(server:entity(zs[1].handle)).toBe(nil)
    end)

    it('an unhurt zombie cannot be reported dead', function()
        server:clientEvent(id, 'wasteland:zombies:server:died', far)
        server:advance(200)
        expect(select(2, server:export('wasteland_zombies', 'GetZombieCount'))).toBe(1)
    end)

    it('zombies far from every player are removed', function()
        server.players[id].coords = { x = -500.0, y = 0.0, z = 30.0 }
        server:advance(7000)
        expect(server:entity(zs[2].handle)).toBe(nil)
        expect(server:export('wasteland_zombies', 'GetZombieCount')).toBe(0)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('zombie admin command and stopping', function()
    local server = world()
    local id = player(server, 'adm')
    server:export('wasteland_zombies', 'SpawnZombie', { x = 80.0, y = 0.0, z = 30.0 })

    it('needs the admin ACE; clear removes all', function()
        server:command(id, 'zombies clear'); server:advance(100)
        expect(#server:lines('tried "zombies" without the wasteland.admin ACE')).toBe(1)
        expect(server:export('wasteland_zombies', 'GetZombieCount')).toBe(1)
        server.aces[id .. '|wasteland.admin'] = true
        server:command(id, 'zombies spawn 2'); server:advance(100)
        local req = last(events(server, id, 'wasteland:zombies:client:findSpawns'))
        expect(req.args[1]).toBe(2); expect(req.args[2]).toBe(15)
        server:command(id, 'zombies clear'); server:advance(100)
        expect(server:export('wasteland_zombies', 'GetZombieCount')).toBe(0)
    end)

    it('stopping the module removes its zombies', function()
        server:export('wasteland_zombies', 'SpawnZombie', { x = 80.0, y = 0.0, z = 30.0 })
        server:stop('wasteland_zombies')
        server:advance(100)
        expect(#server:entityList('wlZombie')).toBe(0)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('custom zombie kinds and models', function()
    local CFG2 = {}
    for k, v in pairs(CFG) do CFG2[k] = v end
    CFG2['zombies.lua'] = [[return {
        population = { perPlayer = 0, maxTotal = 20 },
        kinds = {
            walker = { speed = 1.0 },
            brute = { speed = 1.3, chance = 100, nightChance = 100, damage = { 20, 20 }, models = { 'my_brute' } },
        },
        models = { 'u_m_y_zombie_01' },
    }]]
    local server = newServer({ config = CFG2 })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival', 'wasteland_zombies' })
    local id = player(server, 'kinds')
    local env = server.resources.wasteland_zombies.env

    it('clients learn every model, including each kind\'s own', function()
        local c = last(events(server, -1, 'wasteland:zombies:client:config')).args[1]
        local names = table.concat(c.models, ',')
        expect(names:find('u_m_y_zombie_01', 1, true) ~= nil).toBe(true)
        expect(names:find('my_brute', 1, true) ~= nil).toBe(true)
    end)

    it('a kind with its own models uses them', function()
        local netId = server:export('wasteland_zombies', 'SpawnZombie', { x = 5.0, y = 0.0, z = 30.0 }, 'brute')
        local e = server.entities[netId - 5000]
        expect(e.model).toBe(env.GetHashKey('my_brute'))
        expect(e.state.wlZombie.kind).toBe('brute')
    end)

    it('a model a player game lacks is no longer used (warned once)', function()
        server:clientEvent(id, 'wasteland:zombies:server:missingModels', { 'my_brute', 'not_ours' }); server:advance(100)
        expect(#server:lines('zombie model "my_brute" is not in the game of player')).toBe(1)
        expect(#server:lines('not_ours')).toBe(0) -- not a configured model: ignored
        local netId = server:export('wasteland_zombies', 'SpawnZombie', { x = 6.0, y = 0.0, z = 30.0 }, 'brute')
        expect(server.entities[netId - 5000].model).toBe(env.GetHashKey('u_m_y_zombie_01'))
        expect(#server:lines('raised:')).toBe(0)
    end)
end)

