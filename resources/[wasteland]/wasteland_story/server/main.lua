-- wasteland_story :: server/main.lua
-- Module "story": a quest chain with a story (story.lua). Every character
-- goes through the act once; the server owns the progress (character data
-- `story`) and checks everything: who you talk to, what you choose, what
-- you pick up, where you are. Kills and defending count for group members
-- close by on the same step.

local Rules = WLST.Rules
local M
local states = {}      -- characterId -> state (see shared/rules.lua)
local online = {}      -- characterId -> source
local defending = {}   -- step id -> { nextWave = ms }  (one wave timer per place)
local outSince = {}    -- characterId -> ms the player left a defend area
local runToken = nil
local DATA_KEY = 'story'
local REACH = 4.5

local function inv() return exports.wasteland_inventory end
local function players() return exports.wasteland_players end
local function now() return GetGameTimer() end
local function act() return M.config.act end
local function notice(src, msg) TriggerClientEvent('wasteland:story:client:notice', src, msg) end

local function characterOf(src)
    local ok, cid = pcall(function() return players():GetCharacterId(src) end)
    return ok and cid or nil
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

local function near(src, coords, r)
    local p = playerCoords(src)
    return p ~= nil and coords ~= nil and Rules.dist2d(p, coords) <= r and math.abs(p.z - coords.z) < 12
end

local function save(cid) if states[cid] then players():SetCharacterData(cid, DATA_KEY, states[cid]) end end

local function itemLabel(name)
    local d = inv():GetItemDefinition(name)
    return d and d.label or name
end

-------------------------------------------------------------------------------
-- What the player's game is told
-------------------------------------------------------------------------------

