-- wasteland_hunting :: client/main.lua
-- Finds spawn spots for animals, lets the animals this game runs wander,
-- harvesting (Left Alt on a dead animal), placing a campfire, the cooking
-- window and its progress. Every decision is the server's.

local Rules = WLH.Rules
local COOK = 'cookScreen'
local PROGRESS = 'huntProgress'
local cfg = nil
local harvestingUntil = nil
local cookingFire = nil

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function isOpen(s) return uiRunning() and exports.wasteland_ui:IsOpen(s) end

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:hunting:client:notice', function(m)
    notice(m)
    if isOpen(COOK) then exports.wasteland_ui:Update(COOK, { message = m }) end
end)

-------------------------------------------------------------------------------
-- Animals: spawn spots and wandering
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:hunting:client:findSpots', function(n, minDist, maxDist)
    n = math.max(0, math.min(5, math.tointeger(tonumber(n)) or 0))
    local me = GetEntityCoords(PlayerPedId())
    local points, tries = {}, 0
    while #points < n and tries < n * 8 do
        tries = tries + 1
        local angle = math.random() * math.pi * 2
        local d = minDist + math.random() * (maxDist - minDist)
        local x, y = me.x + math.cos(angle) * d, me.y + math.sin(angle) * d
        local found, z = GetGroundZFor_3dCoord(x, y, me.z + 80.0, false)
        if found and not GetWaterHeight(x, y, z) and not IsPointOnRoad(x, y, z, 0) then
            points[#points + 1] = { x = x, y = y, z = z + 0.5 }
        end
    end
    TriggerServerEvent('wasteland:hunting:server:spots', points)
end)

-- Animals this game runs: wander about (they flee from danger by themselves).
Citizen.CreateThread(function()
    local seen = {}
    while true do
        Citizen.Wait(2000)
        local live = {}
        for _, ped in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) then
                local ok, st = pcall(function() return Entity(ped).state.wlAnimal end)
                if ok and st then
                    live[ped] = true
                    if NetworkHasControlOfEntity(ped) and not seen[ped] and not IsPedDeadOrDying(ped, true) then
                        seen[ped] = true
                        TaskWanderStandard(ped, 10.0, 10)
                    end
                end
            end
        end
        for ped in pairs(seen) do if not live[ped] or not NetworkHasControlOfEntity(ped) then seen[ped] = nil end end
    end
end)

-------------------------------------------------------------------------------
-- Harvesting
-------------------------------------------------------------------------------

local HARVEST_DICT, HARVEST_ANIM = 'amb@medic@standing@kneel@base', 'base'

local function stopHarvest(cancelled)
    harvestingUntil = nil
    ClearPedTasks(PlayerPedId())
    if isOpen(PROGRESS) then exports.wasteland_ui:Close(PROGRESS) end
    if cancelled then TriggerServerEvent('wasteland:hunting:server:harvestCancel') end
end

RegisterNetEvent('wasteland:hunting:client:harvesting', function(seconds)
    local ped = PlayerPedId()
    local start = GetEntityCoords(ped)
    harvestingUntil = GetGameTimer() + seconds * 1000
    RequestAnimDict(HARVEST_DICT)
    local t = GetGameTimer() + 1000
    while not HasAnimDictLoaded(HARVEST_DICT) and GetGameTimer() < t do Citizen.Wait(0) end
    TaskPlayAnim(ped, HARVEST_DICT, HARVEST_ANIM, 4.0, -4.0, -1, 1, 0, false, false, false)
    if uiRunning() then exports.wasteland_ui:Open(PROGRESS, { script = 'html/progress.js', data = { label = 'Harvesting', seconds = seconds } }) end
    Citizen.CreateThread(function()
        while harvestingUntil do
            Citizen.Wait(0)
            if #(GetEntityCoords(PlayerPedId()) - start) > 1.5 or IsControlJustPressed(0, 73) or IsPedDeadOrDying(PlayerPedId(), true) then
                stopHarvest(true)
                notice('Harvesting stopped.')
                return
            end
            if GetGameTimer() >= harvestingUntil then
                stopHarvest(false)
                TriggerServerEvent('wasteland:hunting:server:harvestDone')
                return
            end
        end
    end)
end)

