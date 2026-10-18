-- wasteland_props (server): admins place, move and delete saved props;
-- others are refused; props come back after a restart.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['props.lua'] = "return { presets = { { group = 'Junk', label = 'Barrel', model = 'prop_barrel_02a' } } }",
}

local function teachDatabase(server)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_props/server/sql.lua', 't', env))()
    local SQL, db = env.WLPR.SQL, server.db.backend
    db.data.wl_props = db.data.wl_props or {}
    local nextId = 0
    db:on(SQL.select, function(d)
        local rows = {}
        for _, r in pairs(d.data.wl_props) do rows[#rows + 1] = r end
        return rows
    end)
    db:on(SQL.insert, function(d, p)
        nextId = nextId + 1
        d.data.wl_props[nextId] = { id = nextId, model = p[1], x = p[2], y = p[3], z = p[4], rx = p[5], ry = p[6], rz = p[7], collision = p[8] }
        return { insertId = nextId, affectedRows = 1 }
    end)
    db:on(SQL.update, function(d, p)
        local r = d.data.wl_props[p[8]]
        if not r then return { affectedRows = 0 } end
        r.x, r.y, r.z, r.rx, r.ry, r.rz, r.collision = p[1], p[2], p[3], p[4], p[5], p[6], p[7]
        return { affectedRows = 1 }
    end)
    db:on(SQL.delete, function(d, p)
        d.data.wl_props[p[1]] = nil
        return { affectedRows = 1 }
    end)
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

describe('prop placer', function()
    local server = newServer({ config = CFG })
    teachDatabase(server)
    boot(server, { 'wasteland_players', 'wasteland_ui', 'wasteland_props' })
    local admin = server:connectAndJoin({ name = 'P-admin', license = 'padmin' })
    local plain = server:connectAndJoin({ name = 'P-plain', license = 'pplain' })
    server:advance(300)
    server.players[admin].coords = { x = 0.0, y = 0.0, z = 30.0 }
    server.players[plain].coords = { x = 0.0, y = 0.0, z = 30.0 }
    server.aces[admin .. '|wasteland.admin'] = true

    it('runs', function()
        expect(states(server).props).toBe('running')
    end)

    it('refuses players who are not admins', function()
        server:clientEvent(plain, 'wasteland:props:server:open'); server:advance(200)
        expect(#events(server, plain, 'wasteland:props:client:open')).toBe(0)
        server:clientEvent(plain, 'wasteland:props:server:place', 'prop_barrel_02a', 1.0, 1.0, 30.0, 0.0, 0.0, 90.0, true); server:advance(300)
        expect(count(server.db.backend.data.wl_props)).toBe(0)
    end)

    it('an admin opens the placer with the presets and places a prop (saved, sent to everyone)', function()
        server:clientEvent(admin, 'wasteland:props:server:open'); server:advance(200)
        expect(last(events(server, admin, 'wasteland:props:client:open')).args[1].presets[1].model).toBe('prop_barrel_02a')
        server:clientEvent(admin, 'wasteland:props:server:place', 'prop_barrel_02a', 2.0, 3.0, 30.5, 0.0, 0.0, 450.0, false); server:advance(300)
        local row = server.db.backend.data.wl_props[1]
        expect(row.model).toBe('prop_barrel_02a')
        expect(row.rz).toBe(90.0)
        local set = last(events(server, plain, 'wasteland:props:client:set')).args[1]
        expect(set.id).toBe(1); expect(set.collision).toBe(false)
    end)

    it('refuses spots far from the admin and bad model names', function()
        server:clientEvent(admin, 'wasteland:props:server:place', 'prop_barrel_02a', 500.0, 0.0, 30.0, 0.0, 0.0, 0.0, true); server:advance(300)
        expect(last(events(server, admin, 'wasteland:props:client:notice')).args[1]).toContain('too far')
        server:advance(1100)
        server:clientEvent(admin, 'wasteland:props:server:place', 'bad model;', 1.0, 0.0, 30.0, 0.0, 0.0, 0.0, true); server:advance(300)
        expect(count(server.db.backend.data.wl_props)).toBe(1)
    end)

    it('moves and deletes', function()
        server:advance(1100)
        server:clientEvent(admin, 'wasteland:props:server:update', 1, 4.0, 4.0, 30.0, 0.0, 0.0, 10.0, true); server:advance(300)
        expect(server.db.backend.data.wl_props[1].x).toBe(4.0)
        server:clientEvent(admin, 'wasteland:props:server:place', 'prop_barrel_02a', 1.0, 1.0, 30.0, 0.0, 0.0, 0.0, true); server:advance(300)
        server:clientEvent(admin, 'wasteland:props:server:delete', 2); server:advance(300)
        expect(server.db.backend.data.wl_props[2]).toBe(nil)
        expect(last(events(server, -1, 'wasteland:props:client:remove')).args[1]).toBe(2)
    end)

    it('props come back after a restart', function()
        server:restart('wasteland_props'); server:advance(2000)
        expect(states(server).props).toBe('running')
        local list = last(events(server, -1, 'wasteland:props:client:list')).args[1]
        expect(#list).toBe(1); expect(list[1].x).toBe(4.0)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
