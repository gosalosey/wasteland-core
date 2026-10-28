-- wasteland_zombies :: client/noise.lua
-- Noise meter on screen: how far zombies can hear you right now. Uses the
-- same rule the zombies use (shared/ai.lua AI.hearRange with this game's
-- detection settings), and for gunshots the exact reach the server used
-- (suppressor, night, repeated fire). The survival HUD shows it on its noise
-- ring (event wasteland:zombies:noise); this separate panel is off unless
-- /noise turns it on. Moved and resized in the /hud edit mode; both kept on
-- this computer (KVP).

local SCREEN = 'noiseMeter'
local AI = WLZ.AI

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end

local shown = false   -- the separate panel (the HUD's noise ring shows the level anyway)
local layout = { scale = 1 }      -- x, y: share of the free screen space (nil = default spot)
local editing, before = false, nil
local shot = nil                  -- { radius, at } last gunshot the server reported

local function cleanLayout(p)
    if type(p) ~= 'table' then return { scale = 1 } end
    local function unit(v) return type(v) == 'number' and v == v and math.max(0.0, math.min(1.0, v)) or nil end
    local x, y = unit(p.x), unit(p.y)
    if not x or not y then x, y = nil, nil end
    local scale = type(p.scale) == 'number' and p.scale == p.scale and math.max(0.6, math.min(1.8, p.scale)) or 1
    return { x = x, y = y, scale = scale }
end

do
    local ok, v = pcall(GetResourceKvpString, 'noiseShown')
    if ok and v == 'show' then shown = true end   -- (the old 'yes' / 'no' from before the HUD ring is ignored)
    local okL, raw = pcall(GetResourceKvpString, 'noiseLayout')
    if okL and type(raw) == 'string' then
        local okJ, decoded = pcall(json.decode, raw)
        if okJ then layout = cleanLayout(decoded) end
    end
end

AddEventHandler('wasteland:hud:editing', function(on, saved)
    if on then
        editing, before = true, layout
    elseif editing then
        editing = false
        if saved then SetResourceKvp('noiseLayout', json.encode(layout)) else layout = before or layout end
        before = nil
    end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen == SCREEN and action == 'layout' and editing then layout = cleanLayout(payload) end
end)

-- The server: your gunshot reached this far.
RegisterNetEvent('wasteland:zombies:client:noiseMade', function(radius)
    radius = tonumber(radius)
    if radius and radius > 0 then shot = { radius = radius, at = GetGameTimer() } end
end)

RegisterCommand('noise', function()
    shown = not shown
    SetResourceKvp('noiseShown', shown and 'show' or 'hide')
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(shown and 'Noise panel shown. Type /noise to hide it, /hud to move it.'
        or 'Noise panel hidden (the HUD noise ring still shows it). Type /noise to show it.')
    EndTextCommandThefeedPostTicker(false, false)
end, false)
TriggerEvent('chat:addSuggestion', '/noise', 'Show or hide the separate noise panel (the HUD noise ring always shows it)')

local SHOT_HOLD, SHOT_FADE = 1200, 2500

-- How far zombies hear you now (metres), and what makes the noise.
local function measure(ped)
    local C = WLZ.Client
    local cfg = C and C.cfg()
    if not cfg or not cfg.detection then return nil end
    local d = cfg.detection
    local senses = (cfg.ai and cfg.ai.senses) or AI.DEFAULTS.senses
    local veh = GetVehiclePedIsIn(ped, false)
    local speed = GetEntitySpeed(ped)
    local crouching = GetPedStealthMovement(ped)
    local running = IsPedSprinting(ped) or IsPedRunning(ped)
    local engine = veh ~= 0 and GetIsVehicleEngineRunning(veh)
    local r = AI.hearRange(senses, { walk = d.hearWalk, crouch = d.hearCrouch, sprint = d.hearSprint,
        crouching = crouching, running = running, still = speed < 0.3 and veh == 0,
        vehicle = engine, vehicleMoving = veh ~= 0 and GetEntitySpeed(veh) > 2.0 })
    local source
    if engine then source = 'Engine'
    elseif crouching then source = speed < 0.3 and 'Crouched, still' or 'Sneaking'
    elseif running then source = 'Running'
    elseif speed < 0.3 then source = 'Standing still'
    else source = 'Walking' end
    -- A recent gunshot: its full reach, then fading back down.
    if shot then
        local age = GetGameTimer() - shot.at
        if age > SHOT_HOLD + SHOT_FADE then shot = nil
        else
            local k = age <= SHOT_HOLD and 1 or 1 - (age - SHOT_HOLD) / SHOT_FADE
            local sr = r + (shot.radius - r) * k
            if sr > r then r, source = sr, 'Gunshot' end
        end
    end
    return r, source, shot ~= nil
end

-- Zombies inside that reach right now.
local function inEarshot(ped, radius)
    local C = WLZ.Client
    if not (C and C.isZombie) then return 0 end
    local me = GetEntityCoords(ped)
    local n = 0
    for _, p in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(p) and not IsEntityDead(p) and #(GetEntityCoords(p) - me) <= radius and C.isZombie(p) then n = n + 1 end
    end
    return n
end

Citizen.CreateThread(function()
    local open, tick, count = false, 0, 0
    local sent = nil   -- what the HUD was last told
    while true do
        local ped = PlayerPedId()
        local ready = uiRunning() and not IsPauseMenuActive() and not IsEntityDead(ped)
        if ready then
            local okP, isReady = pcall(function() return exports.wasteland_players:IsReady() end)
            ready = (not okP) or isReady == true
        end
        local radius, source, firing
        if ready then radius, source, firing = measure(ped) end
        if radius then
            tick = tick + 1
            if tick % 4 == 1 then count = inEarshot(ped, radius) end -- every ~0.6 s
            local C = WLZ.Client
            local data = { radius = radius, source = source, firing = firing, count = count,
                safe = C and C.safe and C.safe(ped) or false, layout = layout, editing = editing }
            -- the HUD's noise ring (wasteland_survival): told when it changes
            local key = math.floor(radius + 0.5) .. ':' .. tostring(source) .. ':' .. count .. ':' .. tostring(data.safe)
            if key ~= sent then
                sent = key
                TriggerEvent('wasteland:zombies:noise', { radius = radius, source = source, count = count, safe = data.safe })
            end
            if not shown then   -- the separate panel only when /noise turned it on
                if open then open = false; if exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end end
            elseif open and exports.wasteland_ui:IsOpen(SCREEN) then
                exports.wasteland_ui:Update(SCREEN, data)
            else
                exports.wasteland_ui:Open(SCREEN, { script = 'html/noise.js', data = data, focus = false, cursor = false })
                open = true
            end
            Citizen.Wait(150)
        else
            if sent then sent = nil; TriggerEvent('wasteland:zombies:noise', nil) end
            if open then
                open = false
                if uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
            end
            Citizen.Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
end)
