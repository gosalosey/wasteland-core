-- wasteland_vehicles :: client/main.lua
-- For vehicles this client runs (OneSync owner): apply the saved state
-- (damage, missing wheels, fuel gauge). For the driver: no engine without
-- the parts, fuel use (reported to the server). Target options on every
-- vehicle (check, trunk, parts, refuel, repair, lock) and on gas pumps.
-- The server decides every change.

local Rules = WLVE.Rules
local PROGRESS = 'vehProgress'
local LOCKPICK = 'vehLockpick'
local picking = false  -- the lockpick minigame is open
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
        return s ~= nil and active == nil and not picking and test(s, entity)
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

-- The nearest world vehicle parked next to a pump that is not full, or nil.
local function vehicleAtPump(pump)
    if not pump or pump == 0 or not cfg then return nil end
    local pc = GetEntityCoords(pump)
    local best, bestDist = nil, (cfg.pumpVehicleDistance or 8.0) - 0.5
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local s = stateOf(veh)
        if s and NetworkGetEntityIsNetworked(veh) and (s.fuel or 0) < (s.tank or 50) - 0.5 then
            local d = #(GetEntityCoords(veh) - pc)
            if d < bestDist then best, bestDist = veh, d end
        end
    end
    return best
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
        { label = 'Siphon fuel (hose)', icon = '⛽', distance = 3.0, canInteract = when(function(s) return (s.fuel or 0) >= 0.5 end),
            onSelect = act('siphon') },
        { label = 'Repair (toolkit)', icon = '⚒', distance = 3.0,
            canInteract = when(function(_, veh) return GetVehicleEngineHealth(veh) < 990 or GetVehicleBodyHealth(veh) < 990 end), onSelect = act('repair') },
        { label = 'Fit a lock', icon = '🔒', distance = 3.0, canInteract = when(function(s) return not s.hasLock end), onSelect = act('fitLock') },
        { label = 'Lock / unlock (key)', icon = '🔑', distance = 3.0, canInteract = when(function(s) return s.hasLock end), onSelect = act('toggleLock') },
        { label = 'Pick the lock', icon = '⌕', distance = 3.0, canInteract = when(function(s) return s.locked end), onSelect = act('pickLock') },
        -- Only the survivor who fitted the lock (the server checks it too).
        { label = 'Take the lock off', icon = '🔓', distance = 3.0, onSelect = act('removeLock'),
            canInteract = when(function(s) return s.hasLock and (s.lockBy == nil or s.lockBy == LocalPlayer.state.wlCharacterId) end) },
    })
    if cfg.pumps and #cfg.pumps > 0 then
        targetIds[#targetIds + 1] = exports.wasteland_target:AddModel(cfg.pumps, {
            { label = 'Refuel vehicle', icon = '⛽', distance = 2.5,
                canInteract = function(entity) return active == nil and vehicleAtPump(entity) ~= nil end,
                onSelect = function(data)
                    local veh = vehicleAtPump(data.entity)
                    if not veh then return end
                    local c = GetEntityCoords(data.entity)
                    TriggerServerEvent('wasteland:vehicles:server:pumpRefuel', NetworkGetNetworkIdFromEntity(veh), { x = c.x, y = c.y, z = c.z })
                end },
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
-- Lockpick minigame
-------------------------------------------------------------------------------

local function endPicking()
    if not picking then return end
    picking = false
    ClearPedTasks(PlayerPedId())
    if uiRunning() and exports.wasteland_ui:IsOpen(LOCKPICK) then exports.wasteland_ui:Close(LOCKPICK) end
end

RegisterNetEvent('wasteland:vehicles:client:lockpick', function(p)
    if type(p) ~= 'table' or active or picking or not uiRunning() then
        TriggerServerEvent('wasteland:vehicles:server:cancel')
        return
    end
    picking = true
    local ped = PlayerPedId()
    local dict = 'veh@break_in@0h@p_m_one@'
    Citizen.CreateThread(function()
        RequestAnimDict(dict)
        local t = GetGameTimer() + 1500
        while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Citizen.Wait(10) end
        if picking and HasAnimDictLoaded(dict) then TaskPlayAnim(ped, dict, 'low_force_entry_ds', 2.0, 2.0, -1, 1, 0, false, false, false) end
    end)
    exports.wasteland_ui:Open(LOCKPICK, { script = 'html/lockpick.js', focus = true, cursor = false, data = p })
    -- Dying or getting hurt ends it.
    local health = GetEntityHealth(ped)
    Citizen.CreateThread(function()
        while picking do
            local me = PlayerPedId()
            if IsEntityDead(me) or GetEntityHealth(me) < health then
                endPicking()
                TriggerServerEvent('wasteland:vehicles:server:cancel')
                notice('You were interrupted.')
                return
            end
            Citizen.Wait(100)
        end
    end)
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= LOCKPICK or not picking then return end
    if action == 'result' then
        endPicking()
        TriggerServerEvent('wasteland:vehicles:server:lockpick', type(payload) == 'table' and payload.success == true)
    elseif action == 'cancel' then
        endPicking()
        TriggerServerEvent('wasteland:vehicles:server:cancel')
        notice('You stop picking the lock.')
    end
end)

-------------------------------------------------------------------------------
-- Clear spots (asked by the server before a vehicle first appears here)
-------------------------------------------------------------------------------

local function groundAt(x, y, z)
    local found, g = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, z + 3.0, false)
    if found and math.abs(g - z) < 6.0 then return g end
    return nil
