-- wasteland_players :: client/main.lua
-- Until a character is loaded the player is held (frozen, invisible, no
-- collision) and the character select screen is shown (wasteland_ui). If
-- wasteland_ui is not running, the chat command /character still works.
-- After loading, the player is placed at the character's saved position.
-- Every decision (which characters exist, what may be created) is made by
-- the server; this script only displays and forwards requests.

local SCREEN = 'characterSelect'
local loaded = false
local placing = false
local placedPos, placedUntil = nil, 0 -- where the character was placed (guard against spawnmanager)
local listReceived = false

--- True once a character is loaded and the player has been placed in the
--- world (other modules wait for this before taking over the camera).
exports('IsReady', function() return loaded and not placing end)

local function uiRunning()
    return GetResourceState('wasteland_ui') == 'started'
end

local function setHeld(held)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, held)
    SetEntityVisible(ped, not held, false)
    SetEntityCollision(ped, not held, not held)
    SetEntityInvincible(ped, held)
    LocalPlayer.state:set('wlProtected', held, true)
    DisplayRadar(not held)
end

local function closeScreen()
    if uiRunning() then exports.wasteland_ui:Close(SCREEN) end
end

-- Hold the player and ask for the character list until we get it. A
-- character that is being restored after a resource restart is left alone.
-- spawnmanager (base server) must never spawn us at a random map spawn
-- point: not while choosing a character, not after.
local function noAutoSpawn()
    if GetResourceState('spawnmanager') == 'started' then pcall(function() exports.spawnmanager:setAutoSpawn(false) end) end
end
noAutoSpawn()
AddEventHandler('onClientResourceStart', function(res) if res == 'spawnmanager' then noAutoSpawn() end end)
-- basic-gamemode turns spawnmanager's auto spawn back on (and forces a spawn
-- at a random map spawn point) when the map has loaded - which can be long
-- after we turned it off, e.g. while the player sits at character select.
AddEventHandler('onClientMapStart', function()
    for _, ms in ipairs({ 0, 250, 1000, 3000 }) do SetTimeout(ms, noAutoSpawn) end
end)
-- ... and keep it off (Wasteland places characters and handles respawns;
-- with wasteland_survival stopped, spawnmanager may take death over again).
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(2000)
        if not loaded or GetResourceState('wasteland_survival') == 'started' then noAutoSpawn() end
    end
end)

-- The first spawn when joining. spawnmanager normally does it (and it is
-- what ends GTA's loading screen - without it the game sits at "Awaiting
-- scripts" behind the character screen), but at a random map spawn point.
-- We do it ourselves, at a fixed holding spot (the character is placed at
-- its own position after it is chosen).
local HOLD = { x = 1734.0, y = 3297.0, z = 41.2, heading = 0.0 }
local function firstSpawn()
    if GetResourceState('spawnmanager') == 'started' then
        local done = false
        local ok = pcall(function()
            exports.spawnmanager:spawnPlayer({ x = HOLD.x, y = HOLD.y, z = HOLD.z, heading = HOLD.heading, model = 'mp_m_freemode_01' },
                function() done = true end)
        end)
        local untilT = GetGameTimer() + 15000
        while ok and not done and GetGameTimer() < untilT do Citizen.Wait(100) end
    else
        local ped = PlayerPedId()
        SetEntityCoordsNoOffset(ped, HOLD.x, HOLD.y, HOLD.z, false, false, false)
        NetworkResurrectLocalPlayer(HOLD.x, HOLD.y, HOLD.z, HOLD.heading, true, false)
    end
    noAutoSpawn()
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(500) end
end

Citizen.CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Citizen.Wait(100) end
    noAutoSpawn()
    if LocalPlayer.state.wlCharacterId then return end -- restore in progress
    firstSpawn()
    local lastRequest = 0
    while not loaded do
        setHeld(true) -- spawnmanager may respawn the ped; keep holding it
        if not listReceived and GetGameTimer() - lastRequest > 5000 then
            lastRequest = GetGameTimer()
            TriggerServerEvent('wasteland:players:server:requestCharacters')
        end
        Citizen.Wait(250)
    end
end)

RegisterNetEvent('wasteland:players:client:characters', function(data)
    if type(data) ~= 'table' then return end
    listReceived = true
    if loaded or not uiRunning() then return end
    if exports.wasteland_ui:IsOpen(SCREEN) then
        exports.wasteland_ui:Update(SCREEN, { list = data })
    else
        exports.wasteland_ui:Open(SCREEN, { script = 'html/characters.js', data = { list = data } })
    end
end)

RegisterNetEvent('wasteland:players:client:result', function(result)
    if type(result) ~= 'table' or loaded or not uiRunning() then return end
    if not exports.wasteland_ui:IsOpen(SCREEN) then return end
    exports.wasteland_ui:Update(SCREEN, { result = result })
    if result.ok and (result.action == 'create' or result.action == 'delete') then
        TriggerServerEvent('wasteland:players:server:requestCharacters')
    end
    if result.ok and result.action == 'create' and type(result.slot) == 'number' then
        -- Play the new character straight away (the appearance creator follows).
        TriggerServerEvent('wasteland:players:server:selectCharacter', result.slot)
    end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN or loaded then return end
    payload = type(payload) == 'table' and payload or {}
    if action == 'create' then
        TriggerServerEvent('wasteland:players:server:createCharacter', tostring(payload.firstName or ''), tostring(payload.lastName or ''))
    elseif action == 'select' then
        TriggerServerEvent('wasteland:players:server:selectCharacter', math.tointeger(tonumber(payload.slot)) or 0)
    elseif action == 'delete' then
        TriggerServerEvent('wasteland:players:server:deleteCharacter', math.tointeger(tonumber(payload.slot)) or 0, tostring(payload.confirm or ''))
    elseif action == 'refresh' then
        TriggerServerEvent('wasteland:players:server:requestCharacters')
    end
end)

