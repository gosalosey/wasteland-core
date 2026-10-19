-- Real-database suite: the database and players modules run in the
-- simulated server, but every statement goes to a real MariaDB/MySQL server
-- through the command-line client (tests/lib/mariadbcli.lua). This proves
-- the migrations and SQL are valid on the real database engine.
-- Skipped unless WL_TEST_DB_USER is set (see docs/TESTING.md).

local CLI = require('lib.mariadbcli')
local cfg = CLI.configFromEnv(ROOT .. '/tests/db.env')
if not cfg then
    skip('real MariaDB suite', 'configure tests/db.env or WL_TEST_DB_* variables to run it; see docs/TESTING.md')
    return
end

local IS_WINDOWS = package.config:sub(1, 1) == '\\'
local tmp = ROOT .. '/tests/.tmp'
os.execute(IS_WINDOWS and ('if not exist "' .. tmp:gsub('/', '\\') .. '" mkdir "' .. tmp:gsub('/', '\\') .. '"') or ('mkdir -p "' .. tmp .. '"'))
local backend = CLI.new(cfg, tmp)

local function loadSql()
    local env = { WLP = {} }
    assert(loadfile(RESOURCES .. '/wasteland_players/server/sql.lua', 't', env))()
    return env.WLP
end
local WLP = loadSql()

local OBSERVER = [[
Wasteland.DefineModule({ name = 'obs', version = '1.0.0', core = '^1.1.0', dependencies = { players = '^0.1.0' } })
exports('Save', function(cid)
    exports.wasteland_players:SaveCharacter(cid, function(ok, err) track('saved ' .. cid .. ' ' .. tostring(ok) .. ' ' .. tostring(err)) end)
end)
]]