end

local function rayHits(a, b)
    -- world (1) and objects (16)
    local probe = StartExpensiveSynchronousShapeTestLosProbe(a.x, a.y, a.z, b.x, b.y, b.z, 17, PlayerPedId(), 7)
    local _, hit = GetShapeTestResult(probe)
    return hit == 1
end

-- Is a car-sized spot (5 x 2.4 m) at x, y, z (ground) facing heading free?
local function spotClear(x, y, z, heading, clearance)
    local p = vector3(x, y, z)
    for _, obj in ipairs(GetGamePool('CObject')) do
        if not IsEntityAttached(obj) then
            local c = GetEntityCoords(obj)
            if #(vector2(c.x, c.y) - vector2(x, y)) < clearance and math.abs(c.z - z) < 3.0 then return false end
        end
    end
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local c = GetEntityCoords(veh)
        if #(vector2(c.x, c.y) - vector2(x, y)) < 4.5 and math.abs(c.z - z) < 3.0 then return false end
    end
    local h = math.rad(heading)
    local fwd, right = vector3(-math.sin(h), math.cos(h), 0.0), vector3(math.cos(h), math.sin(h), 0.0)
    for _, up in ipairs({ 0.6, 1.3 }) do
        local base = p + vector3(0.0, 0.0, up)
        if rayHits(base - fwd * 2.6, base + fwd * 2.6) or rayHits(base - right * 1.3, base + right * 1.3)
            or rayHits(base - fwd * 2.6 - right * 1.2, base + fwd * 2.6 + right * 1.2)
            or rayHits(base - fwd * 2.6 + right * 1.2, base + fwd * 2.6 - right * 1.2) then
            return false
        end
    end
    -- Not on steep ground: the corners within 1 m of the middle's height.
    for _, c in ipairs({ p + fwd * 2.3 + right * 1.0, p + fwd * 2.3 - right * 1.0, p - fwd * 2.3 + right * 1.0, p - fwd * 2.3 - right * 1.0 }) do
        local g = groundAt(c.x, c.y, z)
        if not g or math.abs(g - z) > 1.0 then return false end
    end
    return true
end

