-- wasteland_database :: server/driver_oxmysql.lua
-- Driver for oxmysql (https://github.com/overextended/oxmysql), verified
-- against v2.14.3. This is the only file that talks to oxmysql.
--
-- oxmysql facts this relies on (from its source):
--   * exports query/single/scalar/insert/update(sql, params, cb, invokingResource, isPromise)
--   * only with isPromise = true does a failed query call cb(nil, errorMessage);
--     otherwise the error is printed and cb is never called
--   * transaction(queries, params, cb, invokingResource, isPromise) calls
--     cb(true|false); SQL errors give false with the details printed to the
--     console (no message is passed back)
--   * while it has no connection, queries wait indefinitely (we time out)
--   * isReady() reports whether its connection pool exists

WLD = WLD or {}
WLD.Drivers = WLD.Drivers or {}

local RESOURCE = GetCurrentResourceName()
local Driver = { name = 'oxmysql' }
WLD.Drivers.oxmysql = Driver

Driver.KINDS = { query = true, single = true, scalar = true, insert = true, update = true }

function Driver.configure(cfg)
    Driver.resource = cfg.driverResource
end

--- 'started' | 'missing' | other FiveM resource states
function Driver.resourceState()
    return GetResourceState(Driver.resource)
end

--- true when the driver has an established connection pool.
function Driver.isConnected()
    if Driver.resourceState() ~= 'started' then return false end
    local ok, ready = pcall(function() return exports[Driver.resource]:isReady() end)
    return ok and ready == true
end

--- Run one statement. cb(ok, resultOrError) is called exactly once unless
--- the driver never answers (the request layer applies a timeout).
function Driver.execute(kind, sql, params, cb)
    exports[Driver.resource][kind](exports[Driver.resource], sql, params, function(result, err)
        if err ~= nil then
            cb(false, tostring(err))
        else
            cb(true, result)
        end
    end, RESOURCE, true)
end

--- Run statements { { sql, params }, ... } atomically. cb(ok, err).
function Driver.transaction(statements, cb)
    local queries = {}
    for i, st in ipairs(statements) do
        queries[i] = { query = st[1], values = st[2] or {} }
    end
    exports[Driver.resource]:transaction(queries, {}, function(success, err)
        if success == true then
            cb(true)
        elseif err ~= nil then
            cb(false, tostring(err))
        else
            cb(false, 'transaction failed and was rolled back (the SQL error is printed above by ' .. Driver.resource .. ')')
        end
    end, RESOURCE, true)
end

return Driver