-- Put the ped at `pos` without anyone dropping through an unloaded world:
-- the screen stays dark and the ped held (frozen, no collision) while the
-- game loads the world there (a load scene - streaming otherwise follows
-- wherever the camera was) and the ground under the spot. Returns true when
-- it stands on ground, false when the ground never loaded.
local function teleport(pos)
    local ped = PlayerPedId()
    local x, y, z = pos.x + 0.0, pos.y + 0.0, pos.z + 0.0
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Citizen.Wait(0) end
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, (pos.heading or 0.0) + 0.0)
    -- 1. the world around the spot
    NewLoadSceneStartSphere(x, y, z, 120.0, 0)
    local sceneUntil = GetGameTimer() + 15000
    while not IsNewLoadSceneLoaded() and GetGameTimer() < sceneUntil do Citizen.Wait(0) end
    NewLoadSceneStop()
    -- 2. the building, if it is inside one
    local interior = GetInteriorAtCoords(x, y, z)
    if interior ~= 0 then
        PinInteriorInMemory(interior)
        local untilT = GetGameTimer() + 5000
        while not IsInteriorReady(interior) and GetGameTimer() < untilT do Citizen.Wait(0) end
    end
    -- 3. the floor right under where they logged out (looked for from just
    -- above their feet, so a roof is never picked)
    local ground
    local deadline = GetGameTimer() + 10000
    while GetGameTimer() < deadline do
        RequestCollisionAtCoord(x, y, z)
        local found, gz = GetGroundZFor_3dCoord(x, y, z + 1.0, false)
        if found and math.abs(gz - z) < 3.0 then ground = gz; break end
        Citizen.Wait(50)
    end
    if not ground then
        -- not right under them: the highest ground there (outside, most likely)
        local found, gz = GetGroundZFor_3dCoord(x, y, z + 150.0, false)
        if found then ground = gz end
    end
    -- the ped stands on its feet: its position is about 1 m above them
    if ground then SetEntityCoordsNoOffset(ped, x, y, ground + 1.0, false, false, false) end
    DoScreenFadeIn(500)
    return ground ~= nil
end

-- Sent to a safe camp (the server picks it) when the spot could not be used.
local rescued = false
local function rescue(why)
    if rescued then return end
    rescued = true
    print('[wasteland] placing the character failed (' .. tostring(why) .. '): asking for a safe camp')
    TriggerServerEvent('wasteland:players:server:rescue')
end

RegisterNetEvent('wasteland:players:client:rescue', function(pos)
    if type(pos) ~= 'table' or type(pos.x) ~= 'number' then return end
    Citizen.CreateThread(function()
        setHeld(true)
        teleport(pos)
        setHeld(false)
        placedPos, placedUntil = pos, GetGameTimer() + 60000
    end)
end)

RegisterNetEvent('wasteland:players:client:characterLoaded', function(info)
    if type(info) ~= 'table' then return end
    loaded = true
    placing = not info.restored
    closeScreen()
    -- After a resource restart the player never left: do not move them back
    -- to the last saved (older) position.
    if info.restored then
        setHeld(false)
        return
    end
    Citizen.CreateThread(function()
        local pos = info.position
        -- spawnmanager (base server) must not respawn us at a map spawn point.
        if GetResourceState('spawnmanager') == 'started' then pcall(function() exports.spawnmanager:setAutoSpawn(false) end) end
        local placedOk = true
        if type(pos) == 'table' and type(pos.x) == 'number' and type(pos.y) == 'number' and type(pos.z) == 'number' then
            placedOk = teleport(pos)
            placedPos, placedUntil = pos, GetGameTimer() + 60000
        end
        setHeld(false)
        placing = false
        TriggerServerEvent('wasteland:players:server:placed')
        if not placedOk then rescue('no ground at the saved spot'); return end
        -- Watch the first seconds: falling far below where they were put
        -- (through an unloaded world) or still hidden -> a safe camp.
        local startZ = GetEntityCoords(PlayerPedId()).z
        local untilT = GetGameTimer() + 15000
        while GetGameTimer() < untilT and not rescued do
            Citizen.Wait(500)
            local me = PlayerPedId()
            if not IsEntityVisible(me) then setHeld(false) end
            if not IsPedInAnyVehicle(me, false) and GetEntityCoords(me).z < startZ - 25.0 then
                rescue('fell through the map')
            end
        end
    end)
end)

-- spawnmanager's own first spawn can land after we placed the character (it
-- runs on its own timer) and drop them at a random map spawn point. Right
-- after placing, put them back at their saved spot.
AddEventHandler('playerSpawned', function()
    if not loaded or placing or not placedPos or GetGameTimer() > placedUntil then return end
    Citizen.CreateThread(function()
        Citizen.Wait(0)
        teleport(placedPos)
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and not loaded then setHeld(false) end
end)
