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
local searches = 0     -- finished searches since start (admin live view)
local extra = {}       -- signed model hash -> container type (added by admins, kept in KVP)
local EXTRA_KVP = 'extraModels'
local extraNames = {}  -- signed model hash -> prop name the admin gave (optional)
local custom = {}      -- loot categories made in the admin panel: name -> definition (KVP)
local CUSTOM_KVP = 'customTypes'

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

-- Big props (wrecks) are searched from further from their middle.
local function reachFor(typeName)
    local c = M.config.containers[typeName]
    return (c and c.reach) or M.config.reach
end

local function stashOpts(c, coords, open, label)
    return { label = label or c.label, width = c.grid[1], height = c.grid[2], maxWeight = 200, coords = coords, open = open, reach = c.reach }
end

local function isEmpty(id)
    local snap = inv():GetInventory(id)
    return not snap or #snap.items == 0
end

-------------------------------------------------------------------------------
-- Searching
-------------------------------------------------------------------------------

-- Thread only (loading a stash may read the database).
local function begin(src, name, typeName, coords, label)
    local busy = searching[src]
    -- A search that was never finished or cancelled (lost message) expires.
    if busy and now() - busy.startedAt < (M.config.containers[busy.type].searchSeconds + 10) * 1000 then return end
    searching[src] = nil
    local c = M.config.containers[typeName]
    local id, err = inv():EnsureStash(name, stashOpts(c, coords, nil, label))
    if not id then notice(src, 'That cannot be searched right now.'); M.log:warn('stash %s: %s', name, tostring(err)); return end
    if isEmpty(id) and not Rules.needsFill(state[name], true, now(), c.refillMinutes) then
        local left = Rules.minutesLeft(state[name], now(), c.refillMinutes)
        notice(src, typeName == 'body' and 'Already searched. Nothing left.'
            or string.format('Already searched. Nothing left (check back in about %d min).', left))
        return
    end
    searching[src] = { name = name, type = typeName, startedAt = now(), coords = coords, id = id, label = label }
    TriggerClientEvent('wasteland:loot:client:search', src, { seconds = c.searchSeconds,
        label = 'Searching ' .. (label or c.label:lower()), anim = c.anim })
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
    if not p or dist(p, s.coords) > reachFor(s.type) + 1.0 then notice(src, 'You moved away.'); return end
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
    searches = searches + 1
    inv():OpenStash(src, s.name, stashOpts(c, s.coords, true, s.label))
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
    reach = { type = 'number', min = 1, max = 20,
        description = 'How close (m) to the middle of the prop a player must be (big props like car wrecks); default: reach' },
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

-------------------------------------------------------------------------------
-- Props added in the admin panel: model hash -> container type. Kept in this
-- resource's KVP (survives restarts), on top of the models in loot.lua.
-------------------------------------------------------------------------------

-- GTA model hashes are signed 32-bit numbers (as GetEntityModel returns them).
local function signed(h)
    h = math.tointeger(h)
    if not h then return nil end
    h = h & 0xffffffff
    if h >= 0x80000000 then h = h - 0x100000000 end
    return h
end

local function loadExtra()
    extra, extraNames = {}, {}
    local ok, raw = pcall(GetResourceKvpString, EXTRA_KVP)
    if not ok or type(raw) ~= 'string' then return end
    local okJ, list = pcall(json.decode, raw)
    if not okJ or type(list) ~= 'table' then return end
    for _, e in ipairs(list) do
        local h = signed(e.hash)
        if h and M.config.containers[e.type] and e.type ~= 'body' then
            extra[h] = e.type
            if type(e.name) == 'string' and e.name ~= '' then extraNames[h] = e.name end
        elseif h then M.log:warn('admin-added loot prop %s: container type "%s" no longer exists (ignored)', tostring(h), tostring(e.type)) end
    end
end

