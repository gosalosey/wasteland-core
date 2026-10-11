-- wasteland_survival :: client/main.lua
-- HUD, death screen and respawn, eating/drinking animations, and the
-- reports the server needs from the game: deaths, damage taken (bleeding)
-- and the surroundings (temperature). The server owns every stat.

local HUD, DEATH = 'hud', 'death'
local stats = nil             -- last stats from the server
local hudMode = 'compact'     -- compact | immersive | off   (/hud cycles)
local active = false          -- a character is loaded and placed
local reportedDead = false
local expectedDrop = 0        -- health the server's own damage will remove
local lastHealth = nil
local bodyBlips = {}          -- drop id -> blip

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end

local function notice(message)
    if GetResourceState('chat') == 'started' then
        TriggerEvent('chat:addMessage', { args = { 'Survival', message } })
    else
        print('[survival] ' .. message)
    end
end

-------------------------------------------------------------------------------
-- HUD
-------------------------------------------------------------------------------

local function loadHudMode()
    local ok, v = pcall(GetResourceKvpString, 'hudMode')
    if ok and (v == 'compact' or v == 'immersive' or v == 'off') then hudMode = v end
end

local function healthPercent(ped)
    local max = GetEntityMaxHealth(ped)
    local hp = GetEntityHealth(ped)
    if max <= 100 then return math.max(0, math.min(100, hp)) end
    return math.max(0, math.min(100, (hp - 100) / (max - 100) * 100)) -- player peds die at 100
end

local function hudData()
    local ped = PlayerPedId()
    return {
        mode = hudMode,
        health = healthPercent(ped),
        stats = stats,
    }
end

local function ensureHud()
    if not uiRunning() or not active then return end
    if exports.wasteland_ui:IsOpen(HUD) then
        exports.wasteland_ui:Update(HUD, hudData())
    else
        exports.wasteland_ui:Open(HUD, { script = 'html/hud.js', data = hudData(), focus = false, cursor = false })
    end
end

RegisterCommand('hud', function()
    hudMode = (hudMode == 'compact' and 'immersive') or (hudMode == 'immersive' and 'off') or 'compact'
    SetResourceKvp('hudMode', hudMode)
    notice('HUD: ' .. (hudMode == 'immersive' and 'only when it matters' or hudMode))
    ensureHud()
end, false)

-------------------------------------------------------------------------------
-- Server events
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:survival:client:stats', function(s)
    if type(s) ~= 'table' then return end
    stats = s
    ensureHud()
end)

RegisterNetEvent('wasteland:survival:client:damage', function(amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    expectedDrop = expectedDrop + amount
    ApplyDamageToPed(ped, math.floor(amount), false)
end)

RegisterNetEvent('wasteland:survival:client:heal', function(amount)
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + math.floor(tonumber(amount) or 0)))
end)

RegisterNetEvent('wasteland:survival:client:notice', function(message) notice(tostring(message)) end)

-- Animation per kind, and where a held prop sits in the hand
-- (bone, offset x y z, rotation x y z).
local ANIMS = {
    eat = { dict = 'mp_player_inteat@burger', name = 'mp_player_int_eat_burger', ms = 3000,
        bone = 18905, pos = { 0.13, 0.05, 0.02 }, rot = { -50.0, 16.0, 60.0 } },
    drink = { dict = 'mp_player_intdrink', name = 'loop_bottle', ms = 3000,
        bone = 18905, pos = { 0.12, 0.008, 0.03 }, rot = { 240.0, -60.0, 0.0 } },
    treat = { dict = 'missheistdockssetup1clipboard@idle_a', name = 'idle_a', ms = 3000,
        bone = 57005, pos = { 0.12, 0.02, -0.02 }, rot = { -90.0, 0.0, 0.0 } },
}

local function loadModel(name)
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Citizen.Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

