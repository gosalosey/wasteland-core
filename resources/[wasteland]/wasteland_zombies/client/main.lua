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

local ATTACK_DICT, ATTACK_ANIM = 'melee@unarmed@streamed_variations', 'plyr_takedown_front_slap' -- fallback
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

-- Spawn points for a wandering horde: around its centre.
RegisterNetEvent('wasteland:zombies:client:findHordeSpawns', function(id, center, n, spread)
    if type(center) ~= 'table' then return end
    n = math.max(0, math.min(30, math.tointeger(tonumber(n)) or 0))
    spread = math.max(5.0, math.min(60.0, tonumber(spread) or 18.0))
    local points, tries = {}, 0
    while #points < n and tries < n * 6 do
        tries = tries + 1
        local angle, d = math.random() * math.pi * 2, math.random() * spread
        local x, y = center.x + math.cos(angle) * d, center.y + math.sin(angle) * d
        local z = groundAt(x, y, center.z)
        if z then
            local ok, safe = GetSafeCoordForPed(x, y, z + 1.0, true, 16)
            local p = ok and safe or vector3(x, y, z)
            if #(vector2(p.x, p.y) - vector2(center.x, center.y)) <= spread + 10.0 and not GetWaterHeight(p.x, p.y, p.z) then
                points[#points + 1] = { x = p.x, y = p.y, z = p.z }
            end
        end
    end
    TriggerServerEvent('wasteland:zombies:server:hordeSpawns', id, points)
end)

-- A wandering horde is near.
RegisterNetEvent('wasteland:zombies:client:hordeWarning', function(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(true, false)
    PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
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
local warnedLook = {}
local function dressUp(ped, kind, look)
    zombieRelations(ped)
    if type(look) == 'table' and tonumber(look[1]) then
        local head, tex = math.floor(look[1]), math.floor(tonumber(look[2]) or 0)
        local n = GetNumberOfPedDrawableVariations(ped, 0)
        if head < n then
            SetPedComponentVariation(ped, 0, head, tex, 0)
        elseif not warnedLook[head] then
            warnedLook[head] = true
            print(('[wasteland_zombies] zombie look %d not available: this model has %d looks (are its files streamed?)'):format(head, n))
        end
    end
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
        if target ~= 0 and not IsEntityDead(target) and not safe(target) and not (ps and (ps.wlProtected or ps.wlMasked)) then
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
-- zombie (about 60 degrees either side), a clear line. Someone in a vehicle
-- is hit through the door / window (a little further: vehicleReach).
local function landed(ped, target)
    if not target or not DoesEntityExist(target) or IsEntityDead(target) then return false end
    local zc, pc = GetEntityCoords(ped), GetEntityCoords(target)
    local inVehicle = IsPedInAnyVehicle(target, false)
    local reach = inVehicle and (cfg.attack.vehicleReach or 3.0) or (cfg.attack.hitReach or 1.7)
    if #(pc - zc) > reach then return false end
    if inVehicle then return true end
    local fwd = GetEntityForwardVector(ped)
    local to = pc - zc
    local len = math.sqrt(to.x * to.x + to.y * to.y)
    if len > 0.3 and (fwd.x * to.x + fwd.y * to.y) / len < 0.5 then return false end
    return HasEntityClearLosToEntity(ped, target, 17)
end

-- A random zombie attack (zombies.lua attack.anims); headingOffset turns
-- the zombie so a sideways animation still swings at the target.
local function playAttack(ped, target)
    local a = cfg.attack
    local list = a.anims or {}
    local pick = #list > 0 and list[math.random(1, #list)] or nil
    local dict = a.animDict
    if pick and dict then
        RequestAnimDict(dict)
        local untilT = GetGameTimer() + 300
        while not HasAnimDictLoaded(dict) and GetGameTimer() < untilT do Citizen.Wait(0) end
        if HasAnimDictLoaded(dict) then
            if target and DoesEntityExist(target) and (pick.headingOffset or 0) ~= 0 then
                local zc, pc = GetEntityCoords(ped), GetEntityCoords(target)
                SetEntityHeading(ped, GetHeadingFromVector_2d(pc.x - zc.x, pc.y - zc.y) + pick.headingOffset)
            end
            TaskPlayAnim(ped, dict, pick.name, 8.0, -8.0, -1, 48, 0.0, false, false, false)
            return
        end
    end
    RequestAnimDict(ATTACK_DICT)
    if HasAnimDictLoaded(ATTACK_DICT) then
        TaskPlayAnim(ped, ATTACK_DICT, ATTACK_ANIM, 8.0, -8.0, 900, 48, 0.0, false, false, false)
    end
end

-- A zombie knocked this player down.
RegisterNetEvent('wasteland:zombies:client:knockdown', function(ms)
    ms = math.max(300, math.min(5000, tonumber(ms) or 1500))
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    SetPedToRagdoll(ped, ms, ms, 0, false, false, false)
end)

-- A zombie hit this player's vehicle: the engine takes damage, and it may
-- drag them out (then they fall).
RegisterNetEvent('wasteland:zombies:client:vehicleHit', function(engineDamage, pullOut, ragdollMs)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return end
    engineDamage = math.max(0.0, math.min(1000.0, tonumber(engineDamage) or 0.0))
    if engineDamage > 0 and GetPedInVehicleSeat(veh, -1) == ped then
        SetVehicleEngineHealth(veh, math.max(-100.0, GetVehicleEngineHealth(veh) - engineDamage))
    end
    if pullOut then
        TaskLeaveVehicle(ped, veh, 4160) -- thrown out right away
        local ms = math.max(0, math.min(5000, tonumber(ragdollMs) or 1500))
        if ms > 0 then
            SetTimeout(700, function()
                local p = PlayerPedId()
                if not IsPedInAnyVehicle(p, false) then SetPedToRagdoll(p, ms, ms, 0, false, false, false) end
            end)
        end
    end
end)

-- Chasing within reach: the swing (it hits only if the target is still in
-- reach, in front, with nothing in between, when it lands) or keep after
-- them. mods (special infected): { windupMult, cooldownMult }.
local function chaseStep(ped, b, dist, speed, mods)
    local t = GetGameTimer()
    mods = mods or {}
    if b.stunUntil and t < b.stunUntil then return end -- just got hit (hit reactions)
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
            playAttack(ped, b.target)
            b.swing = { target = b.target, at = t + (cfg.attack.windupMs or 450) * (mods.windupMult or 1) }
        end
    elseif t >= (b.nextTask or 0) then
        b.nextTask = t + 1000
        TaskGoToEntity(ped, b.target, -1, cfg.attack.range * 0.6, speed, 1073741824, 0)
    end
end

-------------------------------------------------------------------------------
-- Hit reactions (zombies.lua `hitReaction`): a melee hit stuns the zombie for
-- a moment and cancels the swing it was winding up; heavy weapons can knock
-- it off balance (a short stagger). Done by the game that runs the zombie.
-------------------------------------------------------------------------------

local HIT_DEFAULTS = { enabled = true, stunMs = 600, staggerChance = 0.15, heavyStaggerChance = 0.5, ragdollMs = 900,
    heavyWeapons = { 'WEAPON_BAT', 'WEAPON_HATCHET', 'WEAPON_BATTLEAXE', 'WEAPON_HAMMER', 'WEAPON_WRENCH', 'WEAPON_CROWBAR', 'WEAPON_MACHETE' } }
local heavyHashes, heavyFrom = {}, nil

local function hitSettings()
    local hr = (cfg and cfg.hitReaction) or {}
    local out = {}
    for k, v in pairs(HIT_DEFAULTS) do out[k] = hr[k] == nil and v or hr[k] end
    if heavyFrom ~= out.heavyWeapons then
        heavyFrom, heavyHashes = out.heavyWeapons, {}
        for _, n in ipairs(out.heavyWeapons or {}) do heavyHashes[GetHashKey(n)] = true end
    end
    return out
end

local function react(ped, b, weapon)
    local hr = hitSettings()
    if not hr.enabled or IsPedDeadOrDying(ped, true) then return end
    local t = GetGameTimer()
    b.reactedAt = t
    b.swing = nil                                           -- the swing it was winding up never lands
    b.stunUntil = t + hr.stunMs
    b.nextAttack = math.max(b.nextAttack or 0, t + hr.stunMs + 200)
    local heavy = weapon and heavyHashes[weapon]
    if math.random() < (heavy and hr.heavyStaggerChance or hr.staggerChance) and not IsPedRagdoll(ped) then
        SetPedToRagdoll(ped, hr.ragdollMs, hr.ragdollMs, 0, false, false, false)
    else
        ClearPedTasks(ped)                                  -- a flinch: it stops in its tracks
    end
end

local function isMelee(weapon) return weapon and weapon ~= 0 and GetWeaponDamageType(weapon) == 2 end

-- The game reports the hit at once (on the game that runs the zombie, when
-- that is this one).
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not cfg then return end
    local victim, weapon = args[1], args[7]
    local b = brains[victim]
    if not b or not b.configured or not NetworkHasControlOfEntity(victim) or not isMelee(weapon) then return end
    react(victim, b, weapon)
    b.hp = GetEntityHealth(victim)
end)

-- A hit the event did not bring here (another game reported it): noticed
-- from the health on the next think.
local function hitCheck(ped, b)
    local hp = GetEntityHealth(ped)
    if b.hp and hp < b.hp and hp > 0 and GetGameTimer() - (b.reactedAt or 0) > 400 and HasEntityBeenDamagedByWeapon(ped, 0, 1) then
        local weapon
        for hash in pairs(heavyHashes) do if HasEntityBeenDamagedByWeapon(ped, hash, 0) then weapon = hash; break end end
        react(ped, b, weapon)
        ClearEntityLastWeaponDamage(ped)
    end
    b.hp = hp
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
                            dressUp(ped, info.kind, info.look)
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
                            hitCheck(ped, b)
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
    isZombie = function(ped) return zombieInfo(ped) ~= nil end,
    chaseStep = chaseStep,
    playAttack = playAttack,
}

--- GetZombieMode(ped) -> 'idle' | 'chase' | 'investigate' | (with ai) 'stalk' | 'search' | 'sleep' | 'ambush' | 'return' | nil   (admin overlay;
--- only for zombies this client runs, others return nil)
exports('GetZombieMode', function(ped)
    local b = brains[ped]
    return b and b.configured and b.mode or nil
end)

-- /zcheck [model ...]: does this game have these zombie models (F8 shows the result)?
RegisterCommand('zcheck', function(_, args)
    for _, m in ipairs(#args > 0 and args or { 'u_m_y_zombie_01' }) do
        local hash = GetHashKey(m)
        local line = ('[zcheck] %s: in game %s, valid %s'):format(m, tostring(IsModelInCdimage(hash)), tostring(IsModelValid(hash)))
        if IsModelInCdimage(hash) then
            RequestModel(hash)
            local t = GetGameTimer() + 5000
            while not HasModelLoaded(hash) and GetGameTimer() < t do Citizen.Wait(0) end
            line = line .. ', loaded ' .. tostring(HasModelLoaded(hash))
            if HasModelLoaded(hash) then
                local c = GetEntityCoords(PlayerPedId())
                local ped = CreatePed(4, hash, c.x, c.y, c.z - 20.0, 0.0, false, false)
                line = line .. (', looks %d'):format(GetNumberOfPedDrawableVariations(ped, 0))
                DeleteEntity(ped)
                SetModelAsNoLongerNeeded(hash)
            end
        end
        print(line)
    end
end, false)
