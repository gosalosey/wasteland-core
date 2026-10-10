-- tests/lib/fake_oxmysql.lua
-- Source of a simulated `oxmysql` resource with the same export signatures
-- and error behaviour as oxmysql v2.14 (see the driver file for details).
-- It runs inside the mock as a virtual resource; FAKEDB (injected) controls it:
--   FAKEDB.backend    MemoryDB (or a real-database backend)
--   FAKEDB.connected  false = isReady() false and queries never answer
--   FAKEDB.hang       true  = queries never answer (connection lost)
--   FAKEDB.latencyMs  answer delay on the virtual clock
--   FAKEDB.calls      every call received: { kind, sql, params, resource }

return [=[
local db = FAKEDB

exports('isReady', function() return db.connected == true end)

local function answer(fn)
    if db.hang or not db.connected then return end -- oxmysql waits forever
    Citizen.SetTimeout(db.latencyMs or 0, function()
        if db.hang or not db.connected then return end
        fn()
    end)
end

for _, kind in ipairs({ 'query', 'single', 'scalar', 'insert', 'update' }) do
    exports(kind, function(sql, params, cb, invokingResource, isPromise)
        db.calls[#db.calls + 1] = { kind = kind, sql = sql, params = params, resource = invokingResource }
        answer(function()
            local result, err = db.backend:execute(kind, sql, params or {})
            if err ~= nil then
                print('oxmysql: ' .. tostring(invokingResource) .. ' was unable to execute a query! ' .. tostring(err))
                if cb and isPromise then cb(nil, err) end
                return
            end
            if cb then cb(result) end
        end)
    end)
end

exports('transaction', function(queries, params, cb, invokingResource, isPromise)
    db.calls[#db.calls + 1] = { kind = 'transaction', queries = queries, resource = invokingResource }
    answer(function()
        local list = {}
        for i, q in ipairs(queries) do list[i] = { q.query, q.values or q.parameters or {} } end
        local ok, err = db.backend:transaction(list)
        if not ok then print('oxmysql: ' .. tostring(invokingResource) .. ' was unable to complete a transaction! ' .. tostring(err)) end
        if cb then cb(ok == true) end
    end)
end)
]=]