describe('real MariaDB (' .. cfg.user .. '@' .. cfg.host .. ':' .. cfg.port .. '/' .. cfg.database .. ')', function()
    local okReset, resetErr = backend:resetDatabase()
    it('can reset the test database', function()
        expect(resetErr).toBe(nil)
        expect(okReset).toBe(true)
    end)
    if not okReset then return end

    local server = newServer({ dbBackend = backend, config = {
        ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 60000, slowQueryWarningMs = 60000 }',
        ['players.lua'] = 'return { saveIntervalSeconds = 10, positionSampleSeconds = 1, maxCharacters = 2 }',
    } })
    server.db.latencyMs = 0
    addModule(server, 'fx_obs', OBSERVER, { 'wasteland_players' })
    boot(server, { 'wasteland_players', 'fx_obs' })
    local function P(fn, ...) return server:export('wasteland_players', fn, ...) end
    local function cmd(id, line) server:command(id, line); server:advance(200) end

    it('runs the migrations as real DDL and records them', function()
        expect(states(server).database).toBe('running')
        expect(states(server).players).toBe('running')
        local rows = backend:rows('SELECT module_name, version, name, checksum FROM wl_migrations ORDER BY version')
        expect(#rows).toBe(3)
        expect(rows[1].name).toBe('create_accounts')
        expect(rows[3].version).toBe(3)
        expect(#rows[1].checksum).toBe(8)
    end)

    it('verifies checksums and applies nothing on restart', function()
        server:restart('wasteland_players')
        server:advance(2000)
        expect(states(server).players).toBe('running')
        expect(#backend:rows('SELECT version FROM wl_migrations')).toBe(3)
    end)

    local id = server:connectAndJoin({ name = 'Alice', license = 'alice', identifiers = { 'ip:10.0.0.1', 'discord:7' } })
    server:advance(200)

    it('creates the account on connect (no IP stored)', function()
        expect(id ~= nil).toBe(true)
        local a = backend:rows('SELECT id, license, name, identifiers FROM wl_accounts')
        expect(#a).toBe(1)
        expect(a[1].license).toBe('license:alice')
        expect(a[1].identifiers).toBe('discord:7,license:alice')
    end)

    it('creates characters and the unique slot key holds', function()
        cmd(id, 'character create John Doe')
        cmd(id, "character create Mary O'Neil")
        local rows = backend:rows('SELECT id, slot, first_name, last_name, pos_x FROM wl_characters ORDER BY slot')
        expect(#rows).toBe(2)
        expect(rows[2].last_name).toBe("O'Neil")
        expect(rows[1].pos_x).toBe(1734.0)
        local dupe, err = backend:execute('insert', WLP.SQL.insertCharacter, { 1, 1, 'Dup', 'Licate', 0, 0, 0, 0 })
        expect(dupe).toBe(nil)
        expect(err).toContain('Duplicate entry')
    end)

    it('lists characters with numeric timestamps', function()
        local rows, err = backend:execute('query', WLP.SQL.listCharacters, { 1 })
        expect(err).toBe(nil)
        expect(#rows).toBe(2)
        expect(tonumber(rows[1].created_at) ~= nil).toBe(true)
        expect(rows[1].last_played).toBe(nil)
    end)

    it('loads a character', function()
        cmd(id, 'character select 1')
        server:clientEvent(id, 'wasteland:players:server:placed')
        expect(P('GetCharacterId', id)).toBe(1)
        local r = backend:rows('SELECT last_played IS NOT NULL AS touched FROM wl_characters WHERE id = 1')
        expect(r[1].touched).toBe(1)
    end)

    it('stores character data as JSON and counts revisions', function()
        P('SetCharacterData', 1, 'survival', { hunger = 80, note = 'quote \' and \\ backslash' })
        server:export('fx_obs', 'Save', 1); server:advance(200)
        local r = backend:rows("SELECT data, revision FROM wl_character_data WHERE character_id = 1 AND data_key = 'survival'")
        expect(r[1].revision).toBe(1)
        expect(r[1].data).toContain('"hunger":80')
        expect(r[1].data).toContain([[quote ' and \\ backslash]])
        P('SetCharacterData', 1, 'survival', { hunger = 70 })
        server:export('fx_obs', 'Save', 1); server:advance(200)
        r = backend:rows("SELECT data, revision FROM wl_character_data WHERE character_id = 1 AND data_key = 'survival'")
        expect(r[1].revision).toBe(2)
        P('SetCharacterData', 1, 'temp', 1)
        server:export('fx_obs', 'Save', 1); server:advance(200)
        P('SetCharacterData', 1, 'temp', nil)
        server:export('fx_obs', 'Save', 1); server:advance(200)
        expect(#backend:rows("SELECT data_key FROM wl_character_data WHERE data_key = 'temp'")).toBe(0)
    end)

    it('saves the position periodically', function()
        server.players[id].coords = { x = 100.25, y = -200.5, z = 30.75 }
        server.players[id].heading = 45.5
        server:advance(11000)
        local r = backend:rows('SELECT pos_x, pos_y, pos_z, heading, play_seconds FROM wl_characters WHERE id = 1')
        expect(r[1].pos_x).toBe(100.25)
        expect(r[1].pos_y).toBe(-200.5)
        expect(r[1].heading).toBe(45.5)
        expect(r[1].play_seconds > 0).toBe(true)
    end)

    it('rolls a failed transaction back completely', function()
        local ok = backend:transaction({
            { 'UPDATE wl_characters SET first_name = ? WHERE id = ?', { 'Changed', 1 } },
            { 'SELECT no_such_column FROM wl_characters', {} },
        })
        expect(ok).toBe(false)
        expect(backend:rows('SELECT first_name FROM wl_characters WHERE id = 1')[1].first_name).toBe('John')
    end)

    it('saves on drop and restores on reconnect', function()
        P('SetCharacterData', 1, 'survival', { hunger = 12 })
        server:dropPlayer(id)
        server:advance(500)
        local id2 = server:connectAndJoin({ name = 'Alice', license = 'alice' })
        server:advance(200)
        cmd(id2, 'character select 1')
        server:clientEvent(id2, 'wasteland:players:server:placed')
        expect(P('GetCharacterData', 1, 'survival').hunger).toBe(12)
        id = id2
    end)

    it('soft-deletes a character and frees its slot', function()
        cmd(id, 'character delete 2 Mary')
        local r = backend:rows('SELECT slot, deleted_at IS NOT NULL AS gone FROM wl_characters WHERE id = 2')
        expect(r[1].slot).toBe(nil)
        expect(r[1].gone).toBe(1)
        cmd(id, 'character create Ann Lee')
        local r2 = backend:rows("SELECT slot FROM wl_characters WHERE first_name = 'Ann'")
        expect(r2[1].slot).toBe(2)
    end)

    it('ran every players statement against the real database', function()
        local ran = {}
        for _, l in ipairs(backend.log) do ran[l.sql] = true end
        local missing = {}
        for key, sql in pairs(WLP.SQL) do
            if not ran[(sql:gsub('%s+', ' '))] then missing[#missing + 1] = key end
        end
        table.sort(missing)
        expect(missing).toEqual({})
    end)

    it('raised no script errors', function()
        for _, e in ipairs(server.scriptErrors) do print('       ' .. e) end
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('real MariaDB: inventory', function()
    local env = { WLI = {} }
    assert(loadfile(RESOURCES .. '/wasteland_inventory/server/sql.lua', 't', env))()
    local WLI = env.WLI
    local appearanceEnv = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', appearanceEnv))()

    local server = newServer({ dbBackend = backend, config = {
        ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 60000, slowQueryWarningMs = 60000 }',
        ['players.lua'] = 'return { maxCharacters = 2 }',
    } })
    server.db.latencyMs = 0
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory' })
    local id = server:connectAndJoin({ name = 'Zed', license = 'zed' })
    server:advance(200)
    server.players[id].coords = { x = 50.0, y = 50.0, z = 30.0 }
    server:command(id, 'character create Zed Zero'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', appearanceEnv.WLA.defaults('mp_f_freemode_01'))
    server:advance(1000)
    local function snap()
        local l = server:clientEventsFor(id, 'wasteland:inventory:client:sync')
        return l[#l].args[1]
    end
    local function find(name)
        for _, i in ipairs(snap().inventories) do
            for _, s in ipairs(i.items) do if s.name == name then return s, i.id end end
        end
    end
    local function op(name, ...) server:clientEvent(id, 'wasteland:inventory:server:' .. name, ...); server:advance(1500) end
    local pockets = snap().pockets

    it('runs the inventory migrations and stores starting items and worn clothes', function()
        expect(states(server).inventory).toBe('running')
        local items = backend:rows('SELECT name, count, pos_x, slot, metadata FROM wl_items WHERE inventory_id = ?', { pockets })
        expect(#items).toBe(4) -- with the $50 starting cash
        local worn = backend:rows("SELECT name, slot, metadata FROM wl_items WHERE inventory_id LIKE 'equip:%'")
        expect(#worn).toBe(3)
        expect(worn[1].metadata).toContain('mp_f_freemode_01')
    end)

    it('moves, splits and merges with real rows (a fully merged stack is deleted)', function()
        local beans = find('canned_beans')
        op('move', beans.uid, pockets, pockets, 5, 3, false)
        expect(backend:rows('SELECT pos_x, pos_y FROM wl_items WHERE uid = ?', { beans.uid })[1].pos_x).toBe(5)
        op('split', beans.uid, pockets, 1)
        local stacks = backend:rows("SELECT uid, count FROM wl_items WHERE name = 'canned_beans' AND uid <> ?", { beans.uid })
        expect(#stacks).toBe(1) -- the new stack from the split
        op('merge', stacks[1].uid, pockets, beans.uid, pockets, 1)
        local after = backend:rows("SELECT uid, count FROM wl_items WHERE name = 'canned_beans'")
        expect(#after).toBe(1)
        expect(after[1].count).toBe(2)
    end)

    it('drops to the ground (wl_drops) and picks up again (the empty drop is removed)', function()
        local bottle = find('water_bottle')
        op('drop', bottle.uid, pockets)
        local drops = backend:rows('SELECT id FROM wl_drops')
        expect(#drops).toBe(1)
        expect(backend:rows('SELECT inventory_id FROM wl_items WHERE uid = ?', { bottle.uid })[1].inventory_id).toBe('drop:' .. drops[1].id)
        op('openDrop', drops[1].id)
        op('move', bottle.uid, 'drop:' .. drops[1].id, pockets, 0, 2, false)
        expect(#backend:rows('SELECT id FROM wl_drops')).toBe(0)
        expect(backend:rows('SELECT inventory_id FROM wl_items WHERE uid = ?', { bottle.uid })[1].inventory_id).toBe(pockets)
    end)

    it('reloads the same inventory after a restart of the resource', function()
        server:restart('wasteland_inventory')
        server:advance(5000)
        local bottle = find('water_bottle')
        expect(bottle.x).toBe(0)
        expect(bottle.y).toBe(2)
    end)

    it('stores a body bag with owner, label and expiry', function()
        local result = server:export('wasteland_inventory', 'DeathDrop', id, 'Body of Zed Zero')
        server:advance(1500)
        local r = backend:rows('SELECT owner_character, label, expires_unix - created_unix AS life FROM wl_drops WHERE id = ?', { result.dropIds[1] })
        expect(r[1].owner_character).toBe(server:export('wasteland_players', 'GetCharacterId', id))
        expect(r[1].label).toBe('Body of Zed Zero')
        expect(r[1].life).toBe(7200)
    end)

    it('ran every inventory statement against the real database', function()
        local ran = {}
        for _, l in ipairs(backend.log) do ran[l.sql] = true end
        local missing = {}
        for key, sql in pairs(WLI.SQL) do
            if not ran[(sql:gsub('%s+', ' '))] then missing[#missing + 1] = key end
        end
        table.sort(missing)
        expect(missing).toEqual({})
        for _, e in ipairs(server.scriptErrors) do print('       ' .. e) end
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('real MariaDB: admin', function()
    local env = { WLA_ADMIN = {} }
    assert(loadfile(RESOURCES .. '/wasteland_admin/server/sql.lua', 't', env))()
    local SQLA = env.WLA_ADMIN.SQL
    local server = newServer({ dbBackend = backend, config = {
        ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 60000, slowQueryWarningMs = 60000 }',
    } })
    server.db.latencyMs = 0
    boot(server, { 'wasteland_players', 'wasteland_admin' })
    local admin = server:connectAndJoin({ name = 'Boss', license = 'boss' })
    server.aces[admin .. '|wasteland.admin'] = true
    local function act(action, args)
        server:clientEvent(admin, 'wasteland:admin:server:act', action, args)
        server:advance(3000)
        local l = server:clientEventsFor(admin, 'wasteland:admin:client:result')
        return l[#l].args[1]
    end

    it('stores, enforces and lifts bans, and writes the action log', function()
        expect(states(server).admin).toBe('running')
        expect(act('banLicense', { license = 'license:feedbeef', name = 'Ghost', reason = "can't play", minutes = 60 }).ok).toBe(true)
        local b = backend:rows('SELECT id, reason, expires_unix - created_unix AS life FROM wl_bans WHERE license = ?', { 'license:feedbeef' })
        expect(b[1].reason).toBe("can't play")
        expect(b[1].life).toBe(3600)
        local _, err = server:connectAndJoin({ name = 'Ghost', license = 'feedbeef' })
        expect(err).toContain("Reason: can't play")
        server:clientEvent(admin, 'wasteland:admin:server:list', 'bans'); server:advance(2000)
        expect(act('unban', { banId = b[1].id }).ok).toBe(true)
        expect(backend:rows('SELECT revoked_by FROM wl_bans WHERE id = ?', { b[1].id })[1].revoked_by).toBe('Boss')
        server:clientEvent(admin, 'wasteland:admin:server:list', 'log'); server:advance(2000)
        local log = backend:rows('SELECT action, admin FROM wl_admin_log ORDER BY id')
        expect(log[1].action).toBe('ban')
        expect(log[1].admin).toBe('Boss')
    end)

    it('ran every admin statement against the real database', function()
        local ran = {}
        for _, l in ipairs(backend.log) do ran[l.sql] = true end
        local missing = {}
        for key, sql in pairs(SQLA) do
            if not ran[(sql:gsub('%s+', ' '))] then missing[#missing + 1] = key end
        end
        table.sort(missing)
        expect(missing).toEqual({})
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('real MariaDB: vehicles', function()
    local env = { WLV = {} }
    assert(loadfile(RESOURCES .. '/wasteland_vehicles/server/sql.lua', 't', env))()
    local SQLV = env.WLV.SQL
    local server = newServer({ dbBackend = backend, config = {
        ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 60000, slowQueryWarningMs = 60000 }',
        ['vehicles.lua'] = [[return { spotCheck = { enabled = false }, maxVehicles = 2, respawnMinutes = 1000, saveSeconds = 4, despawnAfterSeconds = 4,
            models = { 'rebel' }, spawnPoints = { { x = 1000.0, y = 0.0, z = 30.0 }, { x = 5000.0, y = 0.0, z = 30.0 } } }]],
    } })
    server.db.latencyMs = 0
    boot(server, { 'wasteland_players', 'wasteland_inventory', 'wasteland_vehicles' })

    it('stores wrecks, saves position and damage, deletes destroyed ones', function()
        expect(states(server).vehicles).toBe('running')
        expect(#backend:rows('SELECT id FROM wl_vehicles')).toBe(2)
        local id = server:connectAndJoin({ name = 'Driver', license = 'driver' })
        server.players[id].coords = { x = 990.0, y = 0.0, z = 30.0 }
        server:advance(3000)
        local e = server:entityList('wlVeh')[1]
        server:clientEvent(e.owner, 'wasteland:vehicles:server:applied', e.netId, e.state.wlVeh.seq); server:advance(500)
        e.coords = { x = 1010.5, y = 2.0, z = 30.0 }
        e.engine = 321.0
        server:advance(5000)
        local row = backend:rows('SELECT x, engine, parts FROM wl_vehicles WHERE x > 1005 AND x < 1020')[1]
        expect(row ~= nil).toBe(true)
        expect(math.floor(row.engine)).toBe(321)
        e.engine = -4000.0
        server:advance(3000)
        expect(#backend:rows('SELECT id FROM wl_vehicles')).toBe(1)
    end)

    it('ran every vehicle statement against the real database', function()
        local ran = {}
        for _, l in ipairs(backend.log) do ran[l.sql] = true end
        local missing = {}
        for key, sql in pairs(SQLV) do
            if not ran[(sql:gsub('%s+', ' '))] then missing[#missing + 1] = key end
        end
        table.sort(missing)
        expect(missing).toEqual({})
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('real MariaDB: supply drops (SDK example)', function()
    local env = { WLSD = {} }
    assert(loadfile(RESOURCES .. '/wasteland_supplydrops/server/sql.lua', 't', env))()
    local SQLS = env.WLSD.SQL
    local server = newServer({ dbBackend = backend, config = {
        ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 60000, slowQueryWarningMs = 60000 }',
        ['supplydrops.lua'] = [[return { intervalMinutes = 0, lootTable = '', rolls = { 1, 1 },
            items = { { name = 'bandage', min = 2, max = 2, weight = 1 } },
            points = { { x = 100.0, y = 100.0, z = 30.0, label = 'the test field' } } }]],
    } })
    server.db.latencyMs = 0
    boot(server, { 'wasteland_players', 'wasteland_inventory', 'wasteland_supplydrops' })

    it('creates its table, stores a drop and who opened it', function()
        expect(states(server).supplydrops).toBe('running')
        local id = server:connectAndJoin({ name = 'Looter', license = 'looter' })
        server:advance(200)
        server.players[id].coords = { x = 101.0, y = 100.0, z = 30.0 }
        server:command(id, 'character create Lou Ter'); server:advance(500)
        server:command(id, 'character select 1'); server:advance(800)
        server:export('wasteland_supplydrops', 'SpawnDrop'); server:advance(800)
        local drop = server:export('wasteland_supplydrops', 'GetActiveDrops')[1]
        expect(drop ~= nil).toBe(true)
        server:clientEvent(id, 'wasteland:supplydrops:server:open', drop.id); server:advance(1500)
        local row = backend:rows('SELECT label, opened_by FROM wl_supply_drops WHERE id = ?', { drop.id })[1]
        expect(row.label).toBe('the test field')
        expect(row.opened_by ~= nil).toBe(true)
    end)

    it('ran every supply drop statement against the real database', function()
        local ran = {}
        for _, l in ipairs(backend.log) do ran[l.sql] = true end
        local missing = {}
        for key, sql in pairs(SQLS) do
            if not ran[(sql:gsub('%s+', ' '))] then missing[#missing + 1] = key end
        end
        table.sort(missing)
        expect(missing).toEqual({})
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('real MariaDB: groups', function()
    local env = { WLG = {} }
    assert(loadfile(RESOURCES .. '/wasteland_groups/server/sql.lua', 't', env))()
    local SQLG = env.WLG.SQL
    local server = newServer({ dbBackend = backend, config = {
        ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 60000, slowQueryWarningMs = 60000 }',
    } })
    server.db.latencyMs = 0
    boot(server, { 'wasteland_players', 'wasteland_groups' })

    it('stores a group and its members, renames, new leader, leaving, disbanding', function()
        expect(states(server).groups).toBe('running')
        local function join(license, first)
            local id = server:connectAndJoin({ name = first, license = license })
            server:advance(200)
            server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
            server:command(id, 'character create ' .. first .. ' Db'); server:advance(500)
            server:command(id, 'character select 1'); server:advance(800)
            return id
        end
        local a, b = join('dbga', 'Ava'), join('dbgb', 'Ben')
        local function act(id, what, ...) server:clientEvent(id, 'wasteland:groups:server:' .. what, ...); server:advance(1500) end
        act(a, 'create', 'Db Crew')
        local g = backend:rows("SELECT id, leader_id FROM wl_groups WHERE name = 'Db Crew'")[1]
        expect(g ~= nil).toBe(true)
        act(a, 'invite', b)
        act(b, 'respond', g.id, true)
        expect(#backend:rows('SELECT character_id FROM wl_group_members WHERE group_id = ?', { g.id })).toBe(2)
        act(a, 'rename', 'Db Crew Two')
        local bId = server:export('wasteland_players', 'GetCharacterId', b)
        act(a, 'promote', bId)
        expect(backend:rows('SELECT leader_id FROM wl_groups WHERE id = ?', { g.id })[1].leader_id).toBe(bId)
        act(a, 'leave')
        local aId = server:export('wasteland_players', 'GetCharacterId', a)
        expect(#backend:rows('SELECT character_id FROM wl_group_members WHERE character_id = ?', { aId })).toBe(0)
        server:clientEvent(b, 'wasteland:groups:server:invite', a); server:advance(1500)
        act(a, 'respond', g.id, true)
        server:clientEvent(b, 'wasteland:groups:server:kick', aId); server:advance(1500)
        act(b, 'disband')
        expect(#backend:rows('SELECT id FROM wl_groups WHERE id = ?', { g.id })).toBe(0)
    end)

    it('ran every group statement against the real database', function()
        local ran = {}
        for _, l in ipairs(backend.log) do ran[l.sql] = true end
        local missing = {}
        for key, sql in pairs(SQLG) do
            if not ran[(sql:gsub('%s+', ' '))] then missing[#missing + 1] = key end
        end
        table.sort(missing)
        expect(missing).toEqual({ 'memberName' })   -- only when a member's name changed
        expect(#server.scriptErrors).toBe(0)
    end)
end)



describe('real MariaDB: base building', function()
    local env = { WLBB = {} }
    assert(loadfile(RESOURCES .. '/wasteland_basebuilding/server/sql.lua', 't', env))()
    local SQLBB = env.WLBB.SQL
    local server = newServer({ dbBackend = backend, config = {
        ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 60000, slowQueryWarningMs = 60000 }',
        ['basebuilding.lua'] = (io.open(RESOURCES .. '/wasteland_config/config/basebuilding.lua'):read('a')
            :gsub('tickMinutes = 5,', 'tickMinutes = 1,'):gsub('perPieceCostPerDay = { wood = 1, stone = 1, metal = 1 },',
                'perPieceCostPerDay = { wood = 1440, stone = 1440, metal = 1440 },')),
    } })
    server.db.latencyMs = 0
    boot(server, { 'wasteland_players', 'wasteland_inventory', 'wasteland_basebuilding' })

    it('stores cupboards, access, pieces, doors, upgrades, health, raid notices', function()
        expect(states(server).basebuilding).toBe('running')
        local function join(license, first, x)
            local id = server:connectAndJoin({ name = first, license = license })
            server:advance(200)
            server:command(id, 'character create ' .. first .. ' Db'); server:advance(500)
            server:command(id, 'character select 1'); server:advance(800)
            server.players[id].coords = { x = x, y = 900.0, z = 30.0 }
            return id
        end
        local a, c = join('dbbba', 'Ada', 900.0), join('dbbbc', 'Cal', 901.0)
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        local function act(id, what, ...) server:clientEvent(id, 'wasteland:basebuilding:server:' .. what, ...); server:advance(1500) end
        I('ClearInventory', a); I('ClearInventory', c); server:advance(500)
        I('AddItem', a, 'wood_planks', 30); I('AddItem', a, 'scrap_metal', 6); I('AddItem', a, 'stone', 10); server:advance(500)
        act(a, 'place', 'toolcupboard', 900.0, 901.0, 30.0, 0.0)
        local cup = backend:rows('SELECT id FROM wl_bb_cupboards')[1]
        expect(cup ~= nil).toBe(true)
        act(a, 'place', 'foundation', 903.0, 900.0, 30.0, 0.0)
        act(a, 'place', 'door', 902.0, 901.0, 30.0, 0.0)
        local door = backend:rows("SELECT id FROM wl_bb_props WHERE piece = 'door'")[1]
        local found = backend:rows("SELECT id FROM wl_bb_props WHERE piece = 'foundation'")[1]
        act(a, 'door', door.id)
        local open = backend:rows('SELECT is_open FROM wl_bb_props WHERE id = ?', { door.id })[1].is_open
        expect(open == 1 or open == true).toBe(true) -- TINYINT(1) comes back as a boolean
        act(a, 'upgrade', found.id)
        expect(backend:rows('SELECT piece FROM wl_bb_props WHERE id = ?', { found.id })[1].piece).toBe('foundation_stone')
        act(a, 'move', door.id, 902.5, 901.0, 30.0, 90.0)
        act(a, 'moveCupboard', cup.id, 900.5, 901.0, 30.0, 0.0)
        expect(backend:rows('SELECT x FROM wl_bb_cupboards WHERE id = ?', { cup.id })[1].x).toBe(900.5)
        expect(backend:rows('SELECT x FROM wl_bb_props WHERE id = ?', { door.id })[1].x).toBe(902.5)
        act(a, 'authorize', cup.id, c)
        expect(#backend:rows('SELECT character_id FROM wl_bb_auth WHERE cupboard_id = ?', { cup.id })).toBe(1)
        local cId = server:export('wasteland_players', 'GetCharacterId', c)
        act(a, 'revoke', cup.id, cId)
        -- the owner logs out; a raider picks the door: the notice waits in the database
        server:dropPlayer(a); server:advance(1500)
        I('AddItem', c, 'lockpick', 1); server:advance(300)
        act(c, 'lockpick', door.id); server:advance(1500)
        act(c, 'lockpickResult', true)
        expect(#backend:rows('SELECT id FROM wl_bb_notices')).toBe(1)
        act(c, 'melee', door.id)
        expect(backend:rows('SELECT health FROM wl_bb_props WHERE id = ?', { door.id })[1].health < 600).toBe(true)
        -- the owner comes back: the notice is delivered and removed
        local a2 = server:connectAndJoin({ name = 'Ada', license = 'dbbba' })
        server:advance(200)
        server:command(a2, 'character select 1'); server:advance(7000)
        expect(#backend:rows('SELECT id FROM wl_bb_notices')).toBe(0)
        server.players[a2].coords = { x = 900.0, y = 900.0, z = 30.0 }
        server:advance(130000) -- upkeep with no supplies: wood decays
        server:restart('wasteland_basebuilding'); server:advance(3000)
        expect(states(server).basebuilding).toBe('running')
        server:clientEvent(a2, 'wasteland:basebuilding:server:remove', door.id); server:advance(1500)
        server:clientEvent(a2, 'wasteland:basebuilding:server:removeCupboard', cup.id); server:advance(3000)
        expect(#backend:rows('SELECT id FROM wl_bb_cupboards')).toBe(0)
        expect(backend:rows('SELECT cupboard_id FROM wl_bb_props WHERE id = ?', { found.id })[1].cupboard_id == nil).toBe(true)
    end)

    it('ran every base building statement against the real database', function()
        local ran = {}
        for _, l in ipairs(backend.log) do ran[l.sql] = true end
        local missing = {}
        for key, sql in pairs(SQLBB) do
            if not ran[(sql:gsub('%s+', ' '))] then missing[#missing + 1] = key end
        end
        table.sort(missing)
        -- attachProp: only when a cupboard is placed over pieces left by an older one;
        -- cupboardHealth: only when explosives hit a cupboard
        expect(missing).toEqual({ 'attachProp', 'cupboardHealth' })
        expect(#server.scriptErrors).toBe(0)
    end)
end)
