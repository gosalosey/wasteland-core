-- wasteland_events :: server/main.lua
-- Module "events": world events (events.lua). Now and then an event starts
-- at a random point: every player gets a message and a map marker. When a
-- player comes near, the danger appears: zombies (through wasteland_zombies)
-- and armed bandits (networked peds; the client that runs one makes it
-- fight). Each bandit drops a small bag. Once every bandit and every event
-- zombie is dead, the loot (an inventory stash, filled when first opened)
-- can be searched. The event ends after its time.

local Rules = WLEV.Rules
local M
local events = {}      -- id -> event
local nextId = 0
local runToken = nil
local lastEventAt = 0
local commandRegistered = false

local function now() return GetGameTimer() end
local function inv() return exports.wasteland_inventory end
local function started(res) return GetResourceState(res) == 'started' end
local function notice(src, msg) TriggerClientEvent('wasteland:events:client:notice', src, msg) end

local function coordsOf(handle)
    local c = GetEntityCoords(handle)
    return { x = c.x, y = c.y, z = c.z }
end

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function playerCoords(src)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return coordsOf(ped)
end

-- The nearest player to a point: source, distance.
local function nearestPlayer(p)
    local best, bestD
    for _, s in ipairs(GetPlayers()) do
        local c = playerCoords(tonumber(s))
        if c then
            local d = dist(c, p)
            if not bestD or d < bestD then best, bestD = tonumber(s), d end
        end
    end
    return best, bestD or math.huge
end

local function isSafe(p)
    if not started('wasteland_camps') then return false end
    local ok, yes = pcall(function() return exports.wasteland_camps:IsInSafeZone(p) end)
    return ok and yes == true
end

-------------------------------------------------------------------------------
-- What clients see
-------------------------------------------------------------------------------

local function counts(e)
    local bandits = 0
    for _, b in ipairs(e.bandits) do if not b.dead then bandits = bandits + 1 end end
    local zombies = 0
    if started('wasteland_zombies') then
        for _, netId in ipairs(e.zombies) do
            local ok, info = pcall(function() return exports.wasteland_zombies:GetZombieInfo(netId) end)
            if ok and info and not info.dead and dist(info.coords, e.center) <= M.config.zombieAreaRadius then zombies = zombies + 1 end
        end
    end
    return bandits, zombies
end

local function public(e)
    return { id = e.id, type = e.type, label = e.def.label, place = e.place, center = e.center, state = e.state,
        props = e.def.props, lootLabel = e.def.lootLabel }
end

local function broadcast(e) TriggerClientEvent('wasteland:events:client:event', -1, public(e)) end

-------------------------------------------------------------------------------
-- Starting and ending
-------------------------------------------------------------------------------

