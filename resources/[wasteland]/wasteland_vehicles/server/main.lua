-- wasteland_vehicles :: server/main.lua
-- Module "vehicles": persistent world vehicles (wrecks to repair). Nobody
-- owns them. Records live in wl_vehicles; the entity exists only while a
-- player is near (created here, OneSync), and its position and damage are
-- saved back. The client that owns the entity applies the state
-- (entity state `wlVeh`): damage, missing wheels, fuel, no start without
-- parts. Every repair, refuel, lock and trunk action is checked and timed
-- here. A car lock creates a key (an item with the lock's code); without
-- the key a lockpick may break the lock.

local Rules = WLVE.Rules
local SQL = WLV.SQL
local M
local vehicles = {}    -- id -> record (+ handle, farSince, seq)
local byHandle = {}    -- entity handle -> id
local acting = {}      -- source -> { id, action, startedAt, coords, seconds }
local pumps = {}       -- pump key -> { litres, refillAt }  (limited fuel, full again 2 h after first use)
local runToken = nil

local function inv() return exports.wasteland_inventory end
local function now() return GetGameTimer() end
local function notice(src, msg) TriggerClientEvent('wasteland:vehicles:client:notice', src, msg) end

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function coordsOf(handle)
    local c = GetEntityCoords(handle)
    return { x = c.x, y = c.y, z = c.z }
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return coordsOf(ped)
end

local uidCounter = 0
local function newId()
    uidCounter = (uidCounter + 1) % 0x1000
    return string.format('%08x%03x%01x', os.time() & 0xffffffff, uidCounter, math.random(0, 15))
end

local function newCode() return string.format('%08x', math.random(0, 0x7fffffff)) end

local function stateOf(v)
    return { id = v.id, fuel = v.fuel, tank = M.config.tankLitres, engine = v.engine, body = v.body, parts = v.parts,
        locked = v.locked == true, hasLock = v.lockCode ~= nil, seq = v.seq or 0, acked = v.ackSeq }
end

-- Tell the owning client about a change (seq makes it apply damage again).
local function publish(v, reapply)
    if reapply then v.seq = (v.seq or 0) + 1 end
    if v.handle and DoesEntityExist(v.handle) then
        Entity(v.handle).state:set('wlVeh', stateOf(v), true)
        SetVehicleDoorsLocked(v.handle, v.locked and 2 or 1)
    end
end

-------------------------------------------------------------------------------
-- Database
-------------------------------------------------------------------------------

local function params(v)
    return { v.x, v.y, v.z, v.heading, v.fuel, v.engine, v.body, Rules.encodeParts(v.parts), v.lockCode, v.locked and 1 or 0, os.time(), v.id }
end

-- Database writes run in their own thread (they wait for the database;
-- callers are often event handlers). The values are taken now.
local function write(fn, sql, values, what)
    Citizen.CreateThread(function()
        local _, err = fn(sql, values)
        if err then M.log:warn('%s failed: %s', what, tostring(err)) end
    end)
end

local function save(v)
    if v.destroyed then return end
    write(WDB.update, SQL.update, params(v), 'saving vehicle ' .. v.id)
end

local function insert(v)
    write(WDB.insert, SQL.insert, { v.id, v.model, v.x, v.y, v.z, v.heading, v.fuel, v.engine, v.body,
        Rules.encodeParts(v.parts), v.lockCode, v.locked and 1 or 0, os.time() }, 'storing vehicle ' .. v.id)
end

-------------------------------------------------------------------------------
-- Spawning, saving, despawning, wrecks
-------------------------------------------------------------------------------

local function spawn(v)
    local h = CreateVehicleServerSetter(GetHashKey(v.model), 'automobile', v.x + 0.0, v.y + 0.0, v.z + 0.5, v.heading + 0.0)
    if not h or h == 0 or not DoesEntityExist(h) then
        M.log:warn('could not create vehicle %s (%s)', v.id, v.model)
        return
    end
    v.handle, v.farSince, v.ackSeq = h, nil, nil
    byHandle[h] = v.id
    publish(v, true)
end

-- Read position and damage from the entity (OneSync keeps them on the
-- server). Damage only once the owning client confirmed it applied the
-- latest state: a fresh entity starts at full health, and a repair is
-- only on the entity after the client applied it.
local function capture(v)
    if not v.handle or not DoesEntityExist(v.handle) then return end
    local c = coordsOf(v.handle)
    v.x, v.y, v.z = c.x, c.y, c.z
    v.heading = GetEntityHeading(v.handle)
    if v.ackSeq == v.seq then
        v.engine = GetVehicleEngineHealth(v.handle)
        v.body = GetVehicleBodyHealth(v.handle)
    end
end

local function destroy(v)
    v.destroyed = true
    vehicles[v.id] = nil
    write(WDB.update, SQL.delete, { v.id }, 'deleting vehicle ' .. v.id)
    pcall(function() inv():DeleteStash('veh_' .. v.id) end)
    M.log:info('vehicle %s (%s) was destroyed', v.id, v.model)
    -- The burnt-out wreck stays a while, then goes.
    local h = v.handle
    if h then
        byHandle[h] = nil
        Citizen.SetTimeout(120000, function() if DoesEntityExist(h) then DeleteEntity(h) end end)
    end
end

local function despawn(v)
    capture(v)
    if v.handle then
        byHandle[v.handle] = nil
        if DoesEntityExist(v.handle) then DeleteEntity(v.handle) end
    end
    v.handle, v.farSince = nil, nil
    save(v)
end

local function playersCoords()
    local out = {}
    for _, src in ipairs(GetPlayers()) do
        local p = playerCoords(tonumber(src))
        if p then out[#out + 1] = p end
    end
    return out
end

local function nearest(list, p)
    local best = math.huge
    for _, q in ipairs(list) do best = math.min(best, dist(p, q)) end
    return best
end

local function createWreck(point)
    local w = Rules.wreck(M.config.wreck, math.random, math.random)
    local v = { id = newId(), model = M.config.models[math.random(1, #M.config.models)],
        x = point.x, y = point.y, z = point.z, heading = point.heading or 0.0,
        fuel = w.fuel, engine = w.engine, body = w.body, parts = w.parts, locked = false }
    vehicles[v.id] = v
    insert(v)
    return v
end

-- A free spawn point: no vehicle within 15 m, no player within 200 m.
local function freePoint(players)
    local points = {}
    for _, p in ipairs(M.config.spawnPoints) do
        local free = nearest(players, p) > 200
        if free then
            for _, v in pairs(vehicles) do
                if dist(v, p) < 15 then free = false; break end
            end
        end
        if free then points[#points + 1] = p end
    end
    if #points == 0 then return nil end
    return points[math.random(1, #points)]
end

local function count()
    local n = 0
    for _ in pairs(vehicles) do n = n + 1 end
    return n
end

local function tick(players, t)
    local cfg = M.config
    for _, v in pairs(vehicles) do
        if v.handle then
            if not DoesEntityExist(v.handle) then
                byHandle[v.handle], v.handle = nil, nil -- gone (deleted elsewhere): stays where it was last saved
            elseif v.ackSeq == v.seq and GetVehicleEngineHealth(v.handle) <= -3900 then
                destroy(v)
            else
                local d = nearest(players, coordsOf(v.handle))
                if d > cfg.despawnDistance then
                    v.farSince = v.farSince or t
                    if t - v.farSince >= cfg.despawnAfterSeconds * 1000 then despawn(v) end
                else
                    v.farSince = nil
                end
            end
        elseif nearest(players, v) <= cfg.spawnDistance then
            spawn(v)
        end
    end
end

local function loop(token)
    local sinceSave, sinceRespawn = 0, 0
    while runToken == token do
        Citizen.Wait(2000)
        if runToken ~= token then return end
        local players = playersCoords()
        tick(players, now())
        sinceSave = sinceSave + 2
        if sinceSave >= M.config.saveSeconds then
            sinceSave = 0
            for _, v in pairs(vehicles) do
                if v.handle then capture(v); save(v) end
            end
        end
        sinceRespawn = sinceRespawn + 2
        if sinceRespawn >= M.config.respawnMinutes * 60 then
            sinceRespawn = 0
            if count() < M.config.maxVehicles then
                local p = freePoint(players)
                if p then createWreck(p) end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------

local LABELS = { battery = 'Installing the battery', engine = 'Fitting engine parts', wheel = 'Mounting a wheel',
    refuel = 'Refuelling', repair = 'Repairing', fitLock = 'Fitting a lock', toggleLock = 'Turning the key',
    pickLock = 'Picking the lock', fillCan = 'Filling the jerry can', pumpRefuel = 'Refuelling at the pump' }

-- The pump at `coords` (everyone shares it), topped up for the time passed.
local function pumpAt(coords)
    local key = Rules.pumpKey(coords)
    local p = pumps[key]
    if not p then
        p = { litres = M.config.pump.litres }
        pumps[key] = p
    end
    return Rules.pumpLevel(p, M.config.pump, now())
end

local function dry(src, pump)
    notice(src, 'This pump is dry. It is full again in ' .. Rules.duration(Rules.pumpWait(pump, M.config.pump, now())) .. '.')
end

-- What a player near a pump sees above it.
local function sendPump(src, coords)
    local pump = pumpAt(coords)
    TriggerClientEvent('wasteland:vehicles:client:pump', src, Rules.pumpKey(coords), {
        litres = math.floor(pump.litres + 0.5), max = M.config.pump.litres, minutes = Rules.pumpWait(pump, M.config.pump, now()),
    })
end

local function keyFor(src, v)
    if not v.lockCode then return nil end
    for _, k in ipairs(inv():FindItems(src, 'vehicle_key')) do
        if k.metadata.code == v.lockCode then return k end
    end
    return nil
end

local function canWithFuel(src)
    local best
    for _, c in ipairs(inv():FindItems(src, 'jerry_can')) do
        if (c.metadata.fuel or 0) > 0 and (not best or c.metadata.fuel > best.metadata.fuel) then best = c end
    end
    return best
end

local function has(src)
    return function(item)
        if item == 'jerry_can' then return canWithFuel(src) ~= nil end
        return (inv():GetItemCount(src, item) or 0) > 0
    end
end

local function vehicleFor(src, netId)
    local h = NetworkGetEntityFromNetworkId(netId)
    local id = h and byHandle[h]
    local v = id and vehicles[id]
    if not v or not v.handle then return nil end
    local p = playerCoords(src)
    if not p or dist(p, coordsOf(v.handle)) > M.config.reach then return nil, 'You are too far away.' end
    return v
end

local function start(src, netId, action)
    if acting[src] and now() - acting[src].startedAt < 30000 then return end
    acting[src] = nil
    local v, why = vehicleFor(src, netId)
    if not v then if why then notice(src, why) end; return end
    if action == 'trunk' then
        local ok, reason = Rules.check('trunk', v, has(src), keyFor(src, v) ~= nil, M.config)
        if not ok then notice(src, reason); return end
        inv():OpenStash(src, 'veh_' .. v.id, { label = 'Trunk', width = 6, height = 5, maxWeight = 80, coords = coordsOf(v.handle), open = true })
        return
    end
    local ok, reason = Rules.check(action, v, has(src), keyFor(src, v) ~= nil, M.config)
    if not ok then notice(src, reason); return end
    acting[src] = { id = v.id, action = action, startedAt = now() }
    TriggerClientEvent('wasteland:vehicles:client:progress', src, { seconds = M.config.seconds[action], label = LABELS[action] })
end

local function finish(src)
    local a = acting[src]
    acting[src] = nil
    if not a then return end
    if now() - a.startedAt < (a.seconds or M.config.seconds[a.action]) * 1000 - 300 then
        M.log:warn('player %d finished "%s" too early', src, a.action)
        return
    end
    local p = playerCoords(src)
    if a.action == 'fillCan' then
        if not p or dist(p, a.coords) > M.config.reach then notice(src, 'You moved away.'); return end
        local pump = pumpAt(a.coords)
        if pump.litres <= 0 then dry(src, pump); return end
        local cap = M.config.jerryCanLitres
        for _, c in ipairs(inv():FindItems(src, 'jerry_can')) do
            local have = c.metadata.fuel or 0
            if have < cap then
                local amount = Rules.pumpTake(pump, M.config.pump, cap - have, now())
                inv():SetItemMetadata(src, c.uid, { fuel = have + amount })
                notice(src, string.format('Jerry can: %.0f of %d L. The pump has %.0f L left.', have + amount, cap, pump.litres))
                sendPump(src, a.coords)
                return
            end
        end
        notice(src, 'You have no jerry can that is not full.')
        return
    end
    if a.action == 'pumpRefuel' then
        local v = vehicles[a.id]
        if not p or dist(p, a.coords) > M.config.reach or not v or not v.handle
            or dist(coordsOf(v.handle), a.coords) > M.config.pump.vehicleDistance then
            notice(src, 'You moved away (or the vehicle did).')
            return
        end
        local pump = pumpAt(a.coords)
        if pump.litres <= 0 then dry(src, pump); return end
        if M.config.tankLitres - v.fuel <= 0 then notice(src, 'The tank is full.'); return end
        local amount = Rules.pumpTake(pump, M.config.pump, M.config.tankLitres - v.fuel, now())
        v.fuel = v.fuel + amount
        sendPump(src, a.coords)
        publish(v, false)
        save(v)
        notice(src, string.format('Added %.0f L. The tank has %.0f of %d L; the pump has %.0f L left.', amount, v.fuel, M.config.tankLitres, pump.litres))
        TriggerEvent('wasteland:vehicles:action', src, 'pumpRefuel', v.id)
        return
    end
    local v = vehicles[a.id]
    if not v or not v.handle or not p or dist(p, coordsOf(v.handle)) > M.config.reach + 1.0 then notice(src, 'You moved away.'); return end
    capture(v)
    local key = keyFor(src, v)
    local item, reason = Rules.check(a.action, v, has(src), key ~= nil, M.config)
    if not item then notice(src, reason); return end

    local cfg = M.config
    if a.action == 'battery' or a.action == 'engine' or a.action == 'wheel' then
        if not inv():RemoveItem(src, item, 1) then notice(src, 'The part is gone.'); return end
        if a.action == 'battery' then v.parts.battery = true
        elseif a.action == 'engine' then v.parts.engine = true
        else v.parts.wheels = math.min(4, v.parts.wheels + 1) end
        notice(src, LABELS[a.action]:gsub('ing', 'ed', 1) .. '.')
    elseif a.action == 'refuel' then
        local c = canWithFuel(src)
        local amount = math.min(c.metadata.fuel, cfg.tankLitres - v.fuel)
        inv():SetItemMetadata(src, c.uid, { fuel = c.metadata.fuel - amount })
        v.fuel = v.fuel + amount
        notice(src, string.format('Added %.0f L. The tank has %.0f of %d L.', amount, v.fuel, cfg.tankLitres))
    elseif a.action == 'repair' then
        if not inv():RemoveItem(src, item, 1) then return end
        v.engine = math.min(1000, v.engine + cfg.repair.engine)
        v.body = math.min(1000, v.body + cfg.repair.body)
        notice(src, string.format('Repaired: engine %d%%, body %d%%.', math.floor(v.engine / 10), math.floor(v.body / 10)))
    elseif a.action == 'fitLock' then
        if not inv():RemoveItem(src, item, 1) then return end
        local code = newCode()
        local ok = inv():AddItem(src, 'vehicle_key', 1, { code = code, vehicle = v.model })
        if not ok then
            inv():AddItem(src, 'vehicle_lock', 1)
            notice(src, 'Make room for the key first.')
            return
        end
        v.lockCode, v.locked = code, true
        notice(src, 'Lock fitted and locked. Keep the key: it is the only one.')
    elseif a.action == 'toggleLock' then
        v.locked = not v.locked
        notice(src, v.locked and 'Locked.' or 'Unlocked.')
    elseif a.action == 'pickLock' then
        TriggerEvent('wasteland:noise', coordsOf(v.handle), cfg.lockpick.noise)
        if math.random() < cfg.lockpick.chance then
            v.lockCode, v.locked = nil, false
            notice(src, 'The lock breaks open.')
            M.log:info('player %d picked the lock of vehicle %s', src, v.id)
        else
            if math.random() < cfg.lockpick.breakChance then
                inv():RemoveItem(src, 'lockpick', 1)
                notice(src, 'The lockpick snaps.')
            else
                notice(src, 'The lock holds.')
            end
        end
    end
    publish(v, a.action == 'repair' or a.action == 'battery' or a.action == 'engine' or a.action == 'wheel')
    save(v)
    TriggerEvent('wasteland:vehicles:action', src, a.action, v.id)
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local PAIR = function(a, b) return { type = 'array', default = { a, b }, minItems = 2, maxItems = 2, items = { type = 'number' } } end
local SECONDS = { type = 'number', min = 0.5, max = 120 }

M = Wasteland.DefineModule({
    name = 'vehicles',
    version = '0.1.0',
    description = 'Persistent vehicles: wrecks to repair, fuel, parts, trunks, locks and keys',
    core = '^1.1.0',
    dependencies = { database = '^0.1.0', players = '^0.1.0', inventory = '^0.1.0' },
    async = true,
    config = {
        file = 'vehicles.lua',
        optional = true,
        schema = { type = 'table', fields = {
            maxVehicles = { type = 'integer', default = 30, min = 0, max = 500 },
            respawnMinutes = { type = 'number', default = 20, min = 0.1, max = 10000 },
            spawnDistance = { type = 'number', default = 250, min = 50, max = 1000 },
            despawnDistance = { type = 'number', default = 350, min = 60, max = 2000 },
            despawnAfterSeconds = { type = 'integer', default = 30, min = 0, max = 3600 },
            saveSeconds = { type = 'integer', default = 30, min = 2, max = 3600 },
            reach = { type = 'number', default = 4.0, min = 1, max = 20 },
            tankLitres = { type = 'number', default = 50, min = 1, max = 1000 },
            jerryCanLitres = { type = 'number', default = 20, min = 1, max = 1000 },
            fuel = { type = 'table', fields = { idlePerMinute = { type = 'number', default = 0.06, min = 0 },
                per100km = { type = 'number', default = 14, min = 0 } } },
            repair = { type = 'table', fields = { engine = { type = 'number', default = 400, min = 0, max = 1000 },
                body = { type = 'number', default = 400, min = 0, max = 1000 } } },
            seconds = { type = 'table', fields = {
                battery = SECONDS, engine = SECONDS, wheel = SECONDS, refuel = SECONDS, repair = SECONDS,
                fitLock = SECONDS, toggleLock = SECONDS, pickLock = SECONDS, fillCan = SECONDS,
            } },
            pump = { type = 'table', fields = {
                litres = { type = 'number', default = 80, min = 1, max = 100000, description = 'Fuel in a full pump (litres)' },
                refillMinutes = { type = 'number', default = 120, min = 0.1, max = 100000,
                    description = 'A used pump is full again this many real minutes after fuel was first taken' },
                litresPerSecond = { type = 'number', default = 4, min = 0.1, max = 1000 },
                vehicleDistance = { type = 'number', default = 8, min = 2, max = 30, description = 'How close the vehicle must be to the pump (m)' },
            } },
            lockpick = { type = 'table', fields = { chance = { type = 'number', default = 0.3, min = 0, max = 1 },
                breakChance = { type = 'number', default = 0.5, min = 0, max = 1 }, noise = { type = 'number', default = 60, min = 0, max = 1000 } } },
            wreck = { type = 'table', fields = {
                batteryMissing = { type = 'number', default = 0.6, min = 0, max = 1 },
                engineMissing = { type = 'number', default = 0.5, min = 0, max = 1 },
                wheelsMissingChance = { type = 'number', default = 0.4, min = 0, max = 1 },
                wheelsMissingMax = { type = 'integer', default = 2, min = 1, max = 4 },
                fuel = PAIR(0, 8), engine = PAIR(250, 700), body = PAIR(300, 800),
            } },
            models = { type = 'array', minItems = 1, default = { 'emperor2' }, items = { type = 'string', pattern = '^[%w_]+$' } },
            pumps = { type = 'array', default = {}, items = { type = 'string', pattern = '^[%w_]+$' } },
            spawnPoints = { type = 'array', default = {}, items = { type = 'table', fields = {
                x = { type = 'number', required = true }, y = { type = 'number', required = true },
                z = { type = 'number', required = true }, heading = { type = 'number', default = 0 },
            } } },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        for action, s in pairs({ battery = 6, engine = 10, wheel = 6, refuel = 8, repair = 10, fitLock = 6, toggleLock = 1, pickLock = 8, fillCan = 8 }) do
            if not M.config.seconds[action] then M.config.seconds[action] = s end
        end
        for _, item in ipairs({ 'car_battery', 'engine_parts', 'car_wheel', 'jerry_can', 'vehicle_repair_kit', 'vehicle_lock', 'vehicle_key', 'lockpick' }) do
            if not inv():GetItemDefinition(item) then return false, string.format('vehicles need the item "%s" in inventory.lua items', item) end
        end
        vehicles, byHandle, acting, pumps = {}, {}, {}, {}
        local token = {}
        runToken = token
        Citizen.CreateThread(function()
            local migrated, err = WDB.migrate('vehicles', WLV.MIGRATIONS)
            if runToken ~= token then return end
            if not migrated then return M.fail('database migrations failed: ' .. tostring(err)) end
            local rows, qerr = WDB.query(SQL.selectAll, {})
            if runToken ~= token then return end
            if not rows then return M.fail('could not load vehicles: ' .. tostring(qerr)) end
            for _, r in ipairs(rows) do
                vehicles[r.id] = { id = r.id, model = r.model, x = r.x, y = r.y, z = r.z, heading = r.heading, fuel = r.fuel,
                    engine = r.engine, body = r.body, parts = Rules.decodeParts(r.parts), lockCode = r.lock_code,
                    locked = r.locked == 1 or r.locked == true }
            end
            -- Fill the world up to the limit on first start.
            local players = playersCoords()
            while count() < M.config.maxVehicles do
                local p = freePoint(players)
                if not p then break end
                createWreck(p)
            end
            M.log:info('%d vehicles in the world', count())
            Citizen.CreateThread(function() loop(token) end)
            M.ready()
        end)
        return true
    end,
    onShutdown = function()
        runToken = nil
        -- A stopping resource cannot wait for the database: capture every
        -- vehicle that is out, remove it, and send one final transaction
        -- that the database resource completes on its own.
        local statements = {}
        for _, v in pairs(vehicles) do
            if v.handle then
                capture(v)
                byHandle[v.handle] = nil
                if DoesEntityExist(v.handle) then DeleteEntity(v.handle) end
                v.handle = nil
                if not v.destroyed then statements[#statements + 1] = { SQL.update, params(v) } end
            end
        end
        if #statements > 0 then
            local ok, err = pcall(function()
                exports[WDB.RESOURCE]:Transaction(statements, function(saved, saveErr)
                    if not saved then print('^1[Wasteland] [ERROR] [vehicles] final save failed: ' .. tostring(saveErr) .. '^7') end
                end)
            end)
            if not ok then print('^1[Wasteland] [ERROR] [vehicles] final save could not be sent: ' .. tostring(err) .. '^7') end
        end
        vehicles, byHandle = {}, {}
    end,
})

local RATE = { burst = 6, perSecond = 2 }
local ACTIONS = { 'battery', 'engine', 'wheel', 'refuel', 'repair', 'fitLock', 'toggleLock', 'pickLock', 'trunk' }

M.netEvent('wasteland:vehicles:server:act', {
    args = { { type = 'integer', required = true, min = 1 }, { type = 'enum', required = true, values = ACTIONS } },
    rateLimit = RATE,
}, start)

M.netEvent('wasteland:vehicles:server:fillCan', {
    args = { { type = 'table', required = true, fields = { x = { type = 'number', required = true }, y = { type = 'number', required = true },
        z = { type = 'number', required = true } } } },
    rateLimit = RATE,
}, function(src, coords)
    if acting[src] and now() - acting[src].startedAt < 30000 then return end
    local p = playerCoords(src)
    if not p or dist(p, coords) > M.config.reach then notice(src, 'You are too far away.'); return end
    local cans = inv():FindItems(src, 'jerry_can')
    if #cans == 0 then notice(src, 'You need a jerry can.'); return end
    local pump = pumpAt(coords)
    if pump.litres <= 0 then dry(src, pump); return end
    acting[src] = { action = 'fillCan', startedAt = now(), coords = coords }
    TriggerClientEvent('wasteland:vehicles:client:progress', src, { seconds = M.config.seconds.fillCan, label = LABELS.fillCan })
end)

-- A player near a pump asks how much fuel it has.
M.netEvent('wasteland:vehicles:server:pumpInfo', {
    args = { { type = 'table', required = true, fields = { x = { type = 'number', required = true }, y = { type = 'number', required = true },
        z = { type = 'number', required = true } } } },
    rateLimit = { burst = 5, perSecond = 1 },
}, function(src, coords)
    local p = playerCoords(src)
    if p and dist(p, coords) <= 10 then sendPump(src, coords) end
end)

-- Refuel a vehicle parked next to a pump, straight from the pump.
M.netEvent('wasteland:vehicles:server:pumpRefuel', {
    args = { { type = 'integer', required = true, min = 1 }, { type = 'table', required = true, fields = {
        x = { type = 'number', required = true }, y = { type = 'number', required = true }, z = { type = 'number', required = true } } } },
    rateLimit = RATE,
}, function(src, netId, coords)
    if acting[src] and now() - acting[src].startedAt < 30000 then return end
    local p = playerCoords(src)
    if not p or dist(p, coords) > M.config.reach then notice(src, 'You are too far away.'); return end
    local h = NetworkGetEntityFromNetworkId(netId)
    local v = h and byHandle[h] and vehicles[byHandle[h]]
    if not v or dist(coordsOf(h), coords) > M.config.pump.vehicleDistance then
        notice(src, 'Park the vehicle next to the pump.')
        return
    end
    local need = M.config.tankLitres - v.fuel
    if need < 0.5 then notice(src, 'The tank is full.'); return end
    local pump = pumpAt(coords)
    if pump.litres <= 0 then dry(src, pump); return end
    local litres = math.min(need, pump.litres)
    local seconds = math.max(2, math.min(20, litres / M.config.pump.litresPerSecond))
    acting[src] = { action = 'pumpRefuel', id = v.id, startedAt = now(), coords = coords, seconds = seconds }
    TriggerClientEvent('wasteland:vehicles:client:progress', src, { seconds = seconds,
        label = string.format('%s (%.0f L, pump has %.0f L)', LABELS.pumpRefuel, litres, pump.litres) })
end)

M.netEvent('wasteland:vehicles:server:config', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    TriggerClientEvent('wasteland:vehicles:client:config', src, { pumps = M.config.pumps, fuel = M.config.fuel, tank = M.config.tankLitres,
        pumpVehicleDistance = M.config.pump.vehicleDistance })
end)

M.netEvent('wasteland:vehicles:server:finish', { rateLimit = RATE }, finish)

-- The client running a vehicle applied state number `seq` (see capture).
M.netEvent('wasteland:vehicles:server:applied', {
    args = { { type = 'integer', required = true, min = 1 }, { type = 'integer', required = true, min = 0 } },
    rateLimit = { burst = 20, perSecond = 10 },
}, function(src, netId, seq)
    local h = NetworkGetEntityFromNetworkId(netId)
    local v = h and byHandle[h] and vehicles[byHandle[h]]
    if v and seq == v.seq and NetworkGetEntityOwner(h) == src and v.ackSeq ~= seq then
        v.ackSeq = seq
        publish(v, false) -- later owners must not apply the old damage again
    end
end)
M.netEvent('wasteland:vehicles:server:cancel', { rateLimit = RATE }, function(src) acting[src] = nil end)

-- The driver reports fuel use (only ever down).
M.netEvent('wasteland:vehicles:server:fuel', {
    args = { { type = 'integer', required = true, min = 1 }, { type = 'number', required = true, min = 0, max = 10000 } },
    rateLimit = { burst = 4, perSecond = 1 },
}, function(src, netId, litres)
    local h = NetworkGetEntityFromNetworkId(netId)
    local v = h and byHandle[h] and vehicles[byHandle[h]]
    if not v then return end
    local driving = GetPedInVehicleSeat(h, -1) == GetPlayerPed(src)
    if (driving or v.lastDriver == src) and litres < v.fuel then
        v.fuel = litres
        publish(v, false)
    end
    -- The client also reports when the driver gets out: save right away, so
    -- a crash or restart soon after does not lose where the car was left.
    if not driving and v.lastDriver == src then
        capture(v)
        save(v)
    end
    if driving then v.lastDriver = src end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then acting[src] = nil end
    -- Save every vehicle that is out (the one they drove among them).
    if M and M.active then
        Citizen.CreateThread(function()
            for _, v in pairs(vehicles) do
                if v.handle then capture(v); save(v) end
            end
        end)
    end
end)

-------------------------------------------------------------------------------
-- Exports (vehicles api 0.1)
-------------------------------------------------------------------------------

--- GetPumpFuel(coords) -> litres left in the pump at coords
exports('GetPumpFuel', function(coords)
    if not (M and M.active) or type(coords) ~= 'table' then return nil end
    return pumpAt(coords).litres
end)

--- GetVehicleCount() -> number in the world
exports('GetVehicleCount', function() return count() end)

--- SpawnWreck(coords, model?) -> id   (events, admins)
exports('SpawnWreck', function(coords, model)
    if not (M and M.active) or type(coords) ~= 'table' then return nil end
    local v = createWreck({ x = coords.x, y = coords.y, z = coords.z, heading = coords.heading or 0.0 })
    if model then v.model = model; save(v) end
    return v.id
end)

--- GetVehicleState(id) -> copy of the record | nil
exports('GetVehicleState', function(id)
    local v = vehicles[id]
    if not v then return nil end
    return { id = v.id, model = v.model, fuel = v.fuel, engine = v.engine, body = v.body,
        parts = { battery = v.parts.battery, engine = v.parts.engine, wheels = v.parts.wheels },
        locked = v.locked, hasLock = v.lockCode ~= nil, spawned = v.handle ~= nil, netId = v.handle and NetworkGetNetworkIdFromEntity(v.handle) or nil }
end)

--- GetVehicleStats() -> { total, out, pumpsUsed }
exports('GetVehicleStats', function()
    local out, used = 0, 0
    for _, v in pairs(vehicles) do if v.handle then out = out + 1 end end
    for _, p in pairs(pumps) do if p.refillAt then used = used + 1 end end
    return { total = count(), out = out, pumpsUsed = used }
end)

--- FixVehicle(netId) -> ok, err   (admin: every part, full fuel, no damage)
exports('FixVehicle', function(netId)
    local h = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local v = h and byHandle[h] and vehicles[byHandle[h]]
    if not v then return false, 'that is not a world vehicle' end
    v.parts = { battery = true, engine = true, wheels = 4 }
    v.fuel, v.engine, v.body = M.config.tankLitres, 1000.0, 1000.0
    publish(v, true)
    save(v)
    return true
end)

--- SpawnWorking(coords, model?) -> id   (admin: a car that drives)
exports('SpawnWorking', function(coords, model)
    if not (M and M.active) or type(coords) ~= 'table' then return nil end
    local v = createWreck({ x = coords.x, y = coords.y, z = coords.z, heading = coords.heading or 0.0 })
    if model then v.model = model end
    v.parts = { battery = true, engine = true, wheels = 4 }
    v.fuel, v.engine, v.body = M.config.tankLitres, 1000.0, 1000.0
    save(v)
    return v.id
end)

--- RefillPumps() -> number of pumps that were not full
exports('RefillPumps', function()
    local n = 0
    for _, p in pairs(pumps) do if p.refillAt then n = n + 1 end end
    pumps = {}
    return n
end)

--- GetSpawnPoints() -> list of { x, y, z, heading }   (admin overlay)
exports('GetSpawnPoints', function() return M and M.config.spawnPoints or {} end)
