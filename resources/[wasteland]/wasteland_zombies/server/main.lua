-- wasteland_zombies :: server/main.lua
-- Module "zombies": the server decides how many zombies each player has
-- around them, creates them (server-side peds, OneSync), and owns every
-- consequence: hits (damage, infection, bleeding through survival),
-- deaths, loot, despawning. The client that owns a zombie entity runs its
-- AI (client/main.lua) and finds spawn points on the ground for the server.
--
-- A zombie is a networked ped with the entity state `wlZombie = { kind }`.
-- Noise (gunshots: `wasteland:weapons:used`) sets `wlInvestigate` on the
-- zombies that hear it; their owner client walks them there.

local Rules = WLZ.Rules
local M
local zombies = {}     -- handle -> { handle, netId, kind, spawnedAt, dead, deadAt, farSince, lastHit, hp }
local pending = {}     -- source -> { n, ring = { spawnMin, spawnMax } } (spawn points asked for)
local runToken = nil

local function players() return exports.wasteland_players end
local function now() return GetGameTimer() end

local function survival(fn, ...)
    if GetResourceState('wasteland_survival') ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, a, b = pcall(function() return exports.wasteland_survival[fn](exports.wasteland_survival, table.unpack(args, 1, args.n)) end)
    if not ok then return nil end
    return a, b
end

local function isNight()
    if GetResourceState('wasteland_world') ~= 'started' then return false end
    local ok, hour = pcall(function() return exports.wasteland_world:GetTime() end)
    return ok and Rules.isNight(hour)
end

