-- wasteland_tailor :: client/main.lua
-- Tailor NPCs (tailor.lua): map blips, the NPC near you, "Restyle my
-- clothes" on it. The screen previews every change on your character (a
-- camera looks at you); Pay sends the looks to the server, Cancel puts your
-- clothes back. Only pieces you wear can be changed.

local SCREEN = 'tailor'
local cfg = nil
local blips, peds, targets = {}, {}, {}
local session = nil   -- open screen: { shop, pieces, cam, heading }

local LABELS = {
    head = 'Hat', eyes = 'Glasses', torso = 'Top', legs = 'Pants', feet = 'Shoes',
    hat = 'Hat', glasses = 'Glasses', top = 'Shirt / jacket', undershirt = 'Undershirt', arms = 'Arms / gloves',
    legsPart = 'Pants', shoes = 'Shoes',
}
local ORDER = { 'head', 'eyes', 'torso', 'legs', 'feet' }

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function targetRunning() return GetResourceState('wasteland_target') == 'started' end

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end

-------------------------------------------------------------------------------
-- Looks on the ped
-------------------------------------------------------------------------------

local function maxDrawable(ped, part)
    if part.component then return GetNumberOfPedDrawableVariations(ped, part.component) - 1 end
    return GetNumberOfPedPropDrawableVariations(ped, part.prop) - 1
end

local function maxTexture(ped, part, d)
    if part.component then return math.max(0, GetNumberOfPedTextureVariations(ped, part.component, d) - 1) end
    return math.max(0, GetNumberOfPedPropTextureVariations(ped, part.prop, d) - 1)
end

local function applyPart(ped, part, d, t)
    if part.component then SetPedComponentVariation(ped, part.component, d, t, 0)
    else SetPedPropIndex(ped, part.prop, d, t, true) end
end

-------------------------------------------------------------------------------
-- The screen
-------------------------------------------------------------------------------

local function closeSession(restore)
    if not session then return end
    if session.cam then
        RenderScriptCams(false, true, 400, true, false)
        DestroyCam(session.cam, false)
    end
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    if session.heading then SetEntityHeading(ped, session.heading) end
    session = nil
    if uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
    if restore and GetResourceState('wasteland_inventory') == 'started' then exports.wasteland_inventory:ApplyClothing() end
end

-- The camera circles the player: yaw (degrees around, 0 = in front),
-- dist (metres), height (camera, from the middle of the body), look (where it
-- aims, from the middle of the body).
local VIEWS = {
    full = { dist = 2.4, height = 0.3, look = 0.0 },
    face = { dist = 0.9, height = 0.65, look = 0.62 },
    top = { dist = 1.4, height = 0.35, look = 0.3 },
    legs = { dist = 1.5, height = -0.35, look = -0.45 },
    feet = { dist = 1.1, height = -0.7, look = -0.85 },
}

local function placeCamera(ped, ease)
    if not session then return end
    local v = session.view
    local c = GetEntityCoords(ped)
    local a = math.rad(session.heading + v.yaw)
    local px, py = c.x - math.sin(a) * v.dist, c.y + math.cos(a) * v.dist
    if not session.cam then session.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true) end
    SetCamCoord(session.cam, px, py, c.z + v.height)
    PointCamAtCoord(session.cam, c.x, c.y, c.z + v.look)
    SetCamFov(session.cam, 45.0)
    if ease then RenderScriptCams(true, true, 400, true, false) end
end

local function pointCamera(ped)
    session.view = { yaw = 0.0, dist = VIEWS.full.dist, height = VIEWS.full.height, look = VIEWS.full.look }
    placeCamera(ped, true)
end

