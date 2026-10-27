-- wasteland_supplydrops :: server/main.lua
-- Module "supplydrops" - the SDK example module (docs/SDK_GUIDE.md).
--
-- Every `intervalMinutes` (when players are online) a supply crate comes
-- down at one of the configured points. Every player gets a map blip and a
-- message; the first to reach it and open it fills it from a loot table, and
-- everyone shares what is inside (an inventory stash). The crate is gone
-- after `lifetimeMinutes`. Drops are written to the database (history).
--
-- What this file shows, top to bottom:
--   1. the module definition (name, versions, dependencies, config schema)
--   2. an async init with a database migration, M.ready() / M.fail()
--   3. a thread stopped by a token (init and shutdown are symmetric)
--   4. guarded net events (M.netEvent) that re-check game state
--   5. calling other modules only through their exports
--   6. an admin command, exports and a server event for other modules

local Rules = WLSD.Rules
local M
local drops = {}        -- id -> { id, coords, label, expiresAt, filled }
local runToken = nil
local lastDropAt = 0
local commandRegistered = false

local function now() return GetGameTimer() end
local function inv() return exports.wasteland_inventory end
local function notice(src, msg) TriggerClientEvent('wasteland:supplydrops:client:notice', src, msg) end
local function stashName(id) return 'supply_' .. id end

-- The table and statements are in server/sql.lua (WLSD.MIGRATIONS, WLSD.SQL)
-- so tests can load them too.
local MIGRATIONS, SQL = WLSD.MIGRATIONS, WLSD.SQL

-------------------------------------------------------------------------------
-- Drops
-------------------------------------------------------------------------------

-- What clients get (never more than they need).
local function public(d)
    return { id = d.id, coords = d.coords, label = d.label, secondsLeft = math.max(0, math.floor((d.expiresAt - now()) / 1000)) }
end