local function saveExtra()
    local list = {}
    for h, t in pairs(extra) do list[#list + 1] = { hash = h, type = t, name = extraNames[h] } end
    table.sort(list, function(a, b) return a.hash < b.hash end)
    SetResourceKvp(EXTRA_KVP, json.encode(list))
end

-------------------------------------------------------------------------------
-- Loot categories made in the admin panel: a container type with its own
-- loot table ("custom_<name>"), kept in KVP and added to the config at start.
-------------------------------------------------------------------------------

local function num(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    return math.max(lo, math.min(hi, v))
end

--- A clean definition or nil, error.
local function cleanCustom(name, d)
    if type(name) ~= 'string' or not name:match('^[a-z][a-z0-9_]*$') or #name > 32 then
        return nil, 'the id must be lower case letters, digits and _ (start with a letter, up to 32)'
    end
    if name == 'body' or (M.config.containers[name] and not M.config.containers[name].custom) then
        return nil, '"' .. name .. '" is already a loot type in loot.lua'
    end
    if type(d) ~= 'table' then return nil, 'no definition' end
    local label = type(d.label) == 'string' and d.label:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if label == '' or #label > 40 then return nil, 'give it a name (up to 40 characters)' end
    local out = {
        label = label,
        searchSeconds = num(d.searchSeconds, 0.5, 60, 4),
        refillMinutes = num(d.refillMinutes, 1, 100000, 45),
        grid = { math.floor(num(d.gridW, 1, 12, 5)), math.floor(num(d.gridH, 1, 12, 4)) },
        emptyChance = num(d.emptyChance, 0, 1, 0.5),
        rolls = { math.floor(num(d.rollsMin, 0, 20, 1)), math.floor(num(d.rollsMax, 0, 20, 2)) },
        items = {},
    }
    if out.rolls[1] > out.rolls[2] then return nil, 'the least items found is more than the most' end
    if type(d.items) ~= 'table' or #d.items == 0 then return nil, 'add at least one item' end
    if #d.items > 40 then return nil, 'up to 40 items' end
    for _, it in ipairs(d.items) do
        if type(it) ~= 'table' or type(it.name) ~= 'string' or not inv():GetItemDefinition(it.name) then
            return nil, 'unknown item "' .. tostring(type(it) == 'table' and it.name) .. '"'
        end
        local mn, mx = math.floor(num(it.min, 1, 1000000, 1)), math.floor(num(it.max, 1, 1000000, 1))
        if mn > mx then return nil, it.name .. ': the least is more than the most' end
        out.items[#out.items + 1] = { name = it.name, min = mn, max = mx, weight = math.floor(num(it.weight, 1, 100000, 1)) }
    end
    return out
end

local function applyCustom(name, d)
    M.config.tables['custom_' .. name] = { emptyChance = d.emptyChance, rolls = d.rolls, items = d.items }
    M.config.containers[name] = { label = d.label, table = 'custom_' .. name, searchSeconds = d.searchSeconds,
        refillMinutes = d.refillMinutes, grid = d.grid, anim = 'search', models = {}, custom = true }
end

local function loadCustom()
    custom = {}
    local ok, raw = pcall(GetResourceKvpString, CUSTOM_KVP)
    if not ok or type(raw) ~= 'string' then return end
    local okJ, list = pcall(json.decode, raw)
    if not okJ or type(list) ~= 'table' then return end
    for name, d in pairs(list) do
        local clean, err = cleanCustom(name, {
            label = d.label, searchSeconds = d.searchSeconds, refillMinutes = d.refillMinutes,
            gridW = d.grid and d.grid[1], gridH = d.grid and d.grid[2], emptyChance = d.emptyChance,
            rollsMin = d.rolls and d.rolls[1], rollsMax = d.rolls and d.rolls[2], items = d.items })
        if clean then custom[name] = clean; applyCustom(name, clean)
        else M.log:warn('loot category "%s" made in the admin panel is skipped: %s', tostring(name), tostring(err)) end
    end
end

local function saveCustom()
    local out = {}
    for name, d in pairs(custom) do out[name] = d end
    SetResourceKvp(CUSTOM_KVP, json.encode(out))
end

-- Model lists per container type: loot.lua names plus admin-added hashes.
local function modelsOf(name, c)
    local out = {}
    for _, m in ipairs(c.models or {}) do out[#out + 1] = m end
    for h, t in pairs(extra) do if t == name then out[#out + 1] = h end end
    return out
end

local function rebuildIndex()
    modelType = Rules.modelIndex(M.config.containers, function(m) return signed(GetHashKey(m)) end)
    for h, t in pairs(extra) do modelType[h] = t end
end

-- What the client needs: container types with models, labels and animations.
local function clientConfig()
    local out = {}
    for name, c in pairs(M.config.containers) do
        out[name] = { label = c.label, models = modelsOf(name, c), anim = c.anim, searchSeconds = c.searchSeconds }
    end
    local names = {}
    for h, n in pairs(extraNames) do names[tostring(h)] = n end
    return { containers = out, reach = M.config.reach, names = names }
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
        loadCustom()
        loadExtra()
        rebuildIndex()
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
        local typeName = modelType[signed(model)]
        if not typeName then
            M.log:warn('player %d tried to search model %d, which is not a container', src, model)
            return
        end
        local p = playerCoords(src)
        if not p or dist(p, coords) > reachFor(typeName) then notice(src, 'You are too far away.'); return end
        -- A prop an admin named shows that name (target, search bar, container).
        local label = extraNames[signed(model)]
        Citizen.CreateThread(function() begin(src, Rules.key(typeName, coords), typeName, coords, label) end)
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

--- GetLootStats() -> { containers (filled since start), searches (since start) }
exports('GetLootStats', function()
    local n = 0
    for _ in pairs(state) do n = n + 1 end
    return { containers = n, searches = searches }
end)

--- GetContainerModels() -> { [typeName] = { label, models } }   (admin overlay; models: names and hashes)
exports('GetContainerModels', function()
    local out = {}
    for name, c in pairs(M and M.config.containers or {}) do out[name] = { label = c.label, models = modelsOf(name, c) } end
    return out
end)

--- GetLootAdminData() -> { containers = { { name, label, table, custom } }, known = { [signedHash] = { type, added, name } },
---   custom = { [name] = definition } }   (admin panel)
exports('GetLootAdminData', function()
    if not (M and M.active) then return nil end
    local list, known = {}, {}
    for name, c in pairs(M.config.containers) do
        if name ~= 'body' then list[#list + 1] = { name = name, label = c.label, table = c.custom and 'own' or c.table, custom = c.custom == true } end
        for _, m in ipairs(c.models or {}) do known[tostring(signed(GetHashKey(m)))] = { type = name, added = false, name = m } end
    end
    for h, t in pairs(extra) do known[tostring(h)] = { type = t, added = true, name = extraNames[h] } end
    table.sort(list, function(a, b) return a.label < b.label end)
    return { containers = list, known = known, custom = custom }
end)

--- SaveLootCategory(name, def) -> ok, err   (admin: create or change an own loot category)
--- def: { label, searchSeconds, refillMinutes, gridW, gridH, emptyChance (0-1), rollsMin, rollsMax,
---        items = { { name, min, max, weight } } }
exports('SaveLootCategory', function(name, d)
    if not (M and M.active) then return false, 'loot module is not running' end
    local clean, err = cleanCustom(name, d)
    if not clean then return false, err end
    custom[name] = clean
    applyCustom(name, clean)
    saveCustom()
    rebuildIndex()
    TriggerClientEvent('wasteland:loot:client:config', -1, clientConfig())
    M.log:info('loot category "%s" saved (%d items)', name, #clean.items)
    return true
end)

--- DeleteLootCategory(name) -> ok, err   (its props stop being searchable)
exports('DeleteLootCategory', function(name)
    if not (M and M.active) then return false, 'loot module is not running' end
    if not custom[name] then return false, 'that is not a loot category made in the admin panel' end
    custom[name] = nil
    M.config.containers[name] = nil
    M.config.tables['custom_' .. name] = nil
    for h, t in pairs(extra) do if t == name then extra[h] = nil; extraNames[h] = nil end end
    saveCustom()
    saveExtra()
    rebuildIndex()
    TriggerClientEvent('wasteland:loot:client:config', -1, clientConfig())
    M.log:info('loot category "%s" deleted', name)
    return true
end)

--- AddContainerModel(modelHash, containerType, name?) -> ok, err   (admin: make a prop searchable)
exports('AddContainerModel', function(model, typeName, propName)
    if not (M and M.active) then return false, 'loot module is not running' end
    local h = signed(model)
    if not h then return false, 'bad model' end
    if typeName == 'body' or not M.config.containers[typeName] then return false, 'unknown loot container type' end
    local current = modelType[h]
    if current and not extra[h] then return false, 'that prop is already a ' .. M.config.containers[current].label:lower() .. ' (loot.lua)' end
    extra[h] = typeName
    propName = type(propName) == 'string' and propName:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if propName:match("^[%w _%-%.'%(%)]+$") and #propName <= 40 then extraNames[h] = propName else extraNames[h] = nil end
    saveExtra()
    rebuildIndex()
    TriggerClientEvent('wasteland:loot:client:config', -1, clientConfig())
    M.log:info('model %d added as loot container "%s"', h, typeName)
    return true
end)

--- RemoveContainerModel(modelHash) -> ok, err   (only props added with AddContainerModel)
exports('RemoveContainerModel', function(model)
    if not (M and M.active) then return false, 'loot module is not running' end
    local h = signed(model)
    if not h or not extra[h] then return false, 'that prop was not added in the admin panel' end
    extra[h] = nil
    extraNames[h] = nil
    saveExtra()
    rebuildIndex()
    TriggerClientEvent('wasteland:loot:client:config', -1, clientConfig())
    M.log:info('model %d is no longer a loot container', h)
    return true
end)

--- RollTable(name) -> list of { name, count } | nil   (other modules: rewards, quests)
exports('RollTable', function(name)
    local t = M and M.config.tables[name]
    if not t then return nil end
    return Rules.roll(t, math.random, math.random)
end)
