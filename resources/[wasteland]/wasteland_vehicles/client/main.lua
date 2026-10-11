-- wasteland_vehicles :: client/main.lua
-- For vehicles this client runs (OneSync owner): apply the saved state
-- (damage, missing wheels, fuel gauge). For the driver: no engine without
-- the parts, fuel use (reported to the server). Target options on every
-- vehicle (check, trunk, parts, refuel, repair, lock) and on gas pumps.
-- The server decides every change.

local Rules = WLVE.Rules
local PROGRESS = 'vehProgress'
local cfg = nil
local applied = {}     -- vehicle handle -> seq applied
local targetIds = {}
local active = nil     -- action in progress
local WHEELS = { 0, 1, 4, 5 } -- tyre indices of a car
local HUD = 'vehHud'
local driving = nil    -- { veh, fuel, why } while this player drives (for the HUD)

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function targetRunning() return GetResourceState('wasteland_target') == 'started' end

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:vehicles:client:notice', function(m) notice(m) end)

local function stateOf(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    local ok, st = pcall(function() return Entity(veh).state.wlVeh end)
    return ok and st or nil
end

-------------------------------------------------------------------------------
-- Applying the state (owner only)
-------------------------------------------------------------------------------

local function apply(veh, s)
    if applied[veh] == nil then SetVehicleOnGroundProperly(veh) end
    applied[veh] = s.seq
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    -- Damage only the first time this state is applied (by any client):
    -- after that the entity carries newer damage than the saved state.
    if s.acked ~= s.seq then
        if (s.body or 0) >= 990 then SetVehicleDeformationFixed(veh) end
        SetVehicleEngineHealth(veh, (s.engine or 1000) + 0.0)
        SetVehicleBodyHealth(veh, (s.body or 1000) + 0.0)
    end
    SetVehicleFuelLevel(veh, math.max(0.0, (s.fuel or 0) / (s.tank or 50) * 100.0))
    local wheels = s.parts and s.parts.wheels or 4
    for i, idx in ipairs(WHEELS) do
        if i > wheels then SetVehicleTyreBurst(veh, idx, true, 1000.0) else SetVehicleTyreFixed(veh, idx) end
    end
    -- Now the server may read damage from the entity again.
    if s.acked ~= s.seq and NetworkGetEntityIsNetworked(veh) then
        TriggerServerEvent('wasteland:vehicles:server:applied', NetworkGetNetworkIdFromEntity(veh), s.seq or 0)
    end
end

-------------------------------------------------------------------------------
-- Targets
-------------------------------------------------------------------------------

local function act(action)
    return function(data)
        if active or not data.entity or not NetworkGetEntityIsNetworked(data.entity) then return end
        TriggerServerEvent('wasteland:vehicles:server:act', NetworkGetNetworkIdFromEntity(data.entity), action)
    end
end

local function when(test)
    return function(entity)
        local s = stateOf(entity)
        return s ~= nil and active == nil and test(s, entity)
    end
end

local function describe(s, veh)
    local p = s.parts or {}
    local parts = {}
    parts[#parts + 1] = string.format('Fuel %.0f/%d L', s.fuel or 0, s.tank or 50)
    parts[#parts + 1] = string.format('Engine %d%%', math.floor(math.max(0, GetVehicleEngineHealth(veh)) / 10))
    parts[#parts + 1] = string.format('Body %d%%', math.floor(math.max(0, GetVehicleBodyHealth(veh)) / 10))
    parts[#parts + 1] = 'Battery: ' .. (p.battery and 'OK' or 'missing')
    parts[#parts + 1] = 'Engine parts: ' .. (p.engine and 'OK' or 'missing')
    parts[#parts + 1] = string.format('Wheels %d/4', p.wheels or 0)
    if s.hasLock then parts[#parts + 1] = s.locked and 'Locked' or 'Unlocked' end
    return table.concat(parts, ' · ')
end

local function register()
    for _, id in ipairs(targetIds) do pcall(function() exports.wasteland_target:Remove(id) end) end
    targetIds = {}
    if not cfg or not targetRunning() then return end
    targetIds[#targetIds + 1] = exports.wasteland_target:AddGlobal('vehicle', {
        { label = 'Check vehicle', icon = '?', distance = 3.0, canInteract = when(function() return true end),
            onSelect = function(data) local s = stateOf(data.entity); if s then notice(describe(s, data.entity)) end end },
        { label = 'Open trunk', icon = '▤', distance = 3.0, canInteract = when(function() return true end), onSelect = act('trunk') },
        { label = 'Install battery', icon = '+', distance = 3.0, canInteract = when(function(s) return not s.parts.battery end), onSelect = act('battery') },
        { label = 'Fit engine parts', icon = '+', distance = 3.0, canInteract = when(function(s) return not s.parts.engine end), onSelect = act('engine') },
        { label = 'Mount a wheel', icon = '+', distance = 3.0, canInteract = when(function(s) return (s.parts.wheels or 0) < 4 end), onSelect = act('wheel') },
        { label = 'Refuel (jerry can)', icon = '⛽', distance = 3.0, canInteract = when(function(s) return (s.fuel or 0) < (s.tank or 50) - 0.5 end),
            onSelect = act('refuel') },
        { label = 'Repair (toolkit)', icon = '⚒', distance = 3.0,
            canInteract = when(function(_, veh) return GetVehicleEngineHealth(veh) < 990 or GetVehicleBodyHealth(veh) < 990 end), onSelect = act('repair') },
        { label = 'Fit a lock', icon = '🔒', distance = 3.0, canInteract = when(function(s) return not s.hasLock end), onSelect = act('fitLock') },
        { label = 'Lock / unlock (key)', icon = '🔑', distance = 3.0, canInteract = when(function(s) return s.hasLock end), onSelect = act('toggleLock') },
        { label = 'Pick the lock', icon = '⌕', distance = 3.0, canInteract = when(function(s) return s.locked end), onSelect = act('pickLock') },
    })
    if cfg.pumps and #cfg.pumps > 0 then
        targetIds[#targetIds + 1] = exports.wasteland_target:AddModel(cfg.pumps, {
            { label = 'Fill jerry can', icon = '⛽', distance = 2.5, canInteract = function() return active == nil end,
                onSelect = function(data)
                    local c = GetEntityCoords(data.entity)
                    TriggerServerEvent('wasteland:vehicles:server:fillCan', { x = c.x, y = c.y, z = c.z })
                end },
        })
    end
end

RegisterNetEvent('wasteland:vehicles:client:config', function(c)
    if type(c) ~= 'table' then return end
    cfg = c
    register()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'wasteland_target' then register() end
end)

-------------------------------------------------------------------------------
-- Actions (progress bar; moving cancels)
-------------------------------------------------------------------------------

local function stop(cancelled)
    if not active then return end
    ClearPedTasks(PlayerPedId())
    active = nil
    if uiRunning() and exports.wasteland_ui:IsOpen(PROGRESS) then exports.wasteland_ui:Close(PROGRESS) end
    if cancelled then
        TriggerServerEvent('wasteland:vehicles:server:cancel')
        notice('Cancelled.')
    end
end

RegisterNetEvent('wasteland:vehicles:client:progress', function(p)
    if type(p) ~= 'table' or active then return end
    local ped = PlayerPedId()
    local seconds = tonumber(p.seconds) or 3
    active = { endsAt = GetGameTimer() + seconds * 1000, start = GetEntityCoords(ped), health = GetEntityHealth(ped) }
    if seconds > 1.5 then TaskStartScenarioInPlace(ped, 'PROP_HUMAN_BUM_BIN', 0, true) end
    if uiRunning() then
        exports.wasteland_ui:Open(PROGRESS, { script = 'html/progress.js', focus = false, cursor = false,
            data = { label = p.label or 'Working', seconds = seconds } })
    end
    Citizen.CreateThread(function()
        while active do
            local me = PlayerPedId()
            if IsEntityDead(me) or #(GetEntityCoords(me) - active.start) > 1.5 or GetEntityHealth(me) < active.health
                or IsControlJustPressed(0, 73) then
                stop(true)
                return
            end
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
            if GetGameTimer() >= active.endsAt then
                stop(false)
                TriggerServerEvent('wasteland:vehicles:server:finish')
                return
            end
            Citizen.Wait(0)
        end
    end)
end)

-------------------------------------------------------------------------------
-- Owner: apply state. Driver: parts, fuel.
-------------------------------------------------------------------------------

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        local seen = {}
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            local s = stateOf(veh)
            if s then
                seen[veh] = true
                if NetworkHasControlOfEntity(veh) and applied[veh] ~= s.seq then apply(veh, s) end
            end
        end
        for veh in pairs(applied) do if not seen[veh] then applied[veh] = nil end end
    end
end)

Citizen.CreateThread(function()
    local fuel, fuelVeh, lastReport, told = nil, nil, 0, nil
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local s = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and stateOf(veh) or nil
        if s and cfg then
            if fuelVeh ~= veh or (s.fuel or 0) > (fuel or 0) + 0.01 then fuel, fuelVeh = s.fuel or 0, veh end
            local can, why = Rules.canRun({ fuel = fuel, engine = GetVehicleEngineHealth(veh), parts = s.parts })
            driving = { veh = veh, fuel = fuel, why = (not can) and why or nil }
            if not can then
                SetVehicleEngineOn(veh, false, true, true)
                SetVehicleUndriveable(veh, true)
                if told ~= veh then told = veh; notice(why) end
            else
                SetVehicleUndriveable(veh, false)
                told = nil
                if GetIsVehicleEngineRunning(veh) then
                    fuel = math.max(0, fuel - Rules.fuelUsed(cfg.fuel, GetEntitySpeed(veh) * 3.6, GetFrameTime()))
                    SetVehicleFuelLevel(veh, fuel / (s.tank or 50) * 100.0)
                    if GetGameTimer() - lastReport > 5000 and fuel < (s.fuel or 0) - 0.05 then
                        lastReport = GetGameTimer()
                        TriggerServerEvent('wasteland:vehicles:server:fuel', NetworkGetNetworkIdFromEntity(veh), fuel + 0.0)
                    end
                end
            end
            Citizen.Wait(0)
        else
            if fuelVeh and fuel and DoesEntityExist(fuelVeh) then
                -- left the vehicle: report the last bit of fuel used
                TriggerServerEvent('wasteland:vehicles:server:fuel', NetworkGetNetworkIdFromEntity(fuelVeh), fuel + 0.0)
            end
            fuel, fuelVeh, told, driving = nil, nil, nil, nil
            Citizen.Wait(500)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
        if ok and ready then break end
        Citizen.Wait(1000)
    end
    TriggerServerEvent('wasteland:vehicles:server:config')
end)

-------------------------------------------------------------------------------
-- Vehicle HUD (any seat)
-------------------------------------------------------------------------------

Citizen.CreateThread(function()
    local shown = false
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and uiRunning() and not IsPauseMenuActive() then
            local s = stateOf(veh) or {}
            local mine = driving and driving.veh == veh
            local data = {
                speed = GetEntitySpeed(veh), metric = ShouldUseMetricMeasurements(),
                fuel = mine and driving.fuel or s.fuel or (GetVehicleFuelLevel(veh) / 2), tank = s.tank or 50,
                engine = GetVehicleEngineHealth(veh), body = GetVehicleBodyHealth(veh),
                locked = s.locked, hasLock = s.hasLock, warning = mine and driving.why or nil,
            }
            if shown and exports.wasteland_ui:IsOpen(HUD) then
                exports.wasteland_ui:Update(HUD, data)
            else
                exports.wasteland_ui:Open(HUD, { script = 'html/hud.js', data = data, focus = false, cursor = false })
                shown = true
            end
            Citizen.Wait(200)
        else
            if shown then
                shown = false
                if uiRunning() and exports.wasteland_ui:IsOpen(HUD) then exports.wasteland_ui:Close(HUD) end
            end
            Citizen.Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stop(false)
    if uiRunning() and exports.wasteland_ui:IsOpen(HUD) then exports.wasteland_ui:Close(HUD) end
end)