RegisterNetEvent('wasteland:survival:client:consumed', function(kind, prop)
    local a = ANIMS[kind] or ANIMS.eat
    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then return end
        RequestAnimDict(a.dict)
        local deadline = GetGameTimer() + 2000
        while not HasAnimDictLoaded(a.dict) and GetGameTimer() < deadline do Citizen.Wait(0) end
        if not HasAnimDictLoaded(a.dict) then return end
        -- The item in the hand (networked, so others see it too).
        local object
        local hash = type(prop) == 'string' and loadModel(prop) or nil
        if hash then
            local c = GetEntityCoords(ped)
            object = CreateObject(hash, c.x, c.y, c.z + 0.2, true, true, false)
            SetEntityCollision(object, false, false)
            AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, a.bone), a.pos[1], a.pos[2], a.pos[3],
                a.rot[1], a.rot[2], a.rot[3], true, true, false, true, 1, true)
            SetModelAsNoLongerNeeded(hash)
        end
        TaskPlayAnim(ped, a.dict, a.name, 4.0, -4.0, a.ms, 49, 0, false, false, false)
        RemoveAnimDict(a.dict)
        Citizen.Wait(a.ms)
        if object and DoesEntityExist(object) then
            DetachEntity(object, true, false)
            DeleteEntity(object)
        end
    end)
end)

-------------------------------------------------------------------------------
-- Death and respawn
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:survival:client:dead', function(info)
    reportedDead = true
    if not uiRunning() then
        notice('You died. Type /respawn when the timer allows it.')
        return
    end
    exports.wasteland_ui:Open(DEATH, { script = 'html/death.js', data = { respawnSeconds = (info and info.respawnSeconds) or 0 } })
end)

RegisterCommand('respawn', function() TriggerServerEvent('wasteland:survival:server:respawn') end, false)

AddEventHandler('wasteland:ui:client:action', function(screen, action)
    if screen == DEATH and action == 'respawn' then TriggerServerEvent('wasteland:survival:server:respawn') end
end)

local function groundZ(x, y, z)
    for _, from in ipairs({ z + 50.0, z + 200.0, 1000.0 }) do
        local found, ground = GetGroundZFor_3dCoord(x, y, from, false)
        if found then return ground end
    end
    return z
end

RegisterNetEvent('wasteland:survival:client:respawn', function(p)
    if type(p) ~= 'table' then return end
    Citizen.CreateThread(function()
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Citizen.Wait(0) end
        if uiRunning() then exports.wasteland_ui:Close(DEATH) end
        local x, y, z = p.x + 0.0, p.y + 0.0, p.z + 0.0
        RequestCollisionAtCoord(x, y, z)
        local ped = PlayerPedId()
        SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
        local deadline = GetGameTimer() + 5000
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do Citizen.Wait(0) end
        z = groundZ(x, y, z)
        NetworkResurrectLocalPlayer(x, y, z, (p.heading or 0.0) + 0.0, true, false)
        ped = PlayerPedId()
        ClearPedTasksImmediately(ped)
        ClearPedBloodDamage(ped)
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        reportedDead, expectedDrop, lastHealth = false, 0, nil
        -- Let the appearance and inventory modules put the look and clothes back.
        TriggerEvent('playerSpawned', { x = x, y = y, z = z })
        DoScreenFadeIn(800)
    end)
end)

-- An admin revived us where we lie.
RegisterNetEvent('wasteland:survival:client:revive', function()
    Citizen.CreateThread(function()
        if uiRunning() then exports.wasteland_ui:Close(DEATH) end
        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
        ped = PlayerPedId()
        ClearPedTasksImmediately(ped)
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        reportedDead, expectedDrop, lastHealth = false, 0, nil
        TriggerEvent('playerSpawned', { x = c.x, y = c.y, z = c.z })
    end)
end)

-------------------------------------------------------------------------------
-- Body bag markers (from the inventory's drop list)
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:inventory:client:drops', function(list)
    if type(list) ~= 'table' then return end
    local mine = tonumber(LocalPlayer.state.wlCharacterId)
    local wanted = {}
    for _, d in ipairs(list) do
        if mine and d.owner == mine then wanted[d.id] = d end
    end
    for id, blip in pairs(bodyBlips) do
        if not wanted[id] then RemoveBlip(blip); bodyBlips[id] = nil end
    end
    for id, d in pairs(wanted) do
        if not bodyBlips[id] then
            local blip = AddBlipForCoord(d.x + 0.0, d.y + 0.0, d.z + 0.0)
            SetBlipSprite(blip, 274)
            SetBlipColour(blip, 1)
            SetBlipScale(blip, 0.9)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('Your body')
            EndTextCommandSetBlipName(blip)
            bodyBlips[id] = blip
        end
    end
end)

-------------------------------------------------------------------------------
-- Reports: death, damage, surroundings
-------------------------------------------------------------------------------

