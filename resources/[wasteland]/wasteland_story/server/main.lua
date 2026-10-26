-- wasteland_story :: server/main.lua
-- Module "story": quest chains with a story (story.lua). Acts are played in
-- order (Act II starts when Act I is done); the choices made (flags) carry
-- over. The server owns the progress (character data `story`) and checks
-- everything: who you talk to, what you choose, what you pick up, where you
-- are. Kills and defending count for group members close by on the same step.
--
-- NPCs and items: the client may move one to the nearest road edge when its
-- spot is inside a building or has no ground (see client); it reports where
-- it put it, and the server accepts spots within MOVED_MAX of the config.

local Rules = WLST.Rules
local M
local data = {}        -- characterId -> { acts = { [actId] = state }, intro = actId | nil }
local online = {}      -- characterId -> source
local defending = {}   -- step id -> { nextWave = ms }  (one wave timer per place)
local outSince = {}    -- characterId -> ms the player left a defend area
local runToken = nil
local DATA_KEY = 'story'
local REACH = 4.5
local MOVED_MAX = 80.0

local function inv() return exports.wasteland_inventory end
local function players() return exports.wasteland_players end
local function now() return GetGameTimer() end
local function acts() return M.config.acts end
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

-- Where the client put a story NPC / item (`at`), if believable; else the config spot.
local function placed(cfgCoords, at)
    if type(at) == 'table' and tonumber(at.x) and tonumber(at.y) and tonumber(at.z)
        and Rules.dist2d(at, cfgCoords) <= MOVED_MAX then
        return { x = at.x, y = at.y, z = at.z }
    end
    return cfgCoords
end

local function save(cid) if data[cid] then players():SetCharacterData(cid, DATA_KEY, { acts = data[cid].acts }) end end

local function itemLabel(name)
    local d = inv():GetItemDefinition(name)
    return d and d.label or name
end

