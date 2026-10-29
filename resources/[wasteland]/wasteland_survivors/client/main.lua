-- wasteland_survivors :: client/main.lua
-- Finds spawn spots, runs the survivors this game owns (fight zombies, fight
-- back the players they hate, wander, call for help), plays what they say
-- (the game's voice lines and the words above their head), reports this
-- player's hits on a survivor, Talk / Trade (Left Alt) and the trade window.
-- Every decision about items is the server's.

local SCREEN = 'survivorTrade'
local cfg = nil
local brains = {}          -- ped -> { configured, target, retaskAt, mode }
local survivorGroup, zombieGroup = nil, nil
local speech = {}          -- ped -> { text, untilT }
local tradingWith = nil    -- net id of the survivor whose trade window is open

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function isOpen(s) return uiRunning() and exports.wasteland_ui:IsOpen(s) end

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:survivors:client:notice', function(m)
    if isOpen(SCREEN) then exports.wasteland_ui:Update(SCREEN, { message = m }) else notice(m) end
end)
RegisterNetEvent('wasteland:survivors:client:config', function(c) cfg = c end)

local function survivorInfo(ped)
    local ok, st = pcall(function() return Entity(ped).state.wlSurvivor end)
    return ok and st or nil
end
local function isZombie(ped)
    local ok, st = pcall(function() return Entity(ped).state.wlZombie end)
    return ok and st ~= nil
end

-------------------------------------------------------------------------------
-- Spawn spots
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:survivors:client:findSpots', function(n, minDist, maxDist)
    n = math.max(0, math.min(5, math.tointeger(tonumber(n)) or 0))
    local me = GetEntityCoords(PlayerPedId())
    local points, tries = {}, 0
    while #points < n and tries < n * 8 do
        tries = tries + 1
        local angle = math.random() * math.pi * 2
        local d = minDist + math.random() * (maxDist - minDist)
        local x, y = me.x + math.cos(angle) * d, me.y + math.sin(angle) * d
        local found, z = GetGroundZFor_3dCoord(x, y, me.z + 80.0, false)
        if found and not GetWaterHeight(x, y, z) then
            local ok, safe = GetSafeCoordForPed(x, y, z + 1.0, true, 16)
            local p = ok and safe or vector3(x, y, z)
            points[#points + 1] = { x = p.x, y = p.y, z = p.z + 0.5 }
        end
    end
    TriggerServerEvent('wasteland:survivors:server:spots', points)
end)

-------------------------------------------------------------------------------
-- Who likes whom: survivors and zombies hate each other, players are
-- respected (until a survivor is told to fight one). Set on every game.
-------------------------------------------------------------------------------

local function relations(ped)
    if not survivorGroup then
        local _, g = AddRelationshipGroup('WL_SURVIVOR')
        survivorGroup = g
        zombieGroup = GetHashKey('WL_ZOMBIE') -- the zombies' group (wasteland_zombies makes it)
        local player = GetHashKey('PLAYER')
        SetRelationshipBetweenGroups(0, survivorGroup, survivorGroup)
        SetRelationshipBetweenGroups(1, survivorGroup, player)
        SetRelationshipBetweenGroups(1, player, survivorGroup)
    end
    -- again every time: the zombies' group may only exist once a zombie showed up
    SetRelationshipBetweenGroups(5, survivorGroup, zombieGroup)
    SetRelationshipBetweenGroups(5, zombieGroup, survivorGroup)
    if GetPedRelationshipGroupHash(ped) ~= survivorGroup then SetPedRelationshipGroupHash(ped, survivorGroup) end
end

local function configure(ped, info)
    relations(ped)
    SetBlockingOfNonTemporaryEvents(ped, true) -- they do what this script says, not GTA's panic
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)      -- always fight
    SetPedCombatAttributes(ped, 5, true)       -- fight armed people even unarmed
    SetPedCombatAbility(ped, 1)
    SetPedCombatRange(ped, 1)
    SetPedAccuracy(ped, (cfg and cfg.accuracy) or 35)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedKeepTask(ped, true)
    SetPedCanBeTargetted(ped, true)
    local hp = (cfg and cfg.health) or 250
    if GetEntityMaxHealth(ped) ~= hp then SetEntityMaxHealth(ped, hp); SetEntityHealth(ped, hp) end
    SetPedArmour(ped, (cfg and cfg.armour) or 0)
    local w = GetHashKey(info.weapon or 'WEAPON_PISTOL')
    GiveWeaponToPed(ped, w, 250, false, true)
    SetCurrentPedWeapon(ped, w, true)
    SetPedInfiniteAmmo(ped, true, w)
    TaskWanderStandard(ped, 10.0, 10)
