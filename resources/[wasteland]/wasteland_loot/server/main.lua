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

local function isAdmin(src)
    if GetResourceState('wasteland_admin') == 'started' then
        local ok, yes = pcall(function() return exports.wasteland_admin:IsAdmin(src) end)
        if ok then return yes == true end
    end
    local allowed = IsPlayerAceAllowed(tostring(src), 'wasteland.admin')
    return allowed == true or allowed == 1
end

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

-- Skill bonus (wasteland_skills; 0 when it is not running).
local function skillBonus(src, skill, key)
    if GetResourceState('wasteland_skills') ~= 'started' then return 0 end
    local ok, v = pcall(function() return exports.wasteland_skills:GetBonus(src, skill, key) end)
    return ok and tonumber(v) or 0
end

-- Containers with `tools` (trees: an axe) need one of them in the inventory.
local function hasTool(src, c)
    if not c.tools or #c.tools == 0 then return true end
    for _, name in ipairs(c.tools) do
        if (tonumber(inv():GetItemCount(src, name)) or 0) > 0 then return true end
    end
    return false
end

local function toolNames(c)
    local names = {}
    for _, name in ipairs(c.tools or {}) do
        local def = inv():GetItemDefinition(name)
        names[#names + 1] = 'a ' .. (def and def.label or name):lower()
    end
    return table.concat(names, ' or ')
end

-- Thread only (loading a stash may read the database).
local function begin(src, name, typeName, coords, label)
    local busy = searching[src]
    -- A search that was never finished or cancelled (lost message) expires.
    if busy and now() - busy.startedAt < ((busy.seconds or 0) + 10) * 1000 then return end
    searching[src] = nil
    local c = M.config.containers[typeName]
    local id, err = inv():EnsureStash(name, stashOpts(c, coords, nil, label))
    if not id then notice(src, 'That cannot be searched right now.'); M.log:warn('stash %s: %s', name, tostring(err)); return end
    if isEmpty(id) and not Rules.needsFill(state[name], true, now(), c.refillMinutes) then
        local left = Rules.minutesLeft(state[name], now(), c.refillMinutes)
        notice(src, typeName == 'body' and 'Already searched. Nothing left.'
            or c.direct and string.format('Nothing left here right now (check back in about %d min).', left)
            or string.format('Already searched. Nothing left (check back in about %d min).', left))
        return
    end
    if not hasTool(src, c) then notice(src, 'You need ' .. toolNames(c) .. ' for that.'); return end
    local seconds = c.searchSeconds * (1 - skillBonus(src, 'scavenging', 'searchTime'))
    searching[src] = { name = name, type = typeName, startedAt = now(), coords = coords, id = id, label = label, seconds = seconds }
    TriggerClientEvent('wasteland:loot:client:search', src, { seconds = seconds,
        label = (c.verb or 'Searching') .. ' ' .. (label or c.label:lower()), anim = c.anim })
end

-- direct: what is found goes straight into the player's inventory (what
-- does not fit stays in the container, which opens).
local function giveDirect(src, s, c)
    local got, left = {}, false
    for _, item in ipairs(Rules.roll(M.config.tables[c.table], math.random, math.random)) do
        local ok = inv():AddItem(src, item.name, item.count)
        if ok then
            local def = inv():GetItemDefinition(item.name)
            got[#got + 1] = string.format('%d x %s', item.count, def and def.label or item.name)
        else
            local okStash, err = inv():AddItem(s.id, item.name, item.count)
            if okStash then left = true
            else M.log:warn('loot %s: %s x %d: %s', s.name, item.name, item.count, tostring(err)) end
        end
    end
    if #got > 0 then notice(src, 'You got ' .. table.concat(got, ', ') .. '.') end
    if left then
        notice(src, 'Your pockets are full: the rest is left here.')
        inv():OpenStash(src, s.name, stashOpts(c, s.coords, true, s.label))
    elseif #got == 0 then
        notice(src, 'You got nothing.')
    end
    TriggerEvent('wasteland:loot:searched', src, s.type, s.name, #got > 0 or left)
end

local finishZoneTree -- tree zones (below)

local function finish(src)
    local s = searching[src]
    searching[src] = nil
    if not s then return end
    if s.zoneTree then return finishZoneTree(src, s) end
    local c = M.config.containers[s.type]
    if now() - s.startedAt < (s.seconds or c.searchSeconds) * 1000 - 300 then
        M.log:warn('player %d finished searching %s too early', src, s.name)
        return
    end
    local p = playerCoords(src)
    if not p or dist(p, s.coords) > reachFor(s.type) + 1.0 then notice(src, 'You moved away.'); return end
    if not inv():GetInventory(s.id) then notice(src, 'That is gone.'); return end
    if not hasTool(src, c) then notice(src, 'You need ' .. toolNames(c) .. ' for that.'); return end
    local empty = isEmpty(s.id)
    if c.direct and empty and Rules.needsFill(state[s.name], true, now(), c.refillMinutes) then
        state[s.name] = { filledAt = now() }
        searches = searches + 1
        giveDirect(src, s, c)
        return
    end
    if Rules.needsFill(state[s.name], empty, now(), c.refillMinutes) then
        state[s.name] = { filledAt = now() }
        local rolls = 1
        if math.random() < skillBonus(src, 'scavenging', 'extraLoot') then rolls = 2 end -- a good scavenger finds more
        for _ = 1, rolls do
            for _, item in ipairs(Rules.roll(M.config.tables[c.table], math.random, math.random)) do
                local ok, err = inv():AddItem(s.id, item.name, item.count)
                if not ok then M.log:warn('loot %s: %s x %d: %s', s.name, item.name, item.count, tostring(err)) end
            end
        end
        empty = isEmpty(s.id)
    end
    if empty then
        notice(src, 'You found nothing.')
        TriggerEvent('wasteland:loot:searched', src, s.type, s.name, false) -- still a search (guide, skills)
        return
    end
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
    anim = { type = 'enum', values = { 'bin', 'search', 'kneel', 'chop', 'hammer' }, default = 'search' },
    action = { type = 'string', maxLength = 24, description = 'What the option says (default "Search")' },
    verb = { type = 'string', maxLength = 24, description = 'The progress bar (default "Searching")' },
    tools = { type = 'array', items = { type = 'string', pattern = '^[%w_]+$' },
        description = 'Items of which the player needs one (e.g. an axe for trees)' },
    direct = { type = 'boolean', default = false, description = 'What is found goes straight into the inventory' },
    models = { type = 'array', default = {}, items = { type = 'string', pattern = '^[%w_]+$' } },
    reach = { type = 'number', min = 1, max = 20,
        description = 'How close (m) to the middle of the prop a player must be (big props like car wrecks); default: reach' },
} }
local TREEZONE = { type = 'table', fields = {
    label = { type = 'string', default = 'Tree zone', maxLength = 40 },
    coords = { type = 'vector3', required = true },
    radius = { type = 'number', default = 75, min = 10, max = 200 },
    trees = { type = 'integer', default = 0, min = 0, max = 200, description = '0 = one per 2 m of radius' },
} }
local function zonesSchema(d) return { type = 'table', fields = {
    enabled = { type = 'boolean', default = true },
    respawnMinutes = { type = 'number', default = 60, min = 1, max = 100000 },
    chopSeconds = { type = 'number', default = d.seconds, min = 1, max = 120 },
    chopDistance = { type = 'number', default = d.distance, min = 1.5, max = 8 },
    spacing = { type = 'number', default = d.spacing, min = 2, max = 50, description = 'Least metres between two' },
    table = { type = 'string', default = d.table, pattern = '^[%a][%w_]*$' },
    tools = { type = 'array', default = d.tools, items = { type = 'string', pattern = '^[%w_]+$' } },
    models = { type = 'array', default = d.models, minItems = 1, items = { type = 'string', pattern = '^[%w_]+$' } },
    stump = { type = 'string', default = d.stump, pattern = '^[%w_]*$', description = 'Left once used ("" = nothing)' },
    marker = { type = 'boolean', default = true, description = 'A marker over usable ones close by' },
    blips = { type = 'boolean', default = true, description = 'Zones on the map' },
    zones = { type = 'array', default = d.zones, items = TREEZONE },
} } end
local TREEZONES = zonesSchema({ seconds = 6, distance = 3.5, spacing = 6, table = 'tree',
    tools = { 'weapon_hatchet', 'weapon_battleaxe' }, stump = 'prop_tree_stump_01',
    models = { 'prop_tree_pine_01', 'prop_tree_pine_02', 'prop_tree_cedar_s_04', 'prop_tree_cedar_s_06' },
    zones = {
        { label = 'Sandy Shores woods', coords = { x = 1385.98, y = 3406.79, z = 45.90 }, radius = 75 },
        { label = 'Route 68 woods', coords = { x = 21.16, y = 3514.90, z = 56.19 }, radius = 75 },
        { label = 'Harmony hills', coords = { x = 38.12, y = 2576.34, z = 80.51 }, radius = 75 },
        { label = 'Tongva hills', coords = { x = -2445.60, y = 1518.15, z = 266.31 }, radius = 75 },
        { label = 'Paleto Forest', coords = { x = -552.8, y = 5348.6, z = 74.7 }, radius = 100 },
        { label = 'Raton Canyon woods', coords = { x = -1520.0, y = 4600.0, z = 40.0 }, radius = 80 },
        { label = 'Mount Chiliad trail', coords = { x = -770.0, y = 5560.0, z = 33.0 }, radius = 70 },
    } })
