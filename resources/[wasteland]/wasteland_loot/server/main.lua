-- wasteland_loot :: server/main.lua
-- Module "loot": searchable world props and zombie bodies. The client
-- targets a container (wasteland_target) and asks to search it; the server
-- checks the container type, the distance and whether anything is left,
-- times the search, fills the container from its loot table when due, and
-- opens it (an inventory stash, shared by everyone) next to the inventory.
--
-- A world container is identified by its type and position (rounded to a
-- metre), so every player sees the same one. Refill state lives in memory:
-- after a server restart, emptied containers can be filled again.

local Rules = WLL.Rules
local M
local modelType = {}   -- model hash -> container type
local state = {}       -- stash name -> { filledAt }
local searching = {}   -- source -> { name, type, startedAt, coords, label }

local function inv() return exports.wasteland_inventory end
local function now() return GetGameTimer() end

local function notice(src, message) TriggerClientEvent('wasteland:loot:client:notice', src, message) end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function stashOpts(c, coords, open)
    return { label = c.label, width = c.grid[1], height = c.grid[2], maxWeight = 200, coords = coords, open = open }
end

local function isEmpty(id)
    local snap = inv():GetInventory(id)
    return not snap or #snap.items == 0
end

-------------------------------------------------------------------------------
-- Searching
-------------------------------------------------------------------------------

-- Thread only (loading a stash may read the database).
local function begin(src, name, typeName, coords)
    local busy = searching[src]
    -- A search that was never finished or cancelled (lost message) expires.
    if busy and now() - busy.startedAt < (M.config.containers[busy.type].searchSeconds + 10) * 1000 then return end
    searching[src] = nil
    local c = M.config.containers[typeName]
    local id, err = inv():EnsureStash(name, stashOpts(c, coords))
    if not id then notice(src, 'That cannot be searched right now.'); M.log:warn('stash %s: %s', name, tostring(err)); return end
    if isEmpty(id) and not Rules.needsFill(state[name], true, now(), c.refillMinutes) then
        local left = Rules.minutesLeft(state[name], now(), c.refillMinutes)
        notice(src, typeName == 'body' and 'Already searched. Nothing left.'
            or string.format('Already searched. Nothing left (check back in about %d min).', left))
        return
    end
    searching[src] = { name = name, type = typeName, startedAt = now(), coords = coords, id = id }
    TriggerClientEvent('wasteland:loot:client:search', src, { seconds = c.searchSeconds, label = 'Searching ' .. c.label:lower(), anim = c.anim })
end

local function finish(src)
    local s = searching[src]
    searching[src] = nil
    if not s then return end
    local c = M.config.containers[s.type]
    if now() - s.startedAt < c.searchSeconds * 1000 - 300 then
        M.log:warn('player %d finished searching %s too early', src, s.name)
        return
    end
    local p = playerCoords(src)
    if not p or dist(p, s.coords) > M.config.reach + 1.0 then notice(src, 'You moved away.'); return end
    if not inv():GetInventory(s.id) then notice(src, 'That is gone.'); return end
    local empty = isEmpty(s.id)
    if Rules.needsFill(state[s.name], empty, now(), c.refillMinutes) then
        state[s.name] = { filledAt = now() }
        for _, item in ipairs(Rules.roll(M.config.tables[c.table], math.random, math.random)) do
            local ok, err = inv():AddItem(s.id, item.name, item.count)
            if not ok then M.log:warn('loot %s: %s x %d: %s', s.name, item.name, item.count, tostring(err)) end
        end
        empty = isEmpty(s.id)
    end
    if empty then notice(src, 'You found nothing.'); return end
    inv():OpenStash(src, s.name, stashOpts(c, s.coords, true))
    TriggerEvent('wasteland:loot:searched', src, s.type, s.name)
end

-------------------------------------------------------------------------------
-- Zombie bodies
-------------------------------------------------------------------------------

AddEventHandler('wasteland:zombies:removed', function(uid)
    if not (M and M.active) or not uid then return end
    local name = Rules.bodyKey(uid)
    state[name] = nil
    if GetResourceState('wasteland_inventory') == 'started' then inv():DeleteStash(name) end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then searching[src] = nil end
end)

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local CONTAINER = { type = 'table', fields = {
    label = { type = 'string', required = true, minLength = 1, maxLength = 40 },
    table = { type = 'string', required = true },
    searchSeconds = { type = 'number', default = 4, min = 0.5, max = 60 },
    refillMinutes = { type = 'number', default = 45, min = 1, max = 100000 },
    grid = { type = 'array', default = { 4, 4 }, minItems = 2, maxItems = 2, items = { type = 'integer', min = 1, max = 12 } },
    anim = { type = 'enum', values = { 'bin', 'search', 'kneel' }, default = 'search' },
    models = { type = 'array', default = {}, items = { type = 'string', pattern = '^[%w_]+$' } },
} }
local TABLE = { type = 'table', fields = {
    emptyChance = { type = 'number', default = 0.5, min = 0, max = 1 },
    rolls = { type = 'array', default = { 1, 1 }, minItems = 2, maxItems = 2, items = { type = 'integer', min = 0, max = 20 } },
    items = { type = 'array', default = {}, items = { type = 'table', fields = {
        name = { type = 'string', required = true, pattern = '^[%w_]+$' },
        min = { type = 'integer', default = 1, min = 1, max = 1000000 },
        max = { type = 'integer', default = 1, min = 1, max = 1000000 },
        weight = { type = 'integer', default = 1, min = 1, max = 100000 },
    } } },
} }

