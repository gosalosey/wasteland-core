-- wasteland_appearance :: client/main.lua
-- Applies appearances to the player's ped and runs the creator: camera,
-- live preview of every change, and submitting the result to the server
-- (which validates and stores it). Clamps every value to the real counts
-- of the game data before applying.

local SCREEN = 'appearanceCreator'
local current = nil      -- last appearance confirmed by the server
local editing = nil      -- creator state: { appearance, cancellable, cam, mode, baseHeading }
local openToken = nil    -- latest openCreator request (a newer one replaces a waiting one)

-------------------------------------------------------------------------------
-- Applying
-------------------------------------------------------------------------------

local function loadModel(name)
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Citizen.Wait(0) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- Set the ped model if it differs (this resets the ped, so do it first).
local function ensureModel(model)
    local hash = GetHashKey(model)
    if GetEntityModel(PlayerPedId()) == hash then return true end
    local loaded = loadModel(model)
    if not loaded then return false end
    local health = GetEntityHealth(PlayerPedId())
    SetPlayerModel(PlayerId(), loaded)
    SetModelAsNoLongerNeeded(loaded)
    local ped = PlayerPedId()
    SetPedDefaultComponentVariation(ped)
    if health > 0 then SetEntityHealth(ped, health) end
    return true
end

--- Apply everything except the model to the current ped.
local function applyLook(a)
    local ped = PlayerPedId()
    local h = a.heritage or {}
    SetPedHeadBlendData(ped, h.mother or 0, h.father or 0, 0, h.mother or 0, h.father or 0, 0,
        (h.shapeMix or 0.5) + 0.0, (h.skinMix or 0.5) + 0.0, 0.0, false)
    for i = 1, WLA.FEATURE_COUNT do
        SetPedFaceFeature(ped, i - 1, clamp(a.features and a.features[i], -1.0, 1.0) + 0.0)
    end
    local hairMax = GetNumberOfPedDrawableVariations(ped, 2) - 1
    local hair = a.hair or {}
    SetPedComponentVariation(ped, 2, math.floor(clamp(hair.style, 0, math.max(0, hairMax))), 0, 0)
    SetPedHairColor(ped, math.floor(clamp(hair.color, 0, 63)), math.floor(clamp(hair.highlight, 0, 63)))
    SetPedEyeColor(ped, math.floor(clamp(a.eyeColor, 0, 31)))
    for _, def in ipairs(WLA.OVERLAYS) do
        local o = (a.overlays or {})[def.index + 1] or {}
        local max = GetPedHeadOverlayNum(def.index) - 1
        local style = math.floor(tonumber(o.style) or 255)
        if style ~= 255 then style = math.floor(clamp(style, 0, math.max(0, max))) end
        SetPedHeadOverlay(ped, def.index, style, clamp(o.opacity, 0.0, 1.0) + 0.0)
        if def.colorType > 0 then
            local c = math.floor(clamp(o.color, 0, 63))
            SetPedHeadOverlayColor(ped, def.index, def.colorType, c, c)
        end
    end
    for _, c in ipairs(a.components or {}) do
        local drawables = GetNumberOfPedDrawableVariations(ped, c.id)
        if drawables > 0 then
            local d = math.floor(clamp(c.drawable, 0, drawables - 1))
            local textures = GetNumberOfPedTextureVariations(ped, c.id, d)
            SetPedComponentVariation(ped, c.id, d, math.floor(clamp(c.texture, 0, math.max(0, textures - 1))), 0)
        end
    end
    for _, p in ipairs(a.props or {}) do
        local d = math.floor(tonumber(p.drawable) or -1)
        if d < 0 then
            ClearPedProp(ped, p.id)
        else
            local drawables = GetNumberOfPedPropDrawableVariations(ped, p.id)
            if drawables > 0 then
                d = math.floor(clamp(d, 0, drawables - 1))
                local textures = GetNumberOfPedPropTextureVariations(ped, p.id, d)
                SetPedPropIndex(ped, p.id, d, math.floor(clamp(p.texture, 0, math.max(0, textures - 1))), true)
            end
        end
    end
end

local function apply(a)
    if type(a) ~= 'table' or type(a.model) ~= 'string' then return false end
    if not ensureModel(a.model) then
        print(string.format('[wasteland_appearance] model %s could not be loaded', a.model))
        return false
    end
    applyLook(a)
    return true
end

--- Real counts for the creator's pickers, for the ped's current model and choices.
local function ranges(a)
    local ped = PlayerPedId()
    local out = {
        hair = math.max(0, GetNumberOfPedDrawableVariations(ped, 2) - 1),
        overlays = {},
        components = {},
        props = {},
    }
    for _, def in ipairs(WLA.OVERLAYS) do
        out.overlays[def.index + 1] = math.max(0, GetPedHeadOverlayNum(def.index) - 1)
    end
    for _, id in ipairs(WLA.COMPONENT_IDS) do
        local drawable = 0
        for _, c in ipairs(a.components or {}) do if c.id == id then drawable = c.drawable end end
        out.components[tostring(id)] = {
            drawables = math.max(0, GetNumberOfPedDrawableVariations(ped, id) - 1),
            textures = math.max(0, GetNumberOfPedTextureVariations(ped, id, drawable) - 1),
        }
    end
    for _, id in ipairs(WLA.PROP_IDS) do
        local drawable = -1
        for _, p in ipairs(a.props or {}) do if p.id == id then drawable = p.drawable end end
        out.props[tostring(id)] = {
            drawables = math.max(-1, GetNumberOfPedPropDrawableVariations(ped, id) - 1),
            textures = drawable >= 0 and math.max(0, GetNumberOfPedPropTextureVariations(ped, id, drawable) - 1) or 0,
        }
    end
    return out