end

-------------------------------------------------------------------------------
-- What they say
-------------------------------------------------------------------------------

local SHOUT = { help = true, angry = true, thanks = true }

RegisterNetEvent('wasteland:survivors:client:say', function(netId, kind, line, text)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local ped = NetworkGetEntityFromNetworkId(netId)
    if ped == 0 or not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then return end
    if type(line) == 'string' then
        StopCurrentPlayingAmbientSpeech(ped)
        PlayPedAmbientSpeechNative(ped, line, SHOUT[kind] and 'SPEECH_PARAMS_FORCE_SHOUTED' or 'SPEECH_PARAMS_FORCE_NORMAL')
    end
    if type(text) == 'string' and text ~= '' then speech[ped] = { text = text, untilT = GetGameTimer() + 3500 } end
end)

local function drawText3d(pos, text)
    local onScreen, x, y = World3dToScreen2d(pos.x, pos.y, pos.z)
    if not onScreen then return end
    SetTextScale(0.0, 0.36)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(240, 230, 200, 255)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

Citizen.CreateThread(function()
    while true do
        if next(speech) then
            local t = GetGameTimer()
            local me = GetEntityCoords(PlayerPedId())
            for ped, s in pairs(speech) do
                if t > s.untilT or not DoesEntityExist(ped) then speech[ped] = nil
                else
                    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
                    if #(head - me) < 40.0 then drawText3d(head + vector3(0.0, 0.0, 0.35), s.text) end
                end
            end
            Citizen.Wait(0)
        else
            Citizen.Wait(250)
        end
    end
end)

-------------------------------------------------------------------------------
-- The survivors this game runs
-------------------------------------------------------------------------------

local function askSay(ped, b, kind, t)
    local v = cfg and cfg.voice and cfg.voice[kind]
    local every = ((v and v.everySeconds) or 20) * 1000
    b.said = b.said or {}
    if t - (b.said[kind] or -1e9) < every then return end
    b.said[kind] = t
    TriggerServerEvent('wasteland:survivors:server:say', NetworkGetNetworkIdFromEntity(ped), kind)
end

local function think(ped, b, info, peds, t)
    local here = GetEntityCoords(ped)
    -- 1. a player it hates, close by
    local enemy, enemyDist
    for _, src in ipairs(info.hostile or {}) do
        local pl = GetPlayerFromServerId(src)
        if pl ~= -1 then
            local pp = GetPlayerPed(pl)
            if pp ~= 0 and not IsEntityDead(pp) then
                local d = #(GetEntityCoords(pp) - here)
                if d < 80.0 and (not enemyDist or d < enemyDist) then enemy, enemyDist = pp, d end
            end
        end
    end
    -- 2. else the nearest zombie
    local zombie, zombieDist
    if not enemy then
        for _, z in ipairs(peds.zombies) do
            local d = #(GetEntityCoords(z) - here)
            if d <= ((cfg and cfg.engageRadius) or 40.0) and (not zombieDist or d < zombieDist) then zombie, zombieDist = z, d end
        end
    end
    local target = enemy or zombie
    if target then
        if b.target ~= target or t >= (b.retaskAt or 0) then
            b.target, b.retaskAt, b.mode = target, t + 4000, 'fight'
            TaskCombatPed(ped, target, 0, 16)
        end
        if zombie then
            -- calls for help when a player can hear it
            for _, pp in ipairs(peds.players) do
                if #(GetEntityCoords(pp) - here) < 70.0 then askSay(ped, b, 'help', t); break end
            end
        end
        return
    end
    if b.mode == 'fight' then
        b.mode, b.target, b.retaskAt = 'idle', nil, 0
        ClearPedTasks(ped)
    end
    -- 3. a player walks up: it turns to them and says hello
    for _, pp in ipairs(peds.players) do
        if #(GetEntityCoords(pp) - here) < 8.0 then
            if b.mode ~= 'greet' then
                b.mode, b.retaskAt = 'greet', t + 6000
                ClearPedTasks(ped)
                TaskTurnPedToFaceEntity(ped, pp, 2000)
                askSay(ped, b, 'greet', t)
            elseif t >= b.retaskAt then
                b.retaskAt = t + 6000
                TaskStandStill(ped, 6000)
            end
            return
        end
    end
    -- 4. wander
    if b.mode ~= 'idle' or t >= (b.retaskAt or 0) then
        b.mode, b.retaskAt = 'idle', t + 30000
        TaskWanderStandard(ped, 10.0, 10)
    end
end

