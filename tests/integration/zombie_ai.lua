-- Zombie AI upgrade (server): the horde layer answers noises with the
-- nearest zombies (capped, spread out), repeated gunfire reaches further,
-- explosions and crashes are noises, screamers call, spitters hit (checked),
-- specials hit harder, and ai.enabled = false gives the original behaviour.
-- Nothing here spawns zombies.

local BASE = [[
        population = { perPlayer = 0, nightMultiplier = 1, maxTotal = 60, spawnBatch = 3, spawnIntervalSeconds = 60,
            despawnDistance = 230, despawnAfterSeconds = 600, corpseSeconds = 10 },
        loot = { chance = 0, lifetimeMinutes = 5, items = {} },
]]

local function world(ai)
    local server = newServer({ config = {
        ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
        ['players.lua'] = 'return { restoreDelayMs = 200 }',
        ['zombies.lua'] = 'return {' .. BASE .. ' ai = ' .. ai .. ' }',
    } })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival',
        'wasteland_weapons', 'wasteland_zombies' })
    return server
end

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function player(server, license)
    local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
    server:advance(200)
    server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    return id
end

local function shot(server, id, radius, at)
    server:triggerEvent('wasteland_weapons', 'wasteland:weapons:used', id, 'weapon_pistol', 2, radius, at or { x = 0.0, y = 0.0, z = 30.0 })
end

local function heard(zs)
    local n = 0
    for _, z in ipairs(zs) do if z.state.wlInvestigate then n = n + 1 end end
    return n
end