-- What the client needs: container types with models, labels and animations.
local function clientConfig()
    local out = {}
    for name, c in pairs(M.config.containers) do
        out[name] = { label = c.label, models = c.models, anim = c.anim, searchSeconds = c.searchSeconds }
    end
    return { containers = out, reach = M.config.reach }
end

M = Wasteland.DefineModule({
    name = 'loot',
    version = '0.1.0',
    description = 'Searchable world props and zombie bodies: shared containers, loot tables, refills',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', inventory = '^0.1.0' },
    optionalDependencies = { zombies = '^0.1.0' },
    config = {
        file = 'loot.lua',
        optional = true,
        schema = { type = 'table', fields = {
            reach = { type = 'number', default = 3.0, min = 1, max = 10, description = 'How close (m) a player must be to search' },
            containers = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%a][%w_]*$' }, values = CONTAINER },
            tables = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%a][%w_]*$' }, values = TABLE },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        for name, c in pairs(M.config.containers) do
            local t = M.config.tables[c.table]
            if not t then return false, string.format('loot.lua: container "%s" uses table "%s", which does not exist', name, c.table) end
        end
        for name, t in pairs(M.config.tables) do
            if t.rolls[1] > t.rolls[2] then return false, string.format('loot.lua: table "%s" has rolls min above max', name) end
            for _, it in ipairs(t.items) do
                if it.min > it.max then return false, string.format('loot.lua: table "%s" item "%s" has min above max', name, it.name) end
                if not inv():GetItemDefinition(it.name) then
                    return false, string.format('loot.lua: table "%s" names item "%s", which is not in inventory.lua items', name, it.name)
                end
            end
        end
        modelType = Rules.modelIndex(M.config.containers, GetHashKey)
        state, searching = {}, {}
        TriggerClientEvent('wasteland:loot:client:config', -1, clientConfig())
        return true
    end,
    onShutdown = function()
        for src in pairs(searching) do TriggerClientEvent('wasteland:loot:client:cancel', src) end
        searching = {}
    end,
})

local COORDS = { type = 'table', required = true, fields = {
    x = { type = 'number', required = true }, y = { type = 'number', required = true }, z = { type = 'number', required = true },
} }
local RATE = { burst = 4, perSecond = 1 }

M.netEvent('wasteland:loot:server:config', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    TriggerClientEvent('wasteland:loot:client:config', src, clientConfig())
end)

-- Search a world prop: its model and where it stands (the server checks
-- that the model is a container and that the player is next to it).
M.netEvent('wasteland:loot:server:start', { args = { { type = 'integer', required = true }, COORDS }, rateLimit = RATE },
    function(src, model, coords)
        local typeName = modelType[model] or modelType[model & 0xffffffff] or modelType[model - 4294967296]
        if not typeName then
            M.log:warn('player %d tried to search model %d, which is not a container', src, model)
            return
        end
        local p = playerCoords(src)
        if not p or dist(p, coords) > M.config.reach then notice(src, 'You are too far away.'); return end
        Citizen.CreateThread(function() begin(src, Rules.key(typeName, coords), typeName, coords) end)
    end)

-- Search a dead zombie.
M.netEvent('wasteland:loot:server:body', { args = { { type = 'integer', required = true, min = 1 } }, rateLimit = RATE },
    function(src, netId)
        if GetResourceState('wasteland_zombies') ~= 'started' or not M.config.containers.body then return end
        local ok, z = pcall(function() return exports.wasteland_zombies:GetZombieInfo(netId) end)
        if not ok or not z or not z.dead then return end
        local p = playerCoords(src)
        if not p or dist(p, z.coords) > M.config.reach then notice(src, 'You are too far away.'); return end
        Citizen.CreateThread(function() begin(src, Rules.bodyKey(z.uid), 'body', z.coords) end)
    end)

M.netEvent('wasteland:loot:server:finish', { rateLimit = RATE }, function(src) finish(src) end)

M.netEvent('wasteland:loot:server:cancel', { rateLimit = RATE }, function(src) searching[src] = nil end)

-------------------------------------------------------------------------------
-- Exports (loot api 0.1)
-------------------------------------------------------------------------------

--- RollTable(name) -> list of { name, count } | nil   (other modules: rewards, quests)
exports('RollTable', function(name)
    local t = M and M.config.tables[name]
    if not t then return nil end
    return Rules.roll(t, math.random, math.random)
end)