--- The act a character is on, and its state. A new act gets a fresh state
--- (and an intro). Every act done: the last act (with step == nil).
local function cur(cid)
    local d = data[cid]
    if not d then return nil end
    local list = acts()
    for _, a in ipairs(list) do
        local st = d.acts[a.id]
        if not st then
            st = Rules.newState(a)
            d.acts[a.id], d.intro = st, a.id
            return a, st
        end
        if st.step then return a, st end
    end
    local a = list[#list]
    return a, d.acts[a.id]
end

-- Every flag from every act (later acts react to earlier choices).
local function flagsOf(cid)
    local out = {}
    for _, st in pairs(data[cid].acts) do for f in pairs(st.flags) do out[f] = true end end
    return out
end

local function actIndex(id)
    for i, a in ipairs(acts()) do if a.id == id then return i end end
    return 0
end

-------------------------------------------------------------------------------
-- What the player's game is told
-------------------------------------------------------------------------------

local function view(cid)
    local a, st = cur(cid)
    local step = Rules.current(a, st)
    local flags = flagsOf(cid)
    local out = { title = a.title, subtitle = a.subtitle, done = step == nil, ending = st.ending and a.endings[st.ending] or nil,
        stepNo = #st.log + 1, steps = #a.steps, actNo = actIndex(a.id), acts = #acts(), npcs = {} }
    for id, n in pairs(a.npcs) do
        if step and Rules.npcVisible(n, st) and not (id == 'tomas' and flags.ruthless) then
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
    if not (src and data[cid]) then return end
    local v = view(cid)
    TriggerClientEvent('wasteland:story:client:state', src, v)
    local d = data[cid]
    if d.intro then
        local a = acts()[actIndex(d.intro)]
        d.intro = nil
        if a then TriggerClientEvent('wasteland:story:client:intro', src, { title = a.title, subtitle = a.subtitle, text = a.intro }) end
    end
end

-- A step is done: log it, move on, tell the player. The last step of an
-- act shows the ending; the next act starts a little later.
local function complete(cid, gotoId)
    local a, st = cur(cid)
    local step = Rules.current(a, st)
    if not step then return end
    Rules.advance(a, st, gotoId)
    outSince[cid] = nil
    save(cid)
    local src = online[cid]
    local actDone = st.step == nil
    if src then
        local nextStep = Rules.current(a, st)
        TriggerClientEvent('wasteland:story:client:stepDone', src, { title = step.title, next = nextStep and nextStep.title or nil,
            ending = actDone and st.ending and a.endings[st.ending] or nil, actDone = actDone })
        TriggerEvent('wasteland:story:stepDone', src, a.id, step.id)
    end
    if actDone and actIndex(a.id) < #acts() then
        -- the next act after the ending card
        Citizen.SetTimeout(8000, function()
            if data[cid] then cur(cid); save(cid); send(cid) end
        end)
        if src then TriggerClientEvent('wasteland:story:client:state', src, view(cid)) end
        return
    end
    send(cid)
end

-------------------------------------------------------------------------------
-- Talking and choosing
-------------------------------------------------------------------------------

local lastTalk = {}   -- characterId -> { npc, at } (where the NPC was talked to)

local function dialogueFor(cid, a, step)
    local flags = flagsOf(cid)
    local lines = {}
    for _, l in ipairs(Rules.lines(step.dialogue, flags)) do
        local n = a.npcs[l.who]
        lines[#lines + 1] = { who = n and n.name or l.who, text = l.text }
    end
    local choices = {}
    for _, c in ipairs(Rules.choices(step, flags)) do
        local needs = {}
        for _, it in ipairs(c.bring or {}) do needs[#needs + 1] = string.format('%s x%d', itemLabel(it.name), it.count) end
        choices[#choices + 1] = { id = c.id, text = c.text, needs = #needs > 0 and table.concat(needs, ', ') or nil }
    end
    local n = a.npcs[step.npc]
    return { npc = n.name, role = n.role, lines = lines, choices = choices }
end

local function talk(src, npcId, at)
    local cid = characterOf(src)
    if not cid or not data[cid] then return end
    local a, st = cur(cid)
    local n = a.npcs[npcId]
    if not n then return end
    local where = placed(n.coords, at)
    if not near(src, where, REACH) then return end
    lastTalk[cid] = { npc = npcId, at = where }
    local step = Rules.current(a, st)
    if step and step.type == 'talk' and step.npc == npcId then
        TriggerClientEvent('wasteland:story:client:dialogue', src, dialogueFor(cid, a, step))
    else
        TriggerClientEvent('wasteland:story:client:dialogue', src, { npc = n.name, role = n.role,
            lines = { { who = n.name, text = n.idle or '...' } }, choices = { { id = '_bye', text = 'Leave' } } })
    end
end

local function choose(src, choiceId)
    local cid = characterOf(src)
    if not cid or not data[cid] then return end
    local a, st = cur(cid)
    local step = Rules.current(a, st)
    if not step or step.type ~= 'talk' then return end
    local lt = lastTalk[cid]
    if not lt or lt.npc ~= step.npc or not near(src, lt.at, REACH) then return end
    local c = Rules.choice(step, choiceId, flagsOf(cid))
    if not c then return end
    local reply = c.reply
    if c.stay then
        TriggerClientEvent('wasteland:story:client:reply', src, { text = reply, close = reply == nil })
        return
    end
    for _, it in ipairs(c.bring or {}) do
        if (inv():GetItemCount(src, it.name) or 0) < it.count then
            TriggerClientEvent('wasteland:story:client:reply', src, { text = 'You need ' .. itemLabel(it.name) .. ' x' .. it.count .. '.', keep = true })
            return
        end
    end
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
        pcall(function() exports.wasteland_zombies:SpawnZombie({ x = lt.at.x, y = lt.at.y, z = lt.at.z }, 'walker') end)
    end
    M.log:info('character %s chose "%s" at story step %s', tostring(cid), c.id, step.id)
    TriggerClientEvent('wasteland:story:client:reply', src, { text = reply, close = reply == nil, done = true })
    complete(cid, c['goto'])
end

-------------------------------------------------------------------------------
-- Collecting, reading
-------------------------------------------------------------------------------

local function stepHere(src, stepId, kind, at)
    local cid = characterOf(src)
    if not cid or not data[cid] then return nil end
    local a, st = cur(cid)
    local step = Rules.current(a, st)
    if not step or step.id ~= stepId or step.type ~= kind then return nil end
    if not near(src, placed(step.coords, at), REACH) then return nil end
    return cid, step
end

local function collect(src, stepId, at)
    local cid, step = stepHere(src, stepId, 'collect', at)
    if not cid then return end
    if not inv():AddItem(src, step.item, 1) then notice(src, 'Make room in your pockets first.'); return end
    if step.found then notice(src, step.found) end
    complete(cid)
end

local function read(src, stepId, at)
    local cid, step = stepHere(src, stepId, 'read', at)
    if not cid then return end
    TriggerClientEvent('wasteland:story:client:note', src, step.note)
    complete(cid)
end

-------------------------------------------------------------------------------
-- Kills (and group members close by on the same step)
-------------------------------------------------------------------------------

local function sharers(cid, stepId, coords)
    local out = { cid }
    if GetResourceState('wasteland_groups') ~= 'started' then return out end
    for other, src in pairs(online) do
        if other ~= cid and data[other] then
            local _, st = cur(other)
            if st and st.step == stepId then
                local ok, same = pcall(function() return exports.wasteland_groups:SameGroup(cid, other) end)
                local p = playerCoords(src)
                if ok and same and p and Rules.dist2d(p, coords) <= M.config.groupRange then out[#out + 1] = other end
            end
        end
    end
    return out
end

AddEventHandler('wasteland:zombies:died', function(_, _, _, killer, coords)
    if not (M and M.active) or not killer or killer <= 0 then return end
    local cid = characterOf(killer)
    if not cid or not data[cid] then return end
    local a, st = cur(cid)
    local step = Rules.current(a, st)
    if not step or step.type ~= 'kill' then return end
    local at = coords or playerCoords(killer)
    if step.near and (not at or Rules.dist2d(at, step.near) > step.near.radius) then return end
    for _, c in ipairs(sharers(cid, step.id, at or step.near)) do
        local _, s = cur(c)
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
    local t = now()
    local active = {}
    for cid, src in pairs(online) do
        local a, st = cur(cid)
        local step = a and Rules.current(a, st)
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
                    notice(src, 'You left. You have to start again.')
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
    local saved = players():GetCharacterData(cid, DATA_KEY)
    -- older saves held one act's state directly (Act I)
    if type(saved) == 'table' and saved.acts == nil and (saved.step ~= nil or saved.log ~= nil) then
        saved = { acts = { act1 = saved } }
    end
    local d = { acts = {} }
    for _, a in ipairs(acts()) do
        local st = type(saved) == 'table' and type(saved.acts) == 'table' and saved.acts[a.id]
        if st then d.acts[a.id] = Rules.clean(a, st) end
    end
    data[cid], online[cid] = d, src
    cur(cid)   -- the first act not done (a new one gets its intro)
    save(cid)
    send(cid)
end

AddEventHandler('wasteland:players:characterLoaded', function(src, character)
    if M and M.active and M.config.enabled and type(character) == 'table' then load(src, character.id) end
end)

AddEventHandler('wasteland:players:characterUnloading', function(_, character)
    if type(character) ~= 'table' then return end
    save(character.id)
    data[character.id], online[character.id], outSince[character.id], lastTalk[character.id] = nil, nil, nil, nil
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
    version = '0.2.0',
    description = 'Story quest chains: acts with characters, dialogue choices, steps, endings, a journal',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', inventory = '^0.1.0' },
    optionalDependencies = { zombies = '^0.1.0', groups = '^0.1.0', survival = '^0.1.0' },
    config = {
        file = 'story.lua',
        optional = true,
        schema = { type = 'table', fields = {
            enabled = { type = 'boolean', default = true },
            groupRange = { type = 'number', default = 120, min = 0, max = 5000 },
            acts = { type = 'any' },
            act = { type = 'any', description = 'One act (older story.lua); use acts' },
        } },
    },
    onInit = function(mod)
        M = mod
        if type(M.config.acts) ~= 'table' or #M.config.acts == 0 then
            M.config.acts = type(M.config.act) == 'table' and { M.config.act } or {}
        end
        if #M.config.acts == 0 then return false, 'story.lua: no acts' end
        local itemExists = function(name) return name and inv():GetItemDefinition(name) ~= nil end
        local ids, stepIds = {}, {}
        for i, a in ipairs(M.config.acts) do
            local errs = Rules.validate(a, itemExists)
            if type(a.id) ~= 'string' or ids[a.id] then errs[#errs + 1] = 'act ' .. i .. ' needs its own id' end
            ids[a.id or i] = true
            for _, s in ipairs(a.steps or {}) do
                if s.id and stepIds[s.id] then errs[#errs + 1] = 'step id "' .. s.id .. '" is used in two acts' end
                if s.id then stepIds[s.id] = true end
            end
            if #errs > 0 then return false, 'story.lua act ' .. tostring(a.id or i) .. ': ' .. table.concat(errs, '; ') end
        end
        if inv():GetItemDefinition('lazarus_serum') then inv():RegisterUsable('lazarus_serum', useSerum) end
        data, online, defending, outSince, lastTalk = {}, {}, {}, {}, {}
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
        for cid in pairs(data) do save(cid) end
        data, online = {}, {}
    end,
})

local ID = { type = 'string', required = true, pattern = '^[%a][%w_]*$', maxLength = 48 }
local AT = { type = 'table', fields = { x = { type = 'number' }, y = { type = 'number' }, z = { type = 'number' } } }
local RATE = { burst = 6, perSecond = 2 }

M.netEvent('wasteland:story:server:state', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    local cid = characterOf(src)
    if cid and data[cid] then send(cid) end
end)
M.netEvent('wasteland:story:server:talk', { args = { ID, AT }, rateLimit = RATE }, talk)
M.netEvent('wasteland:story:server:choose', { args = { ID }, rateLimit = RATE }, choose)
M.netEvent('wasteland:story:server:collect', { args = { ID, AT }, rateLimit = RATE }, collect)
M.netEvent('wasteland:story:server:read', { args = { ID, AT }, rateLimit = RATE }, read)
M.netEvent('wasteland:story:server:journal', { rateLimit = RATE }, function(src)
    local cid = characterOf(src)
    if not cid or not data[cid] then return end
    local entries, curAct, curStep, lastEnding = {}, cur(cid)
    curStep = curAct and Rules.current(curAct, select(2, cur(cid)))
    for _, a in ipairs(acts()) do
        local st = data[cid].acts[a.id]
        if st then
            entries[#entries + 1] = { header = a.subtitle or a.title }
            for _, e in ipairs(Rules.journal(a, st)) do entries[#entries + 1] = e end
            if st.ending and a.endings[st.ending] then
                lastEnding = a.endings[st.ending]
                entries[#entries + 1] = { title = 'Ending: ' .. lastEnding.title, text = lastEnding.text, ending = true }
            end
        end
    end
    TriggerClientEvent('wasteland:story:client:journal', src, { title = curAct.title, subtitle = curAct.subtitle, intro = curAct.intro,
        entries = entries, current = curStep and { title = curStep.title, objective = curStep.objective } or nil,
        ending = not curStep and lastEnding or nil })
end)

-- /story reset | skip [server id]   (admins: test the chains)
RegisterCommand('story', function(source, args)
    local src = tonumber(source) or 0
    if src ~= 0 then
        local allowed = IsPlayerAceAllowed(tostring(src), 'wasteland.admin')
        if not (allowed == true or allowed == 1) then return end
    end
    local target = tonumber(args[2]) or src
    local cid = target ~= 0 and characterOf(target)
    if not (M and M.active) or not cid or not data[cid] then return end
    if args[1] == 'reset' then
        data[cid] = { acts = {} }
        cur(cid); save(cid); send(cid)
        notice(src ~= 0 and src or target, 'Story reset.')
    elseif args[1] == 'skip' then
        complete(cid)
    end
end, false)

--- GetStoryState(source) -> { act, step, flags, ending, done = steps done in this act } | nil
exports('GetStoryState', function(src)
    local cid = characterOf(src)
    if not cid or not data[cid] then return nil end
    local a, st = cur(cid)
    local flags = {}
    for f in pairs(flagsOf(cid)) do flags[#flags + 1] = f end
    return { act = a.id, step = st.step, flags = flags, ending = st.ending, done = #st.log }
end)
