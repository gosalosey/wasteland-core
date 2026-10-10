-- wasteland_database: startup, queries through lib/db.lua, timeouts,
-- health (down/up), safe callbacks and migrations. Runs against the
-- simulated oxmysql (tests/lib/fake_oxmysql.lua) backed by MemoryDB.

local FAST = { ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }' }

-- A module resource that runs `code` in a thread with WDB available.
-- `code` may call track(x); results are read with server:export(res, 'Calls').
local function dbClient(server, resName, code)
    addModule(server, resName, string.format([[
Wasteland.DefineModule({ name = %q, version = '1.0.0', core = '^1.1.0', dependencies = { database = '^0.1.0' },
    onInit = function(M)
        Citizen.CreateThread(function()
%s
        end)
    end })
]], resName:gsub('^fx_', ''), code), { 'wasteland_database' }, { '@wasteland_database/lib/db.lua' })
end

local function lines(server, needle) return #server:lines(needle) end

describe('database startup', function()
    it('connects through oxmysql, creates wl_migrations and runs', function()
        local server = newServer()
        boot(server, { 'wasteland_database' })
        expect(states(server).database).toBe('running')
        expect(lines(server, 'connected through oxmysql')).toBe(1)
        expect(server.db.backend.ddl[1]).toContain('CREATE TABLE IF NOT EXISTS wl_migrations')
        expect(#server.scriptErrors).toBe(0)
    end)

    it('fails with instructions when the driver resource is not installed', function()
        local server = newServer({ config = FAST })
        server.resources.oxmysql = nil
        for i, n in ipairs(server.order) do if n == 'oxmysql' then table.remove(server.order, i) break end end
        server:start('wasteland_database')
        server:advance(3000)
        local s = server:export('wasteland_core', 'GetModuleStatus', 'database')
        expect(s.state).toBe('failed')
        expect(s.reason).toContain('driver resource "oxmysql" is not installed')
        expect(s.reason).toContain('ensure oxmysql')
    end)

    it('fails after connectTimeoutSeconds when the driver is not started', function()
        local server = newServer({ config = FAST })
        server:start('wasteland_database')
        server:advance(1500)
        expect(states(server).database).toBe('initializing')
        server:advance(1500)
        local s = server:export('wasteland_core', 'GetModuleStatus', 'database')
        expect(s.state).toBe('failed')
        expect(s.reason).toContain('did not start')
    end)

    it('fails with a connection-string hint when the driver has no connection', function()
        local server = newServer({ config = FAST, dbConnected = false })
        boot(server, { 'wasteland_database' })
        local s = server:export('wasteland_core', 'GetModuleStatus', 'database')
        expect(s.state).toBe('failed')
        expect(s.reason).toContain('no database connection after 2 s')
        expect(s.reason).toContain('mysql_connection_string')
    end)

    it('keeps dependents waiting with the reason when it fails', function()
        local server = newServer({ config = FAST, dbConnected = false })
        boot(server, { 'wasteland_players' })
        local s = server:export('wasteland_core', 'GetModuleStatus', 'players')
        expect(s.state).toBe('waiting')
        expect(s.reason).toContain('dependency "database" failed')
    end)
end)

describe('queries through lib/db.lua', function()
    local server = newServer({ config = FAST })
    dbClient(server, 'fx_q', [[
            local v, err = WDB.scalar('SELECT 1')
            track({ 'scalar', v, err })
            local rows, qerr = WDB.query('SELECT version, name, checksum FROM wl_migrations WHERE module_name = ? ORDER BY version', { 'nobody' })
            track({ 'query', #rows, qerr })
            local bad, berr = WDB.query('SELECT SIMULATE_ERROR')
            track({ 'error', bad, berr })
            local okTx, txErr = WDB.transaction({
                { 'INSERT INTO wl_migrations (module_name, version, name, checksum) VALUES (?, ?, ?, ?)', { 'tx', 1, 'a', '00000000' } },
                { 'SELECT SIMULATE_ERROR', {} },
            })
            track({ 'tx', okTx, txErr })
            local after = WDB.query('SELECT version, name, checksum FROM wl_migrations WHERE module_name = ? ORDER BY version', { 'tx' })
            track({ 'afterTx', #after })
            local _, inputErr = WDB.query(42)
            track({ 'input', inputErr })
    ]])
    boot(server, { 'fx_q' })
    local calls = server:export('fx_q', 'Calls')
    local byName = {}
    for _, c in ipairs(calls) do byName[c[1]] = c end

    it('returns results with err = nil on success', function()
        expect(byName.scalar[2]).toBe(1)
        expect(byName.scalar[3]).toBe(nil)
        expect(byName.query[2]).toBe(0)
    end)
    it('returns nil and the driver message on SQL errors', function()
        expect(byName.error[2]).toBe(nil)
        expect(byName.error[3]).toContain('SQL syntax')
    end)
    it('rolls back a failed transaction completely', function()
        expect(byName.tx[2]).toBe(nil)
        expect(byName.tx[3]).toContain('rolled back')
        expect(byName.afterTx[2]).toBe(0)
    end)
    it('rejects invalid input without calling the driver', function()
        expect(byName.input[2]).toContain('sql must be a non-empty string')
    end)
    it('passes the invoking resource to the driver and uses the promise error mode', function()
        expect(server.db.calls[#server.db.calls].resource).toBe('wasteland_database')
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('database health: connection lost and restored', function()
    local server = newServer({ config = FAST })
    addModule(server, 'fx_watch', [[
AddEventHandler('wasteland:database:health', function(up, detail) track((up and 'up' or 'down') .. ':' .. tostring(detail)) end)
AddEventHandler('wasteland:core:moduleHealth', function(name, status) track('health:' .. name .. ':' .. status) end)
]])
    server:start('fx_watch')
    boot(server, { 'wasteland_database' })
    dbClient(server, 'fx_slow', [[
            track({ 'hung', WDB.scalar('SELECT 1') })
            -- The timeout triggers a health check, whose own probe must time out
            -- before the database counts as down; ask again after that.
            Citizen.Wait(2500)
            local v, err = WDB.scalar('SELECT 1')
            track({ 'second', v, err })
    ]])
    server.db.hang = true
    server:start('fx_slow')
    server:advance(1500)

    it('fails a query that gets no answer after queryTimeoutMs', function()
        local calls = server:export('fx_slow', 'Calls')
        expect(calls[1][1]).toBe('hung')
        expect(calls[1][3]).toContain('timed out after 1000 ms')
    end)
    it('marks the database degraded right after the timeout and tells other resources', function()
        server:advance(1500)
        local status = server:export('wasteland_core', 'GetModuleStatus', 'database')
        expect(status.state).toBe('running')
        expect(status.health).toBe('degraded')
        expect(server:export('wasteland_database', 'IsUp')).toBe(false)
        local watch = server:export('fx_watch', 'Calls')
        expect(watch).toContain('down:')
        expect(watch).toContain('health:database:degraded')
    end)
    it('fails requests immediately while down (no waiting for a timeout)', function()
        server:advance(1000)
        local calls = server:export('fx_slow', 'Calls')
        expect(#calls).toBe(2)
        expect(calls[2][1]).toBe('second')
        expect(calls[2][3]).toContain('database unavailable')
    end)
    it('shows DEGRADED in the status table', function()
        server:clearOutput()
        server:command(0, 'wasteland status')
        expect(#server:lines('DEGRADED: database unreachable') > 0).toBe(true)
        expect(#server:lines('degraded=1') > 0).toBe(true)
    end)
    it('recovers on the next health check once the connection is back', function()
        server.db.hang = false
        server:advance(2500)
        local status = server:export('wasteland_core', 'GetModuleStatus', 'database')
        expect(status.health).toBe('ok')
        expect(server:export('wasteland_database', 'IsUp')).toBe(true)
        expect(server:export('fx_watch', 'Calls')).toContain('up:connected')
        expect(#server:lines('database connection restored') > 0).toBe(true)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('callbacks to resources that stopped', function()
    it('are dropped with a warning instead of a script error', function()
        local server = newServer({ config = FAST })
        boot(server, { 'wasteland_database' })
        dbClient(server, 'fx_gone', [[ track(WDB.scalar('SELECT 1')) ]])
        server.db.latencyMs = 500
        server:start('fx_gone')
        server:advance(100)
        server:stop('fx_gone')
        server:advance(1000)
        expect(#server.scriptErrors).toBe(0)
        expect(#server:lines('could not deliver a database result to fx_gone')).toBe(1)
    end)

    it('exports answer "not running" when the module is down', function()
        local server = newServer({ config = FAST, dbConnected = false })
        boot(server, { 'wasteland_database' })
        dbClient(server, 'fx_late', [[ track({ WDB.scalar('SELECT 1') }) ]])
        server:start('fx_late')
        server:advance(100)
        -- fx_late depends on database (failed), so it never initialises:
        expect(states(server).late).toBe('waiting')
        expect(server:export('wasteland_database', 'IsUp')).toBe(false)
        local health = server:export('wasteland_database', 'GetHealth')
        expect(health.up).toBe(false)
    end)
end)

describe('migrations', function()
    local function migrator(server, resName, moduleName, list)
        dbClient(server, resName, string.format([[
            local result, err = WDB.migrate(%q, %s)
            track({ result and result.applied, result and result.version, err })
        ]], moduleName, list))
    end
    local V1 = "{ version = 1, name = 'one', up = 'CREATE TABLE IF NOT EXISTS t_one (id INT)' }"
    local V2 = "{ version = 2, name = 'two', up = { 'CREATE TABLE IF NOT EXISTS t_two (id INT)' } }"

    local server = newServer({ config = FAST })
    boot(server, { 'wasteland_database' })

    it('applies pending migrations in order and records them', function()
        migrator(server, 'fx_m1', 'shop', '{ ' .. V1 .. ', ' .. V2 .. ' }')
        server:start('fx_m1'); server:advance(500)
        local r = server:export('fx_m1', 'Calls')[1]
        expect(r[1]).toBe(2); expect(r[2]).toBe(2); expect(r[3]).toBe(nil)
        local recorded = {}
        for _, m in ipairs(server.db.backend.data.wl_migrations) do
            if m.module_name == 'shop' then recorded[#recorded + 1] = m.version .. ':' .. m.name end
        end
        expect(recorded).toEqual({ '1:one', '2:two' })
    end)

    it('applies nothing when the schema is up to date', function()
        server:stop('fx_m1'); server:start('fx_m1'); server:advance(500)
        local r = server:export('fx_m1', 'Calls')[1]
        expect(r[1]).toBe(0); expect(r[2]).toBe(2)
    end)

    it('refuses an applied migration whose SQL changed', function()
        migrator(server, 'fx_m2', 'shop', "{ { version = 1, name = 'one', up = 'CREATE TABLE IF NOT EXISTS t_one (id BIGINT)' }, " .. V2 .. ' }')
        server:start('fx_m2'); server:advance(500)
        local r = server:export('fx_m2', 'Calls')[1]
        expect(r[1]).toBe(nil)
        expect(r[3]).toContain('migration 1 ("one") of module "shop" was changed after it was applied')
    end)

    it('refuses to run against a database newer than the module (downgrade)', function()
        migrator(server, 'fx_m3', 'shop', '{ ' .. V1 .. ' }')
        server:start('fx_m3'); server:advance(500)
        local r = server:export('fx_m3', 'Calls')[1]
        expect(r[3]).toContain('the database has migration 2 ("two") for module "shop"')
        expect(r[3]).toContain('Downgrading is not supported')
    end)

    it('stops at a failing migration and does not record it', function()
        migrator(server, 'fx_m4', 'broken', "{ " .. V1 .. ", { version = 2, name = 'bad', up = 'ALTER SIMULATE_ERROR' }, "
            .. "{ version = 3, name = 'never', up = 'CREATE TABLE IF NOT EXISTS t_never (id INT)' } }")
        server:start('fx_m4'); server:advance(500)
        local r = server:export('fx_m4', 'Calls')[1]
        expect(r[3]).toContain('migration 2 ("bad") of module "broken" failed')
        local versions = {}
        for _, m in ipairs(server.db.backend.data.wl_migrations) do
            if m.module_name == 'broken' then versions[#versions + 1] = m.version end
        end
        expect(versions).toEqual({ 1 })
    end)

    it('rejects malformed migration lists before touching the database', function()
        migrator(server, 'fx_m5', 'gappy', "{ { version = 1, name = 'a', up = 'CREATE TABLE IF NOT EXISTS t_a (id INT)' }, "
            .. "{ version = 3, name = 'c', up = 'CREATE TABLE IF NOT EXISTS t_c (id INT)' } }")
        server:start('fx_m5'); server:advance(500)
        local r = server:export('fx_m5', 'Calls')[1]
        expect(r[3]).toContain('version must be 2')
    end)

    it('runs migrations from several modules one at a time without losing any', function()
        migrator(server, 'fx_m6', 'alpha', '{ ' .. V1 .. ' }')
        migrator(server, 'fx_m7', 'beta', '{ ' .. V1 .. ', ' .. V2 .. ' }')
        server:start('fx_m6'); server:start('fx_m7'); server:advance(1000)
        expect(server:export('fx_m6', 'Calls')[1][1]).toBe(1)
        expect(server:export('fx_m7', 'Calls')[1][1]).toBe(2)
        expect(#server.scriptErrors).toBe(0)
    end)

    it('produces stable checksums that distinguish statement boundaries', function()
        local env = loadCoreFiles({}, {})
        local wld = { WLD = { SQL = {} } }
        setmetatable(wld, { __index = _G })
        assert(loadfile(RESOURCES .. '/wasteland_database/server/migrations.lua', 't', wld))()
        local c = wld.WLD.Migrations.checksum
        expect(c({ 'ab' })).toBe(c({ 'ab' }))
        expect(c({ 'ab' }) ~= c({ 'a', 'b' })).toBe(true)
        expect(#c({ 'x' })).toBe(8)
    end)
end)

describe('restart wasteland_database', function()
    it('restarts module resources FiveM stopped because they depend on it', function()
        local server = newServer({ config = FAST })
        boot(server, { 'wasteland_players' })
        expect(states(server).players).toBe('running')
        server:restart('wasteland_database')
        server:advance(3000)
        expect(server.resources.wasteland_players.state).toBe('started')
        expect(states(server).players).toBe('running')
        expect(#server:lines('restarting module resource "wasteland_players" (stopped because "wasteland_database" restarted)')).toBe(1)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