end

-------------------------------------------------------------------------------
-- Creator camera
-------------------------------------------------------------------------------

local CAMERA = {
    face = { distance = 0.75, height = 0.65, fov = 35.0 },
    -- Whole body, head to feet: the ped's origin is at the hips (~1 m above
    -- the ground), so aim slightly below it and widen the view.
    body = { distance = 3.0, height = -0.1, fov = 50.0 },
}

-- The camera stays where the ped faced when the creator opened (rotating
-- the ped must not rotate the camera with it).
local function placeCamera(mode)
    if not editing then return end
    local ped = PlayerPedId()
    local c = CAMERA[mode] or CAMERA.face
    editing.mode = mode
    if not editing.cam then
        editing.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    end
    local origin = GetEntityCoords(ped)
    local heading = math.rad(editing.baseHeading or GetEntityHeading(ped))
    local fx, fy = -math.sin(heading), math.cos(heading)
    SetCamCoord(editing.cam, origin.x + fx * c.distance, origin.y + fy * c.distance, origin.z + c.height)
    PointCamAtCoord(editing.cam, origin.x, origin.y, origin.z + c.height)
    SetCamFov(editing.cam, c.fov)
    SetCamActive(editing.cam, true)
    RenderScriptCams(true, true, 400, true, false)
end

local function stopCreator()
    if not editing then return end
    if editing.cam then
        RenderScriptCams(false, true, 400, true, false)
        DestroyCam(editing.cam, false)
    end
    editing = nil
    exports.wasteland_ui:Close(SCREEN)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
end

local function labels()
    local overlays = {}
    for i, def in ipairs(WLA.OVERLAYS) do overlays[i] = { label = def.label, colorable = def.colorType > 0 } end
    local components = {}
    for _, id in ipairs(WLA.COMPONENT_IDS) do components[#components + 1] = { id = id, label = WLA.COMPONENT_LABELS[id] } end
    local props = {}
    for _, id in ipairs(WLA.PROP_IDS) do props[#props + 1] = { id = id, label = WLA.PROP_LABELS[id] } end
    return { features = WLA.FEATURE_LABELS, overlays = overlays, components = components, props = props }
end

-- The server opens the creator as the character loads; wait until the
-- players module has placed the player (teleport finished).
local function waitForPlacement()
    local deadline = GetGameTimer() + 15000
    Citizen.Wait(200)
    while GetGameTimer() < deadline do
        local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
        if ok and ready and not IsScreenFadedOut() and not IsScreenFadingIn() and not IsScreenFadingOut() then return end
        Citizen.Wait(100)
    end
end

local function startCreator(info, token)
    if GetResourceState('wasteland_ui') ~= 'started' then
        print('[wasteland_appearance] wasteland_ui is not running; the character creator cannot open')
        return
    end
    waitForPlacement()
    if openToken ~= token then return end
    local start = info.current or current or WLA.defaults('mp_m_freemode_01')
    editing = { appearance = start, cancellable = info.cancellable == true }
    apply(start)
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    editing.baseHeading = GetEntityHeading(ped)
    placeCamera('body')
    exports.wasteland_ui:Open(SCREEN, {
        script = 'html/creator.js',
        data = {
            appearance = start,
            defaults = { male = WLA.defaults('mp_m_freemode_01'), female = WLA.defaults('mp_f_freemode_01') },
            ranges = ranges(start),
            labels = labels(),
            cancellable = editing.cancellable,
            reason = info.reason,
        },
    })
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:appearance:client:openCreator', function(info)
    if type(info) ~= 'table' then return end
    if editing then stopCreator() end
    local token = {}
    openToken = token
    Citizen.CreateThread(function() startCreator(info, token) end)
end)

RegisterNetEvent('wasteland:appearance:client:apply', function(a)
    current = a
    Citizen.CreateThread(function() apply(a) end)
end)

RegisterNetEvent('wasteland:appearance:client:saved', function(a)
    current = a
    stopCreator()
    Citizen.CreateThread(function() apply(a) end)
end)

RegisterNetEvent('wasteland:appearance:client:saveFailed', function(message)
    if editing then exports.wasteland_ui:Update(SCREEN, { error = tostring(message) }) end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN or not editing then return end
    if action == 'preview' and type(payload) == 'table' then
        local modelChanged = payload.model ~= editing.appearance.model
        editing.appearance = payload
        Citizen.CreateThread(function()
            if not editing then return end
            apply(payload)
            if modelChanged then placeCamera(editing.mode or 'face') end
            exports.wasteland_ui:Update(SCREEN, { ranges = ranges(payload) })
        end)
    elseif action == 'camera' and type(payload) == 'table' then
        placeCamera(payload.mode == 'body' and 'body' or 'face')
    elseif action == 'rotate' and type(payload) == 'table' then
        local ped = PlayerPedId()
        SetEntityHeading(ped, GetEntityHeading(ped) + clamp(payload.degrees, -90, 90))
    elseif action == 'save' then
        if type(payload) == 'table' then editing.appearance = payload end
        TriggerServerEvent('wasteland:appearance:server:save', editing.appearance)
    elseif action == 'cancel' and editing.cancellable then
        TriggerServerEvent('wasteland:appearance:server:cancel')
        stopCreator()
    end
end)

-- spawnmanager replaces the model on every (re)spawn: put the look back.
AddEventHandler('playerSpawned', function()
    if current and not editing then
        Citizen.CreateThread(function() apply(current) end)
    end
end)

-- This resource (re)started while a character is loaded: ask for the look.
Citizen.CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Citizen.Wait(250) end
    if LocalPlayer.state.wlCharacterId then
        TriggerServerEvent('wasteland:appearance:server:request')
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and editing then stopCreator() end
end)
