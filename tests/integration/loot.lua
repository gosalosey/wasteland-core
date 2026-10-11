-- wasteland_loot (server): searching world props (checks, timing, fill,
-- shared containers, refills, "found nothing"), zombie bodies, abuse.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['loot.lua'] = [[return {
        containers = {
            dumpster = { label = 'Dumpster', table = 'sure', searchSeconds = 2, refillMinutes = 1, grid = { 4, 4 }, models = { 'prop_dumpster_01a' } },
            bin = { label = 'Trash can', table = 'none', searchSeconds = 1, refillMinutes = 1, models = { 'prop_bin_01a' } },
            body = { label = 'Body', table = 'sure', searchSeconds = 1, refillMinutes = 9999 },
        },
        tables = {
            sure = { emptyChance = 0, rolls = { 1, 1 }, items = { { name = 'bandage', min = 3, max = 3, weight = 1 } } },
            none = { emptyChance = 1, rolls = { 1, 1 }, items = { { name = 'rag', min = 1, max = 1, weight = 1 } } },
        },
    }]],
    ['zombies.lua'] = 'return { population = { perPlayer = 0, corpseSeconds = 30 } }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function world()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival',
        'wasteland_zombies', 'wasteland_loot' })
    return server
end

local function player(server, license, coords)
    local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
    server:advance(200)
    server.players[id].coords = coords or { x = 10.0, y = 10.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    return id
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end

local DUMPSTER = { x = 11.0, y = 10.0, z = 30.0 }

describe('searching world props', function()
    local server = world()
    local a = player(server, 'ann')
    local b = player(server, 'ben', { x = 10.5, y = 10.5, z = 30.0 })
    local env = server.resources.wasteland_loot.env
    local DUMP, BIN = env.GetHashKey('prop_dumpster_01a'), env.GetHashKey('prop_bin_01a')

    it('runs; clients get the container models', function()
        expect(states(server).loot).toBe('running')
        local c = last(events(server, -1, 'wasteland:loot:client:config')).args[1]
        expect(c.containers.dumpster.models[1]).toBe('prop_dumpster_01a')
    end)

    it('refuses models that are not containers and searches from too far', function()
        server:clientEvent(a, 'wasteland:loot:server:start', 12345, DUMPSTER)
        server:advance(100)
        expect(#server:lines('which is not a container')).toBe(1)
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, { x = 50.0, y = 10.0, z = 30.0 })
        server:advance(100)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]).toBe('You are too far away.')
        expect(#events(server, a, 'wasteland:loot:client:search')).toBe(0)
    end)

    it('starts a timed search; finishing early does nothing', function()
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, DUMPSTER)
        server:advance(200)
        local s = last(events(server, a, 'wasteland:loot:client:search')).args[1]
        expect(s.seconds).toBe(2); expect(s.label).toBe('Searching dumpster')
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(100)
        expect(#server:lines('finished searching loot_dumpster_11_10_30 too early')).toBe(1)
        expect(#events(server, a, 'wasteland:inventory:client:open')).toBe(0)
    end)

    it('after the search the container is filled and opens next to the inventory', function()
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, DUMPSTER)
        server:advance(2100)
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(300)
        expect(#events(server, a, 'wasteland:inventory:client:open')).toBe(1)
        local snap = server:export('wasteland_inventory', 'GetInventory', 'stash:loot_dumpster_11_10_30')
        expect(#snap.items).toBe(1); expect(snap.items[1].name).toBe('bandage'); expect(snap.items[1].count).toBe(3)
        expect(snap.label).toBe('Dumpster')
    end)

    it('is shared: the next player finds what is left, and nothing more is added', function()
        server:clientEvent(b, 'wasteland:loot:server:start', DUMP, DUMPSTER)
        server:advance(2100)
        server:clientEvent(b, 'wasteland:loot:server:finish')
        server:advance(300)
        local snap = server:export('wasteland_inventory', 'GetInventory', 'stash:loot_dumpster_11_10_30')
        expect(#snap.items).toBe(1); expect(snap.items[1].count).toBe(3)
    end)

    it('once emptied it stays empty until the refill time', function()
        local uid = server:export('wasteland_inventory', 'GetInventory', 'stash:loot_dumpster_11_10_30').items[1].uid
        server:export('wasteland_inventory', 'RemoveItem', 'stash:loot_dumpster_11_10_30', 'bandage', 3)
        server:advance(100)
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, DUMPSTER)
        server:advance(300)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]).toContain('Already searched')
        server:advance(60000)
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, DUMPSTER)
        server:advance(2100)
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(300)
        local snap = server:export('wasteland_inventory', 'GetInventory', 'stash:loot_dumpster_11_10_30')
        expect(#snap.items).toBe(1); expect(snap.items[1].uid ~= uid).toBe(true)
    end)

    it('an empty roll means "you found nothing" (and it stays empty)', function()
        server:clientEvent(a, 'wasteland:loot:server:start', BIN, { x = 9.0, y = 10.0, z = 30.0 })
        server:advance(1100)
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(300)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]).toBe('You found nothing.')
        server:clientEvent(a, 'wasteland:loot:server:start', BIN, { x = 9.0, y = 10.0, z = 30.0 })
        server:advance(300)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]).toContain('Already searched')
    end)

    it('moving away during the search fails it; a cancelled search cannot be finished', function()
        server.players[a].coords = { x = 30.0, y = 30.0, z = 30.0 }
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, { x = 31.0, y = 30.0, z = 30.0 })
        server:advance(1000)
        server.players[a].coords = { x = 60.0, y = 30.0, z = 30.0 }
        server:advance(1100)
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(300)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]).toBe('You moved away.')
        server.players[a].coords = { x = 30.0, y = 30.0, z = 30.0 }
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, { x = 31.0, y = 30.0, z = 30.0 })
        server:advance(300)
        server:clientEvent(a, 'wasteland:loot:server:cancel')
        server:advance(2100)
        local opens = #events(server, a, 'wasteland:inventory:client:open')
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(300)
        expect(#events(server, a, 'wasteland:inventory:client:open')).toBe(opens)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('searching zombie bodies', function()
    local server = world()
    local a = player(server, 'cat')
    local netId = server:export('wasteland_zombies', 'SpawnZombie', { x = 11.0, y = 10.0, z = 30.0 })
    local z = server:entityList('wlZombie')[1]

    it('a living zombie cannot be searched', function()
        server:clientEvent(a, 'wasteland:loot:server:body', netId)
        server:advance(300)
        expect(#events(server, a, 'wasteland:loot:client:search')).toBe(0)
    end)

    it('a dead one can: its loot opens, and no loot bag is dropped', function()
        z.health = 0
        server:clientEvent(a, 'wasteland:zombies:server:died', netId)
        server:advance(300)
        local drops = last(events(server, -1, 'wasteland:inventory:client:drops'))
        expect(drops == nil or #drops.args[1] == 0).toBe(true)
        server:clientEvent(a, 'wasteland:loot:server:body', netId)
        server:advance(1100)
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(300)
        local name = 'stash:loot_body_' .. z.state.wlZombie.uid
        expect(server:export('wasteland_inventory', 'GetInventory', name).items[1].name).toBe('bandage')
    end)

    it('the body and its loot are gone when the corpse is removed', function()
        local name = 'stash:loot_body_' .. z.state.wlZombie.uid
        server:advance(31000)
        expect(server:entity(z.handle)).toBe(nil)
        expect(server:export('wasteland_inventory', 'GetInventory', name)).toBe(nil)
        local rows = 0
        for _, r in pairs(server.db.backend.data.wl_items) do if r.inventory_id == name then rows = rows + 1 end end
        expect(rows).toBe(0)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
