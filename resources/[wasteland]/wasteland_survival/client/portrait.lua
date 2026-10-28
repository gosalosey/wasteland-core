-- wasteland_survival :: client/portrait.lua
-- The HUD's picture of your own character (Body style). When the character
-- or their clothes change, and the player is standing safely, a copy of the
-- character is put high above them in the sky with a light on it; a camera
-- looks at it for a moment and two screenshots are taken (screenshot-basic):
-- one with the copy, one without. The HUD keeps the pixels that differ, i.e.
-- the character on a clear background, and stores the picture on this PC
-- (so it is only taken again when the clothes change).
-- Without screenshot-basic the HUD keeps the plain figure.

WLPortrait = { sig = nil, shots = nil, wanted = false, busy = false }
local P = WLPortrait

local SS = 'screenshot-basic'
local SKY = 260.0           -- metres above the player where the copy stands
local DIST, FOV = 3.3, 34.0  -- camera distance and field of view (the whole body fits)

local function available() return GetResourceState(SS) == 'started' end

-- What the character looks like: model, every clothing slot and accessory.
local function signature(ped)
    local parts = { tostring(GetEntityModel(ped)) }
    for c = 0, 11 do parts[#parts + 1] = GetPedDrawableVariation(ped, c) .. '.' .. GetPedTextureVariation(ped, c) end
    for p = 0, 7 do parts[#parts + 1] = GetPedPropIndex(ped, p) .. '.' .. GetPedPropTextureIndex(ped, p) end
    return table.concat(parts, ',')
end

-- Why a picture cannot be taken right now (nil = it can). Only when nothing
-- is going on: a camera cut must not cost anyone a fight.
local function blocked(ped)
    if not available() then return 'screenshot-basic is not running (server.cfg needs "ensure screenshot-basic", then a restart)' end
    if IsEntityDead(ped) then return 'you are dead' end
    if IsPedInAnyVehicle(ped, true) then return 'you are in a vehicle' end
    if IsPedRagdoll(ped) or IsPedFalling(ped) or IsPedSwimming(ped) then return 'you are not standing' end
    if IsPedShooting(ped) or IsPedInMeleeCombat(ped) or IsPlayerFreeAiming(PlayerId()) then return 'you are fighting' end
    if IsPauseMenuActive() or IsNuiFocused() then return 'a menu is open' end
    if not IsScreenFadedIn() then return 'the screen is faded' end
    if GetEntitySpeed(ped) >= 0.5 then return 'you are moving' end
    return nil
end

local function say(msg)
    print('[wasteland_survival] character picture: ' .. msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName('HUD picture: ' .. msg)
    EndTextCommandThefeedPostTicker(false, false)
end

-- One screenshot; nil if screenshot-basic does not answer within 3 s.
local function shot()
    local p = promise.new()
    local okCall, err = pcall(function()
        exports[SS]:requestScreenshot({ encoding = 'jpg', quality = 0.92 }, function(data) p:resolve(data) end)
    end)
    if not okCall then error('screenshot-basic: ' .. tostring(err)) end
    SetTimeout(3000, function() p:resolve(nil) end)
    return Citizen.Await(p)
end

local function waitFrames(n) for _ = 1, n do Citizen.Wait(0) end end

local function capture(sig)
    local ped = PlayerPedId()
    local base = GetEntityCoords(ped)
    local at = vector3(base.x, base.y, base.z + SKY)
    local copy = ClonePed(ped, false, false, true)
    if not copy or copy == 0 then return end
    SetEntityCoordsNoOffset(copy, at.x, at.y, at.z, false, false, false)
    SetEntityHeading(copy, 0.0)
    FreezeEntityPosition(copy, true)
    SetEntityInvincible(copy, true)
    SetEntityCollision(copy, false, false)
    SetBlockingOfNonTemporaryEvents(copy, true)
    TaskStandStill(copy, -1)
    -- the camera in front of the copy (it faces north: heading 0)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', at.x, at.y + DIST, at.z + 0.05, 0.0, 0.0, 180.0, FOV, false, 2)
    PointCamAtCoord(cam, at.x, at.y, at.z - 0.05)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    local t0 = GetGameTimer()
    local first, second
    Citizen.CreateThread(function()   -- light and no game HUD while the camera looks
        while cam and GetGameTimer() - t0 < 4000 do
            HideHudAndRadarThisFrame()
            DrawLightWithRange(at.x, at.y + 1.8, at.z + 0.6, 255, 245, 230, 6.0, 4.0)
            DrawLightWithRange(at.x - 1.2, at.y + 1.0, at.z - 0.4, 200, 210, 230, 5.0, 2.0)
            Citizen.Wait(0)
        end
    end)
    local ok, err = pcall(function()
        -- let the clothes stream in on the copy
        local deadline = GetGameTimer() + 1500
        while (not HasPedHeadBlendFinished(copy) or not HaveAllStreamingRequestsCompleted(copy)) and GetGameTimer() < deadline do Citizen.Wait(0) end
        waitFrames(6)
        first = shot()
        SetEntityVisible(copy, false, false)
        waitFrames(3)
        second = shot()
    end)
    -- always hand the view back and remove the copy
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, false)
    cam = nil
    DeleteEntity(copy)
    if not ok then error(err) end
    if type(first) == 'string' and type(second) == 'string' and #first > 100 then
        P.shots = { sig = sig, id = GetGameTimer(), with = first, without = second }
        return true
    end
    error('screenshot-basic took no picture (no answer within 3 s)')
end

-- The HUD asks: it has no picture for this look (or never had one).
function P.need() P.wanted = true end

-- The HUD made and stored the picture: do not send the shots again.
function P.done() P.shots = nil end

-- The HUD could not make a picture from the shots.
function P.failed(why) P.shots = nil; say('failed: ' .. tostring(why or 'no character in the shots')) end

-- What hudData sends: the look, and the shots once after a capture.
function P.data()
    if not P.sig then return nil end
    return { sig = P.sig, shots = P.shots }
end

Citizen.CreateThread(function()
    local last, changedAt = nil, 0
    while true do
        Citizen.Wait(2000)
        local ped = PlayerPedId()
        local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
        if ok and ready and DoesEntityExist(ped) then
            local sig = signature(ped)
            if sig ~= last then last, changedAt = sig, GetGameTimer() end
            -- the look has settled for a few seconds (dressing in the inventory changes it bit by bit)
            if GetGameTimer() - changedAt > 4000 then
                if P.sig ~= sig then P.sig = sig end
                local why = blocked(ped)
                if P.wanted and not P.busy and not why then
                    P.busy, P.wanted = true, false
                    local okC, err = pcall(capture, sig)
                    if not okC then say('failed: ' .. tostring(err)) end
                    P.busy = false
                elseif P.wanted and why and why ~= P.lastWhy then
                    print('[wasteland_survival] character picture waits: ' .. why)
                end
                P.lastWhy = why
            end
        end
    end
end)

-- /hudphoto: take the picture now, and say why if it cannot be taken.
RegisterCommand('hudphoto', function()
    local ped = PlayerPedId()
    if P.busy then return say('already taking it') end
    local why = blocked(ped)
    if why then return say('cannot take it now: ' .. why) end
    Citizen.CreateThread(function()
        P.busy = true
        local sig = signature(ped)
        P.sig = sig
        local ok, err = pcall(capture, sig)
        P.busy = false
        if ok then say('taken; it shows in a moment') else say('failed: ' .. tostring(err)) end
    end)
end, false)