Citizen.CreateThread(function()
    TriggerServerEvent('wasteland:survivors:server:config')
    while true do
        Citizen.Wait(500)
        local t = GetGameTimer()
        local peds = { zombies = {}, players = {} }
        local mine = {}
        for _, ped in ipairs(GetGamePool('CPed')) do
            if IsPedAPlayer(ped) then
                if not IsEntityDead(ped) then peds.players[#peds.players + 1] = ped end
            elseif NetworkGetEntityIsNetworked(ped) then
                local info = survivorInfo(ped)
                if info then
                    relations(ped)
                    if NetworkHasControlOfEntity(ped) and not IsPedDeadOrDying(ped, true) then mine[ped] = info end
                elseif isZombie(ped) and not IsPedDeadOrDying(ped, true) then
                    peds.zombies[#peds.zombies + 1] = ped
                end
            end
        end
        for ped, info in pairs(mine) do
            local b = brains[ped]
            if not b then b = {}; brains[ped] = b end
            if not b.configured and cfg then b.configured = true; configure(ped, info) end
            if b.configured then think(ped, b, info, peds, t) end
        end
        for ped in pairs(brains) do if not mine[ped] then brains[ped] = nil end end -- gone, dead, or another game runs it
    end
end)

-- A zombie's hit (the server checked it): this game runs the survivor.
RegisterNetEvent('wasteland:survivors:client:damage', function(netId, amount)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local ped = NetworkGetEntityFromNetworkId(netId)
    amount = math.max(0, math.min(500, math.floor(tonumber(amount) or 0)))
    if ped ~= 0 and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) and amount > 0 then ApplyDamageToPed(ped, amount, false) end
end)

-- This player hurt a survivor: tell the server (it only turns them on us).
local reported = {}
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local victim, attacker = args[1], args[2]
    if attacker ~= PlayerPedId() or not victim or victim == 0 or not DoesEntityExist(victim) or not IsEntityAPed(victim) then return end
    if not survivorInfo(victim) then return end
    local t = GetGameTimer()
    if t - (reported[victim] or -1e9) < 2000 then return end
    reported[victim] = t
    TriggerServerEvent('wasteland:survivors:server:attacked', NetworkGetNetworkIdFromEntity(victim))
end)

-------------------------------------------------------------------------------
-- Talk / Trade, the trade window
-------------------------------------------------------------------------------

local function friendly(ent)
    if not DoesEntityExist(ent) or IsPedDeadOrDying(ent, true) or not NetworkGetEntityIsNetworked(ent) then return false end
    local info = survivorInfo(ent)
    if not info then return false end
    local me = GetPlayerServerId(PlayerId())
    for _, src in ipairs(info.hostile or {}) do if src == me then return false end end
    return true
end

RegisterNetEvent('wasteland:survivors:client:trade', function(netId, view)
    if not uiRunning() or type(view) ~= 'table' then return end
    tradingWith = netId
    if isOpen(SCREEN) then exports.wasteland_ui:Update(SCREEN, view)
    else exports.wasteland_ui:Open(SCREEN, { script = 'html/barter.js', data = view }) end
end)

local function closeTrade()
    if isOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
    if tradingWith then TriggerServerEvent('wasteland:survivors:server:closeTrade') end
    tradingWith = nil
end
RegisterNetEvent('wasteland:survivors:client:closeTrade', closeTrade)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN then return end
    payload = type(payload) == 'table' and payload or {}
    if action == 'trade' and tradingWith then
        TriggerServerEvent('wasteland:survivors:server:barter', tradingWith, math.tointeger(tonumber(payload.index)) or 0)
    elseif action == 'close' then
        closeTrade()
    end
end)

-- The window closes when you walk away (or they die).
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        if tradingWith then
            local ped = NetworkDoesNetworkIdExist(tradingWith) and NetworkGetEntityFromNetworkId(tradingWith) or 0
            if ped == 0 or not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true)
                or #(GetEntityCoords(ped) - GetEntityCoords(PlayerPedId())) > 6.0 then closeTrade() end
        end
    end
end)

Citizen.CreateThread(function()
    while GetResourceState('wasteland_target') ~= 'started' do Citizen.Wait(1000) end
    exports.wasteland_target:AddGlobal('ped', {
        { label = 'Talk', icon = '💬', distance = 3.0, canInteract = function(ent) return friendly(ent) end,
            onSelect = function(data) TriggerServerEvent('wasteland:survivors:server:talk', NetworkGetNetworkIdFromEntity(data.entity)) end },
        { label = 'Trade', icon = '⇄', distance = 3.0, canInteract = function(ent) return friendly(ent) end,
            onSelect = function(data) TriggerServerEvent('wasteland:survivors:server:openTrade', NetworkGetNetworkIdFromEntity(data.entity)) end },
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
end)
