-- wasteland_supplydrops :: client/main.lua
-- Shows supply drops: a map blip, a message, and near the drop a crate with
-- a red smoke flare and a target option ("Open supply crate"). The client
-- only shows things and asks; the server decides (distance, contents).

local CRATE = GetHashKey('prop_mil_crate_01')
local drops = {}   -- id -> { info, blip, area, object, fx, target }

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:supplydrops:client:notice', function(m) notice(m) end)

local function targetRunning() return GetResourceState('wasteland_target') == 'started' end

local function removeCrate(d)
    if d.target and targetRunning() then pcall(function() exports.wasteland_target:Remove(d.target) end) end
    if d.fx then StopParticleFxLooped(d.fx, false) end
    if d.object and DoesEntityExist(d.object) then DeleteEntity(d.object) end
    d.target, d.fx, d.object = nil, nil, nil
end

-- The crate is a local object, made only when the player is near.
local function makeCrate(id, d)
    RequestModel(CRATE)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(CRATE) and GetGameTimer() < deadline do Citizen.Wait(0) end
    if not HasModelLoaded(CRATE) or not drops[id] then return end
    local c = d.info.coords
    local found, ground = GetGroundZFor_3dCoord(c.x + 0.0, c.y + 0.0, c.z + 50.0, false)
    local z = found and ground or c.z
    d.object = CreateObject(CRATE, c.x + 0.0, c.y + 0.0, z + 0.0, false, false, false)
    SetModelAsNoLongerNeeded(CRATE)
    PlaceObjectOnGroundProperly(d.object)
    FreezeEntityPosition(d.object, true)
    -- Red smoke so players can find it from afar.
    RequestNamedPtfxAsset('core')
    deadline = GetGameTimer() + 2000
    while not HasNamedPtfxAssetLoaded('core') and GetGameTimer() < deadline do Citizen.Wait(0) end
    if HasNamedPtfxAssetLoaded('core') then
        UseParticleFxAssetNextCall('core')
        d.fx = StartParticleFxLoopedAtCoord('exp_grd_flare', c.x + 1.0, c.y, z, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
    end
    if targetRunning() then
        d.target = exports.wasteland_target:AddEntity(d.object, {
            { label = 'Open supply crate', icon = '▣', distance = 2.5,
                onSelect = function() TriggerServerEvent('wasteland:supplydrops:server:open', id) end },
        })
    end
end

RegisterNetEvent('wasteland:supplydrops:client:drop', function(info, announce)
    if type(info) ~= 'table' or drops[info.id] then return end
    local c = info.coords
    local d = { info = info }
    d.area = AddBlipForRadius(c.x + 0.0, c.y + 0.0, c.z + 0.0, 120.0)
    SetBlipColour(d.area, 1)
    SetBlipAlpha(d.area, 80)
    d.blip = AddBlipForCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
    SetBlipSprite(d.blip, 568) -- crate
    SetBlipColour(d.blip, 1)
    SetBlipScale(d.blip, 1.0)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Supply drop')
    EndTextCommandSetBlipName(d.blip)
    drops[info.id] = d
    if announce then
        notice(string.format('~r~Supply drop~s~ coming down near %s. It will not last long.', info.label))
        PlaySoundFrontend(-1, 'CHALLENGE_UNLOCKED', 'HUD_AWARDS', true)
    end
end)

RegisterNetEvent('wasteland:supplydrops:client:remove', function(id)
    local d = drops[id]
    if not d then return end
    removeCrate(d)
    if d.blip then RemoveBlip(d.blip) end
    if d.area then RemoveBlip(d.area) end
    drops[id] = nil
end)

-- Make or remove crates as the player gets near or moves away.
Citizen.CreateThread(function()
    TriggerServerEvent('wasteland:supplydrops:server:sync')
    while true do
        Citizen.Wait(1000)
        local me = GetEntityCoords(PlayerPedId())
        for id, d in pairs(drops) do
            local c = d.info.coords
            local dist = #(me - vector3(c.x, c.y, c.z))
            if dist < 150.0 and not d.object then
                makeCrate(id, d)
            elseif dist > 200.0 and d.object then
                removeCrate(d)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, d in pairs(drops) do
        removeCrate(d)
        if d.blip then RemoveBlip(d.blip) end
        if d.area then RemoveBlip(d.area) end
    end
    drops = {}
end)
