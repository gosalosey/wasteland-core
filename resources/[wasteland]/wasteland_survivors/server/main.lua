-- wasteland_survivors :: server/main.lua
-- Module "survivors": friendly people who wander the map near players.
--   * Spawned out of sight around players (a client finds the spot), gone
--     again when nobody is near.
--   * They fight zombies, and zombies go for them (wasteland_zombies reports
--     a zombie's hit on one: `wasteland:zombies:hitPed`).
--   * A player who hurts one is its enemy (and the enemy of the survivors
--     close by): its game reports the hit, the entity state lists who they
--     fight, the game running the survivor makes them fight back.
--   * Help: zombies killed near a survivor count; after `helpKills` the
--     survivor thanks you and gives you something when you talk to them.
--   * Trade: each survivor has a few item-for-item swaps of their own.
-- A survivor is a networked ped with the entity state
-- `wlSurvivor = { id, name, weapon, hostile = { server ids } }`.

local Rules = WLSV.Rules
local M
local survivors = {}  -- handle -> { handle, netId, id, name, weapon, help = { [src] = kills }, thanked = { [src] = true },
                      --             rewarded = { [cid] = true }, hostile = { [src] = true }, offers, farSince, deadAt }
local pending = {}    -- source -> true while a client looks for a spot
local trading = {}    -- source -> survivor handle (the trade window is open)
local nextId = 0
local runToken = nil
local commandRegistered = false

local function inv() return exports.wasteland_inventory end
local function players() return exports.wasteland_players end
local function now() return GetGameTimer() end
local function notice(src, msg) TriggerClientEvent('wasteland:survivors:client:notice', src, msg) end

local function characterOf(src)
    local ok, cid = pcall(function() return players():GetCharacterId(src) end)
    return ok and cid or nil
end

local function coordsOf(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    local c = GetEntityCoords(ent)
    return { x = c.x, y = c.y, z = c.z }
end
local function playerCoords(src) return coordsOf(GetPlayerPed(tostring(src))) end
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + ((a.z or 0) - (b.z or 0)) ^ 2) end
local function dist2d(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function onlinePlayers()
    local ok, list = pcall(function() return players():GetOnlineCharacters() end)
    return ok and type(list) == 'table' and list or {}
end

local function itemInfo()
    local labels, images = {}, {}
    local ok, list = pcall(function() return inv():GetItemList() end)
    for _, it in ipairs(ok and list or {}) do labels[it.name], images[it.name] = it.label, it.image end
    return labels, images
end

local function label(item)
    local d = inv():GetItemDefinition(item)
    return d and d.label or item
end

-- Give items; what does not fit is dropped at the player's feet.
local function give(src, name, count)
    if count <= 0 then return end
    if inv():AddItem(src, name, count) then return end
    local c = playerCoords(src)
    if c then inv():CreateLootDrop(c, { { name = name, count = count } }, { label = label(name) }) end
    notice(src, label(name) .. ' did not fit and was dropped at your feet.')
end

local function alive(s) return not s.deadAt and DoesEntityExist(s.handle) and GetEntityHealth(s.handle) > 0 end

local function byNet(netId)
    local handle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    return handle and survivors[handle] or nil
end

-- The entity state every game reads (who they fight).
local function publish(s)
    local list = {}
    for src in pairs(s.hostile) do list[#list + 1] = src end
    table.sort(list)
    Entity(s.handle).state:set('wlSurvivor', { id = s.id, name = s.name, weapon = s.weapon, hostile = list }, true)
end

-- Say something: every player close by hears it (and sees the words).
local function say(s, kind)
    local c = coordsOf(s.handle)
    if not c then return end
    local v = M.config.voice[kind]
    if not v then return end
    local line = v.lines[math.random(1, #v.lines)]
    local text = (v.text and #v.text > 0) and v.text[math.random(1, #v.text)] or nil
    for _, p in ipairs(onlinePlayers()) do
        local pc = playerCoords(p.source)
        if pc and dist(pc, c) <= M.config.hearDistance then
            TriggerClientEvent('wasteland:survivors:client:say', p.source, s.netId, kind, line, text)
        end
    end
end

-------------------------------------------------------------------------------
-- Spawning and clean-up
-------------------------------------------------------------------------------

local function spawnAt(point)
    local cfg = M.config
    local model = cfg.models[math.random(1, #cfg.models)]
    local handle = CreatePed(4, GetHashKey(model), point.x + 0.0, point.y + 0.0, point.z + 0.0, math.random() * 360.0, true, true)
    if not handle or handle == 0 or not DoesEntityExist(handle) then
        M.log:warn('could not create a survivor (%s) at %.0f %.0f', model, point.x, point.y)
        return nil
    end
    nextId = nextId + 1
    local s = { handle = handle, netId = NetworkGetNetworkIdFromEntity(handle), id = nextId,
        name = cfg.names[math.random(1, #cfg.names)], weapon = cfg.weapons[math.random(1, #cfg.weapons)],
        help = {}, thanked = {}, rewarded = {}, hostile = {}, offers = Rules.offers(cfg.trade.offers, cfg.trade.offersEach, math.random) }
    survivors[handle] = s
    publish(s)
    return s
end

local function inSafeZone(p)
    if GetResourceState('wasteland_camps') ~= 'started' then return false end
    local ok, safe = pcall(function() return exports.wasteland_camps:IsInSafeZone(p) end)
    return ok and safe == true
end

-- Spots a client found (untrusted: each is checked).
local function spotsFound(src, points)
    if not pending[src] then return end
    pending[src] = nil
    local me = playerCoords(src)
    if not me then return end
    local sp = M.config.spawn
    for _, p in ipairs(points) do
        local d = dist2d(me, p)
        if d >= sp.minDistance - 5 and d <= sp.maxDistance + 5 and math.abs(p.z - me.z) < 120 and not inSafeZone(p) then
            spawnAt(p)
            return -- one at a time
        end
    end
end

local function count(onlyAlive)
    local n = 0
    for _, s in pairs(survivors) do if not onlyAlive or alive(s) then n = n + 1 end end
    return n
end

local function populate()
    local sp = M.config.spawn
    if not sp.enabled then return end
    local total = count(false)
    for _, c in ipairs(onlinePlayers()) do
        local me = playerCoords(c.source)
        if me and not pending[c.source] and total < sp.max then
            local near = 0
            for _, s in pairs(survivors) do
                local p = coordsOf(s.handle)
                if p and alive(s) and dist2d(p, me) <= sp.despawnDistance then near = near + 1 end
            end
            if near < sp.perPlayer and math.random() < sp.chance then
                pending[c.source] = true
                total = total + 1
                TriggerClientEvent('wasteland:survivors:client:findSpots', c.source, 3, sp.minDistance, sp.maxDistance)
                local src = c.source
                Citizen.SetTimeout(10000, function() pending[src] = nil end)
            end
        end
    end
end

local function remove(s)
    survivors[s.handle] = nil
    for src, h in pairs(trading) do
        if h == s.handle then trading[src] = nil; TriggerClientEvent('wasteland:survivors:client:closeTrade', src) end
    end
    if DoesEntityExist(s.handle) then DeleteEntity(s.handle) end
end

local function cleanup()
    local sp = M.config.spawn
    local where = {}
    for _, c in ipairs(onlinePlayers()) do where[#where + 1] = playerCoords(c.source) end
    local t = now()
    for _, s in pairs(survivors) do
        if not DoesEntityExist(s.handle) then
            survivors[s.handle] = nil
        else
            if not s.deadAt and GetEntityHealth(s.handle) <= 0 then s.deadAt = t end
            if s.deadAt and t - s.deadAt >= sp.deadMinutes * 60000 then
                remove(s)
            else
                local p = coordsOf(s.handle)
                local close = false
                for _, w in ipairs(where) do if w and dist2d(w, p) <= sp.despawnDistance then close = true; break end end
                if close then s.farSince = nil
                elseif not s.farSince then s.farSince = t
                elseif t - s.farSince >= sp.despawnAfterSeconds * 1000 then remove(s) end
            end
        end
    end
end

local function loop(token)
    local since = 0
    while runToken == token do
        Citizen.Wait(1000)
        if runToken ~= token then return end
        cleanup()
        since = since + 1
        if since >= M.config.spawn.everySeconds then
            since = 0
            populate()
        end
    end
end

-------------------------------------------------------------------------------
-- Hostility, help, zombies' hits
-------------------------------------------------------------------------------

-- A player hurt a survivor (their own game says so: it only hurts them).
local function attacked(src, netId)
    local s = byNet(netId)
    local me = playerCoords(src)
    if not s or not me then return end
    local here = coordsOf(s.handle)
    if not here or dist(me, here) > 150 then return end
    local turned = 0
    for _, o in pairs(survivors) do
        local oc = coordsOf(o.handle)
        if alive(o) and oc and (o == s or dist(oc, here) <= M.config.hostileSpreadRadius) and not o.hostile[src] then
            o.hostile[src], o.help[src] = true, nil
            publish(o)
            turned = turned + 1
            say(o, 'angry')
        end
    end
    if turned > 0 then notice(src, s.name .. (turned > 1 and ' and the others turn on you!' or ' turns on you!')) end
end

-- A zombie died: the player who killed it helped any survivor close by.
AddEventHandler('wasteland:zombies:died', function(_, _, _, killer, coords)
    killer = tonumber(killer)
    if not (M and M.active) or not killer or killer <= 0 or type(coords) ~= 'table' then return end
    for _, s in pairs(survivors) do
        local c = coordsOf(s.handle)
        if alive(s) and c and not s.hostile[killer] and dist(c, coords) <= M.config.helpRadius then
            s.help[killer] = (s.help[killer] or 0) + 1
            if Rules.helped(s.help[killer], M.config.helpKills) and not s.thanked[killer] then
                s.thanked[killer] = true
                local cid = characterOf(killer)
                if not (cid and s.rewarded[cid]) then
                    say(s, 'thanks')
                    notice(killer, s.name .. ': "Thank you! Come talk to me."')
                end
            end
        end
    end
end)

-- A zombie's swing landed on a survivor (checked by wasteland_zombies): the
-- game running the survivor takes the health off.
AddEventHandler('wasteland:zombies:hitPed', function(netId, damage)
    local s = byNet(netId)
    if not s or not alive(s) then return end
    local owner = NetworkGetEntityOwner(s.handle)
    if owner and owner > 0 then TriggerClientEvent('wasteland:survivors:client:damage', owner, s.netId, tonumber(damage) or 0) end
end)

-------------------------------------------------------------------------------
-- Talking and trading
-------------------------------------------------------------------------------

-- The survivor, when this player stands next to it and is not its enemy.
local function reachable(src, netId)
    local s = byNet(netId)
    if not s or not alive(s) then return nil end
    local me, c = playerCoords(src), coordsOf(s.handle)
    if not me or not c or dist(me, c) > 5.0 then return nil end
    if s.hostile[src] then notice(src, s.name .. ' wants nothing to do with you.'); return nil end
    return s
end

local function talk(src, netId)
    local s = reachable(src, netId)
    if not s then return end
    local cid = characterOf(src)
    if not cid then return end
    if s.rewarded[cid] then
        say(s, 'bye')
        notice(src, s.name .. ': "I already gave you what I could. Stay safe."')
    elseif Rules.helped(s.help[src], M.config.helpKills) then
        s.rewarded[cid] = true
        local got = {}
        for _, it in ipairs(Rules.reward(M.config.rewards, M.config.rewardPicks, math.random)) do
            give(src, it.name, it.count)
            got[#got + 1] = it.count .. ' x ' .. label(it.name)
        end
        say(s, 'thanks')
        notice(src, s.name .. ' gives you ' .. table.concat(got, ', ') .. '.')
    else
        local left = M.config.helpKills - (s.help[src] or 0)
        say(s, 'greet')
        notice(src, ('%s: "Help me keep the dead off and I\'ll make it worth your while." (kill %d more zombie%s near them)')
            :format(s.name, left, left == 1 and '' or 's'))
    end
end

local function tradeView(src, s, message, ok)
    local labels, images = itemInfo()
    local offers = {}
    for i, o in ipairs(s.offers) do
        offers[i] = { index = i, left = o.left,
            give = { name = o.give.name, count = o.give.count, label = labels[o.give.name] or o.give.name, image = images[o.give.name],
                have = inv():GetItemCount(src, o.give.name) or 0 },
            get = { name = o.get.name, count = o.get.count, label = labels[o.get.name] or o.get.name, image = images[o.get.name] } }
    end
    return { title = s.name, offers = offers, message = message, ok = ok }
end

local function openTrade(src, netId)
    local s = reachable(src, netId)
    if not s then return end
    trading[src] = s.handle
    say(s, 'greet')
    TriggerClientEvent('wasteland:survivors:client:trade', src, s.netId, tradeView(src, s))
end

local function barter(src, netId, index)
    local s = reachable(src, netId)
    if not s or trading[src] ~= s.handle then return end
    local o = s.offers[index]
    if not o then return end
    local msg, ok
    if o.left <= 0 then
        msg, ok = 'They have no more of that.', false
    elseif (inv():GetItemCount(src, o.give.name) or 0) < o.give.count then
        msg, ok = ('You need %d x %s.'):format(o.give.count, label(o.give.name)), false
    elseif not inv():RemoveItem(src, o.give.name, o.give.count) then
        msg, ok = 'The trade did not go through.', false
    else
        o.left = o.left - 1
        give(src, o.get.name, o.get.count)
        msg, ok = ('You traded %d x %s for %d x %s.'):format(o.give.count, label(o.give.name), o.get.count, label(o.get.name)), true
    end
    TriggerClientEvent('wasteland:survivors:client:trade', src, s.netId, tradeView(src, s, msg, ok))
end

-------------------------------------------------------------------------------
-- Admin: /survivors count | clear | spawn
-------------------------------------------------------------------------------

local function adminCommand(src, args)
    local reply = function(msg)
        if src == 0 then print(msg) else TriggerClientEvent('wasteland:core:client:consoleOutput', src, { msg }) end
    end
    if src ~= 0 and not IsPlayerAceAllowed(tostring(src), 'wasteland.admin') then return end
    local what = args[1]
    if what == 'clear' then
        local n = 0
        for _, s in pairs(survivors) do remove(s); n = n + 1 end
        reply(('Removed %d survivors.'):format(n))
    elseif what == 'spawn' and src ~= 0 then
        local me = playerCoords(src)
        if not me then return end
        local ped = GetPlayerPed(tostring(src))
        local h = math.rad(GetEntityHeading(ped))
        local s = spawnAt({ x = me.x - math.sin(h) * 6.0, y = me.y + math.cos(h) * 6.0, z = me.z })
        reply(s and ('Spawned %s 6 m in front of you.'):format(s.name) or 'Could not spawn a survivor.')
    else
        reply(('%d survivors (%d alive). Usage: /%s count | clear | spawn'):format(count(false), count(true), M.config.adminCommand))
    end
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local NAME = { type = 'string', required = true, pattern = '^[%w_]+$' }
local STACK = { type = 'table', fields = { name = NAME, count = { type = 'integer', required = true, min = 1, max = 10000 } } }
local VOICE = { type = 'table', fields = {
    lines = { type = 'array', minItems = 1, items = { type = 'string', pattern = '^[%w_]+$' } },
    text = { type = 'array', default = {}, items = { type = 'string', maxLength = 120 } },
    everySeconds = { type = 'number', default = 20, min = 1, max = 600 },
} }

M = Wasteland.DefineModule({
    name = 'survivors',
    version = '0.1.0',
    description = 'Survivors: friendly people who fight zombies, reward help, trade, fight back',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', inventory = '^0.1.0' },
    optionalDependencies = { zombies = '^0.1.0', camps = '^0.1.0' },
    config = {
        file = 'survivors.lua',
        optional = true,
        schema = { type = 'table', fields = {
            spawn = { type = 'table', fields = {
                enabled = { type = 'boolean', default = true },
                perPlayer = { type = 'integer', default = 1, min = 0, max = 10 },
                max = { type = 'integer', default = 12, min = 0, max = 100 },
                minDistance = { type = 'number', default = 110, min = 20, max = 500 },
                maxDistance = { type = 'number', default = 220, min = 30, max = 800 },
                everySeconds = { type = 'number', default = 45, min = 1, max = 3600 },
                chance = { type = 'number', default = 0.5, min = 0, max = 1 },
                despawnDistance = { type = 'number', default = 400, min = 100, max = 3000 },
                despawnAfterSeconds = { type = 'number', default = 60, min = 0, max = 3600 },
                deadMinutes = { type = 'number', default = 5, min = 0, max = 120 },
            } },
            models = { type = 'array', minItems = 1, default = { 'a_m_m_hillbilly_01' }, items = { type = 'string', pattern = '^[%w_]+$' } },
            weapons = { type = 'array', minItems = 1, default = { 'WEAPON_PISTOL' }, items = { type = 'string', pattern = '^[%w_]+$' } },
            names = { type = 'array', minItems = 1, default = { 'Survivor' }, items = { type = 'string', minLength = 1, maxLength = 24 } },
            health = { type = 'integer', default = 250, min = 100, max = 5000 },
            armour = { type = 'integer', default = 25, min = 0, max = 100 },
            accuracy = { type = 'integer', default = 35, min = 0, max = 100 },
            engageRadius = { type = 'number', default = 40, min = 5, max = 150 },
            helpRadius = { type = 'number', default = 30, min = 5, max = 150 },
            helpKills = { type = 'integer', default = 2, min = 1, max = 100 },
            rewardPicks = { type = 'integer', default = 2, min = 1, max = 10 },
            rewards = { type = 'array', minItems = 1, default = { { name = 'bandage', min = 1, max = 2 } }, items = { type = 'table', fields = {
                name = NAME, min = { type = 'integer', default = 1, min = 1, max = 10000 }, max = { type = 'integer', default = 1, min = 1, max = 10000 },
                weight = { type = 'number', default = 1, min = 0, max = 1000 },
            } } },
            hostileSpreadRadius = { type = 'number', default = 40, min = 0, max = 300 },
            trade = { type = 'table', fields = {
                offersEach = { type = 'integer', default = 3, min = 0, max = 10 },
                offers = { type = 'array', default = {}, items = { type = 'table', fields = {
                    give = STACK, get = STACK, times = { type = 'integer', default = 2, min = 1, max = 100 },
                    weight = { type = 'number', default = 1, min = 0, max = 1000 },
                } } },
            } },
            voice = { type = 'table', fields = { help = VOICE, thanks = VOICE, greet = VOICE, angry = VOICE, bye = VOICE } },
            hearDistance = { type = 'number', default = 60, min = 5, max = 300 },
            adminCommand = { type = 'string', default = 'survivors', pattern = '^[a-z][a-z0-9_]*$' },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        local need = {}
        for _, r in ipairs(M.config.rewards) do
            if r.min > r.max then return false, ('survivors.lua: reward "%s" has min above max'):format(r.name) end
            need[#need + 1] = r.name
        end
        for _, o in ipairs(M.config.trade.offers) do need[#need + 1] = o.give.name; need[#need + 1] = o.get.name end
        for _, item in ipairs(need) do
            if not inv():GetItemDefinition(item) then return false, ('survivors.lua names item "%s", which is not in inventory.lua items'):format(item) end
        end
        for _, k in ipairs({ 'help', 'thanks', 'greet', 'angry', 'bye' }) do
            if not M.config.voice[k] then return false, ('survivors.lua: voice.%s is missing'):format(k) end
        end
        if M.config.spawn.minDistance >= M.config.spawn.maxDistance then return false, 'survivors.lua: spawn.minDistance must be below maxDistance' end
        survivors, pending, trading = {}, {}, {}
        if not commandRegistered then
            commandRegistered = true
            RegisterCommand(M.config.adminCommand, function(source, args) adminCommand(tonumber(source) or 0, args) end, false)
        end
        local token = {}
        runToken = token
        Citizen.CreateThread(function() loop(token) end)
        return true
    end,
    onShutdown = function()
        runToken = nil
        for _, s in pairs(survivors) do remove(s) end
        survivors, pending, trading = {}, {}, {}
    end,
})

local RATE = { burst = 6, perSecond = 2 }
local NET = { type = 'integer', required = true, min = 0, max = 1000000 }
local COORD = { type = 'number', required = true, min = -20000, max = 20000 }
local POINT = { type = 'table', fields = { x = COORD, y = COORD, z = COORD } }

local function clientConfig()
    local v = {}
    for k, e in pairs(M.config.voice) do v[k] = { everySeconds = e.everySeconds } end
    return { health = M.config.health, armour = M.config.armour, accuracy = M.config.accuracy,
        engageRadius = M.config.engageRadius, voice = v }
end

M.netEvent('wasteland:survivors:server:config', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    TriggerClientEvent('wasteland:survivors:client:config', src, clientConfig())
end)
AddEventHandler('wasteland:core:moduleState', function(name, state)
    if name == 'survivors' and state == 'running' and M then TriggerClientEvent('wasteland:survivors:client:config', -1, clientConfig()) end
end)

M.netEvent('wasteland:survivors:server:spots', { args = { { type = 'array', required = true, maxItems = 10, items = POINT } }, rateLimit = RATE },
    function(src, points) spotsFound(src, points) end)
M.netEvent('wasteland:survivors:server:attacked', { args = { NET }, rateLimit = RATE }, function(src, netId) attacked(src, netId) end)
M.netEvent('wasteland:survivors:server:talk', { args = { NET }, rateLimit = RATE }, function(src, netId) talk(src, netId) end)
M.netEvent('wasteland:survivors:server:openTrade', { args = { NET }, rateLimit = RATE }, function(src, netId) openTrade(src, netId) end)
M.netEvent('wasteland:survivors:server:barter', { args = { NET, { type = 'integer', required = true, min = 1, max = 20 } }, rateLimit = RATE },
    function(src, netId, index) barter(src, netId, index) end)
M.netEvent('wasteland:survivors:server:closeTrade', { rateLimit = RATE }, function(src) trading[src] = nil end)

-- The game running a survivor asks it to shout (zombies on it, a player near).
local lastSay = {} -- handle -> { [kind] = time }
M.netEvent('wasteland:survivors:server:say', { args = { NET, { type = 'string', required = true, pattern = '^%a+$', maxLength = 12 } },
    rateLimit = { burst = 4, perSecond = 1 } }, function(src, netId, kind)
    local s = byNet(netId)
    local v = M.config.voice[kind]
    if not s or not v or not alive(s) or NetworkGetEntityOwner(s.handle) ~= src then return end
    if kind ~= 'help' and kind ~= 'greet' then return end
    local t = now()
    lastSay[s.handle] = lastSay[s.handle] or {}
    if t - (lastSay[s.handle][kind] or -1e9) < v.everySeconds * 1000 then return end
    lastSay[s.handle][kind] = t
    say(s, kind)
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    pending[src], trading[src] = nil, nil
    for _, s in pairs(survivors) do
        if s.hostile[src] then s.hostile[src] = nil; if DoesEntityExist(s.handle) then publish(s) end end
        s.help[src], s.thanked[src] = nil, nil
    end
end)

--- GetSurvivorCount() -> total, alive
exports('GetSurvivorCount', function() return count(false), count(true) end)

--- SpawnSurvivor(coords) -> netId | nil   (scripted spawns: events, quests)
exports('SpawnSurvivor', function(coords)
    if not (M and M.active) or type(coords) ~= 'table' then return nil end
    local s = spawnAt(coords)
    return s and s.netId or nil
end)

--- IsSurvivor(netId) -> bool
exports('IsSurvivor', function(netId) return byNet(netId) ~= nil end)
