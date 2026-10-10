-- wasteland_database :: server/main.lua
-- Module "database": connects through the configured driver, keeps a health
-- status, and serves queries, transactions and migrations to other modules
-- through callback exports (wrapped as await-style calls by lib/db.lua).
--
-- If the database is unreachable at startup the module FAILS with a precise
-- reason, and every module that depends on it stays waiting. If it becomes
-- unreachable later, the module stays running but reports itself degraded,
-- requests fail immediately with "database unavailable", and modules are
-- told through `wasteland:database:health` so they can refuse valuable
-- operations and retry their saves. There is never an in-memory fallback.

local Requests = WLD.Requests
local Migrations = WLD.Migrations
local SQL = WLD.SQL

local runToken = nil
local health = { up = false, detail = 'not started', since = 0, checkedAt = 0, latencyMs = nil, failures = 0 }
local checkNow = false

local M -- module handle (assigned below; helpers run only after init)

local function setHealth(up, detail)
    local changed = health.up ~= up
    health.up = up
    health.detail = detail
    health.checkedAt = GetGameTimer()
    if changed then
        health.since = GetGameTimer()
        if up then
            M.log:info('database connection restored')
            M.setHealth('ok', 'database connection restored')
        else
            M.log:error('database unreachable: %s', tostring(detail))
            M.setHealth('degraded', 'database unreachable: ' .. tostring(detail))
        end
        TriggerEvent('wasteland:database:health', up, detail)
    end
end

-- One health probe. Returns ok, err.
local function ping()
    local started = GetGameTimer()
    if not Requests.driver.isConnected() then
        local state = Requests.driver.resourceState()
        if state ~= 'started' then
            return false, string.format('driver resource "%s" is %s', Requests.driver.resource, state)
        end
        return false, string.format('%s has no database connection', Requests.driver.resource)
    end
    local ok, result = Requests.await('scalar', SQL.ping, {}, { force = true })
    if not ok then return false, result end
    health.latencyMs = GetGameTimer() - started
    return true
end

local function failStartup(reason)
    runToken = nil
    health.up, health.detail = false, reason
    M.log:error('%s', reason)
    M.fail(reason)
end

--- Request timeouts. A separate thread from the health checks, because a
--- health probe itself waits on a request that may need to time out.
local function watchdog(token)
    while runToken == token do
        Citizen.Wait(250)
        if runToken ~= token then return end
        Requests.expire()
    end
end

--- Periodic health checks (sooner after a request timed out).
local function monitor(token)
    local sinceCheck = 0
    while runToken == token do
        Citizen.Wait(500)
        if runToken ~= token then return end
        sinceCheck = sinceCheck + 500
        if checkNow or sinceCheck >= M.config.healthCheckSeconds * 1000 then
            checkNow = false
            sinceCheck = 0
            local ok, err = ping()
            if runToken ~= token then return end
            if ok then
                health.failures = 0
                setHealth(true, 'connected')
            else
                health.failures = health.failures + 1
                setHealth(false, err)
            end
        end
    end
end

local function startup(token)
    local cfg = M.config
    local driver = Requests.driver
    local state = driver.resourceState()
    if state == 'missing' then
        failStartup(string.format('driver resource "%s" is not installed. Install it and add `ensure %s` to server.cfg BEFORE `ensure %s`.',
            driver.resource, driver.resource, GetCurrentResourceName()))
        return
    end

    -- Wait for the driver to start and connect.
    local deadline = GetGameTimer() + cfg.connectTimeoutSeconds * 1000
    while runToken == token and not driver.isConnected() and GetGameTimer() < deadline do
        Citizen.Wait(250)
    end
    if runToken ~= token then return end
    if not driver.isConnected() then
        local why
        if driver.resourceState() ~= 'started' then
            why = string.format('driver resource "%s" did not start (state: %s). Add `ensure %s` to server.cfg before `ensure %s`.',
                driver.resource, driver.resourceState(), driver.resource, GetCurrentResourceName())
        else
            why = string.format('no database connection after %d s. Check `set mysql_connection_string` in server.cfg and that the database server is running; %s prints the exact error above.',
                cfg.connectTimeoutSeconds, driver.resource)
        end
        failStartup('cannot connect to the database: ' .. why)
        return
    end

    local ok, err = ping()
    if runToken ~= token then return end
    if not ok then
        failStartup('database connection test failed: ' .. tostring(err))
        return
    end
    health.up, health.detail, health.since = true, 'connected', GetGameTimer()

    local okTable, tableErr = Requests.await('query', SQL.createMigrationsTable, {})
    if runToken ~= token then return end
    if not okTable then
        failStartup('could not create the wl_migrations table: ' .. tostring(tableErr))
        return
    end

    M.log:info('connected through %s (round trip %d ms)', driver.resource, health.latencyMs or -1)
    M.ready()
    Citizen.CreateThread(function() monitor(token) end)
