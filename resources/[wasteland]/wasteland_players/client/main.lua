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

Citizen.CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Citizen.Wait(100) end
    noAutoSpawn()
    if LocalPlayer.state.wlCharacterId then return end -- restore in progress
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

local function teleport(pos)
    local ped = PlayerPedId()
    local x, y, z = pos.x + 0.0, pos.y + 0.0, pos.z + 0.0
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Citizen.Wait(0) end
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, (pos.heading or 0.0) + 0.0)
    local deadline = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        Citizen.Wait(0)
    end
    DoScreenFadeIn(500)
end

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
        if type(pos) == 'table' and type(pos.x) == 'number' and type(pos.y) == 'number' and type(pos.z) == 'number' then
            teleport(pos)
            placedPos, placedUntil = pos, GetGameTimer() + 60000
        end
        setHeld(false)
        placing = false
        TriggerServerEvent('wasteland:players:server:placed')
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