-- Rough air temperature from what this client sees (there is no server
-- weather sync yet): weather, time of day, altitude.
local WEATHER_TEMP = {
    EXTRASUNNY = 30, CLEAR = 26, NEUTRAL = 22, SMOG = 24, FOGGY = 14, OVERCAST = 18, CLOUDS = 21,
    CLEARING = 17, RAIN = 13, THUNDER = 11, SNOW = -2, BLIZZARD = -10, SNOWLIGHT = 0, XMAS = -4, HALLOWEEN = 10,
}
local WET_WEATHER = { RAIN = true, THUNDER = true, CLEARING = true }

local function weatherName()
    local a = GetPrevWeatherTypeHashName()
    for name in pairs(WEATHER_TEMP) do
        if GetHashKey(name) == a then return name end
    end
    return 'NEUTRAL'
end

local function environment()
    local ped = PlayerPedId()
    local weather = weatherName()
    local temp = WEATHER_TEMP[weather] or 20
    local hour = GetClockHours()
    if hour < 6 then temp = temp - 9
    elseif hour < 10 then temp = temp - 4
    elseif hour >= 22 then temp = temp - 7
    elseif hour >= 18 then temp = temp - 3 end
    local z = GetEntityCoords(ped).z
    if z > 300 then temp = temp - (z - 300) / 100 end
    local sheltered = IsPedInAnyVehicle(ped, false) or GetInteriorFromEntity(ped) ~= 0
    if sheltered then temp = math.max(temp, 15) end
    local wet = IsEntityInWater(ped) or IsPedSwimming(ped) or (WET_WEATHER[weather] == true and not sheltered)
    return math.max(-40, math.min(60, temp)), wet
end

Citizen.CreateThread(function()
    loadHudMode()
    -- Wait for a loaded, placed character.
    while true do
        local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
        if ok and ready then break end
        Citizen.Wait(500)
    end
    active = true
    -- Death and respawn are handled here, not by spawnmanager.
    if GetResourceState('spawnmanager') == 'started' then exports.spawnmanager:setAutoSpawn(false) end
    TriggerServerEvent('wasteland:survival:server:request')
    local sinceEnv, pendingDamage, sinceDamage = 15000, 0, 0
    while true do
        Citizen.Wait(500)
        local ped = PlayerPedId()
        local hp = GetEntityHealth(ped)
        if IsEntityDead(ped) or IsPedFatallyInjured(ped) then
            if not reportedDead then
                reportedDead = true
                TriggerServerEvent('wasteland:survival:server:died')
            end
        else
            -- Damage from the world (not the server's own damage) can cause bleeding.
            if lastHealth and hp < lastHealth then
                local drop = lastHealth - hp
                local fromServer = math.min(drop, expectedDrop)
                expectedDrop = expectedDrop - fromServer
                pendingDamage = pendingDamage + (drop - fromServer)
            end
            sinceDamage = sinceDamage + 500
            if pendingDamage >= 1 and sinceDamage >= 1000 then
                TriggerServerEvent('wasteland:survival:server:damaged', math.min(400, math.floor(pendingDamage)))
                pendingDamage, sinceDamage = 0, 0
            end
        end
        lastHealth = hp
        sinceEnv = sinceEnv + 500
        if sinceEnv >= 15000 then
            sinceEnv = 0
            local ambient, wet = environment()
            TriggerServerEvent('wasteland:survival:server:environment', ambient + 0.0, wet == true)
        end
        ensureHud()
    end
end)

-- Cold makes the camera shake; a serious infection blurs the screen.
Citizen.CreateThread(function()
    local shaking, blurred = false, false
    while true do
        Citizen.Wait(2000)
        local cold = stats and not stats.dead and stats.temperature and stats.temperature <= 35.5
        if cold and not shaking then ShakeGameplayCam('DRUNK_SHAKE', 0.4); shaking = true
        elseif not cold and shaking then StopGameplayCamShaking(true); shaking = false end
        local sick = stats and not stats.dead and (stats.infection or 0) >= 60
        if sick and not blurred then AnimpostfxPlay('DrugsMichaelAliensFightIn', 0, true); blurred = true
        elseif not sick and blurred then AnimpostfxStop('DrugsMichaelAliensFightIn'); blurred = false end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    StopGameplayCamShaking(true)
    AnimpostfxStop('DrugsMichaelAliensFightIn')
    for _, blip in pairs(bodyBlips) do RemoveBlip(blip) end
    if GetResourceState('spawnmanager') == 'started' then exports.spawnmanager:setAutoSpawn(true) end
end)