local ROCKZONES = zonesSchema({ seconds = 7, distance = 4.5, spacing = 9, table = 'rock', tools = { 'pickaxe' }, stump = '',
    models = { 'prop_rock_4_big', 'prop_rock_4_big2', 'prop_rock_4_c', 'prop_rock_1_a' },
    zones = {
        { label = 'Davis Quartz quarry', coords = { x = 2954.0, y = 2788.0, z = 41.5 }, radius = 100 },
        { label = 'Grand Senora desert rocks', coords = { x = 2340.0, y = 3120.0, z = 48.0 }, radius = 80 },
        { label = 'Mount Chiliad summit', coords = { x = 500.0, y = 5590.0, z = 795.0 }, radius = 70 },
        { label = 'Mount Gordo cliffs', coords = { x = 2850.0, y = 5950.0, z = 350.0 }, radius = 70 },
    } })

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

-------------------------------------------------------------------------------
-- Resource zones: areas where the server places things to gather. Two
-- kinds: tree zones (loot.lua treeZones: chop trees with an axe) and rock
-- zones (rockZones: mine big rocks with a pickaxe), plus zones admins place
-- with /treezone and /rockzone. Every client spawns the same nodes
-- (positions are seeded from the zone); a used node becomes a stump (or
-- disappears) for everyone and comes back after respawnMinutes. Used state
-- is kept in memory: a server restart brings every node back.
-------------------------------------------------------------------------------

