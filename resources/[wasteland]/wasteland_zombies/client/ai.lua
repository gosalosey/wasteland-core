-- wasteland_zombies :: client/ai.lua
-- The upgraded zombie brain (zombies.lua `ai`). client/main.lua hands a
-- zombie it runs to Brain.think when `ai.enabled` is on; otherwise its
-- original think runs unchanged. It reuses main.lua's swing / hit check
-- (WLZ.Client.chaseStep), so hits are reported and checked as before.
--
-- Modes: idle (wander) | sleep | ambush | stalk | chase | search |
-- investigate | return. Personality and special infected come from the
-- zombie's uid (shared/ai.lua), so whichever game runs it agrees.

local AI = WLZ.AI
local Brain = {}
WLZ.Brain = Brain

local ALERT = { chase = true, stalk = true }
-- (breach: attacking a wall / door / gate between it and its target)
local SLEEP_DICT, SLEEP_ANIM = 'dead', 'dead_a'
local SCREAM_DICT, SCREAM_ANIM = 'anim@mp_player_intcelebrationmale@freakout', 'freakout'
local SPIT_DICT, SPIT_ANIM = 'random@drunk_driver_1', 'vomit_outside'

local function C() return WLZ.Client end
local function tbl(v) return { x = v.x, y = v.y, z = v.z } end
local function v3(p) return vector3(p.x, p.y, p.z) end

local function loadDict(d)
    if HasAnimDictLoaded(d) then return true end
    RequestAnimDict(d)
    local untilT = GetGameTimer() + 1000
    while not HasAnimDictLoaded(d) and GetGameTimer() < untilT do Citizen.Wait(0) end
    return HasAnimDictLoaded(d)
end

local function goTo(ped, p, speed)
    TaskGoToCoordAnyMeans(ped, p.x + 0.0, p.y + 0.0, p.z + 0.0, math.max(1.0, speed), 0, false, 786603, 0xbf800000)
end

-------------------------------------------------------------------------------
-- Who this zombie is
-------------------------------------------------------------------------------

local function profile(b, info, ai, phaseName, t)
    if not b.specialChecked then
        b.specialChecked = true
        b.special, b.sp = AI.special(ai, info.uid)
    end
    local function pick()
        local was = b.personality
        b.personality, b.phaseName, b.repickAt = AI.personality(ai, info.uid, phaseName, phaseName), phaseName, nil
        if b.special == 'hunter' then b.personality = 'stalker' end
        if b.special == 'nightterror' then b.personality = phaseName == 'night' and 'stalker' or 'sleeper' end
        if was and was ~= b.personality then b.home = nil; b.nextTask = 0 end
    end
    if not b.personality then pick()
    elseif b.phaseName ~= phaseName then
        -- the time of day changed: pick again, a few zombies at a time, only when calm
        b.repickAt = b.repickAt or (t + math.floor(AI.roll(info.uid, 'stagger') * 60000))
        if not ALERT[b.mode] and b.mode ~= 'investigate' and b.mode ~= 'search' and t >= b.repickAt then
            if b.mode == 'sleep' or b.mode == 'ambush' then ClearPedTasks(b.ped); b.mode = 'idle' end
            pick()
        end
    end
end

-- Special infected: health, armour (once, when it is new) and walking style
-- (every game, it is not synced).
function Brain.configure(ped, info)
    local ai = C().cfg().ai
    local _, sp = AI.special(ai, info.uid)
    if not sp then return end
    if sp.health and GetEntityMaxHealth(ped) ~= sp.health then
        local fresh = GetEntityHealth(ped) >= GetEntityMaxHealth(ped)
        SetEntityMaxHealth(ped, sp.health)
        if fresh then
            SetEntityHealth(ped, sp.health)
            if sp.armour then SetPedArmour(ped, sp.armour) end
        end
    end
end

function Brain.dress(ped, info)
    local cfg = C().cfg()
    if not (cfg and cfg.ai and cfg.ai.enabled) then return end
    local _, sp = AI.special(cfg.ai, info.uid)
    if not sp or type(sp.clipset) ~= 'string' then return end
    RequestAnimSet(sp.clipset)
    local deadline = GetGameTimer() + 1000
    while not HasAnimSetLoaded(sp.clipset) and GetGameTimer() < deadline do Citizen.Wait(0) end
    if HasAnimSetLoaded(sp.clipset) and DoesEntityExist(ped) then SetPedMovementClipset(ped, sp.clipset, 1.0) end
