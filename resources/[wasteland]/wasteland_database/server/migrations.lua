-- wasteland_database :: server/migrations.lua
-- Per-module, numbered, forward-only schema migrations, tracked in
-- wl_migrations. A module passes its full migration list on every start;
-- the runner applies the ones not yet recorded, in order, one at a time
-- across all modules.
--
-- Migration: { version = 1, name = 'create_things', up = 'SQL' | { 'SQL', ... } }
--   * versions are 1, 2, 3 ... with no gaps
--   * each migration's statements and its wl_migrations record are sent as
--     one transaction. NOTE: MySQL/MariaDB commit DDL (CREATE/ALTER/DROP)
--     implicitly, so a migration that fails part-way may leave earlier DDL
--     applied. Keep one DDL statement per migration and make it idempotent
--     (CREATE TABLE IF NOT EXISTS ...), so a retry succeeds.
--   * an applied migration must never change: its checksum is verified
--   * a database that is newer than the module (downgrade) is refused

WLD = WLD or {}
WLD.Migrations = WLD.Migrations or {}
local Migrations = WLD.Migrations
local SQL = WLD.SQL

Migrations.queue = {}
Migrations.running = false
Migrations.log = nil -- set by main.lua

local NAME_PATTERN = '^[a-z0-9_]+$'

--- FNV-1a 32-bit checksum of the migration statements (hex, 8 chars).
function Migrations.checksum(statements)
    local h = 2166136261
    local function byte(b)
        h = ((h ~ b) * 16777619) & 0xffffffff
    end
    for i, sql in ipairs(statements) do
        if i > 1 then byte(0) end -- separator, so {'ab'} and {'a','b'} differ
        for j = 1, #sql do byte(sql:byte(j)) end
    end
    return string.format('%08x', h)
end

--- Validate a module's migration list. Returns normalised list or nil, err.
function Migrations.normalise(moduleName, list)
    if type(moduleName) ~= 'string' or not moduleName:match('^[a-z][a-z0-9_]*$') or #moduleName > 32 then
        return nil, 'module name must match [a-z][a-z0-9_]* (max 32 characters)'
    end
    if type(list) ~= 'table' then return nil, 'migrations must be a list' end
    local out = {}
    for i, m in ipairs(list) do
        local where = string.format('module "%s" migration #%d', moduleName, i)
        if type(m) ~= 'table' then return nil, where .. ': must be a table' end
        if m.version ~= i then
            return nil, string.format('%s: version must be %d (versions are 1, 2, 3 ... in order), got %s', where, i, tostring(m.version))
        end
        if type(m.name) ~= 'string' or not m.name:match(NAME_PATTERN) or #m.name > 128 then
            return nil, where .. ': name must be lowercase letters, digits and "_" (max 128)'
        end
        local up = m.up
        if type(up) == 'string' then up = { up } end
        if type(up) ~= 'table' or #up == 0 then return nil, where .. ': up must be an SQL string or a non-empty list of them' end
        for j, s in ipairs(up) do
            if type(s) ~= 'string' or s:match('^%s*$') then
                return nil, string.format('%s: up[%d] must be a non-empty SQL string', where, j)
            end
        end
        out[i] = { version = i, name = m.name, up = up, checksum = Migrations.checksum(up) }
    end
    local n = 0
    for _ in pairs(list) do n = n + 1 end
    if n ~= #out then return nil, string.format('module "%s": migrations must be a plain list', moduleName) end
    return out
end

-- Runs inside the worker thread. Returns ok, resultOrErr.
local function apply(job)
    local Requests = WLD.Requests
    local list = job.list
    local ok, rows = Requests.await('query', SQL.selectMigrations, { job.module })
    if not ok then return false, 'could not read applied migrations: ' .. tostring(rows) end
    rows = rows or {}
    for i, row in ipairs(rows) do
        local version = tonumber(row.version)
        if version ~= i then
            return false, string.format('wl_migrations for module "%s" is inconsistent: expected version %d, found %s', job.module, i, tostring(row.version))
        end
        local m = list[i]
        if not m then
            return false, string.format('the database has migration %d ("%s") for module "%s", but this version of the module only knows %d migration(s). '
                .. 'Downgrading is not supported: install the newer module version or restore a backup.', i, tostring(row.name), job.module, #list)
        end
        if row.checksum ~= m.checksum then
            return false, string.format('migration %d ("%s") of module "%s" was changed after it was applied (database checksum %s, file checksum %s). '
                .. 'Never edit an applied migration; add a new one instead.', i, m.name, job.module, tostring(row.checksum), m.checksum)
        end
    end
    local applied = 0
    for v = #rows + 1, #list do
        local m = list[v]
        local statements = {}
        for _, sql in ipairs(m.up) do statements[#statements + 1] = { sql, {} } end
        statements[#statements + 1] = { SQL.insertMigration, { job.module, m.version, m.name, m.checksum } }
        local okTx, err = Requests.awaitTransaction(statements)
        if not okTx then
            return false, string.format('migration %d ("%s") of module "%s" failed: %s. Nothing after it was applied. '
                .. 'If it contains several DDL statements, earlier ones may already be applied (MySQL commits DDL implicitly).',
                m.version, m.name, job.module, tostring(err))
        end
        applied = applied + 1
        Migrations.log:info('applied migration %s #%d %s', job.module, m.version, m.name)
    end
    return true, { applied = applied, version = #list }
end

local function worker()
    Migrations.running = true
    while #Migrations.queue > 0 do
        local job = table.remove(Migrations.queue, 1)
        local okCall, ok, result = pcall(apply, job)
        if not okCall then ok, result = false, 'migration runner error: ' .. tostring(ok) end
        if ok then
            if result.applied > 0 then
                Migrations.log:info('module "%s" schema is at version %d (%d migration(s) applied)', job.module, result.version, result.applied)
            else
                Migrations.log:debug('module "%s" schema is up to date (version %d)', job.module, result.version)
            end
        else
            Migrations.log:error('%s', result)
        end
        WLD.Requests.safeCall(job.cb, job.owner, ok, result)
    end
    Migrations.running = false
end

--- Queue a module's migrations. cb(ok, { applied, version } | err).
function Migrations.run(moduleName, list, cb, owner)
    local normalised, err = Migrations.normalise(moduleName, list)
    if not normalised then
        cb(false, err)
        return false
    end
    Migrations.queue[#Migrations.queue + 1] = { module = moduleName, list = normalised, cb = cb, owner = owner }
    if not Migrations.running then
        Migrations.running = true
        Citizen.CreateThread(worker)
    end
    return true
end

return Migrations