local function openTailor(index)
    if session or not cfg or not uiRunning() then return end
    local shop = cfg.shops[index]
    if not shop or GetResourceState('wasteland_inventory') ~= 'started' then return end
    local info = exports.wasteland_inventory:GetClothingInfo()
    if not info then notice('You cannot change clothes right now.'); return end
    local ped = PlayerPedId()
    local pieces = {}
    for _, slot in ipairs(ORDER) do
        local w, parts = info.worn[slot], info.parts[slot]
        if w and parts then
            local list = {}
            for _, part in ipairs(parts) do
                local cur = w.look[part.key] or { 0, 0 }
                list[#list + 1] = { key = part.key, label = LABELS[part.key == 'legs' and 'legsPart' or part.key] or part.key,
                    d = cur[1], t = cur[2], od = cur[1], ot = cur[2],
                    maxD = math.max(0, maxDrawable(ped, part)), maxT = maxTexture(ped, part, cur[1]) }
            end
            pieces[#pieces + 1] = { slot = slot, label = LABELS[slot] or slot, parts = list }
        end
    end
    if #pieces == 0 then notice('You are not wearing anything a tailor can restyle.'); return end
    session = { shop = index, model = info.model, pieces = pieces, heading = GetEntityHeading(ped) }
    FreezeEntityPosition(ped, true)
    ClearPedTasks(ped)
    pointCamera(ped)
    exports.wasteland_ui:Open(SCREEN, { script = 'html/tailor.js',
        data = { title = shop.label, price = cfg.price, pieces = pieces } })
end

local function partOf(slot, key)
    local info = exports.wasteland_inventory:GetClothingInfo()
    for _, p in ipairs(((info and info.parts) or {})[slot] or {}) do if p.key == key then return p end end
    return nil
end

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN or not session then return end
    local ped = PlayerPedId()
    if action == 'close' then
        closeSession(true)
    elseif action == 'set' and type(payload) == 'table' then
        local part = partOf(tostring(payload.slot), tostring(payload.key))
        if not part then return end
        local maxD = math.max(0, maxDrawable(ped, part))
        local d = math.max(0, math.min(maxD, math.tointeger(tonumber(payload.d) or 0) or 0))
        local maxT = maxTexture(ped, part, d)
        local t = math.max(0, math.min(maxT, math.tointeger(tonumber(payload.t) or 0) or 0))
        applyPart(ped, part, d, t)
        exports.wasteland_ui:Update(SCREEN, { part = { slot = payload.slot, key = payload.key, d = d, t = t, maxD = maxD, maxT = maxT } })
    elseif action == 'reset' then
        exports.wasteland_inventory:ApplyClothing()
    elseif action == 'turn' then
        session.view.yaw = (session.view.yaw + 180.0) % 360.0
        placeCamera(ped)
    elseif action == 'cam' and type(payload) == 'table' then
        -- Drag: dx turns around the player, dy moves up/down; wheel: zoom.
        local v = session.view
        v.yaw = (v.yaw - (tonumber(payload.dx) or 0) * 0.35) % 360.0
        local dy = (tonumber(payload.dy) or 0) * 0.004
        v.height = math.max(-0.9, math.min(1.0, v.height + dy))
        v.look = math.max(-0.95, math.min(0.8, v.look + dy))
        v.dist = math.max(0.7, math.min(4.0, v.dist + (tonumber(payload.zoom) or 0) * 0.15))
        placeCamera(ped)
    elseif action == 'view' and type(payload) == 'table' and VIEWS[payload.view] then
        local p = VIEWS[payload.view]
        session.view.dist, session.view.height, session.view.look = p.dist, p.height, p.look
        placeCamera(ped)
    elseif action == 'buy' and type(payload) == 'table' and type(payload.changes) == 'table' then
        TriggerServerEvent('wasteland:tailor:server:buy', session.shop, session.model, payload.changes)
    end
end)

RegisterNetEvent('wasteland:tailor:client:done', function(cost, count)
    closeSession(false) -- the inventory puts the new looks on
    notice(string.format('The tailor restyled %d piece%s for $%d.', count, count == 1 and '' or 's', cost))
end)

RegisterNetEvent('wasteland:tailor:client:notice', function(message)
    if session and uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) then
        exports.wasteland_ui:Update(SCREEN, { message = message })
    else
        notice(message)
    end
end)

-- Cancel when the player dies or something else takes the screen.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        if session and (IsEntityDead(PlayerPedId()) or not (uiRunning() and exports.wasteland_ui:IsOpen(SCREEN))) then
            closeSession(true)
        end
    end
end)

-------------------------------------------------------------------------------
-- Blips and NPCs
-------------------------------------------------------------------------------

local function clearAll()
    for _, b in ipairs(blips) do RemoveBlip(b) end
    for i, ped in pairs(peds) do
        if targets[i] and targetRunning() then pcall(function() exports.wasteland_target:Remove(targets[i]) end) end
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    blips, peds, targets = {}, {}, {}
end

local function spawnTailor(index, shop)
    local hash = GetHashKey(cfg.model)
    if not IsModelInCdimage(hash) then return end
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Citizen.Wait(0) end
    if not HasModelLoaded(hash) then return end
    local c = shop.coords
    local ped = CreatePed(4, hash, c.x + 0.0, c.y + 0.0, c.z - 1.0, (c.heading or 0.0) + 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    StopPedSpeaking(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
    peds[index] = ped
    if targetRunning() then
        targets[index] = exports.wasteland_target:AddEntity(ped, {
            { label = string.format('Restyle my clothes ($%d a piece)', cfg.price), icon = '✂', distance = 3.0,
                onSelect = function() openTailor(index) end },
        })
    end
end

local function makeBlips()
    for _, shop in ipairs(cfg.shops) do
        local b = AddBlipForCoord(shop.coords.x + 0.0, shop.coords.y + 0.0, shop.coords.z + 0.0)
        SetBlipSprite(b, cfg.blip.sprite)
        SetBlipColour(b, cfg.blip.color)
        SetBlipScale(b, 0.8)
        SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(cfg.blip.label)
        EndTextCommandSetBlipName(b)
        blips[#blips + 1] = b
    end
end

RegisterNetEvent('wasteland:tailor:client:config', function(c)
    if type(c) ~= 'table' then return end
    clearAll()
    cfg = c
    makeBlips()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'wasteland_target' and cfg then
        for i, ped in pairs(peds) do
            if DoesEntityExist(ped) then DeleteEntity(ped) end
            peds[i] = nil
        end
    end
end)

Citizen.CreateThread(function()
    TriggerServerEvent('wasteland:tailor:server:config')
    while true do
        Citizen.Wait(1000)
        if cfg then
            local me = GetEntityCoords(PlayerPedId())
            for i, shop in ipairs(cfg.shops) do
                local d = #(me - vector3(shop.coords.x, shop.coords.y, shop.coords.z))
                if d < 80.0 and not peds[i] then spawnTailor(i, shop)
                elseif d > 100.0 and peds[i] then
                    if targets[i] and targetRunning() then pcall(function() exports.wasteland_target:Remove(targets[i]) end) end
                    if DoesEntityExist(peds[i]) then DeleteEntity(peds[i]) end
                    peds[i], targets[i] = nil, nil
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    closeSession(true)
    clearAll()
end)