local function activeList()
    local out = {}
    for _, e in pairs(events) do out[#out + 1] = e end
    return out
end

local function startEvent(typeName, point)
    local def = M.config.types[typeName]
    if not def then return nil, 'unknown event type' end
    local p = point or Rules.pickPoint(M.config.points, activeList(), M.config.minGap, isSafe, math.random)
    if not p then return nil, 'no free event point' end
    nextId = nextId + 1
    local e = { id = nextId, type = typeName, def = def, center = { x = p.x, y = p.y, z = p.z }, place = p.label or 'somewhere',
        state = 'waiting', startedAt = now(), expiresAt = now() + def.minutes * 60000, bandits = {}, zombies = {} }
    events[e.id] = e
    lastEventAt = now()
    broadcast(e)
    TriggerClientEvent('wasteland:events:client:notice', -1, string.format(def.message, e.place))
    M.log:info('event %d: %s near %s (%.0f, %.0f)', e.id, typeName, e.place, p.x, p.y)
    TriggerEvent('wasteland:events:started', e.id, typeName, e.center)
    return e.id
end

local function endEvent(id, why)
    local e = events[id]
    if not e then return end
    events[id] = nil
    for _, b in ipairs(e.bandits) do
        if b.handle and DoesEntityExist(b.handle) then DeleteEntity(b.handle) end
    end
    if started('wasteland_inventory') then inv():DeleteStash('event_' .. id) end
    TriggerClientEvent('wasteland:events:client:remove', -1, id)
    M.log:info('event %d ended (%s)', id, why)
end

-------------------------------------------------------------------------------
-- The danger: bandits and zombies
-------------------------------------------------------------------------------

local function spawnBandit(e, b)
    local def = e.def.bandits
    local model = def.models[math.random(1, #def.models)]
    local h = CreatePed(4, GetHashKey(model), b.spot.x + 0.0, b.spot.y + 0.0, b.spot.z + 0.0, math.random() * 360.0, true, true)
    if not h or h == 0 or not DoesEntityExist(h) then
        M.log:warn('event %d: could not create a bandit (%s)', e.id, model)
        return
    end
    -- Keep the bandit while nobody is near (the server ends the event).
    if SetEntityOrphanMode then pcall(SetEntityOrphanMode, h, 2) end
    local weapon = def.weapons[math.random(1, #def.weapons)]
    if GiveWeaponToPed then pcall(GiveWeaponToPed, h, GetHashKey(weapon), 250, false, true) end
    if SetPedArmour and def.armor > 0 then pcall(SetPedArmour, h, def.armor) end
    Entity(h).state:set('wlBandit', { event = e.id, weapon = weapon, accuracy = def.accuracy, center = e.center }, true)
    b.handle, b.netId, b.lost = h, NetworkGetNetworkIdFromEntity(h), false
end

local function spawnDanger(e, spots)
    local def = e.def
    local nB = def.bandits.count
    for i = 1, nB do
        local b = { spot = spots[i] or Rules.ring(e.center, 1, 8, 20, math.random)[1], dead = false }
        e.bandits[#e.bandits + 1] = b
        spawnBandit(e, b)
    end
    if def.zombies.count > 0 and started('wasteland_zombies') then
        for i = 1, def.zombies.count do
            local spot = spots[nB + i] or Rules.ring(e.center, 1, 10, 35, math.random)[1]
            local kind = math.random() < def.zombies.runnerShare and 'runner' or 'walker'
            local ok, netId = pcall(function() return exports.wasteland_zombies:SpawnZombie(spot, kind) end)
            if ok and netId then e.zombies[#e.zombies + 1] = netId end
        end
    end
    e.state = 'active'
    broadcast(e)
    M.log:info('event %d: %d bandits and %d zombies are here', e.id, #e.bandits, #e.zombies)
end

-- A player came near: ask their game for spots on the ground (it has the
-- map loaded); without an answer in time, a ring at the centre's height.
local function activate(e, src)
    e.state, e.asking = 'spawning', { src = src, at = now() }
    local n = e.def.bandits.count + e.def.zombies.count
    TriggerClientEvent('wasteland:events:client:findSpots', src, e.id, e.center, n, 6, 35)
end

local function banditDied(e, b)
    b.dead = true
    local items = M.config.banditDrop
    if #items > 0 and started('wasteland_inventory') and b.handle and DoesEntityExist(b.handle) then
        local list = {}
        for _, it in ipairs(items) do
            if math.random() < (it.chance or 1) then list[#list + 1] = { name = it.name, count = math.random(it.min, it.max) } end
        end
        if #list > 0 then
            pcall(function() inv():CreateLootDrop(coordsOf(b.handle), list, { label = 'Bandit', lifetimeMinutes = 15 }) end)
        end
    end
    TriggerEvent('wasteland:events:banditKilled', e.id)
end

local function check(e)
    if e.state ~= 'active' then return end
    for _, b in ipairs(e.bandits) do
        if not b.dead then
            if not b.handle or not DoesEntityExist(b.handle) then
                b.lost = true -- gone without dying (nobody near): comes back later
            elseif GetEntityHealth(b.handle) <= 0 then
                banditDied(e, b)
            end
        end
    end
    local banditsLeft, zombiesLeft = counts(e)
    if banditsLeft == 0 and zombiesLeft == 0 then
        e.state = 'cleared'
        e.expiresAt = math.min(e.expiresAt, now() + M.config.lootMinutes * 60000)
        broadcast(e)
        TriggerClientEvent('wasteland:events:client:notice', -1, string.format(e.def.clearedMessage, e.place))
        M.log:info('event %d cleared', e.id)
        TriggerEvent('wasteland:events:cleared', e.id, e.type)
    end
end

local function loop(token)
    while runToken == token do
        Citizen.Wait(2000)
        if runToken ~= token then return end
        local t = now()
        for id, e in pairs(events) do
            if t >= e.expiresAt then
                endEvent(id, 'time is up')
            else
                local src, d = nearestPlayer(e.center)
                if e.state == 'waiting' and src and d <= M.config.activateDistance then
                    activate(e, src)
                elseif e.state == 'spawning' and t - e.asking.at > 8000 then
                    spawnDanger(e, {}) -- nobody answered: spawn around the centre
                elseif e.state == 'active' then
                    -- Bandits that vanished while nobody was near come back.
                    if src and d <= M.config.activateDistance then
                        for _, b in ipairs(e.bandits) do if b.lost and not b.dead then spawnBandit(e, b) end end
                    end
                    check(e)
                end
            end
        end
        local n = 0
        for _ in pairs(events) do n = n + 1 end
        if M.config.intervalMinutes > 0 and t - lastEventAt >= M.config.intervalMinutes * 60000 and n < M.config.maxActive
            and #GetPlayers() >= M.config.minPlayers then
            local typeName = Rules.pickType(M.config.types, math.random)
            if typeName then startEvent(typeName) else lastEventAt = t end
        end
    end
end

-------------------------------------------------------------------------------
-- The loot
-------------------------------------------------------------------------------

local function fill(e, stashId)
    local items
    if started('wasteland_loot') and e.def.lootTable ~= '' then
        local ok, rolled = pcall(function() return exports.wasteland_loot:RollTable(e.def.lootTable) end)
        if ok and type(rolled) == 'table' then items = rolled end
    end
    for _, it in ipairs(items or {}) do
        local ok, err = inv():AddItem(stashId, it.name, it.count)
        if not ok then M.log:warn('event %d loot %s x %d: %s', e.id, it.name, it.count, tostring(err)) end
    end
    -- A few more rolls make it worth the fight.
    for _ = 2, e.def.lootRolls do
        if started('wasteland_loot') and e.def.lootTable ~= '' then
            local ok, rolled = pcall(function() return exports.wasteland_loot:RollTable(e.def.lootTable) end)
            for _, it in ipairs(ok and rolled or {}) do inv():AddItem(stashId, it.name, it.count) end
        end
    end
end

local function openLoot(src, id)
    local e = events[id]
    if not e then notice(src, 'There is nothing left here.'); return end
    local p = playerCoords(src)
    if not p or dist(p, e.center) > M.config.lootReach then notice(src, 'You are too far away.'); return end
    if e.state ~= 'cleared' then
        local b, z = counts(e)
        notice(src, Rules.blockedText(b, z) or 'Too dangerous right now.')
        return
    end
    local name = 'event_' .. id
    local opts = { label = e.def.lootLabel, width = 8, height = 6, maxWeight = 300, coords = e.center, reach = M.config.lootReach }
    local stashId, err = inv():EnsureStash(name, opts)
    if not stashId then notice(src, 'It cannot be opened right now.'); M.log:warn('event stash: %s', tostring(err)); return end
    if not e.filled then
        e.filled = true
        fill(e, stashId)
        TriggerEvent('wasteland:events:looted', src, id, e.type)
    end
    opts.open = true
    inv():OpenStash(src, name, opts)
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local NUM = function(d, a, b) return { type = 'number', default = d, min = a, max = b } end
local INT = function(d, a, b) return { type = 'integer', default = d, min = a, max = b } end
local XYZ = { type = 'table', fields = {
    x = { type = 'number', required = true }, y = { type = 'number', required = true }, z = { type = 'number', required = true },
    label = { type = 'string', default = 'somewhere', maxLength = 64 },
} }
local TYPE = { type = 'table', fields = {
    label = { type = 'string', required = true, maxLength = 48 },
    weight = INT(1, 0, 1000),
    minutes = NUM(30, 1, 600),
    message = { type = 'string', required = true, maxLength = 200 },
    clearedMessage = { type = 'string', default = 'The danger at %s is over. It can be searched.', maxLength = 200 },
    lootLabel = { type = 'string', default = 'Loot', maxLength = 40 },
    lootTable = { type = 'string', default = '', maxLength = 48 },
    lootRolls = INT(2, 1, 10),
    zombies = { type = 'table', fields = { count = INT(0, 0, 60), runnerShare = NUM(0.3, 0, 1) } },
    bandits = { type = 'table', fields = {
        count = INT(0, 0, 20), accuracy = INT(35, 1, 100), armor = INT(25, 0, 100),
        models = { type = 'array', default = { 'g_m_y_lost_01' }, minItems = 1, items = { type = 'string', pattern = '^[%w_]+$' } },
        weapons = { type = 'array', default = { 'WEAPON_PISTOL' }, minItems = 1, items = { type = 'string', pattern = '^[%w_]+$' } },
    } },
    props = { type = 'array', default = {}, items = { type = 'table', fields = {
        model = { type = 'string', required = true, pattern = '^[%w_]+$' },
        x = NUM(0, -50, 50), y = NUM(0, -50, 50), z = NUM(0, -10, 10), heading = NUM(0, 0, 360),
        loot = { type = 'boolean', default = false, description = 'Players search this prop' },
        fx = { type = 'string', pattern = '^[%w_]+$', description = 'A looping particle effect on it (core)' },
    } } },
} }

M = Wasteland.DefineModule({
    name = 'events',
    version = '0.1.0',
    description = 'World events: helicopter crashes, ambushed convoys, bandit hideouts, hordes',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', inventory = '^0.1.0' },
    optionalDependencies = { zombies = '^0.1.0', loot = '^0.1.0', camps = '^0.1.0' },
    config = {
        file = 'events.lua',
        optional = true,
        schema = { type = 'table', fields = {
            intervalMinutes = NUM(35, 0, 10000), maxActive = INT(1, 1, 5), minPlayers = INT(1, 0, 1000),
            minGap = NUM(800, 0, 10000), activateDistance = NUM(150, 50, 400), zombieAreaRadius = NUM(90, 20, 400),
            lootReach = NUM(8, 2, 30), lootMinutes = NUM(15, 1, 600),
            banditDrop = { type = 'array', default = {}, items = { type = 'table', fields = {
                name = { type = 'string', required = true, pattern = '^[%w_]+$' },
                min = INT(1, 1, 100000), max = INT(1, 1, 100000), chance = NUM(1, 0, 1),
            } } },
            types = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[a-z][a-z0-9_]*$', maxLength = 24 }, values = TYPE },
            points = { type = 'array', default = {}, items = XYZ },
            adminCommand = { type = 'string', default = 'event', pattern = '^[a-z][a-z0-9_]*$' },
            adminAce = { type = 'string', default = 'wasteland.admin' },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        if #M.config.points == 0 then return false, 'events.lua: add at least one point' end
        for _, it in ipairs(M.config.banditDrop) do
            if not inv():GetItemDefinition(it.name) then return false, string.format('events.lua: banditDrop item "%s" is not in inventory.lua', it.name) end
        end
        if not commandRegistered then
            RegisterCommand(M.config.adminCommand, function(source, args)
                local src = tonumber(source) or 0
                local reply = function(msg) if src == 0 then print(msg) else notice(src, msg) end end
                if src ~= 0 and not IsPlayerAceAllowed(tostring(src), M.config.adminAce) then return end
                if not (M and M.active) then return end
                local what = args[1]
                if what == 'end' then
                    local n = 0
                    for id in pairs(events) do endEvent(id, 'ended by an admin'); n = n + 1 end
                    reply(string.format('Ended %d event(s).', n))
                elseif what and M.config.types[what] then
                    local point = nil
                    if args[2] == 'here' and src ~= 0 then
                        local p = playerCoords(src)
                        if p then point = { x = p.x + 25.0, y = p.y, z = p.z, label = 'an admin' } end
                    end
                    local id, err = startEvent(what, point)
                    reply(id and string.format('Event %d (%s) started.', id, what) or ('No event: ' .. tostring(err)))
                else
                    local names = {}
                    for name in pairs(M.config.types) do names[#names + 1] = name end
                    table.sort(names)
                    local list = {}
                    for _, e in pairs(events) do list[#list + 1] = string.format('#%d %s at %s (%s)', e.id, e.type, e.place, e.state) end
                    reply(string.format('Events: %s. Running: %s. Usage: /%s <type> [here] | end',
                        table.concat(names, ', '), #list > 0 and table.concat(list, '; ') or 'none', M.config.adminCommand))
                end
            end, false)
            commandRegistered = true
        end
        events, lastEventAt = {}, now()
        local token = {}
        runToken = token
        Citizen.CreateThread(function() loop(token) end)
        return true
    end,
    onShutdown = function()
        runToken = nil
        for id in pairs(events) do endEvent(id, 'module stopped') end
        events = {}
    end,
})

M.netEvent('wasteland:events:server:sync', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    for _, e in pairs(events) do TriggerClientEvent('wasteland:events:client:event', src, public(e)) end
end)

-- A player's game found ground spots around an event.
M.netEvent('wasteland:events:server:spots', {
    args = { { type = 'integer', required = true, min = 1 }, { type = 'array', required = true, maxItems = 80, items = { type = 'table', fields = {
        x = { type = 'number', required = true }, y = { type = 'number', required = true }, z = { type = 'number', required = true },
    } } } },
    rateLimit = { burst = 4, perSecond = 1 },
}, function(src, id, spots)
    local e = events[id]
    if not e or e.state ~= 'spawning' or e.asking.src ~= src then return end
    local ok = {}
    for _, s in ipairs(spots) do
        if dist(s, e.center) <= 60 then ok[#ok + 1] = s end -- only near the event
    end
    spawnDanger(e, ok)
end)

M.netEvent('wasteland:events:server:open', { args = { { type = 'integer', required = true, min = 1 } }, rateLimit = { burst = 4, perSecond = 1 } },
    function(src, id) Citizen.CreateThread(function() openLoot(src, id) end) end)

-------------------------------------------------------------------------------
-- Exports (events api 0.1)
-------------------------------------------------------------------------------

--- GetEvents() -> list of { id, type, label, place, center, state, bandits, zombies }
exports('GetEvents', function()
    local out = {}
    for _, e in pairs(events) do
        local b, z = counts(e)
        out[#out + 1] = { id = e.id, type = e.type, label = e.def.label, place = e.place, center = e.center, state = e.state, bandits = b, zombies = z }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)

--- StartEvent(type, coords?) -> id | nil, err
exports('StartEvent', function(typeName, coords) return startEvent(typeName, type(coords) == 'table' and coords or nil) end)

--- EndEvent(id) -> true
exports('EndEvent', function(id) endEvent(tonumber(id), 'ended by another module'); return true end)

-- Server events: wasteland:events:started(id, type, center), :cleared(id, type),
-- :looted(source, id, type), :banditKilled(id)
