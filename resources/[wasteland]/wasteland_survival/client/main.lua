-- wasteland_survival :: client/main.lua
-- HUD, death screen and respawn, eating/drinking animations, and the
-- reports the server needs from the game: deaths, damage taken (bleeding)
-- and the surroundings (temperature). The server owns every stat.

local HUD, DEATH = 'hud', 'death'
local stats = nil             -- last stats from the server
local hudMode = 'compact'     -- compact | immersive | off   (/hud: edit mode)
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

local MODES = { compact = true, immersive = true, off = true }
local SIZES = { s = true, m = true, l = true }
local hudLayout = { vertical = false, size = 'm' } -- x, y: share of the free screen space (nil = default corner)
local hudEditing = false

-- Layout from the screen or storage (only numbers 0-1 and known sizes).
local function cleanLayout(p)
    if type(p) ~= 'table' then return { vertical = false, size = 'm' } end
    local function unit(v) return type(v) == 'number' and v == v and math.max(0.0, math.min(1.0, v)) or nil end
    local x, y = unit(p.x), unit(p.y)
    if not x or not y then x, y = nil, nil end
    return { x = x, y = y, vertical = p.vertical == true, size = SIZES[p.size] and p.size or 'm' }
end

local function loadHudMode()
    local ok, v = pcall(GetResourceKvpString, 'hudMode')
    if ok and MODES[v] then hudMode = v end
    local okL, raw = pcall(GetResourceKvpString, 'hudLayout')
    if okL and type(raw) == 'string' then
        local okJ, decoded = pcall(json.decode, raw)
        if okJ then hudLayout = cleanLayout(decoded) end
    end
end

local function healthPercent(ped)
    local max = GetEntityMaxHealth(ped)
    local hp = GetEntityHealth(ped)
    if max <= 100 then return math.max(0, math.min(100, hp)) end
    return math.max(0, math.min(100, (hp - 100) / (max - 100) * 100)) -- player peds die at 100
end

-- Cash on the HUD: counted from the inventory snapshots the inventory
-- already sends this client (pockets and worn bag, like GetCash).
local cashItem, cash = nil, nil

local itemDefs = {}
local plate = nil      -- worn armor plate { current, max } (nil = none)

RegisterNetEvent('wasteland:inventory:client:definitions', function(defs)
    if type(defs) == 'table' and type(defs.cashItem) == 'string' then cashItem = defs.cashItem end
    if type(defs) == 'table' and type(defs.items) == 'table' then itemDefs = defs.items end
end)

RegisterNetEvent('wasteland:inventory:client:sync', function(snap)
    if type(snap) ~= 'table' or type(snap.inventories) ~= 'table' then return end
    for _, inv in ipairs(snap.inventories) do
        if inv.id == snap.equip then
            plate = nil
            for _, s in ipairs(inv.items or {}) do
                local d = itemDefs[s.name]
                if s.slot == 'armor' and d and (d.durability or 0) > 0 then
                    plate = { current = (s.metadata and tonumber(s.metadata.durability)) or d.durability, max = d.durability }
                end
            end
        end
    end
    local name = cashItem or 'cash'
    local total = 0
    for _, inv in ipairs(snap.inventories) do
        if inv.id == snap.pockets or inv.id == snap.backpack then
            for _, s in ipairs(inv.items or {}) do
                if s.name == name then total = total + (tonumber(s.count) or 0) end
            end
        end
    end
    cash = total
end)

-- GTA counts sprint stamina used (0 = fresh, 100 = spent).
local function staminaPercent()
    return math.max(0, math.min(100, 100 - GetPlayerSprintStaminaRemaining(PlayerId())))
end

local function hudData()
    local ped = PlayerPedId()
    return {
        mode = hudMode,
        health = healthPercent(ped),
        stamina = staminaPercent(),
        armor = plate and math.max(0, math.min(100, math.floor(plate.current / plate.max * 100 + 0.5))) or nil,
        stats = stats,
        layout = hudLayout,
        editing = hudEditing,
        info = {
            id = GetPlayerServerId(PlayerId()),
            name = stats and stats.name or GetPlayerName(PlayerId()),
            cash = GetResourceState('wasteland_inventory') == 'started' and cash or nil,
        },
    }
end