RegisterNetEvent('wasteland:vehicles:client:checkSpot', function(id, c, opts)
    if type(c) ~= 'table' or type(opts) ~= 'table' then return end
    Citizen.CreateThread(function()
        -- Load the collision there first (the spot may be up to ~250 m away).
        local untilT = GetGameTimer() + 1500
        while GetGameTimer() < untilT do
            RequestCollisionAtCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
            Citizen.Wait(0)
        end
        local clearance, radius = tonumber(opts.clearance) or 3.2, tonumber(opts.radius) or 12
        local heading = tonumber(c.heading) or 0.0
        local g = groundAt(c.x, c.y, c.z)
        if g and spotClear(c.x, c.y, g, heading, clearance) then
            TriggerServerEvent('wasteland:vehicles:server:spot', id, { ok = true })
            return
        end
        -- Rings around the spot, nearest first.
        local step = 2.5
        local r = step
        while r <= radius do
            local n = math.max(8, math.floor(2 * math.pi * r / step))
            for i = 0, n - 1 do
                local a = (i / n) * 2 * math.pi
                local x, y = c.x + math.cos(a) * r, c.y + math.sin(a) * r
                local gz = groundAt(x, y, c.z)
                if gz and spotClear(x, y, gz, heading, clearance) then
                    TriggerServerEvent('wasteland:vehicles:server:spot', id, { x = x, y = y, z = gz, heading = heading })
                    return
                end
            end
            r = r + step
            Citizen.Wait(0)
        end
        TriggerServerEvent('wasteland:vehicles:server:spot', id, { blocked = true })
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
            -- Take the saved level when it went up (refuelled) or clearly down (siphoned).
            if fuelVeh ~= veh or (s.fuel or 0) > (fuel or 0) + 0.01 or (s.fuel or 0) < (fuel or 0) - 0.5 then fuel, fuelVeh = s.fuel or 0, veh end
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
-- Pump level above the pump you stand next to
-------------------------------------------------------------------------------

local pumpInfo = {}    -- pump key -> { litres, max, minutes, at }

RegisterNetEvent('wasteland:vehicles:client:pump', function(key, info)
    if type(key) == 'string' and type(info) == 'table' then info.at = GetGameTimer(); pumpInfo[key] = info end
end)

local function text3d(x, y, z, line1, line2)
    SetDrawOrigin(x, y, z, 0)
    for i, line in ipairs({ line1, line2 }) do
        if line then
            SetTextScale(0.0, 0.32)
            SetTextFont(4)
            SetTextProportional(true)
            SetTextColour(220, 235, 210, 230)
            SetTextOutline()
            SetTextCentre(true)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(line)
            EndTextCommandDisplayText(0.0, (i - 1) * 0.022)
        end
    end
    ClearDrawOrigin()
end

Citizen.CreateThread(function()
    local nearKey, asked = nil, 0
    while true do
        if cfg and cfg.pumps then
            local p = GetEntityCoords(PlayerPedId())
            local near = nil
            for _, model in ipairs(cfg.pumps) do
                local obj = GetClosestObjectOfType(p.x, p.y, p.z, 3.0, GetHashKey(model), false, false, false)
                if obj ~= 0 then near = obj; break end
            end
            if near then
                local c = GetEntityCoords(near)
                local key = Rules.pumpKey({ x = c.x, y = c.y, z = c.z })
                if key ~= nearKey or GetGameTimer() - asked > 5000 then
                    nearKey, asked = key, GetGameTimer()
                    TriggerServerEvent('wasteland:vehicles:server:pumpInfo', { x = c.x, y = c.y, z = c.z })
                end
                -- Draw every frame while standing here (re-checked twice a second).
                local untilMs = GetGameTimer() + 500
                while GetGameTimer() < untilMs do
                    local info = pumpInfo[key]
                    if info then
                        local second = 'Full'
                        if (info.minutes or 0) > 0 then
                            local left = math.max(1, info.minutes - math.floor((GetGameTimer() - info.at) / 60000))
                            second = 'Full again in ' .. Rules.duration(left)
                        end
                        text3d(c.x, c.y, c.z + 1.25, string.format('Fuel: %d / %d L', info.litres, info.max), second)
                    else
                        text3d(c.x, c.y, c.z + 1.25, 'Fuel: ...', nil)
                    end
                    Citizen.Wait(0)
                end
            else
                nearKey = nil
                Citizen.Wait(750)
            end
        else
            Citizen.Wait(2000)
        end
    end
end)

-------------------------------------------------------------------------------
-- Vehicle HUD (any seat). Moved and resized in the /hud edit mode; the
-- layout is kept on this computer (KVP) like the main HUD's.
-------------------------------------------------------------------------------

local hudLayout = { scale = 1 }   -- x, y: share of the free screen space (nil = bottom middle)
local hudEditing, hudBefore = false, nil

local function cleanLayout(p)
    if type(p) ~= 'table' then return { scale = 1 } end
    local function unit(v) return type(v) == 'number' and v == v and math.max(0.0, math.min(1.0, v)) or nil end
    local x, y = unit(p.x), unit(p.y)
    if not x or not y then x, y = nil, nil end
    local scale = type(p.scale) == 'number' and p.scale == p.scale and math.max(0.6, math.min(1.8, p.scale)) or 1
    return { x = x, y = y, scale = scale }
end

do
    local ok, raw = pcall(GetResourceKvpString, 'vehHudLayout')
    if ok and type(raw) == 'string' then
        local okJ, decoded = pcall(json.decode, raw)
        if okJ then hudLayout = cleanLayout(decoded) end
    end
end

AddEventHandler('wasteland:hud:editing', function(on, saved)
    if on then
        hudEditing, hudBefore = true, hudLayout
    elseif hudEditing then
        hudEditing = false
        if saved then SetResourceKvp('vehHudLayout', json.encode(hudLayout)) else hudLayout = hudBefore or hudLayout end
        hudBefore = nil
    end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen == HUD and action == 'layout' and hudEditing then hudLayout = cleanLayout(payload) end
end)

Citizen.CreateThread(function()
    local shown = false
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if (veh ~= 0 or hudEditing) and uiRunning() and not IsPauseMenuActive() then
            local data
            if veh ~= 0 then
                local s = stateOf(veh) or {}
                local mine = driving and driving.veh == veh
                data = {
                    speed = GetEntitySpeed(veh), metric = false, -- always mph (owner's choice)
                    fuel = mine and driving.fuel or s.fuel or (GetVehicleFuelLevel(veh) / 2), tank = s.tank or 50,
                    engine = GetVehicleEngineHealth(veh), body = GetVehicleBodyHealth(veh),
                    locked = s.locked, hasLock = s.hasLock, warning = mine and driving.why or nil,
                }
            else
                -- Not in a vehicle while moving the HUDs: show an example.
                data = { speed = 19.0, metric = false, fuel = 32, tank = 50, engine = 870, body = 640, locked = false, hasLock = true }
            end
            data.layout, data.editing = hudLayout, hudEditing
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
    endPicking()
    if uiRunning() and exports.wasteland_ui:IsOpen(HUD) then exports.wasteland_ui:Close(HUD) end
end)
