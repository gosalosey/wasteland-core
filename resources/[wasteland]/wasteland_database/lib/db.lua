-- wasteland_database :: lib/db.lua  (database api 0.1)
-- Await-style database access for module resources. Include it in the
-- module's fxmanifest.lua (after the SDK):
--     server_script '@wasteland_database/lib/db.lua'
-- and declare `dependencies = { database = '^0.1.0' }` in the module.
--
-- Every function must be called from a thread (Citizen.CreateThread) or an
-- event handler, because it waits for the answer. Results follow one rule:
--     value, err = WDB.<fn>(...)      -- err ~= nil means the call failed
-- so always check `err`, not the value (a query can legitimately return nil).
--
--   WDB.query(sql, params)    -> rows (list of { column = value })
--   WDB.single(sql, params)   -> first row or nil
--   WDB.scalar(sql, params)   -> first column of the first row or nil
--   WDB.insert(sql, params)   -> insert id
--   WDB.update(sql, params)   -> affected rows
--   WDB.transaction({ { sql, params }, ... }) -> true | nil, err
--   WDB.migrate(moduleName, migrations)      -> { applied, version } | nil, err
--   WDB.isUp()                -> boolean (no waiting)
--
-- Use `?` placeholders and pass values in `params`; never build SQL from
-- player input. Values: strings, numbers, booleans; nil becomes NULL.

WDB = WDB or {}
WDB.RESOURCE = WDB.RESOURCE or 'wasteland_database'

-- Call a callback-style export and wait for its answer: ok, resultOrError.
local function call(exportName, ...)
    local p = promise.new()
    local args = table.pack(...)
    args.n = args.n + 1
    args[args.n] = function(ok, result) p:resolve({ ok == true, result }) end
    local okCall, err = pcall(function()
        return exports[WDB.RESOURCE][exportName](exports[WDB.RESOURCE], table.unpack(args, 1, args.n))
    end)
    if not okCall then
        return false, string.format('%s is not available: %s', WDB.RESOURCE, tostring(err))
    end
    local r = Citizen.Await(p)
    return r[1], r[2]
end

local function execute(kind, sql, params)
    local ok, result = call('Execute', kind, sql, params or {})
    if not ok then return nil, tostring(result) end
    return result, nil
end

function WDB.query(sql, params)
    local rows, err = execute('query', sql, params)
    if err then return nil, err end
    return rows or {}, nil
end

function WDB.single(sql, params) return execute('single', sql, params) end
function WDB.scalar(sql, params) return execute('scalar', sql, params) end
function WDB.insert(sql, params) return execute('insert', sql, params) end
function WDB.update(sql, params) return execute('update', sql, params) end

function WDB.transaction(statements)
    local ok, err = call('Transaction', statements)
    if not ok then return nil, tostring(err) end
    return true, nil
end

function WDB.migrate(moduleName, migrations)
    local ok, result = call('Migrate', moduleName, migrations)
    if not ok then return nil, tostring(result) end
    return result, nil
end

function WDB.isUp()
    local ok, up = pcall(function() return exports[WDB.RESOURCE]:IsUp() end)
    return ok and up == true
end

return WDB