end

M = Wasteland.DefineModule({
    name = 'database',
    version = '0.1.0',
    description = 'Database adapter: queries, transactions, migrations, health',
    core = '^1.1.0',
    async = true,
    config = {
        file = 'database.lua',
        optional = true,
        schema = {
            type = 'table',
            fields = {
                driver = { type = 'enum', values = { 'oxmysql' }, default = 'oxmysql',
                    description = 'Database driver. Only oxmysql is supported.' },
                driverResource = { type = 'string', default = 'oxmysql', pattern = '^[%w_%-]+$',
                    description = 'Name of the driver resource.' },
                connectTimeoutSeconds = { type = 'integer', default = 20, min = 1, max = 300,
                    description = 'How long to wait for a connection at startup before failing.' },
                queryTimeoutMs = { type = 'integer', default = 10000, min = 500, max = 120000,
                    description = 'A query with no answer after this long fails (and triggers a health check).' },
                slowQueryWarningMs = { type = 'integer', default = 250, min = 1, max = 60000,
                    description = 'Queries slower than this are logged as warnings.' },
                healthCheckSeconds = { type = 'integer', default = 15, min = 1, max = 600,
                    description = 'Seconds between health checks.' },
            },
        },
    },

    onInit = function(M, ctx)
        local driver = WLD.Drivers[M.config.driver]
        driver.configure(M.config)
        Requests.cfg = M.config
        Requests.log = M.log
        Requests.driver = driver
        Requests.isUp = function() return health.up, health.detail end
        Requests.onTimeout = function() checkNow = true end
        Migrations.log = M.log
        health = { up = false, detail = 'connecting', since = GetGameTimer(), checkedAt = 0, latencyMs = nil, failures = 0 }

        local token = {}
        runToken = token
        Citizen.CreateThread(function() watchdog(token) end)
        Citizen.CreateThread(function() startup(token) end)
        return true
    end,

    onShutdown = function(M, reason)
        runToken = nil
        health.up = false
        health.detail = 'database module stopped (' .. tostring(reason) .. ')'
        Requests.abortAll('database module stopped')
    end,
})

-------------------------------------------------------------------------------
-- Exports (database api 0.1). Callback style: cb(ok, resultOrError) is
-- always called exactly once. Use lib/db.lua for await-style calls.
-------------------------------------------------------------------------------

local function caller()
    return GetInvokingResource() or GetCurrentResourceName()
end

local function notRunning(cb)
    local why = 'database module is not running'
    if cb then Requests.safeCall(cb, caller(), false, why) end
    return false
end

--- Execute(kind, sql, params, cb): kind = query | single | scalar | insert | update
exports('Execute', function(kind, sql, params, cb)
    if not M.active or not Requests.cfg then return notRunning(cb) end
    if cb == nil then return false end
    return Requests.execute(kind, sql, params, cb, caller())
end)

--- Transaction(statements, cb): statements = { { sql, params }, ... }; cb(ok, err)
exports('Transaction', function(statements, cb)
    if not M.active or not Requests.cfg then return notRunning(cb) end
    if cb == nil then return false end
    return Requests.transaction(statements, cb, caller())
end)

--- Migrate(moduleName, migrations, cb): cb(ok, { applied, version } | err)
exports('Migrate', function(moduleName, migrations, cb)
    if not M.active or not Requests.cfg then return notRunning(cb) end
    if cb == nil then return false end
    return Migrations.run(moduleName, migrations, cb, caller())
end)

--- IsUp() -> boolean
exports('IsUp', function()
    return M.active and health.up == true
end)

--- GetHealth() -> { up, detail, since, checkedAt, latencyMs, failures, driver, pending, stats }
exports('GetHealth', function()
    local pending = 0
    for _ in pairs(Requests.pending) do pending = pending + 1 end
    local stats = {}
    for k, v in pairs(Requests.stats) do stats[k] = v end
    return {
        up = M.active and health.up == true,
        detail = health.detail,
        since = health.since,
        checkedAt = health.checkedAt,
        latencyMs = health.latencyMs,
        failures = health.failures,
        driver = Requests.driver and Requests.driver.resource or nil,
        pending = pending,
        stats = stats,
    }
end)