describe('zombie ai: horde', function()
    local server = world('{ specials = { enabled = false }, horde = { maxResponders = 4, spread = 6 } }')
    local id = player(server, 'horde')
    for i = 1, 8 do server:export('wasteland_zombies', 'SpawnZombie', { x = 20.0 + i * 5, y = 0.0, z = 30.0 }) end
    local far = server:export('wasteland_zombies', 'SpawnZombie', { x = 150.0, y = 0.0, z = 30.0 })
    local zs = server:entityList('wlZombie')

    it('only the nearest answer a gunshot (the cap), each to its own spot', function()
        shot(server, id, 100)
        expect(heard(zs)).toBe(4)
        local spots = {}
        for _, z in ipairs(zs) do
            local i = z.state.wlInvestigate
            if i then
                local key = string.format('%.1f:%.1f', i.x, i.y)
                expect(spots[key]).toBe(nil); spots[key] = true
                expect(i.kind).toBe('gunshot'); expect(i.intensity).toBe(2)
            end
        end
        expect(spots['0.0:0.0']).toBe(true) -- the nearest goes to the shot itself
    end)

    it('the same noise in the same spot is not repeated straight away (cooldown)', function()
        for _, z in ipairs(zs) do z.state.wlInvestigate = nil end
        shot(server, id, 100)
        expect(heard(zs)).toBe(0)
    end)

    it('repeated gunfire reaches further: a zombie 150 m away comes after a few shots', function()
        local farZ
        for _, z in ipairs(zs) do if z.netId == far then farZ = z end end
        local reached = false
        for _ = 1, 8 do
            server:advance(500)
            shot(server, id, 100)
            if farZ.state.wlInvestigate then reached = true end
        end
        expect(reached).toBe(true)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('zombie ai: other noises', function()
    local server = world('{ specials = { enabled = false } }')
    local id = player(server, 'boom')
    server:export('wasteland_zombies', 'SpawnZombie', { x = 80.0, y = 0.0, z = 30.0 })
    local zs = server:entityList('wlZombie')

    it('an explosion is heard 120 m away, loud enough to wake sleepers', function()
        server:triggerEvent('wasteland_zombies', 'explosionEvent', id, { posX = 0.0, posY = 0.0, posZ = 30.0 })
        local i = zs[1].state.wlInvestigate
        expect(i ~= nil).toBe(true); expect(i.kind).toBe('explosion'); expect(i.intensity).toBe(3)
    end)

    it('a vehicle crash only counts from a player in a vehicle', function()
        zs[1].state.wlInvestigate = nil
        server:clientEvent(id, 'wasteland:zombies:server:crash'); server:advance(100)
        expect(zs[1].state.wlInvestigate).toBe(nil) -- on foot (and 80 m is out of a crash's 45 m anyway)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('zombie ai: special infected', function()
    local server = world('{ specials = { spitter = { chance = 100 } } }')
    local id = player(server, 'spit')
    local netId = server:export('wasteland_zombies', 'SpawnZombie', { x = 8.0, y = 0.0, z = 30.0 })
    local z = server:entityList('wlZombie')[1]
    z.owner = id
    local function damage() return server:clientEventsFor(id, 'wasteland:survival:client:damage') end

    it('a spitter\'s spit from its own game hurts; again only after its cooldown', function()
        server:clientEvent(id, 'wasteland:zombies:server:spit', netId, id); server:advance(100)
        expect(#damage()).toBe(1)
        expect(damage()[1].args[1]).toBe(8)
        server:clientEvent(id, 'wasteland:zombies:server:spit', netId, id); server:advance(100)
        expect(#damage()).toBe(1)
        server:advance(8000)
        server:clientEvent(id, 'wasteland:zombies:server:spit', netId, id); server:advance(100)
        expect(#damage()).toBe(2)
    end)

    it('refused from too far, or from a game that does not run it', function()
        server:advance(8000)
        z.coords = { x = 30.0, y = 0.0, z = 30.0 }
        server:clientEvent(id, 'wasteland:zombies:server:spit', netId, id); server:advance(100)
        expect(#damage()).toBe(2)
        z.coords = { x = 8.0, y = 0.0, z = 30.0 }
        z.owner = 99
        server:clientEvent(id, 'wasteland:zombies:server:spit', netId, id); server:advance(100)
        expect(#damage()).toBe(2)
        z.owner = id
    end)

    it('only a screamer / howler can call (a spitter cannot)', function()
        local other = server:export('wasteland_zombies', 'SpawnZombie', { x = 40.0, y = 0.0, z = 30.0 })
        server:clientEvent(id, 'wasteland:zombies:server:shout', netId, 'scream'); server:advance(100)
        for _, e in ipairs(server:entityList('wlZombie')) do
            if e.netId == other then expect(e.state.wlInvestigate).toBe(nil) end
        end
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('zombie ai: screamers and brutes', function()
    local server = world('{ specials = { screamer = { chance = 100 } } }')
    local id = player(server, 'scream')
    local netId = server:export('wasteland_zombies', 'SpawnZombie', { x = 5.0, y = 0.0, z = 30.0 })
    local other = server:export('wasteland_zombies', 'SpawnZombie', { x = 50.0, y = 0.0, z = 30.0 })
    local zs = server:entityList('wlZombie')
    zs[1].owner = id

    it('a screamer\'s scream brings the zombies near it', function()
        server:clientEvent(id, 'wasteland:zombies:server:shout', netId, 'scream'); server:advance(100)
        local o
        for _, z in ipairs(zs) do if z.netId == other then o = z end end
        expect(o.state.wlInvestigate ~= nil).toBe(true)
        expect(o.state.wlInvestigate.kind).toBe('scream')
    end)

end)

describe('zombie ai: brutes', function()
    local s2 = world('{ specials = { brute = { chance = 100, damageMult = 3 } } }')
    local p = player(s2, 'brute')
    local n = s2:export('wasteland_zombies', 'SpawnZombie', { x = 1.0, y = 0.0, z = 30.0 }, 'walker')
    s2:entityList('wlZombie')[1].owner = p

    it('brutes hit harder (damageMult), through the usual hit check', function()
        s2:clientEvent(p, 'wasteland:zombies:server:hit', n, p); s2:advance(100)
        local d = s2:clientEventsFor(p, 'wasteland:survival:client:damage')
        expect(#d).toBe(1)
        expect(d[1].args[1] >= 18).toBe(true) -- the test walker does 6-10, x 3
    end)
end)

describe('zombie ai: switched off', function()
    local server = world('{ enabled = false }')
    local id = player(server, 'off')
    for i = 1, 6 do server:export('wasteland_zombies', 'SpawnZombie', { x = 20.0 + i * 5, y = 0.0, z = 30.0 }) end
    local zs = server:entityList('wlZombie')

    it('every zombie that hears the shot goes to the shot itself (the original behaviour)', function()
        shot(server, id, 100)
        expect(heard(zs)).toBe(6)
        for _, z in ipairs(zs) do expect(z.state.wlInvestigate.x).toBe(0.0); expect(z.state.wlInvestigate.kind).toBe(nil) end
    end)

    it('the clients are told it is off', function()
        server:clientEvent(id, 'wasteland:zombies:server:config'); server:advance(100)
        local list = server:clientEventsFor(id, 'wasteland:zombies:client:config')
        expect(list[#list].args[1].ai.enabled).toBe(false)
    end)
end)