local KINDS = {
    tree = { cfg = 'treeZones', kvp = 'treeZones', prefix = 'z', admin = 'a', command = 'treezone', label = 'Tree',
        option = 'Chop tree', progress = 'Chopping tree', anim = 'axe', zoneName = 'Tree zone', blip = 'Lumber',
        gone = 'This tree has already been chopped down.', busy = 'Someone is already chopping this tree.' },
    rock = { cfg = 'rockZones', kvp = 'rockZones', prefix = 'rz', admin = 'ra', command = 'rockzone', label = 'Rock',
        option = 'Mine rock', progress = 'Mining rock', anim = 'pickaxe', zoneName = 'Rock zone', blip = 'Mining',
        gone = 'This rock has already been mined out.', busy = 'Someone is already mining this rock.' },
}
local KIND_ORDER = { 'tree', 'rock' }

local trees = {}       -- node id -> { id, kind, zone, x, y, z, m, downAt, by }   (trees and rocks)
local treeList = {}    -- ordered node ids (what clients get)
local adminZones = { tree = {}, rock = {} } -- placed in game: { id, label, coords = {x,y,z}, radius, trees }
local zoneList = {}    -- every zone: { id, kind, label, coords, radius, admin }

local function kcfg(kind) return M.config[KINDS[kind].cfg] end

-- The container-like definition giveDirect / stashOpts / hasTool use.
local function nodeContainer(kind)
    local c = kcfg(kind)
    return { label = KINDS[kind].label, table = c.table, grid = { 4, 3 }, reach = 6, tools = c.tools }
