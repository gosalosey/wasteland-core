-- wasteland_database :: server/requests.lua
-- Request layer between callers and the driver: input checks, fail-fast
-- while the database is down, timeouts, slow-query warnings and safe
-- callbacks (a caller's resource may have stopped before its answer arrives).

WLD = WLD or {}
WLD.Requests = WLD.Requests or {}
local Requests = WLD.Requests

Requests.pending = {}   -- [id] = { deadline, finish, label }
Requests.nextId = 0
Requests.stats = { total = 0, failed = 0, timedOut = 0, slow = 0, late = 0 }

-- Set by main.lua
Requests.cfg = nil
Requests.log = nil
Requests.driver = nil
Requests.isUp = function() return false, 'not initialised' end
Requests.onTimeout = function() end

local function shorten(sql)
    sql = tostring(sql):gsub('%s+', ' ')
    if #sql > 120 then sql = sql:sub(1, 117) .. '...' end
    return sql
end

--- Call a caller-supplied callback without letting its failure escape.
function Requests.safeCall(cb, owner, ...)
    local ok, err = pcall(cb, ...)
    if not ok then
        Requests.log:warn('could not deliver a database result to %s (stopped?): %s', tostring(owner or 'caller'), tostring(err))
    end
end

local function track(label, owner, cb)
    Requests.nextId = Requests.nextId + 1
    local id = Requests.nextId
    local started = GetGameTimer()
    local entry = { label = label, owner = owner, done = false }
    entry.deadline = started + Requests.cfg.queryTimeoutMs
    Requests.pending[id] = entry
    Requests.stats.total = Requests.stats.total + 1
    entry.finish = function(ok, result, timedOut)
        if entry.done then
            if not timedOut then
                -- The driver answered after we gave up: for writes this means
                -- the change WAS applied even though the caller saw an error.
                Requests.stats.late = Requests.stats.late + 1
                Requests.log:warn('%s from %s completed %d ms after it timed out (ok=%s); the caller was told it failed',
                    label, tostring(owner), GetGameTimer() - started, tostring(ok))
            end
            return
        end
        entry.done = true
        Requests.pending[id] = nil
        local elapsed = GetGameTimer() - started
        if not ok then
            Requests.stats.failed = Requests.stats.failed + 1
            Requests.log:error('%s from %s failed: %s', label, tostring(owner), tostring(result))
        elseif elapsed >= Requests.cfg.slowQueryWarningMs then
            Requests.stats.slow = Requests.stats.slow + 1
            Requests.log:warn('slow %s from %s: %d ms', label, tostring(owner), elapsed)
        end
        Requests.safeCall(cb, owner, ok, result)
    end
    return entry
end

--- Fail requests whose deadline passed. Called by the watchdog thread.
function Requests.expire()
    local now = GetGameTimer()
    local expired = {}
    for id, entry in pairs(Requests.pending) do
        if now >= entry.deadline then expired[#expired + 1] = id end
    end
    table.sort(expired)
    for _, id in ipairs(expired) do
        local entry = Requests.pending[id]
        if entry then
            Requests.stats.timedOut = Requests.stats.timedOut + 1
            entry.finish(false, string.format('timed out after %d ms (the database did not answer)', Requests.cfg.queryTimeoutMs), true)
        end
    end
    if #expired > 0 then Requests.onTimeout() end
    return #expired
end

--- Fail every pending request (used when the module shuts down).
function Requests.abortAll(reason)
    local ids = {}
    for id in pairs(Requests.pending) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local entry = Requests.pending[id]
        if entry then entry.finish(false, reason, true) end
    end
end

local function checkParams(params)
    if params == nil then return {} end
    if type(params) ~= 'table' then return nil, 'params must be a table (list of values for the ? placeholders)' end
    return params
end

--- Run one statement. cb(ok, result|err) is always called exactly once.
--- opts.force skips the "database is down" fast-fail (health checks).
function Requests.execute(kind, sql, params, cb, owner, opts)
    if not Requests.driver.KINDS[kind] then
        cb(false, string.format('unknown query kind %s (expected query, single, scalar, insert or update)', tostring(kind)))
        return false
    end
    if type(sql) ~= 'string' or sql == '' then
        cb(false, 'sql must be a non-empty string')
        return false
    end
    local p, perr = checkParams(params)
    if not p then cb(false, perr); return false end
    if not (opts and opts.force) then
        local up, why = Requests.isUp()
        if not up then
            cb(false, 'database unavailable: ' .. tostring(why))
            return false
        end
    end
    local entry = track(kind .. ' "' .. shorten(sql) .. '"', owner, cb)
    local ok, err = pcall(Requests.driver.execute, kind, sql, p, entry.finish)
    if not ok then entry.finish(false, 'driver error: ' .. tostring(err)) end
    return true
end

--- Run statements atomically. statements = { { sql, params }, ... }.
function Requests.transaction(statements, cb, owner)
    if type(statements) ~= 'table' or #statements == 0 then
        cb(false, 'transaction needs a non-empty list of { sql, params } statements')
        return false
    end
    for i, st in ipairs(statements) do
        if type(st) ~= 'table' or type(st[1]) ~= 'string' or st[1] == '' then
            cb(false, string.format('transaction statement %d must be { sql, params }', i))
            return false
        end
        local p, perr = checkParams(st[2])
        if not p then cb(false, string.format('transaction statement %d: %s', i, perr)); return false end
        st[2] = p
    end
    local up, why = Requests.isUp()
    if not up then
        cb(false, 'database unavailable: ' .. tostring(why))
        return false
    end
    local entry = track(string.format('transaction (%d statements, first "%s")', #statements, shorten(statements[1][1])), owner, cb)
    local ok, err = pcall(Requests.driver.transaction, statements, entry.finish)
    if not ok then entry.finish(false, 'driver error: ' .. tostring(err)) end
    return true
end

--- Await helpers for use inside this resource's own threads.
function Requests.await(kind, sql, params, opts)
    local p = promise.new()
    Requests.execute(kind, sql, params, function(ok, result) p:resolve({ ok, result }) end, GetCurrentResourceName(), opts)
    local r = Citizen.Await(p)
    return r[1], r[2]
end

function Requests.awaitTransaction(statements)
    local p = promise.new()
    Requests.transaction(statements, function(ok, err) p:resolve({ ok, err }) end, GetCurrentResourceName())
    local r = Citizen.Await(p)
    return r[1], r[2]
end

return Requests
