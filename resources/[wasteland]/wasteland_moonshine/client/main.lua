-- wasteland_moonshine :: client/main.lua
-- Draws the stills (spawned here, not networked), Left Alt opens one, places
-- a still from its item, shows being drunk (walk, camera, blur) and the
-- Zombie Blind meter (safe from zombies / not safe).

local STILL_SCREEN, METER = 'moonshineStill', 'moonshineMeter'
local cfg = nil
local stills = {}      -- id -> info
local spawned = {}     -- id -> { obj, targets }
local placing = false
local mood = { drunk = 0, blind = 0, masked = false }

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(msg))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:moonshine:client:notice', function(m) notify(m) end)

local function loadModel(name)
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local untilT = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < untilT do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

-------------------------------------------------------------------------------
-- Stills
-------------------------------------------------------------------------------

local function despawn(id)
    local e = spawned[id]
    if not e then return end
    if e.targets and GetResourceState('wasteland_target') == 'started' then
        for _, t in ipairs(e.targets) do pcall(function() exports.wasteland_target:Remove(t) end) end
    end
    if DoesEntityExist(e.obj) then DeleteEntity(e.obj) end
    spawned[id] = nil
end

local function spawn(s)
    local hash = cfg and loadModel(cfg.model)
    if not hash or spawned[s.id] then return end
    local obj = CreateObjectNoOffset(hash, s.coords.x, s.coords.y, s.coords.z, false, false, false)
    SetEntityHeading(obj, s.heading)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    local e = { obj = obj }
    if GetResourceState('wasteland_target') == 'started' then
        e.targets = { exports.wasteland_target:AddEntity(obj, {
            { label = 'Use moonshine still', icon = '⚗', distance = 3.0, onSelect = function() TriggerServerEvent('wasteland:moonshine:server:open', s.id) end },
        }) }
    end
    spawned[s.id] = e
end

RegisterNetEvent('wasteland:moonshine:client:sync', function(c, list)
    for id in pairs(spawned) do despawn(id) end
    stills, cfg = {}, c
    for _, s in ipairs(type(list) == 'table' and list or {}) do stills[s.id] = s end
end)
RegisterNetEvent('wasteland:moonshine:client:still', function(s) if type(s) == 'table' and s.id then stills[s.id] = s end end)
RegisterNetEvent('wasteland:moonshine:client:remove', function(id) stills[id] = nil; despawn(id) end)

Citizen.CreateThread(function()
    Wait(2500)
    TriggerServerEvent('wasteland:moonshine:server:sync')
    while true do
        if cfg then
            local me = GetEntityCoords(PlayerPedId())
            local r = cfg.streamDistance or 150.0
            for id, s in pairs(stills) do
                local d = #(me - vector3(s.coords.x, s.coords.y, s.coords.z))
                if d <= r and not spawned[id] then spawn(s)
                elseif d > r + 20.0 and spawned[id] then despawn(id) end
            end
        end
        Wait(1000)
    end
end)

-- The still screen
RegisterNetEvent('wasteland:moonshine:client:view', function(v)
    if not uiRunning() or type(v) ~= 'table' then return end
    if exports.wasteland_ui:IsOpen(STILL_SCREEN) then exports.wasteland_ui:Update(STILL_SCREEN, v)
    else exports.wasteland_ui:Open(STILL_SCREEN, { script = 'html/still.js', data = v, focus = true, cursor = true }) end
end)
RegisterNetEvent('wasteland:moonshine:client:closeView', function()
    if uiRunning() and exports.wasteland_ui:IsOpen(STILL_SCREEN) then exports.wasteland_ui:Close(STILL_SCREEN) end
end)
AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= STILL_SCREEN then return end
    payload = type(payload) == 'table' and payload or {}
    local id = tonumber(payload.id)
    if action == 'close' then exports.wasteland_ui:Close(STILL_SCREEN)
    elseif action == 'brew' and id and type(payload.flavour) == 'string' then TriggerServerEvent('wasteland:moonshine:server:brew', id, payload.flavour)
    elseif action == 'collect' and id then TriggerServerEvent('wasteland:moonshine:server:collect', id)
    elseif action == 'pickup' and id then TriggerServerEvent('wasteland:moonshine:server:pickup', id)
    elseif action == 'refresh' and id then TriggerServerEvent('wasteland:moonshine:server:open', id) end
end)

