-- wasteland_quests :: server/main.lua
-- Module "quests": jobs from camp traders. A character takes up to
-- `maxActive` quests; kills, searches, crafts and visits count while a quest
-- is active (events from zombies, loot, crafting; positions checked here);
-- items are counted live and taken at hand-in. Hand-in happens at a camp
-- that offers the quest: rewards first (refused when they do not fit), then
-- the items. Each quest can be done again after its cooldown.
-- State per character: character data `quests = { active, done }`.

local Rules = WLQ.Rules
local M
local states = {}      -- characterId -> { active = { [id] = { progress } }, done = { [id] = unix } }
local online = {}      -- characterId -> source
local lastSent = {}    -- source -> tracker json (skip identical updates)
local runToken = nil
local DATA_KEY = 'quests'

local function inv() return exports.wasteland_inventory end
local function players() return exports.wasteland_players end
local function nowUnix() return os.time() end

local function characterOf(src)
    local ok, cid = pcall(function() return players():GetCharacterId(src) end)
    return ok and cid or nil
end

local function stateOf(src)
    local cid = characterOf(src)
    return cid and states[cid], cid
end

local function save(cid)
    if states[cid] then players():SetCharacterData(cid, DATA_KEY, states[cid]) end
end

local function countFor(src) return function(item) return inv():GetItemCount(src, item) or 0 end end

local function itemLabel(name)
    local d = name and inv():GetItemDefinition(name)
    return d and d.label or name
end

local function objectiveLabel(o)
    if o.type == 'bring' then return itemLabel(o.item) end
    if o.type == 'craft' and GetResourceState('wasteland_crafting') == 'started' then
        return itemLabel(o.recipe)
    end
    return nil
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

-------------------------------------------------------------------------------
-- What the player sees
-------------------------------------------------------------------------------

local function objectivesOf(src, id, quest, progress)
    local out = {}
    for i, o in ipairs(quest.objectives) do
        local have, n = Rules.objective(quest, progress, i, countFor(src))
        out[i] = { text = Rules.text(o, have, n, objectiveLabel(o)), done = have >= n,
            coords = (o.type == 'visit' and o.coords) or o.near or nil }
    end
    return out
end

-- The tracker: active quests and their objectives.
local function sendTracker(src)
    local s = stateOf(src)
    if not s then return end
    local list = {}
    local ids = {}
    for id in pairs(s.active) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local q = M.config.quests[id]
        if q then
            list[#list + 1] = { id = id, label = q.label, objectives = objectivesOf(src, id, q, s.active[id].progress),
                ready = Rules.complete(q, s.active[id].progress, countFor(src)) }
        end
    end
    local key = json.encode(list)
    if lastSent[src] == key then return end
    lastSent[src] = key
    TriggerClientEvent('wasteland:quests:client:tracker', src, list)
end

local function offers(quest, campId)
    if not quest.camps then return true end
    for _, c in ipairs(quest.camps) do if c == campId then return true end end
    return false
end

local function campOf(src, campId)
    if GetResourceState('wasteland_camps') ~= 'started' then return nil end
    local ok, list = pcall(function() return exports.wasteland_camps:GetCamps() end)
    if not ok then return nil end
    local p = playerCoords(src)
    for _, c in ipairs(list or {}) do
        if c.id == campId and p then
            for _, t in ipairs(c.traders) do
                if Rules.dist(p, t.coords) <= M.config.giverDistance then return c end
            end
        end
    end
    return nil
end

