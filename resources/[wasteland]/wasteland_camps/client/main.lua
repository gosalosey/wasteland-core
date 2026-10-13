-- wasteland_camps :: client/main.lua
-- Camp blips, "Entering ... - safe zone" messages, trader NPCs (local peds,
-- created when you are near), the "Trade" target and the trade screen.
-- Every trade is decided by the server.

local Zones = WLC.Zones
local SCREEN = 'trader'
local SPAWN_DISTANCE = 80.0
local cfg = nil
local blips = {}
local peds = {}        -- "<camp>:<index>" -> ped
local targets = {}     -- "<camp>:<index>" -> target id
local insideCamp = nil

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function targetRunning() return GetResourceState('wasteland_target') == 'started' end

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end

--- IsInSafeZone(coords?) -> boolean   (client; zombies stop chasing players inside)
exports('IsInSafeZone', function(coords)
    if not cfg then return false end
    local p = coords or GetEntityCoords(PlayerPedId())
    return Zones.isSafe(cfg.camps, { x = p.x, y = p.y, z = p.z })
end)

-------------------------------------------------------------------------------
-- Blips
-------------------------------------------------------------------------------

local function clearBlips()
    for _, b in ipairs(blips) do RemoveBlip(b) end
    blips = {}
end

local function makeBlips()
    clearBlips()
    for _, c in ipairs(cfg.camps) do
        local area = AddBlipForRadius(c.coords.x + 0.0, c.coords.y + 0.0, c.coords.z + 0.0, c.radius + 0.0)
        SetBlipColour(area, (c.blip and c.blip.color) or 2)
        SetBlipAlpha(area, 70)
        local b = AddBlipForCoord(c.coords.x + 0.0, c.coords.y + 0.0, c.coords.z + 0.0)
        SetBlipSprite(b, (c.blip and c.blip.sprite) or 40)
        SetBlipColour(b, (c.blip and c.blip.color) or 2)
        SetBlipScale(b, 0.9)
        SetBlipAsShortRange(b, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(c.label)
        EndTextCommandSetBlipName(b)
        blips[#blips + 1] = area
        blips[#blips + 1] = b
    end
end

-------------------------------------------------------------------------------
-- Traders
-------------------------------------------------------------------------------

local function removeTrader(key)
    if targets[key] and targetRunning() then pcall(function() exports.wasteland_target:Remove(targets[key]) end) end
    targets[key] = nil
    if peds[key] and DoesEntityExist(peds[key]) then DeleteEntity(peds[key]) end
    peds[key] = nil
end

local function spawnTrader(camp, index, t)
    local key = camp.id .. ':' .. index
    local hash = GetHashKey(t.model)
    if not IsModelInCdimage(hash) then return end
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Citizen.Wait(0) end
    if not HasModelLoaded(hash) then return end
    local c = t.coords
    local ped = CreatePed(4, hash, c.x + 0.0, c.y + 0.0, c.z - 1.0, (c.heading or 0.0) + 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    StopPedSpeaking(ped, true)
    DisablePedPainAudio(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
    peds[key] = ped
    if targetRunning() then
        targets[key] = exports.wasteland_target:AddEntity(ped, {
            { label = 'Trade (' .. t.label .. ')', icon = '$', distance = 3.0,
                onSelect = function() TriggerServerEvent('wasteland:camps:server:open', camp.id, index) end },
        })
    end
end

-------------------------------------------------------------------------------
-- Trade screen
-------------------------------------------------------------------------------

local current = nil -- { camp, trader }

RegisterNetEvent('wasteland:camps:client:trader', function(data)
    if type(data) ~= 'table' or not uiRunning() then return end
    current = { camp = data.camp, trader = data.trader }
    if exports.wasteland_ui:IsOpen(SCREEN) then
        exports.wasteland_ui:Update(SCREEN, data)
    else
        exports.wasteland_ui:Open(SCREEN, { script = 'html/trader.js', data = data })
    end
end)

local function closeScreen()
    current = nil
    if uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
end

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN then return end
    if action == 'close' or not current then closeScreen(); return end
    if (action == 'buy' or action == 'sell') and type(payload) == 'table' and type(payload.item) == 'string' then
        local count = math.tointeger(tonumber(payload.count)) or 1
        TriggerServerEvent('wasteland:camps:server:' .. action, current.camp, current.trader, payload.item, math.max(1, math.min(10000, count)))
    end
end)

-------------------------------------------------------------------------------
-- Main loop: traders near you, camp messages, screen closes when you walk off
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:camps:client:config', function(c)
    if type(c) ~= 'table' then return end
    for key in pairs(peds) do removeTrader(key) end
    cfg = c
    makeBlips()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'wasteland_target' then
        for key in pairs(peds) do removeTrader(key) end -- recreated with targets below
    end
end)

Citizen.CreateThread(function()
    while true do
        local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
        if ok and ready then break end
        Citizen.Wait(1000)
    end
    TriggerServerEvent('wasteland:camps:server:config')
    while true do
        Citizen.Wait(500)
        if cfg then
            local p = GetEntityCoords(PlayerPedId())
            local here = Zones.campAt(cfg.camps, { x = p.x, y = p.y, z = p.z })
            if here and (not insideCamp or insideCamp.id ~= here.id) then
                notice(here.label .. (here.safe ~= false and ' - safe zone' or ''))
            elseif not here and insideCamp then
                notice('Leaving ' .. insideCamp.label)
            end
            insideCamp = here
            for _, camp in ipairs(cfg.camps) do
                for i, t in ipairs(camp.traders) do
                    local key = camp.id .. ':' .. i
                    local near = #(p - vector3(t.coords.x, t.coords.y, t.coords.z)) < SPAWN_DISTANCE
                    if near and not peds[key] then spawnTrader(camp, i, t)
                    elseif not near and peds[key] then removeTrader(key) end
                end
            end
            if current then
                local trader = nil
                for _, camp in ipairs(cfg.camps) do if camp.id == current.camp then trader = camp.traders[current.trader] end end
                if not trader or #(p - vector3(trader.coords.x, trader.coords.y, trader.coords.z)) > 6.0 then closeScreen() end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearBlips()
    for key in pairs(peds) do removeTrader(key) end
    closeScreen()
end)

-------------------------------------------------------------------------------
-- New characters: where do you start?
-------------------------------------------------------------------------------

local SPAWN = 'spawnChoice'

RegisterNetEvent('wasteland:camps:client:chooseSpawn', function(list, returning)
    if type(list) ~= 'table' or GetResourceState('wasteland_ui') ~= 'started' then return end
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    DoScreenFadeOut(300)
    exports.wasteland_ui:Open(SPAWN, { script = 'html/spawn.js', data = { camps = list, returning = returning == true } })
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SPAWN then return end
    if action == 'choose' and type(payload) == 'table' and type(payload.id) == 'string' then
        TriggerServerEvent('wasteland:camps:server:chooseSpawn', payload.id)
    end
end)

-- exact: the saved position (maybe inside a building): put them exactly
-- there. Otherwise (a camp point) find the ground under the point.
RegisterNetEvent('wasteland:camps:client:spawnAt', function(at, label, exact)
    if type(at) ~= 'table' then return end
    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        DoScreenFadeOut(400)
        while not IsScreenFadedOut() do Citizen.Wait(0) end
        if GetResourceState('wasteland_ui') == 'started' and exports.wasteland_ui:IsOpen(SPAWN) then exports.wasteland_ui:Close(SPAWN) end
        local x, y, z = at.x + 0.0, at.y + 0.0, at.z + 0.0
        RequestCollisionAtCoord(x, y, z)
        SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
        SetEntityHeading(ped, (at.heading or 0.0) + 0.0)
        local deadline = GetGameTimer() + 5000
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do Citizen.Wait(0) end
        if not exact then
            -- look from just above the point: from higher up the first thing found can be a roof
            local found, ground = GetGroundZFor_3dCoord(x, y, z + 1.0, false)
            if found and math.abs(ground - z) < 3.0 then SetEntityCoordsNoOffset(ped, x, y, ground + 0.1, false, false, false) end
        else
            -- inside a building: wait for its interior so the floor is there
            local interior = GetInteriorAtCoords(x, y, z)
            if interior ~= 0 then
                PinInteriorInMemory(interior)
                local until_ = GetGameTimer() + 5000
                while not IsInteriorReady(interior) and GetGameTimer() < until_ do Citizen.Wait(0) end
            end
            SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
        end
        FreezeEntityPosition(ped, false)
        SetEntityInvincible(ped, false)
        DoScreenFadeIn(600)
        if label then
            BeginTextCommandThefeedPost('STRING')
            AddTextComponentSubstringPlayerName('Welcome to ' .. tostring(label) .. '. Good luck out there.')
            EndTextCommandThefeedPostTicker(false, false)
        end
    end)
end)