--- Living players with a loaded character: list of { source, coords }.
local function activePlayers()
    local out = {}
    local ok, list = pcall(function() return players():GetOnlineCharacters() end)
    if not ok or type(list) ~= 'table' then return out end
    for _, c in ipairs(list) do
        local src = c.source
        if src and not survival('IsDead', src) then
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local p = GetEntityCoords(ped)
                out[#out + 1] = { source = src, coords = { x = p.x, y = p.y, z = p.z } }
            end
        end
    end
    return out
end

-- Safe zones (camps): no zombies inside.
local function inSafeZone(coords)
    if GetResourceState('wasteland_camps') ~= 'started' then return false end
    local ok, safe = pcall(function() return exports.wasteland_camps:IsInSafeZone(coords) end)
    return ok and safe == true
end

local function coordsOf(handle)
    local p = GetEntityCoords(handle)
    return { x = p.x, y = p.y, z = p.z }
end

local function count(alive)
    local n = 0
    for _, z in pairs(zombies) do if not alive or not z.dead then n = n + 1 end end
    return n
end

local function remove(z)
    zombies[z.handle] = nil
    if DoesEntityExist(z.handle) then DeleteEntity(z.handle) end
    -- The body is gone (looting deletes what was left on it).
    TriggerEvent('wasteland:zombies:removed', z.uid, z.netId)
end

local uidCounter = 0
local function newUid()
    uidCounter = (uidCounter + 1) % 0x10000
    return string.format('%08x%04x', os.time() & 0xffffffff, uidCounter)
end

-------------------------------------------------------------------------------
-- Spawning
-------------------------------------------------------------------------------

local missingModels = {}  -- model name -> true: a player's game does not have it

local function spawnAt(point, kind)
    local pool = Rules.modelPool(M.config.kinds[kind], M.config.models, missingModels)
    if #pool == 0 then pool = { 'u_m_y_zombie_01' } end -- GTA's own zombie: always there
    local model = pool[math.random(1, #pool)]
    local handle = CreatePed(4, GetHashKey(model), point.x + 0.0, point.y + 0.0, point.z + 0.0, math.random() * 360.0, true, true)
    if not handle or handle == 0 or not DoesEntityExist(handle) then
        M.log:warn('could not create a zombie (%s) at %.0f %.0f', model, point.x, point.y)
        return nil
    end
    local uid = newUid()
    Entity(handle).state:set('wlZombie', { kind = kind, uid = uid }, true)
    local z = { handle = handle, netId = NetworkGetNetworkIdFromEntity(handle), kind = kind, spawnedAt = now(),
        hp = GetEntityHealth(handle), uid = uid }
    zombies[handle] = z
    return z
end

local function requestSpawns(list)
    local night = isNight()
    local pop = M.config.population
    local total = count(true)
    for _, p in ipairs(list) do
        local near = 0
        for _, z in pairs(zombies) do
            if not z.dead and DoesEntityExist(z.handle) and Rules.dist2d(coordsOf(z.handle), p.coords) <= pop.despawnDistance then
                near = near + 1
            end
        end
        local n = Rules.toSpawn(pop, night, near, total + (pending[p.source] and pending[p.source].n or 0))
        if n > 0 and not pending[p.source] then
            pending[p.source] = { n = n, ring = { spawnMin = pop.spawnMin, spawnMax = pop.spawnMax } }
            TriggerClientEvent('wasteland:zombies:client:findSpawns', p.source, n, pop.spawnMin, pop.spawnMax)
            total = total + n
        end
    end
end

-- Points found by a client (untrusted: each one is checked).
local function spawnsFound(src, points)
    local req = pending[src]
    pending[src] = nil
    if not req or not (M and M.active) then return end
    local asked = req.n
    local list = activePlayers()
    local me
    for _, p in ipairs(list) do if p.source == src then me = p end end
    if not me then return end
    local night = isNight()
    local spawned = 0
    for _, point in ipairs(points) do
        if spawned >= asked or count(true) >= M.config.population.maxTotal then break end
        -- Checked against the ring that was asked for (admin spawns are closer).
        local ok = Rules.validSpawn(req.ring, point, me.coords, list)
        if ok and not inSafeZone(point) then
            if spawnAt(point, Rules.pickKind(M.config.kinds, night, math.random())) then spawned = spawned + 1 end
        end
    end
end

-------------------------------------------------------------------------------
-- Deaths, loot, despawning
-------------------------------------------------------------------------------

local function dropLoot(z)
    if GetResourceState('wasteland_inventory') ~= 'started' then return end
    -- With wasteland_loot running, the body itself is searched instead.
    if GetResourceState('wasteland_loot') == 'started' then return end
    local items = Rules.loot(M.config.loot, math.random(), math.random)
    if not items then return end
    local c = coordsOf(z.handle)
    local ok, id = pcall(function()
        return exports.wasteland_inventory:CreateLootDrop({ x = c.x, y = c.y, z = c.z - 0.9 }, items,
            { label = 'Zombie remains', lifetimeMinutes = M.config.loot.lifetimeMinutes })
    end)
    if not ok then M.log:warn('zombie loot failed: %s', tostring(id)) end
end

-- killer: server id of the player who killed it (0 = unknown).
local function markDead(z, cause, killer)
    if z.dead then return end
    z.dead, z.deadAt = true, now()
    TriggerEvent('wasteland:zombies:died', z.netId, z.kind, cause, killer or 0, coordsOf(z.handle))
    dropLoot(z)
end

local function maintain()
    local pop = M.config.population
    local list = activePlayers()
    local t = now()
    for _, z in pairs(zombies) do
        if not DoesEntityExist(z.handle) then
            zombies[z.handle] = nil
        elseif z.dead then
            if t - z.deadAt >= pop.corpseSeconds * 1000 then remove(z) end
        else
            if GetEntityHealth(z.handle) <= 0 then markDead(z, 'health') end
            local c = coordsOf(z.handle)
            if inSafeZone(c) then
                remove(z) -- wandered into a camp
                goto continue
            end
            local close = false
            for _, p in ipairs(list) do
                if Rules.dist2d(c, p.coords) <= pop.despawnDistance then close = true; break end
            end
            if close then
                z.farSince = nil
            elseif not z.farSince then
                z.farSince = t
            elseif t - z.farSince >= pop.despawnAfterSeconds * 1000 then
                remove(z)
            end
        end
        ::continue::
    end
    return list
end

local function loop(token)
    local sinceSpawn = 0
    while runToken == token do
        Citizen.Wait(1000)
        if runToken ~= token then return end
        local list = maintain()
        sinceSpawn = sinceSpawn + 1
        if sinceSpawn >= M.config.population.spawnIntervalSeconds then
            sinceSpawn = 0
            requestSpawns(list)
        end
    end
end

-------------------------------------------------------------------------------
-- Hits and noise
-------------------------------------------------------------------------------

local function zombieByNet(netId)
    local handle = NetworkGetEntityFromNetworkId(netId)
    return handle and zombies[handle] or nil
end

-- The client running a zombie says it hit a player. Checked: the reporter
-- owns the zombie, it is alive, close enough, and not hitting too often.
local function hit(src, netId, victim)
    local z = zombieByNet(netId)
    if not z or z.dead then return end
    local ps = Player(victim) and Player(victim).state
    if ps and ps.wlProtected then return end -- making a character / choosing where to start
    if NetworkGetEntityOwner(z.handle) ~= src then
        M.log:warn('player %d reported a hit by zombie %d it does not run', src, netId)
        return
    end
    local t = now()
    if z.lastHit and t - z.lastHit < M.config.attack.cooldownMs then return end
    local ped = GetPlayerPed(victim)
    if not ped or ped == 0 or not DoesEntityExist(ped) or survival('IsDead', victim) then return end
    if Rules.dist3d(coordsOf(z.handle), coordsOf(ped)) > M.config.attack.range + 1.0 then return end
    if inSafeZone(coordsOf(ped)) then return end
    z.lastHit = t
    local r = Rules.hit(M.config.kinds[z.kind], {
        damage = math.random(), infection = math.random(), infectionAmount = math.random(), bleeding = math.random(),
    })
    -- An armor plate (survival) takes the damage; then the hit cannot cut.
    local _, absorbed = survival('Damage', victim, r.damage)
    r.absorbed = absorbed == true
    if r.infection > 0 then survival('AddInfection', victim, r.infection) end
    if r.bleeding > 0 and not r.absorbed then survival('AddBleeding', victim, r.bleeding) end
    TriggerEvent('wasteland:zombies:hit', victim, z.netId, r)
end

-- Noise: zombies that hear it go and look.
local function noise(coords, radius)
    if not (M and M.active) or type(coords) ~= 'table' or type(coords.x) ~= 'number' then return end
    local list = {}
    for _, z in pairs(zombies) do
        if not z.dead and DoesEntityExist(z.handle) then list[#list + 1] = { id = z.handle, coords = coordsOf(z.handle) } end
    end
    for _, handle in ipairs(Rules.hearers(list, coords, tonumber(radius) or 0)) do
        Entity(handle).state:set('wlInvestigate', { x = coords.x, y = coords.y, z = coords.z,
            untilMs = M.config.noise.investigateSeconds * 1000, at = now() }, true)
    end
end

-- Gunshots and hits (weapons), and any other noise (lock picking, alarms).
AddEventHandler('wasteland:weapons:used', function(_, _, _, radius, coords) noise(coords, radius) end)
AddEventHandler('wasteland:noise', function(coords, radius) noise(coords, radius) end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then pending[src] = nil end
end)

-------------------------------------------------------------------------------
-- Admin command: /zombies count | clear | spawn <n>
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Sync check (/zombies sync): every player's game lists the zombies it shows
-- within SYNC_RADIUS; the server compares that with the zombies it has
-- there. Everyone should see every zombie near them.
-------------------------------------------------------------------------------

local SYNC_RADIUS = 150.0
local syncChecks, syncSeq = {}, 0

local function playerPos(src)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return coordsOf(ped)
end

local function startSyncCheck(reply)
    syncSeq = syncSeq + 1
    local seq = syncSeq
    local check = { expected = {}, replies = {}, names = {}, known = {} }
    for _, z in pairs(zombies) do
        if DoesEntityExist(z.handle) then check.known[z.netId] = true end
    end
    local asked = 0
    for _, s in ipairs(GetPlayers()) do
        local p = tonumber(s)
        local c = p and playerPos(p)
        if c then
            local list = {}
            for _, z in pairs(zombies) do
                if DoesEntityExist(z.handle) and Rules.dist3d(coordsOf(z.handle), c) <= SYNC_RADIUS then list[#list + 1] = z.netId end
            end
            check.expected[p], check.names[p] = list, GetPlayerName(s) or ('player ' .. p)
            asked = asked + 1
            TriggerClientEvent('wasteland:zombies:client:syncCheck', p, seq, SYNC_RADIUS)
        end
    end
    syncChecks[seq] = check
    reply(string.format('Sync check: asking %d player(s) which zombies they see within %d m...', asked, SYNC_RADIUS))
    Citizen.SetTimeout(3000, function()
        syncChecks[seq] = nil
        local bad = 0
        for p, expected in pairs(check.expected) do
            local seen = check.replies[p]
            if not seen then
                bad = bad + 1
                reply(string.format('  #%d %s: no answer (still loading, or the zombie script is not running in their game)', p, check.names[p]))
            else
                local missing, ghosts = Rules.compareSync(expected, seen, check.known)
                if #missing > 0 or #ghosts > 0 then bad = bad + 1 end
                reply(string.format('  #%d %s: sees %d of the %d zombies near them%s%s', p, check.names[p], #expected - #missing, #expected,
                    #missing > 0 and string.format(', MISSING %d', #missing) or '',
                    #ghosts > 0 and string.format(', %d the server does not have', #ghosts) or ''))
            end
        end
        reply(bad == 0 and 'Sync check: OK - every player sees every zombie near them.'
            or string.format('Sync check: %d player(s) out of sync (a zombie that just appeared can take a moment; run it again).', bad))
        M.log:info('zombie sync check: %d player(s) out of sync', bad)
    end)
end

local function adminCommand(src, args)
    local reply = function(msg)
        if src == 0 then print(msg) else TriggerClientEvent('wasteland:core:client:consoleOutput', src, { msg }) end
    end
    if src ~= 0 and not IsPlayerAceAllowed(tostring(src), 'wasteland.admin') then
        M.log:warn('player %d tried "%s" without the wasteland.admin ACE', src, M.config.adminCommand)
        return
    end
    local what = args[1]
    if what == 'clear' then
        local n = 0
        for _, z in pairs(zombies) do remove(z); n = n + 1 end
        reply(string.format('Removed %d zombies.', n))
    elseif what == 'sync' then
        startSyncCheck(reply)
    elseif what == 'spawn' and src ~= 0 then
        local n = math.max(1, math.min(20, math.tointeger(tonumber(args[2] or '5')) or 5))
        pending[src] = { n = n, ring = { spawnMin = 15, spawnMax = 35 } }
        TriggerClientEvent('wasteland:zombies:client:findSpawns', src, n, 15, 35)
        reply(string.format('Spawning up to %d zombies 15-35 m around you.', n))
    else
        reply(string.format('%d zombies (%d alive). Usage: %s count | clear | spawn <n> | sync', count(false), count(true), M.config.adminCommand))
    end
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local NUM = function(default, min, max) return { type = 'number', default = default, min = min, max = max } end
local INT = function(default, min, max) return { type = 'integer', default = default, min = min, max = max } end
local RANGE = function(a, b) return { type = 'array', default = { a, b }, minItems = 2, maxItems = 2, items = { type = 'number', min = 0, max = 400 } } end
-- A kind of zombie (zombies.lua `kinds`; any name, 'walker' is required).
local KIND = { type = 'table', fields = {
    speed = NUM(1.0, 0.5, 4), damage = RANGE(6, 10), infectionChance = NUM(0.25, 0, 1),
    infection = RANGE(6, 12), bleedingChance = NUM(0.15, 0, 1),
    chance = NUM(0, 0, 100), nightChance = NUM(0, 0, 100),
    shamble = { type = 'boolean', default = false, description = 'Stagger like a drunk when walking' },
    models = { type = 'array', default = {}, items = { type = 'string', pattern = '^[%w_]+$' },
        description = 'Models for this kind only (empty = the general models list)' },
} }
local commandRegistered = false

M = Wasteland.DefineModule({
    name = 'zombies',
    version = '0.1.0',
    description = 'Zombies: population around players, AI by the owning client, hits, noise, loot',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0' },
    optionalDependencies = { survival = '^0.1.0', inventory = '^0.1.0', weapons = '^0.1.0', world = '^0.1.0' },
    config = {
        file = 'zombies.lua',
        optional = true,
        schema = { type = 'table', fields = {
            population = { type = 'table', fields = {
                perPlayer = INT(8, 0, 50), nightMultiplier = NUM(1.5, 0, 5), maxTotal = INT(60, 0, 300),
                spawnMin = NUM(70, 10, 400), spawnMax = NUM(140, 20, 500), spawnBatch = INT(3, 1, 20),
                spawnIntervalSeconds = INT(6, 1, 120), despawnDistance = NUM(230, 50, 1000),
                despawnAfterSeconds = INT(20, 0, 600), corpseSeconds = INT(90, 5, 3600),
            } },
            kinds = { type = 'map', keys = { type = 'string', pattern = '^[a-z][a-z0-9_]*$', maxLength = 24 }, values = KIND,
                default = {
                    walker = { speed = 1.0, damage = { 6, 10 }, infectionChance = 0.25, infection = { 6, 12 }, bleedingChance = 0.15, shamble = true },
                    runner = { speed = 2.6, chance = 15, nightChance = 30, damage = { 5, 8 }, infectionChance = 0.2, infection = { 5, 10 },
                        bleedingChance = 0.2 },
                } },
            models = { type = 'array', minItems = 1, default = { 'u_m_y_zombie_01' }, items = { type = 'string', pattern = '^[%w_]+$' } },
            detection = { type = 'table', fields = {
                sightDay = NUM(35, 0, 200), sightNight = NUM(18, 0, 200), hearSprint = NUM(25, 0, 200),
                hearWalk = NUM(9, 0, 200), hearCrouch = NUM(3, 0, 200), loseSeconds = INT(10, 1, 120),
                alertRadius = NUM(0, 0, 100), -- a zombie that spots a player brings the others this close
            } },
            attack = { type = 'table', fields = { range = NUM(2.6, 0.5, 5), cooldownMs = INT(1500, 200, 10000) } },
            noise = { type = 'table', fields = { investigateSeconds = INT(40, 1, 600) } },
            loot = { type = 'table', fields = {
                chance = NUM(0.25, 0, 1), lifetimeMinutes = INT(15, 1, 1440),
                items = { type = 'array', default = {}, items = { type = 'table', fields = {
                    name = { type = 'string', required = true, pattern = '^[%w_]+$' },
                    min = INT(1, 1, 100000), max = INT(1, 1, 100000), weight = INT(1, 1, 1000),
                } } },
            } },
            adminCommand = { type = 'string', default = 'zombies', pattern = '^[a-z][a-z0-9_]*$' },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        if not M.config.kinds.walker then return false, 'zombies.lua: kinds must have a "walker" (the usual zombie)' end
        missingModels = {}
        local pop = M.config.population
        if pop.spawnMin >= pop.spawnMax then return false, 'zombies.lua: population.spawnMin must be below spawnMax' end
        for _, it in ipairs(M.config.loot.items) do
            if it.min > it.max then return false, string.format('zombies.lua: loot item "%s" has min above max', it.name) end
        end
        zombies, pending = {}, {}
        if not commandRegistered then
            RegisterCommand(M.config.adminCommand, function(source, args) adminCommand(tonumber(source) or 0, args) end, false)
            commandRegistered = true
        end
        local token = {}
        runToken = token
        Citizen.CreateThread(function() loop(token) end)
        return true
    end,
    onShutdown = function()
        runToken = nil
        for _, z in pairs(zombies) do remove(z) end
        zombies, pending = {}, {}
    end,
})

-- What the clients running zombie AI need to know.
local function clientConfig()
    -- Every model a zombie may use, so clients can say which they do not have.
    local all, seen = {}, {}
    local function add(list) for _, m in ipairs(list or {}) do if not seen[m] then seen[m] = true; all[#all + 1] = m end end end
    add(M.config.models)
    for _, k in pairs(M.config.kinds) do add(k.models) end
    return { detection = M.config.detection, attack = M.config.attack, kinds = M.config.kinds, models = all }
end

-- A client lists the zombie models its game does not have (custom models
-- not streamed, a typo): they are not used until the module restarts.
-- A player's answer to a sync check: the zombies their game shows.
M.netEvent('wasteland:zombies:server:syncReport', {
    args = { { type = 'integer', required = true, min = 1 },
        { type = 'array', required = true, maxItems = 500, items = { type = 'integer' } } },
    rateLimit = { burst = 3, perSecond = 1 },
}, function(src, seq, list)
    local check = syncChecks[seq]
    if check and check.expected[src] then check.replies[src] = list end
end)

M.netEvent('wasteland:zombies:server:missingModels', {
    args = { { type = 'array', required = true, maxItems = 100, items = { type = 'string', pattern = '^[%w_]+$', maxLength = 64 } } },
    rateLimit = { burst = 2, perSecond = 0.1 },
}, function(src, list)
    local known = {}
    for _, m in ipairs(clientConfig().models) do known[m] = true end
    for _, m in ipairs(list) do
        if known[m] and not missingModels[m] then
            missingModels[m] = true
            M.log:warn('zombie model "%s" is not in the game of player %d: not used (stream it with wasteland_zombiemodels, or check the name)', m, src)
        end
    end
end)

M.netEvent('wasteland:zombies:server:config', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    TriggerClientEvent('wasteland:zombies:client:config', src, clientConfig())
end)

AddEventHandler('wasteland:core:moduleState', function(name, state)
    if name == 'zombies' and state == 'running' and M then
        TriggerClientEvent('wasteland:zombies:client:config', -1, clientConfig())
    end
end)

local POINT = { type = 'table', fields = {
    x = { type = 'number', required = true }, y = { type = 'number', required = true }, z = { type = 'number', required = true },
} }

M.netEvent('wasteland:zombies:server:spawns', {
    args = { { type = 'array', required = true, maxItems = 20, items = POINT } },
    rateLimit = { burst = 3, perSecond = 1 },
}, function(src, points) spawnsFound(src, points) end)

M.netEvent('wasteland:zombies:server:hit', {
    args = { { type = 'integer', required = true, min = 1 }, { type = 'integer', required = true, min = 1, max = 65535 } },
    rateLimit = { burst = 10, perSecond = 6 },
}, function(src, netId, victim) hit(src, netId, victim) end)

M.netEvent('wasteland:zombies:server:died', {
    args = { { type = 'integer', required = true, min = 1 }, { type = 'integer', min = 0, max = 65535 } },
    rateLimit = { burst = 10, perSecond = 5 },
}, function(src, netId, killer)
    local z = zombieByNet(netId)
    if not z or z.dead then return end
    -- Only the client running it, and only when it really is hurt.
    if NetworkGetEntityOwner(z.handle) ~= src then return end
    if GetEntityHealth(z.handle) >= (z.hp or 200) then return end
    -- The killer must be a player near the body (quests count kills).
    if killer and killer > 0 then
        local ped = GetPlayerPed(killer)
        if not ped or ped == 0 or not DoesEntityExist(ped) or Rules.dist3d(coordsOf(ped), coordsOf(z.handle)) > 250 then killer = 0 end
    end
    markDead(z, 'reported', killer)
end)

-------------------------------------------------------------------------------
-- Exports (zombies api 0.1)
-------------------------------------------------------------------------------

--- GetZombieCount() -> total, alive
exports('GetZombieCount', function() return count(false), count(true) end)

--- SpawnZombie(coords, kind?) -> netId | nil   (scripted spawns: events, quests)
exports('SpawnZombie', function(coords, kind)
    if not (M and M.active) or type(coords) ~= 'table' then return nil end
    local z = spawnAt(coords, (type(kind) == 'string' and M.config.kinds[kind]) and kind or 'walker')
    return z and z.netId or nil
end)

--- GetZombieInfo(netId) -> { uid, kind, dead, coords } | nil
exports('GetZombieInfo', function(netId)
    local z = zombieByNet(tonumber(netId))
    if not z or not DoesEntityExist(z.handle) then return nil end
    return { uid = z.uid, kind = z.kind, dead = z.dead == true, coords = coordsOf(z.handle) }
end)

--- ClearZombies() -> number removed
exports('ClearZombies', function()
    local n = 0
    for _, z in pairs(zombies) do remove(z); n = n + 1 end
    return n
end)

--- SpawnNear(source, n) -> ok   (admin: up to n zombies 15-35 m around a player)
exports('SpawnNear', function(src, n)
    src = tonumber(src)
    if not (M and M.active) or not src then return false end
    n = math.max(1, math.min(20, math.tointeger(tonumber(n)) or 5))
    pending[src] = { n = n, ring = { spawnMin = 15, spawnMax = 35 } }
    TriggerClientEvent('wasteland:zombies:client:findSpawns', src, n, 15, 35)
    return true
end)
