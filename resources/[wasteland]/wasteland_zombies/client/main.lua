-- wasteland_zombies :: client/main.lua
-- 1. Finds spawn points on the ground around this player when the server
--    asks (the server checks them and creates the zombies).
-- 2. Runs the AI of every zombie this client owns (OneSync gives each
--    networked ped to one client): wander, notice players by sight and
--    sound, chase, attack (the server decides what a hit does), walk to
--    gunshots the server says they heard, report their death.

local Rules = WLZ.Rules
local cfg = nil        -- detection / attack / kinds, from the server
local brains = {}      -- ped handle -> { mode, target, lastSeen, nextTask, nextAttack, configured, investigate, reported }

local ATTACK_DICT, ATTACK_ANIM = 'melee@unarmed@streamed_variations', 'plyr_takedown_front_slap'
local WALK_CLIPSET = 'move_m@drunk@verydrunk'
local zombieGroup = nil

RegisterNetEvent('wasteland:zombies:client:config', function(c)
    if type(c) ~= 'table' then return end
    cfg = c
    -- Tell the server which zombie models this game does not have.
    local missing = {}
    for _, m in ipairs(c.models or {}) do
        if not IsModelInCdimage(GetHashKey(m)) then missing[#missing + 1] = m end
    end
    if #missing > 0 then TriggerServerEvent('wasteland:zombies:server:missingModels', missing) end
end)

-------------------------------------------------------------------------------
-- Spawn points
-------------------------------------------------------------------------------

local function groundAt(x, y, nearZ)
    for _, from in ipairs({ nearZ + 40.0, nearZ + 150.0, 900.0 }) do
        local found, z = GetGroundZFor_3dCoord(x, y, from, false)
        if found then return z end
    end
    return nil
end

RegisterNetEvent('wasteland:zombies:client:findSpawns', function(n, minDist, maxDist)
    n = math.max(0, math.min(20, math.tointeger(tonumber(n)) or 0))
    if n == 0 then return end
    local me = GetEntityCoords(PlayerPedId())
    local points, tries = {}, 0
    while #points < n and tries < n * 6 do
        tries = tries + 1
        local angle = math.random() * math.pi * 2
        local d = minDist + math.random() * (maxDist - minDist)
        local x, y = me.x + math.cos(angle) * d, me.y + math.sin(angle) * d
        local z = groundAt(x, y, me.z)
        if z then
            local ok, safe = GetSafeCoordForPed(x, y, z + 1.0, true, 16)
            local p = ok and safe or vector3(x, y, z)
            local water = GetWaterHeight(p.x, p.y, p.z)
            if not water then points[#points + 1] = { x = p.x, y = p.y, z = p.z } end
        end
    end
    TriggerServerEvent('wasteland:zombies:server:spawns', points)
end)

-------------------------------------------------------------------------------
-- AI
-------------------------------------------------------------------------------

local function zombieInfo(ped)
    local ok, state = pcall(function() return Entity(ped).state end)
    if not ok or not state then return nil end
    return state.wlZombie, state.wlInvestigate
end

-- Zombies and players are enemies (5 = hate). Without this the game treats
-- a zombie as a neutral bystander: no melee lock-on, and walking or swinging
-- into one gives the "bump" (feels like an invisible block). Set on every
-- game, not only the one running the zombie.
local function zombieRelations(ped)
    if not zombieGroup then
        local _, group = AddRelationshipGroup('WL_ZOMBIE')
        zombieGroup = group
        local player = GetHashKey('PLAYER')
        SetRelationshipBetweenGroups(0, zombieGroup, zombieGroup)
        SetRelationshipBetweenGroups(5, zombieGroup, player)
        SetRelationshipBetweenGroups(5, player, zombieGroup)
    end
    if ped and GetPedRelationshipGroupHash(ped) ~= zombieGroup then SetPedRelationshipGroupHash(ped, zombieGroup) end
end

local function configure(ped, kind)
    zombieRelations(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAbility(ped, 0)          -- no blocking or dodging the player's melee
    SetPedCombatMovement(ped, 0)
    SetPedCanEvasiveDive(ped, false)
    SetPedConfigFlag(ped, 281, true)   -- no writhing on the ground
    SetPedConfigFlag(ped, 100, false)  -- no drunk stagger interruptions
    SetPedSuffersCriticalHits(ped, true) -- headshots
    StopPedSpeaking(ped, true)
    DisablePedPainAudio(ped, true)
    SetAmbientVoiceName(ped, 'kerry') -- a voice with no ambient lines
    SetPedKeepTask(ped, true)
    TaskWanderStandard(ped, 10.0, 10)
end

-- How a zombie looks: blood and the stagger. Not shared over the network,
-- so every game applies it to every zombie it shows (not only the game that
-- runs the zombie), and all players see the same zombie.
local function dressUp(ped, kind)
    zombieRelations(ped)
    ApplyPedDamagePack(ped, 'BigHitByVehicle', 0.0, 9.0)
    ApplyPedDamagePack(ped, 'SCR_Dumpster', 0.0, 9.0)
    local k = cfg and cfg.kinds and cfg.kinds[kind]
    if k and k.shamble then
        RequestAnimSet(WALK_CLIPSET)
        local deadline = GetGameTimer() + 1000
        while not HasAnimSetLoaded(WALK_CLIPSET) and GetGameTimer() < deadline do Citizen.Wait(0) end
        if HasAnimSetLoaded(WALK_CLIPSET) and DoesEntityExist(ped) then SetPedMovementClipset(ped, WALK_CLIPSET, 1.0) end
    end
end

-- Sync check (/zombies sync): which zombies does this game show near us?
RegisterNetEvent('wasteland:zombies:client:syncCheck', function(seq, radius)
    local me = GetEntityCoords(PlayerPedId())
    local list = {}
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) and #(GetEntityCoords(ped) - me) <= (tonumber(radius) or 150.0) then
            local info = zombieInfo(ped)
            if info then list[#list + 1] = NetworkGetNetworkIdFromEntity(ped) end
        end
    end
    TriggerServerEvent('wasteland:zombies:server:syncReport', seq, list)
end)

-- Players inside a safe zone (camp) are left alone.
local function safe(target)
    local at = GetEntityCoords(target)
    if GetResourceState('wasteland_camps') == 'started' then
        local ok, yes = pcall(function() return exports.wasteland_camps:IsInSafeZone(at) end)
        if ok and yes == true then return true end
    end
    if GetResourceState('wasteland_basebuilding') == 'started' then
        local ok, yes = pcall(function() return exports.wasteland_basebuilding:IsInBaseZone(at) end)
        if ok and yes == true then return true end
    end
    return false
end

-- Who can this zombie sense? Nearest living player it sees or hears.
local function sense(ped, night)
    local d = cfg.detection
    local zc = GetEntityCoords(ped)
    local best, bestDist = nil, math.huge
    for _, pl in ipairs(GetActivePlayers()) do
        local target = GetPlayerPed(pl)
        local ps = Player(GetPlayerServerId(pl)).state
        if target ~= 0 and not IsEntityDead(target) and not safe(target) and not (ps and ps.wlProtected) then
            local dist = #(GetEntityCoords(target) - zc)
            if dist < bestDist then
                local sight = night and d.sightNight or d.sightDay
                local hear = d.hearWalk
                if GetPedStealthMovement(target) then hear = d.hearCrouch
                elseif IsPedSprinting(target) or IsPedRunning(target) then hear = d.hearSprint end
                if IsPedInAnyVehicle(target, false) then hear = math.max(hear, d.hearSprint) end
                local heard = dist <= hear
                local seen = dist <= sight and HasEntityClearLosToEntity(ped, target, 17)
                if heard or seen then best, bestDist = target, dist end
            end
        end
    end
    return best, bestDist
end

-- Does a swing that lands now hit `target`? Within reach, in front of the
-- zombie (about 60 degrees either side), a clear line, not in a vehicle.
local function landed(ped, target)
    if not target or not DoesEntityExist(target) or IsEntityDead(target) or IsPedInAnyVehicle(target, false) then return false end
    local zc, pc = GetEntityCoords(ped), GetEntityCoords(target)
    local reach = cfg.attack.hitReach or 1.7
    if #(pc - zc) > reach then return false end
    local fwd = GetEntityForwardVector(ped)
    local to = pc - zc
    local len = math.sqrt(to.x * to.x + to.y * to.y)
    if len > 0.3 and (fwd.x * to.x + fwd.y * to.y) / len < 0.5 then return false end
    return HasEntityClearLosToEntity(ped, target, 17)
end

local function playAttack(ped)
    RequestAnimDict(ATTACK_DICT)
    if HasAnimDictLoaded(ATTACK_DICT) then
        TaskPlayAnim(ped, ATTACK_DICT, ATTACK_ANIM, 8.0, -8.0, 900, 48, 0.0, false, false, false)
    end
end

-- Chasing within reach: the swing (it hits only if the target is still in
-- reach, in front, with nothing in between, when it lands) or keep after
-- them. mods (special infected): { windupMult, cooldownMult }.
local function chaseStep(ped, b, dist, speed, mods)
    local t = GetGameTimer()
    mods = mods or {}
    if b.swing and t >= b.swing.at then
        -- The swing lands now: it hits only if the player is still within
        -- reach, in front of the zombie, with nothing in between.
        local target = b.swing.target
        b.swing = nil
        if landed(ped, target) then
            local player = NetworkGetPlayerIndexFromPed(target)
            if player ~= -1 then
                TriggerServerEvent('wasteland:zombies:server:hit', NetworkGetNetworkIdFromEntity(ped), GetPlayerServerId(player))
            end
        end
    end
    if dist <= cfg.attack.range then
        if t >= (b.nextAttack or 0) and not b.swing then
            -- Start a swing; whether it hits is decided when it lands.
            b.nextAttack = t + cfg.attack.cooldownMs * (mods.cooldownMult or 1)
            TaskTurnPedToFaceEntity(ped, b.target, 300)
            playAttack(ped)
            b.swing = { target = b.target, at = t + (cfg.attack.windupMs or 450) * (mods.windupMult or 1) }
        end
    elseif t >= (b.nextTask or 0) then
        b.nextTask = t + 1000
        TaskGoToEntity(ped, b.target, -1, cfg.attack.range * 0.6, speed, 1073741824, 0)
    end
end

local function think(ped, b, info, investigate, night)
    -- The upgraded AI (client/ai.lua), when zombies.lua `ai.enabled` is on.
    if cfg.ai and cfg.ai.enabled and WLZ.Brain then return WLZ.Brain.think(ped, b, info, investigate, night) end
    local kind = info.kind
    local t = GetGameTimer()
    local k = cfg.kinds[kind] or cfg.kinds.walker
    local target, dist = sense(ped, night)
    if target then
        local fresh = b.mode ~= 'chase'
        b.mode, b.target, b.lastSeen = 'chase', target, t
        -- It spotted someone: the others close by come too.
        local radius = cfg.detection.alertRadius or 0
        if fresh and radius > 0 then
            local here = GetEntityCoords(ped)
            for other, ob in pairs(brains) do
                if other ~= ped and ob.mode ~= 'chase' and ob.configured and DoesEntityExist(other) and not IsPedDeadOrDying(other, true)
                    and #(GetEntityCoords(other) - here) <= radius then
                    ob.mode, ob.target, ob.lastSeen, ob.nextTask = 'chase', target, t, 0
                end
            end
        end
    elseif b.mode == 'chase' and (not DoesEntityExist(b.target) or IsEntityDead(b.target) or safe(b.target)
        or t - b.lastSeen > cfg.detection.loseSeconds * 1000) then
        b.mode, b.target, b.nextTask = 'idle', nil, 0
    end

    if b.mode ~= 'chase' and type(investigate) == 'table' and investigate.at ~= b.heardAt then
        -- A new noise: go and look.
        b.heardAt = investigate.at
        b.mode, b.investigate, b.investigateUntil = 'investigate', investigate, t + (investigate.untilMs or 30000)
        b.nextTask = 0
    end

    if b.mode == 'chase' and b.target then
        dist = dist or #(GetEntityCoords(b.target) - GetEntityCoords(ped))
        chaseStep(ped, b, dist, k.speed)
    elseif b.mode == 'investigate' then
        local i = b.investigate
        if t > b.investigateUntil or #(vector3(i.x, i.y, i.z) - GetEntityCoords(ped)) < 4.0 then
            b.mode, b.nextTask = 'idle', 0
        elseif t >= (b.nextTask or 0) then
            b.nextTask = t + 4000
            TaskGoToCoordAnyMeans(ped, i.x, i.y, i.z, math.max(1.0, k.speed * 0.8), 0, false, 786603, 0xbf800000)
        end
    elseif t >= (b.nextTask or 0) then
        b.mode, b.nextTask = 'idle', t + 20000
        TaskWanderStandard(ped, 10.0, 10)
    end
end

Citizen.CreateThread(function()
    TriggerServerEvent('wasteland:zombies:server:config')
    while true do
        Citizen.Wait(250)
        if cfg then
            local hour = GetClockHours()
            local night = Rules.isNight(hour)
            local seen = {}
            for _, ped in ipairs(GetGamePool('CPed')) do
                if not IsPedAPlayer(ped) then
                    local info, investigate = zombieInfo(ped)
                    if info then
                        seen[ped] = true
                        local b = brains[ped]
                        if not b then b = { mode = 'idle' }; brains[ped] = b end
                        if not b.dressed then
                            b.dressed = true
                            dressUp(ped, info.kind)
                            if WLZ.Brain then WLZ.Brain.dress(ped, info) end
                        end
                        if IsPedDeadOrDying(ped, true) then
                            if not b.reported and NetworkGetEntityIsNetworked(ped) and NetworkHasControlOfEntity(ped) then
                                b.reported = true
                                -- Who killed it (a player), for quests.
                                local source = GetPedSourceOfDeath(ped)
                                -- run over: the driver killed it
                                if source and source ~= 0 and IsEntityAVehicle(source) then source = GetPedInVehicleSeat(source, -1) end
                                local killer = 0
                                if source and source ~= 0 and IsEntityAPed(source) and IsPedAPlayer(source) then
                                    local pl = NetworkGetPlayerIndexFromPed(source)
                                    if pl ~= -1 then killer = GetPlayerServerId(pl) end
                                end
                                if killer == 0 then
                                    -- the game did not say: the nearest player who hurt it
                                    local best, bestD = nil, 60.0
                                    for _, pl in ipairs(GetActivePlayers()) do
                                        local pp = GetPlayerPed(pl)
                                        if pp ~= 0 and HasEntityBeenDamagedByEntity(ped, pp, true) then
                                            local d = #(GetEntityCoords(pp) - GetEntityCoords(ped))
                                            if d < bestD then best, bestD = pl, d end
                                        end
                                    end
                                    if best then killer = GetPlayerServerId(best) end
                                end
                                TriggerServerEvent('wasteland:zombies:server:died', NetworkGetNetworkIdFromEntity(ped), killer)
                            end
                        elseif NetworkHasControlOfEntity(ped) then
                            if not b.configured then
                                b.configured = true
                                configure(ped, info.kind)
                                if cfg.ai and cfg.ai.enabled and WLZ.Brain then WLZ.Brain.configure(ped, info) end
                            end
                            think(ped, b, info, investigate, night)
                            if WLZ.Brain then WLZ.Brain.defense(ped, b) end -- barbed wire, spikes
                        else
                            b.configured = false -- another client runs it; configure again if it comes back
                        end
                    end
                end
            end
            for ped in pairs(brains) do if not seen[ped] then brains[ped] = nil end end
        end
    end
end)

-- What the upgraded brain (client/ai.lua) uses from here.
WLZ.Client = {
    brains = brains,
    cfg = function() return cfg end,
    safe = safe,
    chaseStep = chaseStep,
    playAttack = playAttack,
}

--- GetZombieMode(ped) -> 'idle' | 'chase' | 'investigate' | (with ai) 'stalk' | 'search' | 'sleep' | 'ambush' | 'return' | nil   (admin overlay;
--- only for zombies this client runs, others return nil)
exports('GetZombieMode', function(ped)
    local b = brains[ped]
    return b and b.configured and b.mode or nil
end)
