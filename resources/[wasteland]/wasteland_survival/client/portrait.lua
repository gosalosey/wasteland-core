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

-- Only when nothing is going on: a camera cut must not cost anyone a fight.
local function calm(ped)
    return not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, true) and not IsPedRagdoll(ped) and not IsPedFalling(ped)
        and not IsPedSwimming(ped) and not IsPedShooting(ped) and not IsPedInMeleeCombat(ped) and not IsPlayerFreeAiming(PlayerId())
        and not IsPauseMenuActive() and not IsNuiFocused() and IsScreenFadedIn() and GetEntitySpeed(ped) < 0.5
end

local function shot()
    local p = promise.new()
    exports[SS]:requestScreenshot({ encoding = 'jpg', quality = 0.92 }, function(data) p:resolve(data) end)
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
        P.shots = { sig = sig, with = first, without = second }
    end
end

-- The HUD asks: it has no picture for this look (or never had one).
function P.need() P.wanted = true end

-- The HUD made and stored the picture: do not send the shots again.
function P.done() P.shots = nil end

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
                if P.wanted and not P.busy and available() and calm(ped) then
                    P.busy, P.wanted = true, false
                    local okC, err = pcall(capture, sig)
                    if not okC then print('[wasteland_survival] character picture failed: ' .. tostring(err)) end
                    P.busy = false
                end
            end
        end
    end
end)
