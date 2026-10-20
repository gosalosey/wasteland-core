-- wasteland_events :: client/main.lua
-- World events on the map and in the world: blips, the props (a crashed
-- helicopter, wrecked trucks, tents) with fire or smoke, the "search" target
-- on the loot prop, ground spots for the server, and the fighting of the
-- bandits this game runs (OneSync gives each networked ped to one game).

local events = {}   -- id -> { info, blip, area, objects = {}, fx = {}, targets = {} }

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:events:client:notice', function(m)
    notice(m)
    PlaySoundFrontend(-1, 'CHALLENGE_UNLOCKED', 'HUD_AWARDS', true)
end)

local function targetRunning() return GetResourceState('wasteland_target') == 'started' end

-------------------------------------------------------------------------------
-- Map and props
-------------------------------------------------------------------------------

local BLIPS = { helicrash = 64, convoy = 67, hideout = 84, horde = 310 }

local function setBlips(ev)
    local i, c = ev.info, ev.info.center
    if not ev.blip then
        ev.area = AddBlipForRadius(c.x + 0.0, c.y + 0.0, c.z + 0.0, 150.0)
        SetBlipAlpha(ev.area, 80)
        ev.blip = AddBlipForCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
        SetBlipSprite(ev.blip, BLIPS[i.type] or 161)
        SetBlipScale(ev.blip, 1.0)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(i.label)
        EndTextCommandSetBlipName(ev.blip)
    end
    local color = i.state == 'cleared' and 2 or 1 -- green when it can be searched
    SetBlipColour(ev.area, color)
    SetBlipColour(ev.blip, color)
end

local function removeProps(ev)
    for _, id in ipairs(ev.targets) do if targetRunning() then pcall(function() exports.wasteland_target:Remove(id) end) end end
    for _, fx in ipairs(ev.fx) do StopParticleFxLooped(fx, false) end
    for _, o in ipairs(ev.objects) do if DoesEntityExist(o) then DeleteEntity(o) end end
    ev.objects, ev.fx, ev.targets, ev.built = {}, {}, {}, false
end

local function loadModel(hash)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Citizen.Wait(0) end
    return HasModelLoaded(hash)
end

local function buildProps(id, ev)
    ev.built = true
    local c = ev.info.center
    RequestNamedPtfxAsset('core')
    for _, p in ipairs(ev.info.props or {}) do
        local hash = GetHashKey(p.model)
        if loadModel(hash) and events[id] == ev then
            local x, y = c.x + (p.x or 0.0), c.y + (p.y or 0.0)
            local found, ground = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, c.z + 50.0, false)
            local z = (found and ground or c.z) + (p.z or 0.0)
            local o = CreateObject(hash, x + 0.0, y + 0.0, z + 0.0, false, false, false)
            SetModelAsNoLongerNeeded(hash)
            SetEntityHeading(o, (p.heading or 0.0) + 0.0)
            if (p.z or 0.0) == 0.0 then PlaceObjectOnGroundProperly(o) end
            FreezeEntityPosition(o, true)
            ev.objects[#ev.objects + 1] = o
            if p.fx and HasNamedPtfxAssetLoaded('core') then
                UseParticleFxAssetNextCall('core')
                local fx = StartParticleFxLoopedAtCoord(p.fx, x + 0.0, y + 0.0, z + 0.5, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
                if fx and fx ~= 0 then ev.fx[#ev.fx + 1] = fx end
            end
            if p.loot and targetRunning() then
                ev.targets[#ev.targets + 1] = exports.wasteland_target:AddEntity(o, {
                    { label = 'Search: ' .. (ev.info.lootLabel or 'loot'), icon = '⌕', distance = 4.0,
                        onSelect = function() TriggerServerEvent('wasteland:events:server:open', id) end },
                })
            end
        end
    end
end

RegisterNetEvent('wasteland:events:client:event', function(info)
    if type(info) ~= 'table' or not info.id then return end
    local ev = events[info.id]
    if not ev then
        ev = { objects = {}, fx = {}, targets = {} }
        events[info.id] = ev
    end
    ev.info = info
    setBlips(ev)
end)

RegisterNetEvent('wasteland:events:client:remove', function(id)
    local ev = events[id]
    if not ev then return end
    removeProps(ev)
    if ev.blip then RemoveBlip(ev.blip) end
    if ev.area then RemoveBlip(ev.area) end
    events[id] = nil
end)

-- Props only near the event.
Citizen.CreateThread(function()
    TriggerServerEvent('wasteland:events:server:sync')
    while true do
        Citizen.Wait(1000)
        local me = GetEntityCoords(PlayerPedId())
        for id, ev in pairs(events) do
            local c = ev.info.center
            local d = #(me - vector3(c.x, c.y, c.z))
            if d < 300.0 and not ev.built then buildProps(id, ev)
            elseif d > 350.0 and ev.built then removeProps(ev) end
        end
    end
end)

-------------------------------------------------------------------------------
-- Ground spots for the bandits and zombies (asked by the server)
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:events:client:findSpots', function(id, c, n, rMin, rMax)
    if type(c) ~= 'table' then return end
    n = math.max(0, math.min(80, math.tointeger(tonumber(n)) or 0))
    Citizen.CreateThread(function()
        local untilT = GetGameTimer() + 1500
        while GetGameTimer() < untilT do RequestCollisionAtCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0); Citizen.Wait(0) end
        local spots, tries = {}, 0
        while #spots < n and tries < n * 6 do
            tries = tries + 1
            local a = math.random() * math.pi * 2
            local r = rMin + math.random() * (rMax - rMin)
            local x, y = c.x + math.cos(a) * r, c.y + math.sin(a) * r
            local found, z = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, c.z + 30.0, false)
            if found and math.abs(z - c.z) < 15.0 and not GetWaterHeight(x + 0.0, y + 0.0, z + 0.0) then
                local ok, safe = GetSafeCoordForPed(x + 0.0, y + 0.0, z + 1.0, true, 16)
                local p = ok and safe or vector3(x, y, z)
                spots[#spots + 1] = { x = p.x, y = p.y, z = p.z }
            end
        end
        TriggerServerEvent('wasteland:events:server:spots', id, spots)
    end)
end)