local function activeList()
    local out = {}
    for _, d in pairs(drops) do out[#out + 1] = d end
    return out
end

-- Thread only (WDB waits for the database).
local function spawnDrop(point)
    local p = point or Rules.pickPoint(M.config.points, activeList(), M.config.minGap, math.random)
    if not p then return nil, 'no free drop point' end
    local id, err = WDB.insert(SQL.insert, { p.label or 'Supply drop', p.x, p.y, p.z, os.time() })
    if not id then
        M.log:warn('could not store a supply drop: %s', tostring(err))
        return nil, 'database error'
    end
    local d = { id = id, coords = { x = p.x, y = p.y, z = p.z }, label = p.label or 'Supply drop',
        expiresAt = now() + M.config.lifetimeMinutes * 60000, filled = false }
    drops[id] = d
    lastDropAt = now()
    M.log:info('supply drop %d at %s (%.0f, %.0f)', id, d.label, p.x, p.y)
    TriggerClientEvent('wasteland:supplydrops:client:drop', -1, public(d), true)
    TriggerEvent('wasteland:supplydrops:dropped', id, d.coords, d.label)
    return id
end

local function removeDrop(id, why)
    local d = drops[id]
    if not d then return end
    drops[id] = nil
    if GetResourceState('wasteland_inventory') == 'started' then inv():DeleteStash(stashName(id)) end
    TriggerClientEvent('wasteland:supplydrops:client:remove', -1, id)
    M.log:debug('supply drop %d removed (%s)', id, why)
end

-- Fill a crate the first time it is opened: from wasteland_loot's table if
-- that module runs (optional dependency), else from our own item list.
local function fill(stashId)
    local items
    if GetResourceState('wasteland_loot') == 'started' and M.config.lootTable ~= '' then
        local ok, rolled = pcall(function() return exports.wasteland_loot:RollTable(M.config.lootTable) end)
        if ok and type(rolled) == 'table' then items = rolled end
    end
    -- never empty: a table that rolled nothing (or does not exist) falls back to our own list
    if not items or #items == 0 then items = Rules.rollItems(M.config.items, M.config.rolls, math.random) end
    local added = 0
    for _, it in ipairs(items) do
        local ok, err = inv():AddItem(stashId, it.name, it.count)
        if ok then added = added + 1 else M.log:warn('supply crate: %s x %d: %s', it.name, it.count, tostring(err)) end
    end
    if added == 0 then
        for _, it in ipairs(Rules.rollItems(M.config.items, { math.max(1, M.config.rolls[1]), math.max(1, M.config.rolls[2]) }, math.random)) do
            inv():AddItem(stashId, it.name, it.count)
        end
    end
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

local function openDrop(src, id)
    local d = drops[id]
    if not d then notice(src, 'The crate is gone.'); return end
    -- The client says "I opened crate 12"; the server checks it is true.
    local p = playerCoords(src)
    -- Distance along the ground, with room for slopes and steps: the crate's
    -- height on the ground can differ from the point's by a few metres.
    local dx, dy, dz = (p and p.x or 1e9) - d.coords.x, (p and p.y or 0) - d.coords.y, (p and p.z or 0) - d.coords.z
    if dx * dx + dy * dy > M.config.reach * M.config.reach or math.abs(dz) > 4.0 then notice(src, 'You are too far away.'); return end
    local opts = { label = 'Supply crate', width = M.config.grid[1], height = M.config.grid[2], maxWeight = 200,
        coords = d.coords, reach = M.config.reach + 4.0 }
    local stashId, err = inv():EnsureStash(stashName(id), opts)
    if not stashId then notice(src, 'The crate is stuck.'); M.log:warn('stash: %s', tostring(err)); return end
    if not d.filled then
        d.filled = true
        fill(stashId)
        local cid = exports.wasteland_players:GetCharacterId(src)
        WDB.update(SQL.opened, { cid, os.time(), id })
        TriggerEvent('wasteland:supplydrops:opened', src, id)
        TriggerClientEvent('wasteland:supplydrops:client:notice', -1, string.format('Someone opened the supply crate at %s.', d.label))
    end
    opts.open = true
    inv():OpenStash(src, stashName(id), opts)
end

-- Runs while the module runs; the token stops it on shutdown.
local function loop(token)
    while runToken == token do
        Citizen.Wait(5000)
        if runToken ~= token then return end
        for id, d in pairs(drops) do
            if now() >= d.expiresAt then removeDrop(id, 'expired') end
        end
        local active = 0
        for _ in pairs(drops) do active = active + 1 end
        if M.config.intervalMinutes > 0 and Rules.due(now() - lastDropAt, M.config.intervalMinutes, active, M.config.maxActive,
            #GetPlayers(), M.config.minPlayers) then
            spawnDrop()
        end
    end
end

-------------------------------------------------------------------------------
-- Module definition
-------------------------------------------------------------------------------

local XYZ = { type = 'table', fields = {
    x = { type = 'number', required = true }, y = { type = 'number', required = true }, z = { type = 'number', required = true },
    label = { type = 'string', default = 'Supply drop', maxLength = 64 },
} }

M = Wasteland.DefineModule({
    name = 'supplydrops',
    version = '1.0.0',
    description = 'Supply drops: crates with loot come down now and then (SDK example)',
    core = '^1.1.0',
    dependencies = { database = '^0.1.0', players = '^0.1.0', inventory = '^0.1.0' },
    optionalDependencies = { loot = '^0.1.0' },
    async = true, -- the migration waits for the database; we call M.ready() after it
    config = {
        file = 'supplydrops.lua',
        optional = true,
        schema = { type = 'table', fields = {
            intervalMinutes = { type = 'number', default = 45, min = 0, max = 10000, description = 'Minutes between drops (0 = only by command)' },
            lifetimeMinutes = { type = 'number', default = 20, min = 1, max = 10000 },
            maxActive = { type = 'integer', default = 1, min = 1, max = 10 },
            minPlayers = { type = 'integer', default = 1, min = 0, max = 1000 },
            minGap = { type = 'number', default = 300, min = 0, max = 10000, description = 'Metres between two active drops' },
            reach = { type = 'number', default = 3.5, min = 1, max = 20 },
            grid = { type = 'array', default = { 6, 5 }, minItems = 2, maxItems = 2, items = { type = 'integer', min = 1, max = 12 } },
            lootTable = { type = 'string', default = 'supplydrop', maxLength = 48, description = 'loot.lua table ("" = use items below)' },
            rolls = { type = 'array', default = { 3, 5 }, minItems = 2, maxItems = 2, items = { type = 'integer', min = 0, max = 30 } },
            items = { type = 'array', default = {}, items = { type = 'table', fields = {
                name = { type = 'string', required = true, pattern = '^[%w_]+$' },
                min = { type = 'integer', default = 1, min = 1 }, max = { type = 'integer', default = 1, min = 1 },
                weight = { type = 'integer', default = 1, min = 1 },
            } } },
            points = { type = 'array', default = {}, items = XYZ },
            adminCommand = { type = 'string', default = 'supplydrop', pattern = '^[a-z][a-z0-9_]*$' },
            adminAce = { type = 'string', default = 'wasteland.admin' },
        } },
    },

    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        -- Checks a schema cannot express: fail with a clear message.
        if #M.config.points == 0 then return false, 'supplydrops.lua: add at least one point' end
        for _, it in ipairs(M.config.items) do
            if not inv():GetItemDefinition(it.name) then   -- may be registered later by another resource
                M.log:warn('supplydrops.lua: item "%s" is not in inventory.lua items (yet)', it.name)
            end
        end
        if not commandRegistered then
            -- /supplydrop        a drop now at a random point
            -- /supplydrop here   a drop where you stand
            RegisterCommand(M.config.adminCommand, function(source, args)
                local src = tonumber(source) or 0
                if src ~= 0 and not IsPlayerAceAllowed(tostring(src), M.config.adminAce) then return end
                if not (M and M.active) then return end
                Citizen.CreateThread(function()
                    local point = nil
                    if args[1] == 'here' and src ~= 0 then
                        local p = playerCoords(src)
                        if p then point = { x = p.x + 3.0, y = p.y, z = p.z, label = 'your position' } end
                    end
                    local id, err = spawnDrop(point)
                    local msg = id and ('Supply drop ' .. id .. ' is coming down.') or ('No supply drop: ' .. tostring(err))
                    if src == 0 then print(msg) else notice(src, msg) end
                end)
            end, false)
            commandRegistered = true
        end
        drops, lastDropAt = {}, now()
        local token = {}
        runToken = token
        Citizen.CreateThread(function()
            local ok, err = WDB.migrate('supplydrops', MIGRATIONS)
            if runToken ~= token then return end
            if not ok then return M.fail('database migrations failed: ' .. tostring(err)) end
            Citizen.CreateThread(function() loop(token) end)
            M.ready()
        end)
        return true
    end,

    onShutdown = function()
        runToken = nil -- stops the loop
        for id in pairs(drops) do removeDrop(id, 'module stopped') end
        drops = {}
    end,
})

-------------------------------------------------------------------------------
-- Network: only through M.netEvent (checked arguments, rate limits)
-------------------------------------------------------------------------------

-- A client (joining, or after a restart) asks for the drops that are out.
M.netEvent('wasteland:supplydrops:server:sync', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    for _, d in pairs(drops) do TriggerClientEvent('wasteland:supplydrops:client:drop', src, public(d), false) end
end)

M.netEvent('wasteland:supplydrops:server:open', {
    args = { { type = 'integer', required = true, min = 1 } },
    rateLimit = { burst = 4, perSecond = 1 },
}, function(src, id)
    Citizen.CreateThread(function() openDrop(src, id) end) -- the stash may load from the database
end)

-------------------------------------------------------------------------------
-- Exports (supplydrops api 1.0) - how other modules use this one
-------------------------------------------------------------------------------

--- GetActiveDrops() -> list of { id, coords, label, secondsLeft }
exports('GetActiveDrops', function()
    local out = {}
    for _, d in pairs(drops) do out[#out + 1] = public(d) end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)

--- SpawnDrop(coords?) -> true   (coords = { x, y, z, label? }; nil = a random point)
exports('SpawnDrop', function(coords)
    if not (M and M.active) then return false end
    Citizen.CreateThread(function() spawnDrop(type(coords) == 'table' and coords or nil) end)
    return true
end)

-- Server events other modules can listen to (AddEventHandler):
--   wasteland:supplydrops:dropped (id, coords, label)
--   wasteland:supplydrops:opened  (source, id)