local function boardData(src, camp)
    local s = stateOf(src)
    local out = {}
    local ids = {}
    for id, q in pairs(M.config.quests) do if offers(q, camp.id) or (s.active[id]) then ids[#ids + 1] = id end end
    table.sort(ids, function(a, b) return M.config.quests[a].label < M.config.quests[b].label end)
    for _, id in ipairs(ids) do
        local q = M.config.quests[id]
        local status, minutes = Rules.status(id, q, s, nowUnix(), countFor(src))
        local rewards = {}
        if q.rewards.cash and q.rewards.cash > 0 then rewards[#rewards + 1] = '$' .. q.rewards.cash end
        for _, it in ipairs(q.rewards.items) do rewards[#rewards + 1] = it.count .. ' x ' .. itemLabel(it.name) end
        local progress = s.active[id] and s.active[id].progress or Rules.fresh(q)
        out[#out + 1] = { id = id, label = q.label, description = q.description, status = status, minutes = minutes,
            handInHere = offers(q, camp.id), objectives = objectivesOf(src, id, q, progress), rewards = rewards }
    end
    local active = 0
    for _ in pairs(s.active) do active = active + 1 end
    return { camp = camp.id, place = camp.label, quests = out, active = active, maxActive = M.config.maxActive }
end

local function sendBoard(src, camp, message, ok)
    local d = boardData(src, camp)
    d.message, d.ok = message, ok
    TriggerClientEvent('wasteland:quests:client:board', src, d)
end

-------------------------------------------------------------------------------
-- Accept, abandon, hand in
-------------------------------------------------------------------------------

local function accept(src, campId, id)
    local camp = campOf(src, campId)
    local s, cid = stateOf(src)
    local q = M.config.quests[id]
    if not camp or not s or not q or not offers(q, campId) then return end
    local status, minutes = Rules.status(id, q, s, nowUnix(), countFor(src))
    if status ~= 'available' then
        sendBoard(src, camp, status == 'cooldown' and string.format('Come back in %d min.', minutes) or 'You already have this job.', false)
        return
    end
    local active = 0
    for _ in pairs(s.active) do active = active + 1 end
    if active >= M.config.maxActive then sendBoard(src, camp, string.format('You can only have %d jobs at once.', M.config.maxActive), false); return end
    s.active[id] = { progress = Rules.fresh(q), startedAt = nowUnix() }
    save(cid)
    M.log:info('player %d (character %d) accepted quest %s', src, cid, id)
    sendBoard(src, camp, 'Accepted: ' .. q.label .. '.', true)
    sendTracker(src)
end

local function abandon(src, campId, id)
    local camp = campOf(src, campId)
    local s, cid = stateOf(src)
    if not camp or not s or not s.active[id] then return end
    s.active[id] = nil
    save(cid)
    sendBoard(src, camp, 'Job dropped.', true)
    sendTracker(src)
end

local function handIn(src, campId, id)
    local camp = campOf(src, campId)
    local s, cid = stateOf(src)
    local q = M.config.quests[id]
    if not camp or not s or not q or not s.active[id] or not offers(q, campId) then return end
    if not Rules.complete(q, s.active[id].progress, countFor(src)) then sendBoard(src, camp, 'Not done yet.', false); return end
    -- 1. rewards (all or nothing)
    local given = {}
    for _, it in ipairs(q.rewards.items) do
        local ok = inv():AddItem(src, it.name, it.count)
        if not ok then
            for _, g in ipairs(given) do inv():RemoveItem(src, g.name, g.count) end
            sendBoard(src, camp, 'Make room in your inventory for the reward first.', false)
            return
        end
        given[#given + 1] = it
    end
    -- 2. the items asked for
    local taken = {}
    for _, o in ipairs(q.objectives) do
        if o.type == 'bring' then
            local ok = inv():RemoveItem(src, o.item, o.count)
            if not ok then
                for _, t in ipairs(taken) do inv():AddItem(src, t.item, t.count) end
                for _, g in ipairs(given) do inv():RemoveItem(src, g.name, g.count) end
                sendBoard(src, camp, 'Some of the items are gone.', false)
                return
            end
            taken[#taken + 1] = o
        end
    end
    if q.rewards.cash and q.rewards.cash > 0 then inv():AddCash(src, q.rewards.cash) end
    s.active[id] = nil
    s.done[id] = nowUnix()
    save(cid)
    M.log:info('player %d (character %d) completed quest %s', src, cid, id)
    TriggerEvent('wasteland:quests:completed', src, id)
    sendBoard(src, camp, 'Job done: ' .. q.label .. '. Thanks.', true)
    sendTracker(src)
end

-------------------------------------------------------------------------------
-- Progress from the world
-------------------------------------------------------------------------------

local function progress(src, ev)
    local s, cid = stateOf(src)
    if not s then return end
    local changed = false
    for id, a in pairs(s.active) do
        local q = M.config.quests[id]
        if q and Rules.apply(q, a.progress, ev) then changed = true end
    end
    if changed then
        save(cid)
        sendTracker(src)
    end
end

AddEventHandler('wasteland:zombies:died', function(_, _, _, killer, coords)
    if M and M.active and killer and killer > 0 then progress(killer, { type = 'kill', coords = coords }) end
end)

AddEventHandler('wasteland:loot:searched', function(src, containerType)
    if M and M.active then progress(src, { type = 'search', container = containerType, coords = playerCoords(src) }) end
end)

AddEventHandler('wasteland:crafting:crafted', function(src, recipe)
    if M and M.active then progress(src, { type = 'craft', recipe = recipe, count = 1 }) end
end)

-- Items changed: the "bring" lines of the tracker.
AddEventHandler('wasteland:inventory:playerUpdated', function(src)
    if M and M.active then sendTracker(src) end
end)

local function load(src, cid)
    local data = players():GetCharacterData(cid, DATA_KEY)
    if type(data) ~= 'table' then data = {} end
    data.active = type(data.active) == 'table' and data.active or {}
    data.done = type(data.done) == 'table' and data.done or {}
    -- Quests removed from the config are dropped.
    for id in pairs(data.active) do if not M.config.quests[id] then data.active[id] = nil end end
    states[cid], online[cid] = data, src
    lastSent[src] = nil
    sendTracker(src)
end

AddEventHandler('wasteland:players:characterLoaded', function(src, character)
    if M and M.active and type(character) == 'table' then load(src, character.id) end
end)

AddEventHandler('wasteland:players:characterUnloading', function(src, character)
    if type(character) ~= 'table' then return end
    save(character.id)
    states[character.id], online[character.id] = nil, nil
    if src then lastSent[src] = nil end
end)

-- Visits: the server checks where every player with a visit objective is.
local function loop(token)
    while runToken == token do
        Citizen.Wait(2000)
        if runToken ~= token then return end
        for cid, src in pairs(online) do
            local s = states[cid]
            local wants = false
            for id in pairs(s.active) do
                local q = M.config.quests[id]
                for _, o in ipairs(q and q.objectives or {}) do if o.type == 'visit' then wants = true end end
            end
            if wants then progress(src, { type = 'visit', coords = playerCoords(src) }) end
        end
    end
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local XYZ = { type = 'table', nullable = true, fields = { x = { type = 'number', required = true }, y = { type = 'number', required = true },
    z = { type = 'number', required = true }, radius = { type = 'number', default = 50, min = 1, max = 5000 } } }

M = Wasteland.DefineModule({
    name = 'quests',
    version = '0.1.0',
    description = 'Jobs from camp traders: bring, kill, visit, search, craft; repeatable with cooldowns',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', inventory = '^0.1.0' },
    optionalDependencies = { camps = '^0.1.0', zombies = '^0.1.0', loot = '^0.1.0', crafting = '^0.1.0' },
    config = {
        file = 'quests.lua',
        optional = true,
        schema = { type = 'table', fields = {
            maxActive = { type = 'integer', default = 3, min = 1, max = 20 },
            giverDistance = { type = 'number', default = 4.0, min = 1, max = 20 },
            quests = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%a][%w_]*$' }, values = { type = 'table', fields = {
                label = { type = 'string', required = true, minLength = 1, maxLength = 48 },
                description = { type = 'string', default = '', maxLength = 300 },
                camps = { type = 'array', items = { type = 'string', pattern = '^[%a][%w_]*$' } },
                cooldownMinutes = { type = 'number', default = 60, min = 0, max = 100000 },
                objectives = { type = 'array', required = true, minItems = 1, items = { type = 'table', fields = {
                    type = { type = 'enum', required = true, values = { 'bring', 'kill', 'visit', 'search', 'craft' } },
                    item = { type = 'string', pattern = '^[%w_]+$' },
                    recipe = { type = 'string', pattern = '^[%w_]+$' },
                    container = { type = 'string', pattern = '^[%w_]+$' },
                    count = { type = 'integer', default = 1, min = 1, max = 100000 },
                    coords = XYZ, near = XYZ,
                    radius = { type = 'number', default = 40, min = 1, max = 5000 },
                    label = { type = 'string', maxLength = 48 },
                } } },
                rewards = { type = 'table', fields = {
                    cash = { type = 'integer', default = 0, min = 0, max = 10000000 },
                    items = { type = 'array', default = {}, items = { type = 'table', fields = {
                        name = { type = 'string', required = true, pattern = '^[%w_]+$' },
                        count = { type = 'integer', default = 1, min = 1, max = 100000 },
                    } } },
                } },
            } } },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        for id, q in pairs(M.config.quests) do
            for i, o in ipairs(q.objectives) do
                local where = string.format('quests.lua: quest "%s" objective %d', id, i)
                if o.type == 'bring' and (not o.item or not inv():GetItemDefinition(o.item)) then return false, where .. ': bring needs a known item' end
                if o.type == 'visit' and not o.coords then return false, where .. ': visit needs coords' end
                if o.type == 'craft' and not o.recipe then return false, where .. ': craft needs a recipe' end
            end
            for _, it in ipairs(q.rewards.items) do
                if not inv():GetItemDefinition(it.name) then return false, string.format('quests.lua: quest "%s" rewards unknown item "%s"', id, it.name) end
            end
        end
        states, online, lastSent = {}, {}, {}
        for _, c in ipairs(players():GetOnlineCharacters()) do
            if c.source then load(c.source, c.id) end
        end
        local token = {}
        runToken = token
        Citizen.CreateThread(function() loop(token) end)
        return true
    end,
    onShutdown = function()
        runToken = nil
        for cid in pairs(states) do save(cid) end
        states, online = {}, {}
    end,
})

local CAMP = { type = 'string', required = true, pattern = '^[%a][%w_]*$', maxLength = 48 }
local QUEST = { type = 'string', required = true, pattern = '^[%a][%w_]*$', maxLength = 48 }
local RATE = { burst = 6, perSecond = 2 }

M.netEvent('wasteland:quests:server:board', { args = { CAMP }, rateLimit = RATE }, function(src, campId)
    local camp = campOf(src, campId)
    if camp and stateOf(src) then sendBoard(src, camp) end
end)
M.netEvent('wasteland:quests:server:accept', { args = { CAMP, QUEST }, rateLimit = RATE }, accept)
M.netEvent('wasteland:quests:server:abandon', { args = { CAMP, QUEST }, rateLimit = RATE }, abandon)
M.netEvent('wasteland:quests:server:handIn', { args = { CAMP, QUEST }, rateLimit = RATE }, handIn)
-- Where the quest givers stand (the camps' traders), for the "Jobs" targets.
M.netEvent('wasteland:quests:server:givers', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    if GetResourceState('wasteland_camps') ~= 'started' then return end
    local ok, list = pcall(function() return exports.wasteland_camps:GetCamps() end)
    if not ok then return end
    local out = {}
    for _, c in ipairs(list or {}) do
        local spots = {}
        for i, t in ipairs(c.traders) do spots[i] = t.coords end
        out[#out + 1] = { id = c.id, label = c.label, traders = spots }
    end
    TriggerClientEvent('wasteland:quests:client:givers', src, out)
end)

M.netEvent('wasteland:quests:server:tracker', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    lastSent[src] = nil
    sendTracker(src)
end)

-------------------------------------------------------------------------------
-- Exports (quests api 0.1)
-------------------------------------------------------------------------------

--- GetActiveQuests(source) -> list of quest ids
exports('GetActiveQuests', function(src)
    local s = stateOf(tonumber(src))
    local out = {}
    for id in pairs(s and s.active or {}) do out[#out + 1] = id end
    table.sort(out)
    return out
end)

--- AddProgress(source, event) -> ok   (other modules: custom kill/visit/search/craft events)
exports('AddProgress', function(src, ev)
    if type(ev) ~= 'table' or type(ev.type) ~= 'string' then return false end
    progress(tonumber(src), ev)
    return true
end)

--- GetQuestSummary(source) -> { active = { { id, label, ready, objectives = { text } } },
---   cooldowns = { { id, label, minutes } } }   (admin panel)
exports('GetQuestSummary', function(src)
    src = tonumber(src)
    local s = stateOf(src)
    if not s then return nil end
    local out = { active = {}, cooldowns = {} }
    for id, a in pairs(s.active) do
        local q = M.config.quests[id]
        if q then
            local lines = {}
            for _, o in ipairs(objectivesOf(src, id, q, a.progress)) do lines[#lines + 1] = o.text end
            out.active[#out.active + 1] = { id = id, label = q.label, ready = Rules.complete(q, a.progress, countFor(src)), objectives = lines }
        end
    end
    for id in pairs(s.done) do
        local q = M.config.quests[id]
        local status, minutes = q and Rules.status(id, q, s, nowUnix(), countFor(src))
        if status == 'cooldown' then out.cooldowns[#out.cooldowns + 1] = { id = id, label = q.label, minutes = minutes } end
    end
    table.sort(out.active, function(a, b) return a.label < b.label end)
    table.sort(out.cooldowns, function(a, b) return a.label < b.label end)
    return out
end)

--- DropQuest(source, id) -> ok   (admin)
exports('DropQuest', function(src, id)
    local s, cid = stateOf(tonumber(src))
    if not s or not s.active[id] then return false end
    s.active[id] = nil
    save(cid)
    sendTracker(tonumber(src))
    return true
end)

--- ResetCooldowns(source) -> number reset   (admin)
exports('ResetCooldowns', function(src)
    local s, cid = stateOf(tonumber(src))
    if not s then return 0 end
    local n = 0
    for id in pairs(s.done) do s.done[id] = nil; n = n + 1 end
    save(cid)
    return n
end)