-------------------------------------------------------------------------------
-- Bandits: the game that runs one makes it fight players
-------------------------------------------------------------------------------

local banditGroup = nil
local brains = {}   -- ped -> { configured, nextLook }

local function groups()
    if banditGroup then return banditGroup end
    local _, g = AddRelationshipGroup('WL_BANDIT')
    banditGroup = g
    local player = GetHashKey('PLAYER')
    SetRelationshipBetweenGroups(5, banditGroup, player)   -- hate players
    SetRelationshipBetweenGroups(5, player, banditGroup)
    SetRelationshipBetweenGroups(0, banditGroup, banditGroup)
    -- Leave zombies alone (the fight is with players).
    local _, zombies = AddRelationshipGroup('WL_ZOMBIE')
    SetRelationshipBetweenGroups(1, banditGroup, zombies)
    SetRelationshipBetweenGroups(1, zombies, banditGroup)
    return banditGroup
end

local function safe(target)
    if GetResourceState('wasteland_camps') ~= 'started' then return false end
    local ok, yes = pcall(function() return exports.wasteland_camps:IsInSafeZone(GetEntityCoords(target)) end)
    return ok and yes == true
end

local function configure(ped, info)
    SetPedRelationshipGroupHash(ped, groups())
    local weapon = GetHashKey(info.weapon or 'WEAPON_PISTOL')
    if not HasPedGotWeapon(ped, weapon, false) then GiveWeaponToPed(ped, weapon, 250, false, true) end
    SetCurrentPedWeapon(ped, weapon, true)
    SetPedAccuracy(ped, info.accuracy or 35)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)  -- always fight
    SetPedCombatAttributes(ped, 5, true)   -- fight armed opponents
    SetPedCombatAbility(ped, 1)
    SetPedCombatMovement(ped, 2)           -- advance and take cover
    SetPedCombatRange(ped, 1)
    SetPedSeeingRange(ped, 90.0)
    SetPedHearingRange(ped, 70.0)
    SetPedKeepTask(ped, true)
    TaskCombatHatedTargetsAroundPed(ped, 80.0, 0)
end

-- The nearest living player this bandit should fight (not in a camp).
local function nearestPlayer(ped, range)
    local here = GetEntityCoords(ped)
    local best, bestD = nil, range
    for _, pl in ipairs(GetActivePlayers()) do
        local p = GetPlayerPed(pl)
        local ps = Player(GetPlayerServerId(pl)).state
        if p ~= 0 and not IsEntityDead(p) and not safe(p) and not (ps and (ps.wlProtected or ps.wlMasked)) then
            local d = #(GetEntityCoords(p) - here)
            if d < bestD then best, bestD = p, d end
        end
    end
    return best
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        local seen = {}
        for _, ped in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ped) then
                local ok, state = pcall(function() return Entity(ped).state end)
                local info = ok and state and state.wlBandit
                if info then
                    seen[ped] = true
                    local b = brains[ped] or {}
                    brains[ped] = b
                    if IsPedDeadOrDying(ped, true) then
                        b.configured = false
                    elseif NetworkHasControlOfEntity(ped) then
                        if not b.configured then b.configured = true; configure(ped, info) end
                        local t = GetGameTimer()
                        if t >= (b.nextLook or 0) then
                            b.nextLook = t + 1500
                            local target = nearestPlayer(ped, 85.0)
                            if target and not IsPedInCombat(ped, target) then
                                TaskCombatPed(ped, target, 0, 16)
                            elseif not target and info.center then
                                -- Nobody to fight: stay near the event.
                                local c = info.center
                                if #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) > 40.0 and not IsPedInCombat(ped, 0) then
                                    TaskGoToCoordAnyMeans(ped, c.x + 0.0, c.y + 0.0, c.z + 0.0, 2.0, 0, false, 786603, 0xbf800000)
                                end
                            end
                        end
                    else
                        b.configured = false -- another game runs it; set it up again if it comes back
                    end
                end
            end
        end
        for ped in pairs(brains) do if not seen[ped] then brains[ped] = nil end end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, ev in pairs(events) do
        removeProps(ev)
        if ev.blip then RemoveBlip(ev.blip) end
        if ev.area then RemoveBlip(ev.area) end
    end
    events = {}
end)