end

-------------------------------------------------------------------------------
-- Senses
-------------------------------------------------------------------------------

-- The nearest living player this zombie sees or hears.
-- -> target ped, distance, seen (bool), isolated (bool)
local function sense(ped, b, ai, phaseName, phase, night)
    local d = C().cfg().detection
    local pers = ai.personalities[b.personality] or {}
    local zc = GetEntityCoords(ped)
    local fwd = GetEntityForwardVector(ped)
    local list = {}
    for _, pl in ipairs(GetActivePlayers()) do
        local target = GetPlayerPed(pl)
        local ps = Player(GetPlayerServerId(pl)).state
        if target ~= 0 and not IsEntityDead(target) and not (ps and ps.wlProtected) then
            list[#list + 1] = { ped = target, pos = GetEntityCoords(target) }
        end
    end
    local best, bestDist, bestSeen, bestPos
    for _, p in ipairs(list) do
        local dist = #(p.pos - zc)
        if dist < (bestDist or 250.0) and not C().safe(p.ped) then
            local veh = GetVehiclePedIsIn(p.ped, false)
            local speed = GetEntitySpeed(p.ped)
            local crouching = GetPedStealthMovement(p.ped)
            local running = IsPedSprinting(p.ped) or IsPedRunning(p.ped)
            local hear = AI.hearRange(ai.senses, { walk = d.hearWalk, crouch = d.hearCrouch, sprint = d.hearSprint,
                crouching = crouching, running = running, still = speed < 0.3 and veh == 0,
                vehicle = veh ~= 0 and GetIsVehicleEngineRunning(veh), vehicleMoving = veh ~= 0 and GetEntitySpeed(veh) > 2.0 })
            local specialSight = (b.sp and b.sp.nightSightMult and phaseName == 'night') and b.sp.nightSightMult or 1
            local sight = AI.sightRange(ai.senses, { base = night and d.sightNight or d.sightDay, phaseSight = phase.sight,
                specialSight = specialSight, inFront = AI.inFront(ai.senses, fwd, zc, p.pos), speed = speed,
                sprinting = IsPedSprinting(p.ped) })
            if b.mode == 'sleep' then
                -- asleep: only someone very close (or a loud noise) wakes it
                hear, sight = (pers.wakeRadius or 7) * (crouching and 0.5 or 1), 0
            elseif b.mode == 'ambush' then
                hear = math.max(hear, pers.triggerRadius or 9)
            end
            local heard = dist <= hear
            local seen = (not heard or b.mode ~= 'sleep') and dist <= sight and HasEntityClearLosToEntity(ped, p.ped, 17)
            if heard or seen then best, bestDist, bestSeen, bestPos = p.ped, dist, seen, p.pos end
        end
    end
    local isolated = true
    if best and b.sp and b.sp.isolation then
        local others = {}
        for _, p in ipairs(list) do if p.ped ~= best then others[#others + 1] = p.pos end end
        isolated = AI.isolated(bestPos, others, b.sp.isolation)
    end
    return best, bestDist, bestSeen, isolated
end

-------------------------------------------------------------------------------
-- Special infected actions
-------------------------------------------------------------------------------

-- Screamer / howler / alpha: a call the server turns into a horde alert.
local function shout(ped, b, t, kind, cooldownSeconds)
    if t < (b.nextShout or 0) then return end
    b.nextShout = t + (cooldownSeconds or 30) * 1000
    b.busyUntil = t + 2200
    ClearPedTasks(ped)
    if loadDict(SCREAM_DICT) then TaskPlayAnim(ped, SCREAM_DICT, SCREAM_ANIM, 8.0, -8.0, 2000, 0, 0.0, false, false, false) end
    DisablePedPainAudio(ped, false)
    PlayPain(ped, kind == 'howl' and 8 or 7, 0.0)
    TriggerServerEvent('wasteland:zombies:server:shout', NetworkGetNetworkIdFromEntity(ped), kind)
end

-- Spitter: a telegraphed ranged attack (it stops, retches, then spits).
local function spitStep(ped, b, t, dist)
    local sp = b.sp
    if b.spit then
        if t >= b.spit.at then
            local target = b.spit.target
            b.spit = nil
            RequestNamedPtfxAsset('scr_amb_chop')
            if HasNamedPtfxAssetLoaded('scr_amb_chop') then
                UseParticleFxAssetNextCall('scr_amb_chop')
                local fx = StartParticleFxLoopedOnEntityBone('ent_anim_dog_peeing', ped, 0.1, 0.15, 0.0, 0.0, 0.0, 0.0,
                    GetPedBoneIndex(ped, 31086), 1.5, false, false, false)
                SetTimeout(900, function() StopParticleFxLooped(fx, false) end)
            end
            if DoesEntityExist(target) and not IsEntityDead(target)
                and #(GetEntityCoords(target) - GetEntityCoords(ped)) <= sp.range + 1.0 and HasEntityClearLosToEntity(ped, target, 17) then
                local pl = NetworkGetPlayerIndexFromPed(target)
                if pl ~= -1 then
                    TriggerServerEvent('wasteland:zombies:server:spit', NetworkGetNetworkIdFromEntity(ped), GetPlayerServerId(pl))
                end
            end
        end
        return true
    end
    if dist >= (sp.minRange or 4) and dist <= sp.range and t >= (b.nextSpit or 0) and HasEntityClearLosToEntity(ped, b.target, 17) then
        b.nextSpit = t + sp.cooldownSeconds * 1000
        ClearPedTasks(ped)
        TaskTurnPedToFaceEntity(ped, b.target, 600)
        if loadDict(SPIT_DICT) then TaskPlayAnim(ped, SPIT_DICT, SPIT_ANIM, 8.0, -8.0, 1600, 0, 0.0, false, false, false) end
        b.spit = { at = t + 1200, target = b.target }
        b.busyUntil = t + 1700
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Engaging, losing, giving up
-------------------------------------------------------------------------------

local function startStalk(b, t, pers)
    b.mode, b.swing, b.nextTask = 'stalk', nil, 0
    b.stalkUntil = t + AI.between(pers.stalkSeconds, math.random()) * 1000
    b.stalkDist = AI.between(pers.keepDistance, math.random())
    b.stalkTurn = (math.random() < 0.5 and -1 or 1) * math.rad(30 + math.random() * 40)
end

local function engage(ped, b, target, t, ai)
    local pers = ai.personalities[b.personality] or {}
    if b.mode == 'sleep' or b.mode == 'ambush' then ClearPedTasks(ped) end
    b.target, b.nextTask, b.spotAt, b.swing = target, 0, nil, nil
    b.chase = { startedAt = t, from = tbl(GetEntityCoords(ped)) }
    if b.personality == 'stalker' then
        startStalk(b, t, pers)
    else
        b.mode, b.chargeAt = 'chase', t
    end
    if b.personality == 'sprinter' then b.sprintUntil, b.recoverUntil = t + pers.sprintSeconds * 1000, nil end
    if b.special == 'screamer' then shout(ped, b, t, 'scream', b.sp.cooldownSeconds)
    elseif b.special == 'howler' or b.special == 'alpha' then shout(ped, b, t, 'howl', b.sp.cooldownSeconds) end
    -- the original alert: others close by come too (each in its own way)
    local radius = C().cfg().detection.alertRadius or 0
    if radius > 0 then
        local here = GetEntityCoords(ped)
        for other, ob in pairs(C().brains) do
            if other ~= ped and ob.configured and not ALERT[ob.mode] and DoesEntityExist(other) and not IsPedDeadOrDying(other, true)
                and #(GetEntityCoords(other) - here) <= radius then
                ob.sTarget, ob.spotAt, ob.nextSense = target, -1e9, t + 1000
            end
        end
    end
end

-- The barricade (wall, door, gate) to attack: near the zombie, and on the
-- way to where the target is. nil when there is none (or no base building).
local function findBarricade(ai, here, targetPos)
    local cfgB = ai.barricades
    if not (cfgB and cfgB.enabled) or GetResourceState('wasteland_basebuilding') ~= 'started' then return nil end
    if targetPos and #(targetPos - here) > cfgB.playerRadius then return nil end
    local ok, list = pcall(function() return exports.wasteland_basebuilding:GetBarricadesNear(tbl(here), cfgB.searchRadius) end)
    if not ok or type(list) ~= 'table' then return nil end
    local best, bestScore
    for _, p in ipairs(list) do
        local pos = vector3(p.x, p.y, p.z)
        local score = #(pos - here) + (targetPos and #(pos - targetPos) * 0.5 or 0)
        if not bestScore or score < bestScore then best, bestScore = p, score end
    end
    return best
end

local function startBreach(b, piece, t, ai)
    b.mode, b.piece, b.swing, b.nextTask, b.pieceHitAt = 'breach', piece, nil, 0, nil
    b.breachUntil = t + ai.barricades.giveUpSeconds * 1000
end

local function giveUp(b)
    b.mode, b.target, b.chase, b.spit, b.swing, b.nextTask = 'return', nil, nil, nil, nil, 0
end

-------------------------------------------------------------------------------
-- Think (every 250 ms for each zombie this game runs)
-------------------------------------------------------------------------------

function Brain.think(ped, b, info, investigate, night)
    local cfg = C().cfg()
    local ai = cfg.ai
    local t = GetGameTimer()
    b.ped = ped
    local phaseName, phase = AI.phase(ai, GetClockHours())
    profile(b, info, ai, phaseName, t)
    local pers = ai.personalities[b.personality] or {}
    local k = cfg.kinds[info.kind] or cfg.kinds.walker
    local sp = b.sp or {}
    local speedMul = (phase.speed or 1) * (sp.speedMult or 1)
    if sp.nightSpeedMult and phaseName == 'night' then speedMul = speedMul * sp.nightSpeedMult end
    local here = GetEntityCoords(ped)
    if not b.home then
        b.home = tbl(here)
        if b.personality == 'ambusher' then
            local p = AI.ambushPointFor(ai.ambushPoints, b.home)
            if p then b.home = { x = p.x, y = p.y, z = p.z } end
        end
    end
    if b.busyUntil and t < b.busyUntil then
        if b.spit then spitStep(ped, b, t, 0) end
        return
    end

    -- senses (staggered: not every zombie on the same tick)
    if t >= (b.nextSense or 0) then
        b.nextSense = t + ai.senses.senseEveryMs + (ped % 7) * 20
        b.sTarget, b.sDist, b.sSeen, b.sIso = sense(ped, b, ai, phaseName, phase, night)
    end
    local target = b.sTarget
    if target and (not DoesEntityExist(target) or IsEntityDead(target)) then target, b.sTarget = nil, nil end

    if target then
        b.lastKnown, b.lastSeen = tbl(GetEntityCoords(target)), t
        if ALERT[b.mode] then
            b.target = target
        elseif b.mode == 'breach' and not (b.sSeen and not C().safe(target)) then
            b.target = target -- heard through the wall: keep breaking through
        else
            -- reaction time: it turns to look first
            b.spotAt = b.spotAt or t
            local react = b.mode == 'ambush' and 0 or (pers.reactMs or 500)
            if t - b.spotAt >= react then engage(ped, b, target, t, ai)
            elseif t >= (b.nextFace or 0) and b.mode ~= 'sleep' then
                b.nextFace = t + 1000
                TaskTurnPedToFaceEntity(ped, target, 800)
            end
        end
    else
        b.spotAt = nil
    end

    -- lost them, or they got away
    if ALERT[b.mode] then
        local gone = not b.target or not DoesEntityExist(b.target) or IsEntityDead(b.target)
        if gone or AI.giveUp(ai.memory, b.chase, t, tbl(here)) then
            giveUp(b)
        elseif C().safe(b.target) or (not target and t - (b.lastSeen or 0) > 1500) then
            -- hiding in a base or behind its walls: break through if a wall,
            -- door or gate is in the way; otherwise look where they were last
            local piece = findBarricade(ai, here, GetEntityCoords(b.target))
            if piece then startBreach(b, piece, t, ai)
            elseif C().safe(b.target) then giveUp(b)
            else
                b.mode, b.searchAt, b.searchFirst = 'search', b.lastKnown, true
                b.searchUntil, b.nextTask = t + ai.memory.searchSeconds * 1000, 0
            end
        end
    end

    -- a noise (the server picked who heard it)
    if not ALERT[b.mode] and type(investigate) == 'table' and investigate.at ~= b.heardAt then
        b.heardAt = investigate.at
        if b.mode ~= 'sleep' or (investigate.intensity or 1) >= 2 then
            if b.mode == 'sleep' or b.mode == 'ambush' then ClearPedTasks(ped) end
            b.mode, b.inv, b.viaDone = 'investigate', investigate, type(investigate.via) ~= 'table'
            b.investigateUntil, b.nextTask = t + (investigate.untilMs or 30000), 0
        end
    end

    local mode = b.mode
    if mode == 'chase' then
        local tp = GetEntityCoords(b.target)
        local dist = #(tp - here)
        local speed = k.speed * speedMul
        if b.personality == 'sprinter' then
            if b.sprintUntil and t < b.sprintUntil then speed = math.max(speed, pers.sprintSpeed * (phase.speed or 1))
            elseif b.sprintUntil then b.sprintUntil, b.recoverUntil = nil, t + pers.cooldownSeconds * 1000
            elseif b.recoverUntil and t < b.recoverUntil then speed = pers.recoverSpeed
            else b.sprintUntil, b.recoverUntil = t + pers.sprintSeconds * 1000, nil end
        end
        -- not getting any closer (a wall, door or gate in the way): break through
        if dist > cfg.attack.range + 1.0 then
            if not b.progress or t - b.progress.t > 3000 then
                if b.progress and b.progress.d - dist < 1.0 then
                    local piece = findBarricade(ai, here, tp)
                    if piece then startBreach(b, piece, t, ai); return end
                end
                b.progress = { d = dist, t = t }
            end
        else
            b.progress = nil
        end
        if b.special == 'spitter' and spitStep(ped, b, t, dist) then b.swing = nil; return end
        if (b.special == 'howler' or b.special == 'alpha') then shout(ped, b, t, 'howl', sp.cooldownSeconds) end
        -- a stalker whose charge does not reach you may back off and come again
        if b.personality == 'stalker' and dist > 4.0 and b.chargeAt and t - b.chargeAt > 10000 then
            b.chargeAt = t
            if math.random() < (pers.disengageChance or 0) then startStalk(b, t, pers); return end
        end
        if b.personality == 'pack' and dist > (pers.ringRadius or 3.5) + 1.5 then
            -- surround: every pack hunter on this target takes its own side
            local members = {}
            for other, ob in pairs(C().brains) do
                if ob.mode == 'chase' and ob.personality == 'pack' and ob.target == b.target and DoesEntityExist(other)
                    and #(GetEntityCoords(other) - here) <= (pers.packRadius or 35) then members[#members + 1] = other end
            end
            table.sort(members)
            local index = 1
            for i, m in ipairs(members) do if m == ped then index = i end end
            if #members > 1 then
                b.swing = nil
                if t >= (b.nextTask or 0) then
                    b.nextTask = t + 1000
                    local slot = AI.packSlot(index, #members, tbl(tp), pers.ringRadius or 3.5, math.rad(GetEntityHeading(b.target)))
                    goTo(ped, slot, speed)
                end
                return
            end
        end
        C().chaseStep(ped, b, dist, speed, { windupMult = sp.windupMult, cooldownMult = sp.cooldownMult })
    elseif mode == 'stalk' then
        local tp = GetEntityCoords(b.target)
        local dist = #(tp - here)
        local tf = GetEntityForwardVector(b.target)
        local to = here - tp
        local behind = (tf.x * to.x + tf.y * to.y) / math.max(0.1, #to) < -0.2 -- the player faces away
        local charge = dist <= (pers.chargeDistance or 8) or t >= b.stalkUntil
            or (behind and dist <= (pers.chargeDistance or 8) * 2)
        if charge and b.special == 'hunter' and not b.sIso and dist > (pers.chargeDistance or 8) * 0.6 then
            charge, b.stalkUntil = false, t + 5000 -- not alone: keep waiting
        end
        if charge then
            b.mode, b.chargeAt, b.nextTask = 'chase', t, 0
        elseif t >= (b.nextTask or 0) then
            b.nextTask = t + 2500
            goTo(ped, AI.stalkPoint(tbl(here), tbl(tp), b.stalkDist, b.stalkTurn), math.max(1.0, k.speed * speedMul))
        end
    elseif mode == 'breach' then
        local p = b.piece
        local pos = vector3(p.x, p.y, p.z)
        if t > b.breachUntil then giveUp(b); return end
        if t >= (b.nextPieceCheck or 0) then
            -- still standing (and still shut)?
            b.nextPieceCheck = t + 2000
            local ok, list = pcall(function() return exports.wasteland_basebuilding:GetBarricadesNear(p, 0.5) end)
            local still = false
            for _, q in ipairs(ok and list or {}) do if q.id == p.id then still = true end end
            if not still then
                -- broken through: back after the target
                if b.target and DoesEntityExist(b.target) and not IsEntityDead(b.target) and not C().safe(b.target) then
                    engage(ped, b, b.target, t, ai)
                else giveUp(b) end
                return
            end
        end
        if b.pieceHitAt and t >= b.pieceHitAt then
            b.pieceHitAt = nil
            TriggerServerEvent('wasteland:zombies:server:hitPiece', NetworkGetNetworkIdFromEntity(ped), p.id)
        end
        local flat = vector3(pos.x, pos.y, here.z)
        if #(flat - here) > 2.4 then
            if t >= (b.nextTask or 0) then
                b.nextTask = t + 1500
                -- the side of the piece the zombie is on
                local dir = here - flat
                local len = math.max(0.1, #dir)
                goTo(ped, { x = pos.x + dir.x / len * 1.0, y = pos.y + dir.y / len * 1.0, z = here.z }, k.speed * speedMul)
            end
        elseif t >= (b.nextAttack or 0) and not b.pieceHitAt then
            b.nextAttack = t + cfg.attack.cooldownMs * 1.3 * (sp.cooldownMult or 1)
            TaskTurnPedToFaceCoord(ped, pos.x, pos.y, here.z, 300)
            C().playAttack(ped)
            b.pieceHitAt = t + (cfg.attack.windupMs or 450) * (sp.windupMult or 1)
        end
    elseif mode == 'search' then
        if t > b.searchUntil then giveUp(b)
        elseif t >= (b.nextTask or 0) then
            local p = b.searchAt
            if b.searchFirst and #(v3(p) - here) > 3.0 then
                b.nextTask = t + 3000
            else
                b.searchFirst = false
                b.nextTask = t + 5000
                p = AI.searchPoint(b.searchAt, ai.memory.searchRadius, math.random(), math.random())
            end
            goTo(ped, p, math.max(1.0, k.speed * speedMul * 0.8))
        end
    elseif mode == 'investigate' then
        local i = b.inv
        local goal = (not b.viaDone) and i.via or i
        if t > b.investigateUntil then giveUp(b)
        elseif #(v3(goal) - here) < 4.0 then
            if not b.viaDone then b.viaDone, b.nextTask = true, 0
            else
                -- got there: look around
                b.mode, b.searchAt, b.searchFirst = 'search', { x = i.x, y = i.y, z = i.z }, false
                b.searchUntil, b.nextTask = t + ai.memory.searchSeconds * 1000, 0
            end
        elseif t >= (b.nextTask or 0) then
            b.nextTask = t + 4000
            goTo(ped, goal, k.speed * speedMul * 0.8)
        end
    else
        -- idle / return: back to what it does when nothing is going on
        local homeDist = #(v3(b.home) - here)
        if b.personality == 'sleeper' or b.personality == 'ambusher' then
            if homeDist > 3.0 then
                if mode ~= 'return' or t >= (b.nextTask or 0) then b.mode, b.nextTask = 'return', t + 4000; goTo(ped, b.home, 1.0) end
            elseif b.personality == 'sleeper' then
                if mode ~= 'sleep' or (t >= (b.nextTask or 0) and not IsEntityPlayingAnim(ped, SLEEP_DICT, SLEEP_ANIM, 3)) then
                    b.mode, b.nextTask = 'sleep', t + 2000
                    if loadDict(SLEEP_DICT) then TaskPlayAnim(ped, SLEEP_DICT, SLEEP_ANIM, 8.0, -8.0, -1, 1, 0.0, false, false, false) end
                end
            elseif mode ~= 'ambush' or t >= (b.nextTask or 0) then
                b.mode, b.nextTask = 'ambush', t + 20000
                TaskStandStill(ped, 20000)
            end
        elseif mode ~= 'idle' or t >= (b.nextTask or 0) then
            b.mode, b.nextTask = 'idle', t + 20000
            TaskWanderStandard(ped, 10.0, 10)
        end
    end
end

-------------------------------------------------------------------------------
-- Vehicle crashes are loud (the driver's game reports its own crash; the
-- server uses the player's real position).
-------------------------------------------------------------------------------

Citizen.CreateThread(function()
    local lastSpeed, nextReport = 0.0, 0
    while true do
        local cfg = C() and C().cfg()
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if cfg and cfg.ai and cfg.ai.enabled and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local speed = GetEntitySpeed(veh)
            if lastSpeed - speed > 6.0 and HasEntityCollidedWithAnything(veh) and GetGameTimer() >= nextReport then
                nextReport = GetGameTimer() + 3000
                TriggerServerEvent('wasteland:zombies:server:crash')
            end
            lastSpeed = speed
            Citizen.Wait(200)
        else
            lastSpeed = 0.0
            Citizen.Wait(1000)
        end
    end
end)