-- Once a character is in the world the stats (and the HUD) must arrive;
-- if they do not, ask the server again until they do.
local statsAt = 0
local function watchStats()
    local since = GetGameTimer()
    Citizen.CreateThread(function()
        Citizen.Wait(4000)
        for _ = 1, 20 do
            if statsAt > since then return end
            TriggerServerEvent('wasteland:survival:server:sync')
            Citizen.Wait(3000)
        end
    end)
end
RegisterNetEvent('wasteland:players:client:characterLoaded', function() watchStats() end)
AddEventHandler('onClientResourceStart', function(res)
    if res == GetCurrentResourceName() and LocalPlayer.state.wlCharacterId then watchStats() end
end)

local function ensureHud()
    if not uiRunning() or not active then return end
    if exports.wasteland_ui:IsOpen(HUD) then
        exports.wasteland_ui:Update(HUD, hudData())
    else
        exports.wasteland_ui:Open(HUD, { script = 'html/hud.js', data = hudData(), focus = false, cursor = false })
    end
end

-- Other HUD pieces (the vehicle HUD) move in the same edit mode:
-- 'wasteland:hud:editing'(true) when it starts, (false, saved) when it ends.
local function stopEditing(saved)
    hudEditing = false
    if uiRunning() and exports.wasteland_ui:IsOpen(HUD) then exports.wasteland_ui:SetFocus(HUD, false, false) end
    ensureHud()
    TriggerEvent('wasteland:hud:editing', false, saved == true)
end

-- /hud: move the HUD and choose what it shows, row or column, and size.
RegisterCommand('hud', function()
    if not uiRunning() or not active then
        notice('The HUD can be moved once your character is in the world.')
        return
    end
    if hudEditing then stopEditing(); return end
    hudEditing = true
    ensureHud()
    exports.wasteland_ui:SetFocus(HUD, true, true)
    TriggerEvent('wasteland:hud:editing', true)
end, false)

-------------------------------------------------------------------------------
-- Server events
-------------------------------------------------------------------------------

local toldFull = {}
RegisterNetEvent('wasteland:survival:client:stats', function(s)
    if type(s) ~= 'table' then return end
    -- a reminder once when a meter is full
    for field, msg in pairs({ bladder = 'You really need to pee. (/pee)', bowel = 'You really need to poop. (/poop)' }) do
        if (s[field] or 0) >= 100 and not toldFull[field] then toldFull[field] = true; notice(msg)
        elseif (s[field] or 0) < 90 then toldFull[field] = nil end
    end
    stats = s
    statsAt = GetGameTimer()
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
    if hudEditing then stopEditing() end
    if not uiRunning() then
        notice('You died. Type /respawn when the timer allows it.')
        return
    end
    exports.wasteland_ui:Open(DEATH, { script = 'html/death.js', data = { respawnSeconds = (info and info.respawnSeconds) or 0 } })
end)

-------------------------------------------------------------------------------
-- Toilet: /pee and /poop
-------------------------------------------------------------------------------

local relieving = false
RegisterCommand('pee', function()
    if relieving or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    TriggerServerEvent('wasteland:survival:server:relieve', 'pee')
end, false)
RegisterCommand('poop', function()
    if relieving or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    TriggerServerEvent('wasteland:survival:server:relieve', 'poop')
end, false)

local function loadDict(d)
    RequestAnimDict(d)
    local until_ = GetGameTimer() + 3000
    while not HasAnimDictLoaded(d) and GetGameTimer() < until_ do Citizen.Wait(0) end
    return HasAnimDictLoaded(d)
end

local function loadPtfx(asset)
    RequestNamedPtfxAsset(asset)
    local until_ = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < until_ do Citizen.Wait(0) end
    return HasNamedPtfxAssetLoaded(asset)
end

-- Every client near the player shows the particles; the player's own client
-- plays the animation (the game syncs it to the others).
-- The pee stream: from the hips, placed by survival.lua toilet.pee
-- (male / female: offset, rotation, scale).
local STREAM_DEFAULT = {
    male = { offset = { 0.2, 0.2, 0.0 }, rotation = { -110.0, 0.0, 0.0 }, scale = 2.0 },
    female = { offset = { 0.2, 0.2, 0.0 }, rotation = { -110.0, 0.0, 0.0 }, scale = 1.2 },
}
local function peeStream(ped, male, stream)
    local s = (type(stream) == 'table' and stream[male and 'male' or 'female']) or STREAM_DEFAULT[male and 'male' or 'female']
    local o, r = s.offset, s.rotation
    UseParticleFxAssetNextCall('scr_amb_chop')
    return StartParticleFxLoopedOnEntityBone('ent_anim_dog_peeing', ped, o[1] + 0.0, o[2] + 0.0, o[3] + 0.0,
        r[1] + 0.0, r[2] + 0.0, r[3] + 0.0, GetPedBoneIndex(ped, 11816), s.scale + 0.0, false, false, false)