local function view(cid)
    local a, st = act(), states[cid]
    local step = Rules.current(a, st)
    local out = { title = a.title, subtitle = a.subtitle, done = step == nil, ending = st.ending and a.endings[st.ending] or nil,
        stepNo = #st.log + 1, steps = #a.steps, npcs = {} }
    for id, n in pairs(a.npcs) do
        if Rules.npcVisible(n, st) and not (id == 'tomas' and st.flags.ruthless) then
            out.npcs[#out.npcs + 1] = { id = id, name = n.name, model = n.model, coords = n.coords, scenario = n.scenario }
        end
    end
    if step then
        local s = { id = step.id, type = step.type, title = step.title, objective = step.objective, progress = st.progress }
        if step.type == 'talk' then
            local n = a.npcs[step.npc]
            s.coords, s.radius, s.where = n.coords, step.radius or 5, n.name
        elseif step.type == 'kill' then
            s.count = step.count
            if step.near then s.coords, s.radius, s.where = step.near, step.near.radius, step.placeLabel end
        else
            s.coords, s.radius = step.coords, step.radius or 5
            if step.type == 'defend' then s.seconds = step.seconds end
            if step.type == 'collect' or step.type == 'read' then s.prop, s.label = step.prop, step.label end
        end
        out.step = s
    end
    return out
end

local function send(cid)
    local src = online[cid]
    if src and states[cid] then TriggerClientEvent('wasteland:story:client:state', src, view(cid)) end
end

-- A step is done: log it, move on, tell the player.
local function complete(cid, gotoId)
    local st, a = states[cid], act()
    local step = Rules.current(a, st)
    if not step then return end
    Rules.advance(a, st, gotoId)
    outSince[cid] = nil
    save(cid)
    local src = online[cid]
    if src then
        local nextStep = Rules.current(a, st)
        TriggerClientEvent('wasteland:story:client:stepDone', src, { title = step.title, next = nextStep and nextStep.title or nil,
            ending = st.ending and a.endings[st.ending] or nil })
        TriggerEvent('wasteland:story:stepDone', src, a.id, step.id)
    end
    send(cid)
end

-------------------------------------------------------------------------------
-- Talking and choosing
-------------------------------------------------------------------------------

local function npcNear(src, npcId)
    local n = act().npcs[npcId]
    return n and near(src, n.coords, REACH)
end

local function dialogueFor(cid, step)
    local a, st = act(), states[cid]
    local lines = {}
    for _, l in ipairs(Rules.lines(step.dialogue, st.flags)) do
        local n = a.npcs[l.who]
        lines[#lines + 1] = { who = n and n.name or l.who, text = l.text }
    end
    local choices = {}
    for _, c in ipairs(Rules.choices(step, st.flags)) do
        local needs = {}
        for _, it in ipairs(c.bring or {}) do needs[#needs + 1] = string.format('%s x%d', itemLabel(it.name), it.count) end
        choices[#choices + 1] = { id = c.id, text = c.text, needs = #needs > 0 and table.concat(needs, ', ') or nil }
    end
    local n = a.npcs[step.npc]
    return { npc = n.name, role = n.role, lines = lines, choices = choices }
end

local function talk(src, npcId)
    local cid = characterOf(src)
    local st = cid and states[cid]
    if not st or not npcNear(src, npcId) then return end
    local a = act()
    local step = Rules.current(a, st)
    local n = a.npcs[npcId]
    if step and step.type == 'talk' and step.npc == npcId then
        TriggerClientEvent('wasteland:story:client:dialogue', src, dialogueFor(cid, step))
    else
        TriggerClientEvent('wasteland:story:client:dialogue', src, { npc = n.name, role = n.role,
            lines = { { who = n.name, text = (not step and st.ending and 'You did what you did. Live with it.') or n.idle or '...' } },
            choices = { { id = '_bye', text = 'Leave' } } })
    end
end

local function choose(src, choiceId)
    local cid = characterOf(src)
    local st = cid and states[cid]
    if not st then return end
    local a = act()
    local step = Rules.current(a, st)
    if not step or step.type ~= 'talk' or not npcNear(src, step.npc) then return end
    local c = Rules.choice(step, choiceId, st.flags)
    if not c then return end
    local reply = c.reply
    if c.stay then
        TriggerClientEvent('wasteland:story:client:reply', src, { text = reply, close = reply == nil })
        return
    end
    -- items to hand over
    for _, it in ipairs(c.bring or {}) do
        if (inv():GetItemCount(src, it.name) or 0) < it.count then
            TriggerClientEvent('wasteland:story:client:reply', src, { text = 'You need ' .. itemLabel(it.name) .. ' x' .. it.count .. '.', keep = true })
            return
        end
    end
    -- items given: all or nothing
    local given = {}
    for _, it in ipairs(c.give or {}) do
        if inv():AddItem(src, it.name, it.count) then given[#given + 1] = it
        else
            for _, g in ipairs(given) do inv():RemoveItem(src, g.name, g.count) end
            TriggerClientEvent('wasteland:story:client:reply', src, { text = 'Make room in your pockets first.', keep = true })
            return
        end
    end
    for _, it in ipairs(c.bring or {}) do inv():RemoveItem(src, it.name, it.count) end
    if c.cash and c.cash > 0 then inv():AddCash(src, c.cash) end
    for _, f in ipairs(c.flags or {}) do st.flags[f] = true end
    if c.ending then st.ending = c.ending end
    if c.effect == 'turn' and GetResourceState('wasteland_zombies') == 'started' then
        local n = a.npcs[step.npc]
        pcall(function() exports.wasteland_zombies:SpawnZombie({ x = n.coords.x, y = n.coords.y, z = n.coords.z }, 'walker') end)
    end
    M.log:info('character %s chose "%s" at story step %s', tostring(cid), c.id, step.id)
    TriggerClientEvent('wasteland:story:client:reply', src, { text = reply, close = reply == nil, done = true })
    complete(cid, c['goto'])
end

-------------------------------------------------------------------------------
-- Collecting, reading
-------------------------------------------------------------------------------

local function collect(src, stepId)
    local cid = characterOf(src)
    local st = cid and states[cid]
    local step = st and Rules.current(act(), st)
    if not step or step.id ~= stepId or step.type ~= 'collect' or not near(src, step.coords, REACH) then return end
    if not inv():AddItem(src, step.item, 1) then notice(src, 'Make room in your pockets first.'); return end
    if step.found then notice(src, step.found) end
    complete(cid)
end

local function read(src, stepId)
    local cid = characterOf(src)
    local st = cid and states[cid]
    local step = st and Rules.current(act(), st)
    if not step or step.id ~= stepId or step.type ~= 'read' or not near(src, step.coords, REACH) then return end
    TriggerClientEvent('wasteland:story:client:note', src, step.note)
    complete(cid)
end

-------------------------------------------------------------------------------
-- Kills (and group members close by on the same step)
-------------------------------------------------------------------------------

-- The characters who share an event at `coords` with `cid`: themselves and
-- group members online within groupRange on the same step.
local function sharers(cid, stepId, coords)
    local out = { cid }
    if GetResourceState('wasteland_groups') ~= 'started' then return out end
    for other, src in pairs(online) do
        local st = states[other]
        if other ~= cid and st and st.step == stepId then
            local ok, same = pcall(function() return exports.wasteland_groups:SameGroup(cid, other) end)
            local p = playerCoords(src)
            if ok and same and p and Rules.dist2d(p, coords) <= M.config.groupRange then out[#out + 1] = other end
        end
    end
    return out
end

AddEventHandler('wasteland:zombies:died', function(_, _, _, killer, coords)
    if not (M and M.active) or not killer or killer <= 0 then return end
    local cid = characterOf(killer)
    local st = cid and states[cid]
    local step = st and Rules.current(act(), st)
    if not step or step.type ~= 'kill' then return end
    local at = coords or playerCoords(killer)
    if step.near and (not at or Rules.dist2d(at, step.near) > step.near.radius) then return end
    for _, c in ipairs(sharers(cid, step.id, at or step.near)) do
        local s = states[c]
        s.progress = s.progress + 1
        if s.progress >= step.count then complete(c) else send(c) end
    end
end)

-------------------------------------------------------------------------------
-- Visits and defending (checked every second)
-------------------------------------------------------------------------------

local function isDead(src)
    if GetResourceState('wasteland_survival') ~= 'started' then return false end
    local ok, dead = pcall(function() return exports.wasteland_survival:IsDead(src) end)
    return ok and dead == true
end

local function wave(step)
    if GetResourceState('wasteland_zombies') ~= 'started' then return end
    for _ = 1, step.waveSize or 4 do
        local a, r = math.random() * math.pi * 2, math.random(22, 38)
        local at = { x = step.coords.x + math.cos(a) * r, y = step.coords.y + math.sin(a) * r, z = step.coords.z }
        pcall(function() exports.wasteland_zombies:SpawnZombie(at, math.random() < 0.2 and 'runner' or 'walker') end)
    end
end

local function tick()
    local a, t = act(), now()
    local active = {}
    for cid, src in pairs(online) do
        local st = states[cid]
        local step = st and Rules.current(a, st)
        if step and step.type == 'visit' and near(src, step.coords, step.radius or 30) then
            if step.arrive then notice(src, step.arrive) end
            complete(cid)
        elseif step and step.type == 'defend' then
            local inside = near(src, step.coords, step.radius or 30) and not isDead(src)
            local carries = not step.needs or (inv():GetItemCount(src, step.needs) or 0) > 0
            if inside and carries then
                outSince[cid] = nil
                if st.progress == 0 and step.start then notice(src, step.start) end
                active[step.id] = step
                st.progress = st.progress + 1
                if st.progress >= step.seconds then complete(cid) else send(cid) end
            elseif inside and not carries then
                if not outSince[cid] then notice(src, 'You need ' .. itemLabel(step.needs) .. ' to open it.'); outSince[cid] = t end
            elseif st.progress > 0 then
                outSince[cid] = outSince[cid] or t
                if t - outSince[cid] > 10000 then
                    st.progress, outSince[cid] = 0, nil
                    notice(src, 'You left. The reader reset; you have to start again.')
                    send(cid)
                end
            end
        end
    end
    for id, step in pairs(active) do
        local d = defending[id]
        if not d then d = { nextWave = t + 3000 }; defending[id] = d end
        if t >= d.nextWave then d.nextWave = t + (step.waveSeconds or 15) * 1000; wave(step) end
    end
    for id in pairs(defending) do if not active[id] then defending[id] = nil end end
end

local function loop(token)
    while runToken == token do
        Citizen.Wait(1000)
        if runToken ~= token then return end
        local ok, err = pcall(tick)
        if not ok then M.log:warn('story tick: %s', tostring(err)) end
    end
end

-------------------------------------------------------------------------------
-- Loading, saving
-------------------------------------------------------------------------------

local function load(src, cid)
    local data = players():GetCharacterData(cid, DATA_KEY)
    states[cid] = Rules.clean(act(), data)
    online[cid] = src
    if data == nil then
        save(cid)
        TriggerClientEvent('wasteland:story:client:intro', src, { title = act().title, subtitle = act().subtitle, text = act().intro })
    end
    send(cid)
end

AddEventHandler('wasteland:players:characterLoaded', function(src, character)
    if M and M.active and M.config.enabled and type(character) == 'table' then load(src, character.id) end
end)

AddEventHandler('wasteland:players:characterUnloading', function(_, character)
    if type(character) ~= 'table' then return end
    save(character.id)
    states[character.id], online[character.id], outSince[character.id] = nil, nil, nil
end)

-- Lazarus serum: clears infection.
local function useSerum(src)
    if GetResourceState('wasteland_survival') ~= 'started' then return false, 'Nothing happens.' end
    local ok = pcall(function() exports.wasteland_survival:AddInfection(src, -100) end)
    if not ok then return false, 'Nothing happens.' end
    notice(src, 'The serum burns going in. Then, for the first time in weeks, your head is clear. The infection is gone.')
    return 1
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

M = Wasteland.DefineModule({
    name = 'story',
    version = '0.1.0',
    description = 'Story quest chain: characters, dialogue with choices, steps, endings, a journal',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', inventory = '^0.1.0' },
    optionalDependencies = { zombies = '^0.1.0', groups = '^0.1.0', survival = '^0.1.0' },
    config = {
        file = 'story.lua',
        optional = true,
        schema = { type = 'table', fields = {
            enabled = { type = 'boolean', default = true },
            groupRange = { type = 'number', default = 120, min = 0, max = 5000 },
            act = { type = 'any', required = true },
        } },
    },
    onInit = function(mod)
        M = mod
        local errs = Rules.validate(M.config.act, function(name) return name and inv():GetItemDefinition(name) ~= nil end)
        if #errs > 0 then return false, 'story.lua: ' .. table.concat(errs, '; ') end
        if inv():GetItemDefinition('lazarus_serum') then inv():RegisterUsable('lazarus_serum', useSerum) end
        states, online, defending, outSince = {}, {}, {}, {}
        if M.config.enabled then
            for _, c in ipairs(players():GetOnlineCharacters()) do
                if c.source then load(c.source, c.id) end
            end
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

local ID = { type = 'string', required = true, pattern = '^[%a][%w_]*$', maxLength = 48 }
local RATE = { burst = 6, perSecond = 2 }

M.netEvent('wasteland:story:server:state', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    local cid = characterOf(src)
    if cid and states[cid] then send(cid) end
end)
M.netEvent('wasteland:story:server:talk', { args = { ID }, rateLimit = RATE }, talk)
M.netEvent('wasteland:story:server:choose', { args = { ID }, rateLimit = RATE }, choose)
M.netEvent('wasteland:story:server:collect', { args = { ID }, rateLimit = RATE }, collect)
M.netEvent('wasteland:story:server:read', { args = { ID }, rateLimit = RATE }, read)
M.netEvent('wasteland:story:server:journal', { rateLimit = RATE }, function(src)
    local cid = characterOf(src)
    local st = cid and states[cid]
    if not st then return end
    local a = act()
    local step = Rules.current(a, st)
    TriggerClientEvent('wasteland:story:client:journal', src, { title = a.title, subtitle = a.subtitle, intro = a.intro,
        entries = Rules.journal(a, st), current = step and { title = step.title, objective = step.objective } or nil,
        ending = st.ending and a.endings[st.ending] or nil })
end)

-- /story reset | skip [server id]   (admins: test the chain)
RegisterCommand('story', function(source, args)
    local src = tonumber(source) or 0
    if src ~= 0 then
        local allowed = IsPlayerAceAllowed(tostring(src), 'wasteland.admin')
        if not (allowed == true or allowed == 1) then return end
    end
    local target = tonumber(args[2]) or src
    local cid = target ~= 0 and characterOf(target)
    if not (M and M.active) or not cid or not states[cid] then return end
    if args[1] == 'reset' then
        states[cid] = Rules.newState(act()); save(cid); send(cid)
        notice(src ~= 0 and src or target, 'Story reset.')
    elseif args[1] == 'skip' then
        complete(cid)
    end
end, false)

--- GetStoryState(source) -> { step, flags, ending, done = number of steps done } | nil
exports('GetStoryState', function(src)
    local cid = characterOf(src)
    local st = cid and states[cid]
    if not st then return nil end
    local flags = {}
    for f in pairs(st.flags) do flags[#flags + 1] = f end
    return { step = st.step, flags = flags, ending = st.ending, done = #st.log }
end)
