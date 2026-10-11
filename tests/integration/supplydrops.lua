-- wasteland_supplydrops (server): the SDK example module, tested the way you
-- would test your own module. Pattern:
--   1. a small test config (fast timings, known points)
--   2. teach the in-memory database the module's SQL (server/sql.lua)
--   3. boot the modules it needs, make a player with a character
--   4. drive it with exports, client events and time (server:advance)
--   5. check what clients were told, the database and the logs

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['supplydrops.lua'] = [[return {
        intervalMinutes = 1, lifetimeMinutes = 2, minPlayers = 1, lootTable = '',
        rolls = { 1, 1 }, items = { { name = 'bandage', min = 3, max = 3, weight = 1 } },
        points = { { x = 100.0, y = 100.0, z = 30.0, label = 'the test field' } },
    }]],
}

-- 2. The module's statements, answered by the in-memory database.
local function teachDatabase(server)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_supplydrops/server/sql.lua', 't', env))()
    local SQL, db = env.WLSD.SQL, server.db.backend
    db.data.wl_supply_drops = {}
    local nextId = 0
    db:on(SQL.insert, function(d, p)
        nextId = nextId + 1
        d.data.wl_supply_drops[nextId] = { id = nextId, label = p[1], x = p[2], y = p[3], z = p[4], created_unix = p[5] }
        return { insertId = nextId, affectedRows = 1 }
    end)
    db:on(SQL.opened, function(d, p)
        local row = d.data.wl_supply_drops[p[3]]
        if not row or row.opened_by then return { affectedRows = 0 } end
        row.opened_by, row.opened_unix = p[1], p[2]
        return { affectedRows = 1 }
    end)
end

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end

describe('supply drops (SDK example)', function()
    local server = newServer({ config = CFG })
    teachDatabase(server)
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_supplydrops' })
    local id = server:connectAndJoin({ name = 'P-sd', license = 'sd' })
    server:advance(200)
    server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
    server:command(id, 'character create Drop Test'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
    local function SD(fn, ...) return server:export('wasteland_supplydrops', fn, ...) end

    it('runs (its migration created the table)', function()
        expect(states(server).supplydrops).toBe('running')
        expect(#SD('GetActiveDrops')).toBe(0)
    end)

    it('drops a crate after the interval and tells every client', function()
        server:advance(61000)
        local list = SD('GetActiveDrops')
        expect(#list).toBe(1)
        expect(list[1].label).toBe('the test field')
        local e = last(events(server, -1, 'wasteland:supplydrops:client:drop')).args
        expect(e[1].id).toBe(list[1].id); expect(e[2]).toBe(true)
        expect(server.db.backend.data.wl_supply_drops[list[1].id].label).toBe('the test field')
    end)

    it('only opens for a player standing at it; the first opener fills it', function()
        local drop = SD('GetActiveDrops')[1]
        server:clientEvent(id, 'wasteland:supplydrops:server:open', drop.id); server:advance(300)
        expect(last(events(server, id, 'wasteland:supplydrops:client:notice')).args[1]).toBe('You are too far away.')
        server.players[id].coords = { x = 101.0, y = 100.0, z = 30.0 }
        server:advance(1100) -- the open event is rate limited
        server:clientEvent(id, 'wasteland:supplydrops:server:open', drop.id); server:advance(300)
        expect(#events(server, id, 'wasteland:inventory:client:open')).toBe(1)
        local snap = server:export('wasteland_inventory', 'GetInventory', 'stash:supply_' .. drop.id)
        expect(snap.items[1].name).toBe('bandage'); expect(snap.items[1].count).toBe(3)
        expect(server.db.backend.data.wl_supply_drops[drop.id].opened_by).toBe(1)
    end)

    it('is gone after its lifetime', function()
        server:advance(125000)
        expect(#events(server, -1, 'wasteland:supplydrops:client:remove') >= 1).toBe(true)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)