end

-- /peetest x y z [rx ry rz] [scale]: shows the stream on you for 5 s at that
-- spot (only you see it), to find the numbers for survival.lua toilet.pee.
RegisterCommand('peetest', function(_, args)
    local ped = PlayerPedId()
    local male = GetEntityModel(ped) == GetHashKey('mp_m_freemode_01')
    local d = STREAM_DEFAULT[male and 'male' or 'female']
    local s = {
        offset = { tonumber(args[1]) or d.offset[1], tonumber(args[2]) or d.offset[2], tonumber(args[3]) or d.offset[3] },
        rotation = { tonumber(args[4]) or d.rotation[1], tonumber(args[5]) or d.rotation[2], tonumber(args[6]) or d.rotation[3] },
        scale = tonumber(args[7]) or d.scale,
    }
    RequestNamedPtfxAsset('scr_amb_chop')
    local untilT = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded('scr_amb_chop') and GetGameTimer() < untilT do Citizen.Wait(0) end
    local fx = peeStream(ped, male, { [male and 'male' or 'female'] = s })
    notice(string.format('peetest (%s): offset = { %.2f, %.2f, %.2f }, rotation = { %.1f, %.1f, %.1f }, scale = %.1f',
        male and 'male' or 'female', s.offset[1], s.offset[2], s.offset[3], s.rotation[1], s.rotation[2], s.rotation[3], s.scale))
    SetTimeout(5000, function() StopParticleFxLooped(fx, false) end)
end, false)

RegisterNetEvent('wasteland:survival:client:relieve', function(serverId, kind, stream)
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then return end
    local ped = GetPlayerPed(player)
    if not DoesEntityExist(ped) or #(GetEntityCoords(ped) - GetEntityCoords(PlayerPedId())) > 60.0 then return end
    local mine = serverId == GetPlayerServerId(PlayerId())
    local male = GetEntityModel(ped) == GetHashKey('mp_m_freemode_01')
    local seconds = kind == 'pee' and 9 or 12
    Citizen.CreateThread(function()
        if mine then
            relieving = true
            local dict, name = 'missfbi3ig_0', 'shit_loop_trev'      -- squat
            if kind == 'pee' and male then dict, name = 'misscarsteal2peeing', 'peeing_loop' end
            if loadDict(dict) then
                ClearPedTasks(ped)
                TaskPlayAnim(ped, dict, name, 8.0, -8.0, seconds * 1000, 1, 0, false, false, false)
                RemoveAnimDict(dict)
            end
        end
        Citizen.Wait(kind == 'pee' and 1200 or 3000)
        local fx
        if loadPtfx('scr_amb_chop') then
            UseParticleFxAssetNextCall('scr_amb_chop')
            if kind == 'pee' then
                fx = peeStream(ped, male, stream)
            else
                fx = StartParticleFxLoopedOnEntityBone('ent_anim_dog_poo', ped, 0.0, -0.1, -0.3, 0.0, 0.0, 20.0,
                    GetPedBoneIndex(ped, 11816), 2.0, false, false, false)
            end
        end
        Citizen.Wait(kind == 'pee' and 6500 or 5000)
        if fx then StopParticleFxLooped(fx, false) end
        if kind == 'poop' and mine then
            -- leave a pile behind (gone after a minute)
            local hash = GetHashKey('prop_big_shit_02')
            RequestModel(hash)
            local until_ = GetGameTimer() + 3000
            while not HasModelLoaded(hash) and GetGameTimer() < until_ do Citizen.Wait(0) end
            if HasModelLoaded(hash) then
                local at = GetOffsetFromEntityInWorldCoords(ped, 0.0, -0.4, 0.0)
                local pile = CreateObject(hash, at.x, at.y, at.z, true, true, false)
                PlaceObjectOnGroundProperly(pile)
                SetModelAsNoLongerNeeded(hash)
                SetTimeout(60000, function() if DoesEntityExist(pile) then DeleteEntity(pile) end end)
            end
        end
        if mine then
            Citizen.Wait(kind == 'pee' and 500 or 3000)
            ClearPedTasks(ped)
            relieving = false
        end
    end)
end)

