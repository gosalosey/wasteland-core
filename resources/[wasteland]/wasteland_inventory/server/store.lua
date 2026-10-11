-- wasteland_inventory :: server/store.lua
-- Persistence. Memory is authoritative while the server runs; every
-- operation changes memory synchronously (no yields, so two requests can
-- never interleave) and queues ONE transaction with all its row changes.
-- The queue is written strictly in order and a failed transaction is
-- retried until it succeeds, so the database always holds a prefix of the
-- operation history: never half an operation, never an item twice.
-- While the database is down or the queue is too long, new operations are
-- refused (no silent memory-only changes, conventions §error handling 5).

local SQL = WLI.SQL
local Store = {}
WLI.Store = Store

Store.queue = {}       -- { { statements, label } }
Store.MAX_ATTEMPTS_WHILE_UP = 10
Store.writing = false
Store.failures = 0
Store.token = nil

local function log() return WLI.M.log end

--- Row values for a stack (absolute values: retries are safe).
function Store.rowParams(stack, inventoryId)
    local meta = nil
    if stack.metadata and next(stack.metadata) ~= nil then meta = json.encode(stack.metadata) end
    return {
        stack.uid, inventoryId, stack.name, stack.count,
        stack.x, stack.y, stack.rotated and 1 or 0, stack.slot, meta,
    }
end

function Store.upsert(stack, inventoryId)
    return { SQL.upsertItem, Store.rowParams(stack, inventoryId) }
end

function Store.delete(uid)
    return { SQL.deleteItem, { uid } }
end

--- Can a new operation be accepted? Returns true or false, reason.
function Store.accepting()
    if not WDB.isUp() then return false, 'the database is unavailable' end
    if #Store.queue >= WLI.cfg.maxQueuedWrites then return false, 'the server is still saving earlier changes' end
    return true
end

local function worker(token)
    Store.writing = true
    while Store.token == token and #Store.queue > 0 do
        local job = Store.queue[1]
        local ok, err = WDB.transaction(job.statements)
        if Store.token ~= token then break end
        if ok then
            table.remove(Store.queue, 1)
            if Store.failures > 0 then
                Store.failures = 0
                log():info('inventory writes recovered')
                WLI.M.setHealth('ok')
            end
        else
            Store.failures = Store.failures + 1
            if Store.failures == 1 or Store.failures % 10 == 0 then
                log():error('could not save inventory change "%s" (attempt %d, %d queued): %s',
                    job.label, Store.failures, #Store.queue, tostring(err))
            end
            if Store.failures >= Store.MAX_ATTEMPTS_WHILE_UP and WDB.isUp() then
                -- The database is reachable but refuses this change: a
                -- permanent error. Drop it so later changes are not blocked.
                log():error('DROPPED inventory change "%s" after %d attempts with the database up: %s. '
                    .. 'Memory and database may now differ for this change; report it.', job.label, Store.failures, tostring(err))
                table.remove(Store.queue, 1)
                Store.failures = 0
            else
                WLI.M.setHealth('degraded', string.format('%d inventory change(s) waiting to be saved', #Store.queue))
                Citizen.Wait(math.min(30000, 1000 * Store.failures))
            end
        end
    end
    Store.writing = false
end

--- Queue an operation's statements (one transaction).
function Store.enqueue(statements, label)
    if #statements == 0 then return end
    Store.queue[#Store.queue + 1] = { statements = statements, label = label }
    if not Store.writing and Store.token then
        local token = Store.token
        Store.writing = true
        Citizen.CreateThread(function() worker(token) end)
    end
end

--- Wait (thread only) until every queued write has been saved, or timeout.
function Store.drain(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 30000)
    while #Store.queue > 0 and GetGameTimer() < deadline do Citizen.Wait(50) end
    return #Store.queue == 0
end

--- Read the stacks of an inventory (thread only). Waits for queued writes
--- first so it never reads rows that are about to change.
--- Returns { [uid] = stack } or nil, err.
function Store.loadItems(inventoryId)
    if not Store.drain(30000) then return nil, 'earlier inventory changes are still being saved' end
    local rows, err = WDB.query(SQL.selectItems, { inventoryId })
    if err then return nil, err end
    local items = {}
    for _, r in ipairs(rows) do
        local meta = {}
        if r.metadata and r.metadata ~= '' then
            local ok, decoded = pcall(json.decode, r.metadata)
            if ok and type(decoded) == 'table' then
                meta = decoded
            else
                log():error('item %s in %s has damaged metadata; keeping the item without it', tostring(r.uid), inventoryId)
            end
        end
        if WLI.defs[r.name] == nil then
            log():warn('item %s in %s is "%s", which is not defined (removed from config?); it stays stored but hidden',
                tostring(r.uid), inventoryId, tostring(r.name))
        else
            items[r.uid] = {
                uid = r.uid, name = r.name, count = tonumber(r.count),
                x = tonumber(r.pos_x), y = tonumber(r.pos_y),
                rotated = r.rotated == true or r.rotated == 1,
                slot = r.slot, metadata = meta,
            }
        end
    end
    return items
end

function Store.start()
    Store.token = {}
    Store.failures = 0
    if #Store.queue > 0 then
        local token = Store.token
        Store.writing = true
        Citizen.CreateThread(function() worker(token) end)
    end
end

--- Shutdown: hand everything still queued to the database resource as
--- ONE transaction (keeps the order) without waiting for it.
function Store.stop()
    Store.token = nil
    local n = #Store.queue
    if n > 0 then
        local all = {}
        for _, job in ipairs(Store.queue) do
            for _, st in ipairs(job.statements) do all[#all + 1] = st end
        end
        pcall(function()
            exports[WDB.RESOURCE]:Transaction(all, function(ok, err)
                if not ok then
                    print(string.format('^1[Wasteland] [ERROR] [inventory] final write of %d queued change(s) failed: %s^7', n, tostring(err)))
                end
            end)
        end)
    end
    Store.queue = {}
    Store.writing = false
    return n
end

return Store