end

local function stashName(id) return 'loot_tz_' .. id:gsub('[^%w]', '') end

local function loadAdminZones()
    for _, kind in ipairs(KIND_ORDER) do
        local list = {}
        adminZones[kind] = list
        local ok, raw = pcall(GetResourceKvpString, KINDS[kind].kvp)
        local okJ, saved = false, nil
        if ok and type(raw) == 'string' then okJ, saved = pcall(json.decode, raw) end
        for _, z in ipairs(okJ and type(saved) == 'table' and saved or {}) do
            if type(z) == 'table' and type(z.id) == 'string' and type(z.coords) == 'table' and tonumber(z.coords.x) and tonumber(z.radius) then
                list[#list + 1] = { id = z.id, label = tostring(z.label or KINDS[kind].zoneName),
                    coords = { x = tonumber(z.coords.x), y = tonumber(z.coords.y), z = tonumber(z.coords.z) or 0.0 },
                    radius = num(z.radius, 10, 200, 75), trees = math.floor(num(z.trees, 0, 200, 0)) }
            end
        end
    end
end

local function saveAdminZones(kind) SetResourceKvp(KINDS[kind].kvp, json.encode(adminZones[kind])) end

local function zoneTreeData()
    local out, zones, kinds = {}, {}, {}
    for _, id in ipairs(treeList) do
        local t = trees[id]
        out[#out + 1] = { id = id, kind = t.kind, x = t.x, y = t.y, z = t.z, m = t.m, down = t.downAt ~= nil }
    end
    for _, z in ipairs(zoneList) do
        zones[#zones + 1] = { kind = z.kind, label = z.label, x = z.coords.x, y = z.coords.y, z = z.coords.z, radius = z.radius }
    end
    local any = false
    for _, kind in ipairs(KIND_ORDER) do
        local c = kcfg(kind)
        any = any or c.enabled
        kinds[kind] = { enabled = c.enabled, models = c.models, stump = c.stump, marker = c.marker, blips = c.blips,
            distance = c.chopDistance, option = KINDS[kind].option, blip = KINDS[kind].blip }
    end
    return { enabled = any, trees = out, zones = zones, kinds = kinds }
end

local function sendTrees(target) TriggerClientEvent('wasteland:loot:client:trees', target or -1, zoneTreeData()) end

-- (Re)builds every zone's nodes. Nodes that keep their id keep their state.
local function buildTrees()
    local old = trees
    trees, treeList, zoneList = {}, {}, {}
    for _, kind in ipairs(KIND_ORDER) do
        local c, k = kcfg(kind), KINDS[kind]
        if c.enabled then
            for i, z in ipairs(c.zones) do
                zoneList[#zoneList + 1] = { id = k.prefix .. i, kind = kind, label = z.label,
                    coords = { x = z.coords.x, y = z.coords.y, z = z.coords.z }, radius = z.radius, trees = z.trees }
            end
            for _, z in ipairs(adminZones[kind]) do
                zoneList[#zoneList + 1] = { id = z.id, kind = kind, label = z.label, coords = z.coords, radius = z.radius,
                    trees = z.trees, admin = true }
            end
        end
    end
    for _, z in ipairs(zoneList) do
        local c = kcfg(z.kind)
        for n, p in ipairs(Rules.zoneTrees(z, c.spacing, #c.models)) do
            local id = z.id .. '_' .. n
            local prev = old[id]
            trees[id] = { id = id, kind = z.kind, zone = z.id, x = p.x, y = p.y, z = z.coords.z, m = p.m, downAt = prev and prev.downAt }
            treeList[#treeList + 1] = id
        end
    end
end

local function setDown(t, down)
    t.downAt = down and now() or nil
    t.by = nil
    TriggerClientEvent('wasteland:loot:client:treestate', -1, t.id, t.downAt ~= nil)
end

local function chopping(t)
    local s = t.by and searching[t.by]
    return s and s.zoneTree == t.id
end

-- Thread only (the overflow stash may read the database).
local function beginZoneTree(src, id, groundZ)
    local t = trees[id]
    if not t then return end
    local busy = searching[src]
    if busy and now() - busy.startedAt < ((busy.seconds or 0) + 10) * 1000 then return end
    searching[src] = nil
    local c, k = kcfg(t.kind), KINDS[t.kind]
    local p = playerCoords(src)
    if not p or (p.x - t.x) ^ 2 + (p.y - t.y) ^ 2 > (c.chopDistance + 1.5) ^ 2 or math.abs(p.z - groundZ) > 6 then
        notice(src, 'You are too far away.'); return
    end
    if t.downAt then notice(src, k.gone); return end
    if chopping(t) then notice(src, k.busy); return end
    local nc = nodeContainer(t.kind)
    if not hasTool(src, nc) then notice(src, 'You need ' .. toolNames(nc) .. ' for that.'); return end
    local coords = { x = t.x, y = t.y, z = groundZ }
    local name = stashName(id)
    local stash, err = inv():EnsureStash(name, stashOpts(nc, coords, nil, k.label))
    if not stash then notice(src, 'That cannot be done right now.'); M.log:warn('stash %s: %s', name, tostring(err)); return end
    local seconds = c.chopSeconds * (1 - skillBonus(src, 'scavenging', 'searchTime'))
    searching[src] = { name = name, type = t.kind, startedAt = now(), coords = coords, id = stash, seconds = seconds, zoneTree = id }
    t.by = src
    TriggerClientEvent('wasteland:loot:client:search', src, { seconds = seconds, label = k.progress, anim = k.anim,
        face = { x = t.x, y = t.y, z = groundZ } })
end

finishZoneTree = function(src, s)
    local t = trees[s.zoneTree]
    if t and t.by == src then t.by = nil end
    if not t then return end
    if now() - s.startedAt < s.seconds * 1000 - 300 then
        M.log:warn('player %d finished %s too early', src, t.id)
        return
    end
    local c, k = kcfg(t.kind), KINDS[t.kind]
    local p = playerCoords(src)
    if not p or (p.x - t.x) ^ 2 + (p.y - t.y) ^ 2 > (c.chopDistance + 2.5) ^ 2 then notice(src, 'You moved away.'); return end
    if t.downAt then notice(src, k.gone); return end
    local nc = nodeContainer(t.kind)
    if not hasTool(src, nc) then notice(src, 'You need ' .. toolNames(nc) .. ' for that.'); return end
    setDown(t, true)
    searches = searches + 1
    giveDirect(src, s, nc)
end

local respawnToken = nil
local function respawnLoop(token)
    while respawnToken == token do
        Citizen.Wait(15000)
        if respawnToken ~= token then return end
        for _, id in ipairs(treeList) do
            local t = trees[id]
            if t and t.downAt and now() - t.downAt >= kcfg(t.kind).respawnMinutes * 60000 then
                setDown(t, false)
                inv():DeleteStash(stashName(id))
            end
        end
    end
end

-- /treezone | /rockzone  add <radius 50-100> [count] [name] | remove | list   (admins)
local function zoneCommand(kind, source, args)
    local src = tonumber(source) or 0
    if not (M and M.active) then return end
    if src ~= 0 and not isAdmin(src) then return end
    local k = KINDS[kind]
    local function say(msg) if src == 0 then print('[' .. k.command .. '] ' .. msg) else notice(src, msg) end end
    local list = adminZones[kind]
    local noun = kind == 'tree' and 'trees' or 'rocks'
    local sub = args[1]
    if not kcfg(kind).enabled then say(k.zoneName .. 's are turned off in loot.lua.'); return end
    if sub == 'add' and src ~= 0 then
        local radius = math.floor(num(args[2], 50, 100, 75))
        local count = math.floor(num(args[3], 0, 200, 0))
        local label = table.concat(args, ' ', 4)
        if label == '' then label = k.zoneName end
        local n = 1
        for _, z in ipairs(list) do n = math.max(n, (tonumber(z.id:match('^' .. k.admin .. '(%d+)$')) or 0) + 1) end
        list[#list + 1] = { id = k.admin .. n, label = label:sub(1, 40), coords = playerCoords(src), radius = radius, trees = count }
        saveAdminZones(kind)
        buildTrees()
        sendTrees()
        say(string.format('%s "%s" placed here: %d m, %d %s.', k.zoneName, label, radius,
            Rules.zoneTreeCount({ radius = radius, trees = count }), noun))
    elseif sub == 'remove' and src ~= 0 then
        local p = playerCoords(src)
        local best, bestD = nil, math.huge
        for i, z in ipairs(list) do
            local d = (z.coords.x - p.x) ^ 2 + (z.coords.y - p.y) ^ 2
            if d < bestD and d <= (z.radius + 50) ^ 2 then best, bestD = i, d end
        end
        if not best then say('No ' .. k.zoneName:lower() .. ' placed with /' .. k.command .. ' near you (zones in loot.lua are removed there).'); return end
        local z = table.remove(list, best)
        saveAdminZones(kind)
        buildTrees()
        sendTrees()
        say(k.zoneName .. ' "' .. z.label .. '" removed.')
    else
        local any = false
        for _, z in ipairs(zoneList) do
            if z.kind == kind then
                any = true
                local up, n = 0, 0
                for _, id in ipairs(treeList) do
                    if trees[id].zone == z.id then n = n + 1; if not trees[id].downAt then up = up + 1 end end
                end
                say(string.format('%s%s: %.0f, %.0f, %d m, %d/%d %s standing', z.label, z.admin and ' (placed)' or '',
                    z.coords.x, z.coords.y, z.radius, up, n, noun))
            end
        end
        if not any then say('No ' .. k.zoneName:lower() .. 's.') end
        say('/' .. k.command .. ' add <radius 50-100> [' .. noun .. '] [name] | /' .. k.command .. ' remove')
    end
end

local commandRegistered = false

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
        out[name] = { label = c.label, models = modelsOf(name, c), anim = c.anim, searchSeconds = c.searchSeconds, action = c.action }
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
            treeZones = TREEZONES,
            rockZones = ROCKZONES,
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        for name, c in pairs(M.config.containers) do
            local t = M.config.tables[c.table]
            if not t then return false, string.format('loot.lua: container "%s" uses table "%s", which does not exist', name, c.table) end
            for _, tool in ipairs(c.tools or {}) do
                if not inv():GetItemDefinition(tool) then
                    return false, string.format('loot.lua: container "%s" needs tool "%s", which is not in inventory.lua items', name, tool)
                end
            end
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
        -- A broken tree / rock zone setting only turns those zones off.
        for _, key in ipairs({ 'treeZones', 'rockZones' }) do
            local c = M.config[key]
            if c.enabled and not M.config.tables[c.table] then
                M.log:warn('loot.lua: %s uses table "%s", which does not exist: those zones are off', key, c.table)
                c.enabled = false
            end
            for _, tool in ipairs(c.enabled and c.tools or {}) do
                if not inv():GetItemDefinition(tool) then
                    M.log:warn('loot.lua: %s needs tool "%s", which is not in inventory.lua items: those zones are off', key, tool)
                    c.enabled = false
                end
            end
        end
        loadCustom()
        loadExtra()
        rebuildIndex()
        state, searching = {}, {}
        TriggerClientEvent('wasteland:loot:client:config', -1, clientConfig())
        loadAdminZones()
        buildTrees()
        sendTrees()
        local token = {}
        respawnToken = token
        Citizen.CreateThread(function() respawnLoop(token) end)
        if not commandRegistered then
            commandRegistered = true -- FiveM commands cannot be unregistered
            RegisterCommand('treezone', function(source, args) zoneCommand('tree', source, args) end, false)
            RegisterCommand('rockzone', function(source, args) zoneCommand('rock', source, args) end, false)
        end
        return true
    end,
    onShutdown = function()
        respawnToken = nil
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
    sendTrees(src)
end)

-- Chop a tree in a tree zone: its id and the ground height the client found.
M.netEvent('wasteland:loot:server:chopzone', { args = { { type = 'string', required = true, maxLength = 24 },
    { type = 'number', required = true } }, rateLimit = RATE },
    function(src, id, groundZ)
        if not trees[id] then return end
        Citizen.CreateThread(function() beginZoneTree(src, id, groundZ) end)
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