RegisterCommand('respawn', function() TriggerServerEvent('wasteland:survival:server:respawn') end, false)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen == DEATH and action == 'respawn' then TriggerServerEvent('wasteland:survival:server:respawn') end
    if screen == HUD and hudEditing then
        if action == 'saveLayout' and type(payload) == 'table' then
            hudLayout = cleanLayout(payload)
            if MODES[payload.mode] then hudMode = payload.mode end
            SetResourceKvp('hudLayout', json.encode(hudLayout))
            SetResourceKvp('hudMode', hudMode)
            notice('HUD saved.')
            stopEditing(true)
        elseif action == 'cancelLayout' then
            stopEditing()
        end
    end
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
    -- under a roof built with base building counts too
    if not sheltered and GetResourceState('wasteland_basebuilding') == 'started' then
        local ok, yes = pcall(function() return exports.wasteland_basebuilding:IsSheltered() end)
        sheltered = ok and yes == true
    end
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

-- Stamina bar: refresh quickly only while stamina is changing.
Citizen.CreateThread(function()
    local lastStamina = 100
    while true do
        if active then
            local s = staminaPercent()
            if s ~= lastStamina then
                lastStamina = s
                ensureHud()
                Citizen.Wait(150)
            else
                Citizen.Wait(400)
            end
        else
            Citizen.Wait(1000)
        end
    end
end)

-- Armor plate: while it holds, GTA armour is kept full so the game puts
-- gunshots and blows on the armour instead of health; what it took is
-- reported and the server wears the plate down. No plate: no armour.
-- Only armour lost after it was full on this same ped is a hit: a new ped
-- (logging in, respawning, a new look) starts at 0 and that is not damage.
Citizen.CreateThread(function()
    local holding, pending, lastReport, lastPed = false, 0, 0, nil
    while true do
        local ped = PlayerPedId()
        if ped ~= lastPed then lastPed, holding = ped, false end
        local working = plate ~= nil and plate.current > 0 and not (stats and stats.dead) and not IsEntityDead(ped)
            and not IsScreenFadedOut()
        if working then
            local a = GetPedArmour(ped)
            if holding and a < 100 then pending = pending + (100 - a) end
            if a ~= 100 then SetPedArmour(ped, 100) end
            holding = true
        elseif holding then
            SetPedArmour(ped, 0)
            holding = false
        end
        if pending > 0 and GetGameTimer() - lastReport > 1000 then
            TriggerServerEvent('wasteland:survival:server:armorHit', math.min(pending, 400) + 0.0)
            pending, lastReport = 0, GetGameTimer()
        end
        Citizen.Wait(100)
    end
end)

-- GTA's health and armour bars under the minimap: hidden (the HUD shows
-- health). The minimap's own scaleform is told to draw no bars, every
-- frame, because the game resets it.
Citizen.CreateThread(function()
    local minimap = RequestScaleformMovie('minimap')
    local deadline = GetGameTimer() + 5000
    while not HasScaleformMovieLoaded(minimap) and GetGameTimer() < deadline do Citizen.Wait(0) end
    -- Toggling the big map once makes the minimap re-read the setting.
    SetRadarBigmapEnabled(true, false)
    Citizen.Wait(0)
    SetRadarBigmapEnabled(false, false)
    while true do
        BeginScaleformMovieMethod(minimap, 'SETUP_HEALTH_ARMOUR')
        ScaleformMovieMethodAddParamInt(3)
        EndScaleformMovieMethod()
        Citizen.Wait(0)
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

--- GetVitals() -> { health, armor, hunger, thirst, temperature, bleeding, infection, treatment, dead, cures, limits } | nil
--- (the inventory's health panel)
exports('GetVitals', function()
    if not stats then return nil end
    local ped = PlayerPedId()
    return {
        health = healthPercent(ped),
        armor = plate and math.max(0, math.min(100, math.floor(plate.current / plate.max * 100 + 0.5))) or nil,
        hunger = stats.hunger, thirst = stats.thirst, temperature = stats.temperature,
        bleeding = stats.bleeding, infection = stats.infection, treatment = stats.treatment, dead = stats.dead,
        cures = stats.cures, limits = stats.limits,
    }
end)