-- Placing a still
local function rotToDir(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

RegisterNetEvent('wasteland:moonshine:client:place', function()
    if placing or not cfg then return end
    local hash = loadModel(cfg.model)
    if not hash then notify('The still cannot be shown right now.'); return end
    placing = true
    local ped = PlayerPedId()
    local start = GetEntityCoords(ped)
    local ghost = CreateObjectNoOffset(hash, start.x, start.y, start.z, false, false, false)
    SetEntityAlpha(ghost, 160, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    local heading = GetEntityHeading(ped)
    Citizen.CreateThread(function()
        while placing do
            Wait(0)
            for _, c in ipairs({ 24, 25, 14, 15, 16, 17, 37, 44, 140, 141, 142, 177, 194, 200 }) do DisableControlAction(0, c, true) end
            if IsDisabledControlJustPressed(0, 14) then heading = (heading - 15.0) % 360.0 end
            if IsDisabledControlJustPressed(0, 15) then heading = (heading + 15.0) % 360.0 end
            local from = GetGameplayCamCoord()
            local to = from + rotToDir(GetGameplayCamRot(2)) * 10.0
            local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, -1, ghost, 7)
            local _, hit, pos = GetShapeTestResult(ray)
            local at = hit == 1 and pos or to
            SetEntityCoordsNoOffset(ghost, at.x, at.y, at.z, false, false, false)
            SetEntityHeading(ghost, heading)
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('Moonshine still~n~~INPUT_CONTEXT~ place   ~INPUT_FRONTEND_RRIGHT~ cancel~n~Wheel: turn')
            EndTextCommandDisplayHelp(0, false, false, -1)
            if IsControlJustReleased(0, 38) then
                if hit == 1 and #(GetEntityCoords(ped) - at) <= 7.5 then
                    TriggerServerEvent('wasteland:moonshine:server:place', at.x, at.y, at.z, heading)
                    placing = false
                else
                    notify('Aim at the ground (or a floor) close to you.')
                end
            end
            if IsDisabledControlJustReleased(0, 177) or IsDisabledControlJustReleased(0, 194) or IsDisabledControlJustReleased(0, 200) or IsEntityDead(ped) then
                placing = false
                notify('Placing cancelled.')
            end
        end
        if DoesEntityExist(ghost) then DeleteEntity(ghost) end
    end)
end)

-------------------------------------------------------------------------------
-- Drunk: walking, camera sway and blur grow with how drunk you are
-------------------------------------------------------------------------------

local clipset = nil
local function setWalk(name)
    local ped = PlayerPedId()
    if name == clipset then return end
    clipset = name
    if not name then ResetPedMovementClipset(ped, 0.5); return end
    RequestAnimSet(name)
    local untilT = GetGameTimer() + 1000
    while not HasAnimSetLoaded(name) and GetGameTimer() < untilT do Wait(0) end
    SetPedMovementClipset(ped, name, 0.5)
end

local function applyDrunk(level)
    if level <= 5 then
        setWalk(nil)
        ClearTimecycleModifier()
        StopGameplayCamShaking(true)
        SetPedIsDrunk(PlayerPedId(), false)
        return
    end
    setWalk(level >= 55 and 'move_m@drunk@verydrunk' or 'move_m@drunk@slightlydrunk')
    SetTimecycleModifier('spectator5')
    SetTimecycleModifierStrength(math.min(1.0, level / 100))
    ShakeGameplayCam('DRUNK_SHAKE', math.min(2.0, level / 40))
    SetPedIsDrunk(PlayerPedId(), true)
end

RegisterNetEvent('wasteland:moonshine:client:drank', function()
    local ped = PlayerPedId()
    RequestAnimDict('mp_player_intdrink')
    local untilT = GetGameTimer() + 1500
    while not HasAnimDictLoaded('mp_player_intdrink') and GetGameTimer() < untilT do Wait(0) end
    if HasAnimDictLoaded('mp_player_intdrink') and not IsPedInAnyVehicle(ped, false) then
        TaskPlayAnim(ped, 'mp_player_intdrink', 'loop_bottle', 4.0, -4.0, 2500, 49, 0, false, false, false)
    end
end)

-------------------------------------------------------------------------------
-- The Zombie Blind meter
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:moonshine:client:state', function(s)
    if type(s) ~= 'table' then return end
    local wasDrunk = mood.drunk
    mood = { drunk = tonumber(s.drunk) or 0, blind = tonumber(s.blind) or 0, masked = s.masked == true }
    if math.abs(mood.drunk - wasDrunk) > 0.5 or mood.drunk <= 5 then applyDrunk(mood.drunk) end
    if not uiRunning() then return end
    local data = { blind = mood.blind, masked = mood.masked, unmaskBelow = cfg and cfg.unmaskBelow or 40, drunk = mood.drunk }
    if mood.blind > 0 or mood.masked then
        if exports.wasteland_ui:IsOpen(METER) then exports.wasteland_ui:Update(METER, data)
        else exports.wasteland_ui:Open(METER, { script = 'html/meter.js', data = data, focus = false, cursor = false }) end
    elseif exports.wasteland_ui:IsOpen(METER) then
        exports.wasteland_ui:Close(METER)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do despawn(id) end
    applyDrunk(0)
    if uiRunning() then
        for _, sc in ipairs({ STILL_SCREEN, METER }) do if exports.wasteland_ui:IsOpen(sc) then exports.wasteland_ui:Close(sc) end end
    end
end)