local function harvestable(ent)
    if not DoesEntityExist(ent) or IsPedAPlayer(ent) or IsPedHuman(ent) or not IsPedDeadOrDying(ent, true) then return false end
    if not NetworkGetEntityIsNetworked(ent) then return false end
    local ok, done = pcall(function() return Entity(ent).state.wlHarvested end)
    return not (ok and done)
end

-------------------------------------------------------------------------------
-- Campfires
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:hunting:client:placeFire', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then notice('Get out of the vehicle first.'); return end
    if isOpen('inventory') then exports.wasteland_ui:Close('inventory') end
    local c = GetEntityCoords(ped)
    local x, y = Rules.inFront(c.x, c.y, GetEntityHeading(ped), 1.4)
    local found, z = GetGroundZFor_3dCoord(x, y, c.z + 1.0, false)
    if not found then z = c.z - 1.0 end
    TriggerServerEvent('wasteland:hunting:server:placeFire', x, y, z)
end)

local function isFire(ent)
    local ok, st = pcall(function() return Entity(ent).state.wlCampfire end)
    return ok and st ~= nil
end

-------------------------------------------------------------------------------
-- Cooking window
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:hunting:client:cookScreen', function(data)
    if not uiRunning() or type(data) ~= 'table' then return end
    cookingFire = data.fire
    if isOpen(COOK) then exports.wasteland_ui:Update(COOK, { view = data })
    else exports.wasteland_ui:Open(COOK, { script = 'html/cook.js', data = { view = data } }) end
end)

RegisterNetEvent('wasteland:hunting:client:cooking', function(p)
    if isOpen(COOK) then exports.wasteland_ui:Update(COOK, { progress = p }) end
    if type(p) == 'table' and p.done and p.message and not isOpen(COOK) then notice(p.message) end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= COOK then return end
    payload = type(payload) == 'table' and payload or {}
    if action == 'cook' and cookingFire then
        TriggerServerEvent('wasteland:hunting:server:cook', cookingFire, tostring(payload.item or ''), math.max(1, math.tointeger(tonumber(payload.count)) or 1))
    elseif action == 'stop' then
        TriggerServerEvent('wasteland:hunting:server:stopCook')
    elseif action == 'close' then
        exports.wasteland_ui:Close(COOK)
    end
end)

-------------------------------------------------------------------------------
-- Target options
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:hunting:client:config', function(c) cfg = c end)
RegisterNetEvent('wasteland:hunting:client:fires', function() end) -- fires are found by their state

Citizen.CreateThread(function()
    TriggerServerEvent('wasteland:hunting:server:config')
    while not cfg do Citizen.Wait(500) end
    while GetResourceState('wasteland_target') ~= 'started' do Citizen.Wait(1000) end
    exports.wasteland_target:AddGlobal('ped', {
        { label = 'Harvest', icon = '✂', distance = 2.5,
            canInteract = function(ent) return harvestable(ent) end,
            onSelect = function(data)
                if harvestingUntil then return end
                TriggerServerEvent('wasteland:hunting:server:harvest', NetworkGetNetworkIdFromEntity(data.entity))
            end },
    })
    exports.wasteland_target:AddModel(cfg.fireModel, {
        { label = 'Cook', icon = '♨', distance = 2.5, canInteract = function(ent) return isFire(ent) end,
            onSelect = function(data) TriggerServerEvent('wasteland:hunting:server:openCook', NetworkGetNetworkIdFromEntity(data.entity)) end },
        { label = 'Put out and pick up', icon = '⇩', distance = 2.5, canInteract = function(ent) return isFire(ent) end,
            onSelect = function(data) TriggerServerEvent('wasteland:hunting:server:pickUp', NetworkGetNetworkIdFromEntity(data.entity)) end },
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if harvestingUntil then stopHarvest(false) end
    if isOpen(COOK) then exports.wasteland_ui:Close(COOK) end
end)
