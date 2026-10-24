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
    if type(data) ~= 'table' or loaded then return end
    -- Only counts once a screen shows it: until then the request is repeated.
    if not uiRunning() then return end
    listReceived = true
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

-- The screen could not be shown (its script failed to load): ask again.
AddEventHandler('wasteland:ui:client:failed', function(screen)
    if screen == SCREEN and not loaded then listReceived = false end
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


-------------------------------------------------------------------------------
-- Placing the player. This is the one way the ped is put somewhere: logging
-- in, the spawn choice (wasteland_camps), /stuck, rescues.
--
-- The screen stays dark and the ped is held at the spot (frozen, no
-- collision) while, in order:
--   1. the look is applied (a model change replaces the ped),
--   2. the world around the spot loads,
--   3. the collision there loads,
--   4. the building (interior) loads, if the spot is inside one,
--   5. the surface under the spot is found: map ground or something built.
--      Base floors are objects, which GetGroundZ does not see, so a ray that
--      hits objects is used.
-- Each wait re-takes PlayerPedId() and holds it again, so a ped that was
-- replaced meanwhile is held too. A newer placement replaces one that is
-- still running.
-------------------------------------------------------------------------------

local placeGen = 0      -- bumped by every placement; a running one stops when it changes
local lastPlaced = nil  -- the last spot a placement put the ped (ped position)
local lastRescue = -60000

local function release()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    DisplayRadar(true)
end

local function pin(x, y, z, heading)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, heading)
    return ped
end

-- Hold the ped at the spot while busy() is true, at most `ms`. False when a
-- newer placement started meanwhile.
local function holdWhile(gen, ms, spot, busy)
    local untilT = GetGameTimer() + ms
    while GetGameTimer() < untilT do
        if gen ~= placeGen then return false end
        pin(spot.x, spot.y, spot.z, spot.heading)
        if not busy() then break end
        Citizen.Wait(50)
    end
    return gen == placeGen
end

-- The top of whatever is under (x, y) between `top` and `bottom`: map
-- collision or an object (a base floor), never the player's ped. -> z | nil
local function surface(x, y, top, bottom)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(x, y, top, x, y, bottom, 1 | 16, PlayerPedId(), 7)
    local _, hit, at = GetShapeTestResult(ray)
    if hit == 1 and at then return at.z end
    local found, gz = GetGroundZFor_3dCoord(x, y, top, false)
    if found and gz <= top and gz >= bottom then return gz end
    return nil
end

local function appearanceBusy()
    if GetResourceState('wasteland_appearance') ~= 'started' then return false end
    local ok, busy = pcall(function() return exports.wasteland_appearance:IsApplying() end)
    return ok and busy == true
end

local function validPos(p)
    return type(p) == 'table' and type(p.x) == 'number' and type(p.y) == 'number' and type(p.z) == 'number'
        and p.x == p.x and p.y == p.y and p.z == p.z -- not NaN
end

--- Put the ped at `pos` ({ x, y, z, heading }: a ped position, about 1 m
--- above the feet). exact: a saved position (maybe on a base floor or
--- inside a building): the surface right under the feet is waited for.
--- Otherwise (a camp point) the ground near the point is used.
--- Returns true (placed; and where), false (no ground found), nil (a newer
--- placement replaced this one).
local function place(pos, exact)
    placeGen = placeGen + 1
    local gen = placeGen
    placing = true
    local spot = { x = pos.x + 0.0, y = pos.y + 0.0, z = pos.z + 0.0, heading = (tonumber(pos.heading) or 0.0) + 0.0 }
    if not IsScreenFadedOut() then
        DoScreenFadeOut(250)
        local t = GetGameTimer() + 1500
        while not IsScreenFadedOut() and GetGameTimer() < t do Citizen.Wait(0) end
    end
    -- 1. the look (a new model is a new ped: placing the old one is lost)
    if not holdWhile(gen, 10000, spot, appearanceBusy) then return nil end
    -- 2. the world around the spot
    NewLoadSceneStartSphere(spot.x, spot.y, spot.z, 120.0, 0)
    local ok = holdWhile(gen, 15000, spot, function() return not IsNewLoadSceneLoaded() end)
    NewLoadSceneStop()
    if not ok then return nil end
    -- 3. collision
    if not holdWhile(gen, 10000, spot, function()
        RequestCollisionAtCoord(spot.x, spot.y, spot.z)
        return not HasCollisionLoadedAroundEntity(PlayerPedId())
    end) then return nil end
    -- 4. the building
    local interior = GetInteriorAtCoords(spot.x, spot.y, spot.z)
    if interior ~= 0 then
        PinInteriorInMemory(interior)
        if not holdWhile(gen, 6000, spot, function() return not IsInteriorReady(interior) end) then return nil end
    end
    -- 5. the surface. Looked for from just above the feet, so a roof is
    -- never picked. A saved spot: wait for the surface the feet stood on
    -- (base pieces appear a second or two after the world).
    local ground
    local feet = spot.z - 1.0
    if exact then
        ok = holdWhile(gen, 12000, spot, function()
            ground = surface(spot.x, spot.y, spot.z + 0.5, spot.z - 3.0)
            return not (ground and math.abs(ground - feet) < 0.6)
        end)
    else
        ok = holdWhile(gen, 3000, spot, function()
            ground = surface(spot.x, spot.y, spot.z + 1.5, spot.z - 6.0)
            return ground == nil
        end)
    end
    if not ok then return nil end
    -- nothing near: the surface somewhere below, then the highest ground there
    if not ground then ground = surface(spot.x, spot.y, spot.z + 2.0, spot.z - 80.0) end
    if not ground then
        local found, gz = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 150.0, false)
        if found then ground = gz end
    end
    if not ground then
        placing = false
        release()
        DoScreenFadeIn(500)
        return false
    end
    local at = { x = spot.x, y = spot.y, z = ground + 1.0, heading = spot.heading }
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, at.x, at.y, at.z, false, false, false)
    SetEntityHeading(ped, at.heading)
    ClearPedTasksImmediately(ped)
    release()
    lastPlaced = at
    placing = false
    DoScreenFadeIn(500)
    return true, at
end

-- A safe camp (the server picks it). At most once every 30 s.
local function rescue(why)
    local t = GetGameTimer()
    if t - lastRescue < 30000 then return end
    lastRescue = t
    print('[wasteland] placing the character failed (' .. tostring(why) .. '): asking for a safe camp')
    TriggerServerEvent('wasteland:players:server:rescue')
end

-- Place, tell the server, and watch the first seconds: dropping well below
-- the spot (the world was not really there) means one more try from the
-- highest ground there, then a safe camp.
local function placeAndWatch(pos, exact, message)
    local ok, at = place(pos, exact)
    if ok == nil then return end -- a newer placement took over
    if not ok then rescue('no ground at the spot'); return end
    TriggerServerEvent('wasteland:players:server:placed')
    if message then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(message)
        EndTextCommandThefeedPostTicker(false, false)
    end
    local gen, retried = placeGen, false
    local untilT = GetGameTimer() + 15000
    while GetGameTimer() < untilT do
        Citizen.Wait(500)
        if gen ~= placeGen then return end
        local me = PlayerPedId()
        if not IsEntityVisible(me) and not placing then SetEntityVisible(me, true, false) end
        if not IsPedInAnyVehicle(me, false) and not IsEntityDead(me) and GetEntityCoords(me).z < at.z - 20.0 then
            if retried then rescue('fell through the map after placing'); return end
            retried = true
            ok, at = place({ x = at.x, y = at.y, z = at.z + 50.0, heading = at.heading }, false)
            if ok == nil then return end
            if not ok then rescue('no ground at the spot'); return end
            gen, untilT = placeGen, GetGameTimer() + 15000
        end
    end
end

--- PlaceAt(pos, exact, message): put the player at pos (see place above);
--- returns at once (the placement runs on its own). message: shown when
--- they have arrived.
exports('PlaceAt', function(pos, exact, message)
    if not validPos(pos) then return false end
    local p = { x = pos.x, y = pos.y, z = pos.z, heading = tonumber(pos.heading) or 0.0 }
    Citizen.CreateThread(function() placeAndWatch(p, exact == true, type(message) == 'string' and message or nil) end)
    return true
end)

RegisterNetEvent('wasteland:players:client:rescue', function(pos)
    if not validPos(pos) then return end
    Citizen.CreateThread(function() placeAndWatch(pos, false) end)
end)

RegisterNetEvent('wasteland:players:client:characterLoaded', function(info)
    if type(info) ~= 'table' then return end
    loaded = true
    closeScreen()
    noAutoSpawn()
    -- After a resource restart the player never left: do not move them back
    -- to the last saved (older) position.
    if info.restored then
        placing = false
        setHeld(false)
        return
    end
    placing = true
    Citizen.CreateThread(function()
        if info.hold then
            -- Another module places us (the spawn choice): stay held and dark
            -- until it does. If it never does, the saved spot after 2 minutes.
            local gen = placeGen
            local untilT = GetGameTimer() + 120000
            while placeGen == gen and GetGameTimer() < untilT do
                if not placing then return end
                setHeld(true)
                Citizen.Wait(250)
            end
            if placeGen ~= gen then return end
            print('[wasteland] the spawn choice never placed the character: using the saved spot')
        end
        setHeld(true)
        -- New characters have no position yet: the holding spot (they pick a
        -- camp after the creator).
        local pos = validPos(info.position) and info.position or HOLD
        placeAndWatch(pos, pos ~= HOLD)
        if not placing then LocalPlayer.state:set('wlProtected', false, true) end
    end)
end)

-- spawnmanager (base server) can still spawn us at a random map spawn point
-- (basic-gamemode forces one when the map loads). Its spawns carry the spawn
-- point's model/index; Wasteland's own (survival respawns) do not. Put the
-- player back where they were placed.
AddEventHandler('playerSpawned', function(spawn)
    if not loaded or placing or not lastPlaced or type(spawn) ~= 'table' then return end
    if spawn.model == nil and spawn.idx == nil then return end
    if GetResourceState('wasteland_survival') ~= 'started' then return end -- spawnmanager handles deaths then
    print('[wasteland] spawnmanager spawned the player: putting them back')
    local back = lastPlaced
    Citizen.CreateThread(function() placeAndWatch(back, true) end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and (not loaded or placing) then
        setHeld(false)
        if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(500) end
    end
end)

-- Fell through the map (any time, not only after logging in): the ground
-- (or a big map pack's collision) did not load in time and the ped drops
-- below the world. Remember the last spot where the ped stood on something;
-- when it is falling and is under the ground there (or has been falling a
-- long way with nothing found), put it back on that spot.
Citizen.CreateThread(function()
    local lastGood, fallingSince, fallStartZ, lastFix = nil, nil, nil, -60000
    while true do
        Citizen.Wait(500)
        local ped = PlayerPedId()
        if loaded and not placing and not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false) then
            local c = GetEntityCoords(ped)
            local skydiving = GetPedParachuteState(ped) >= 0 or IsPedInParachuteFreeFall(ped)
            local free = not IsEntityPositionFrozen(ped) and not GetEntityCollisionDisabled(ped)
            if not free then
                -- frozen or flying (noclip, an admin freeze): not a spot to go back to
                fallingSince, fallStartZ = nil, nil
            elseif not IsPedFalling(ped) and not IsPedRagdoll(ped) and not IsEntityInAir(ped) and not IsPedSwimming(ped) and not skydiving then
                fallingSince, fallStartZ = nil, nil
                -- standing on something (ground or a base floor) just under the feet
                local gz = surface(c.x, c.y, c.z + 0.5, c.z - 2.5)
                if gz then lastGood = { x = c.x, y = c.y, z = gz + 1.0, heading = GetEntityHeading(ped) } end
            elseif (IsPedFalling(ped) or IsEntityInAir(ped)) and not skydiving then
                fallingSince = fallingSince or GetGameTimer()
                fallStartZ = fallStartZ or c.z
                -- under the world: ground above us, none below us
                local below = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.5, false)
                local above, ground = GetGroundZFor_3dCoord(c.x, c.y, c.z + 500.0, false)
                local under = not below and above and c.z < ground - 4.0
                local lost = not below and not above and GetGameTimer() - fallingSince > 4000 and fallStartZ - c.z > 60.0
                if under or lost then
                    fallingSince, fallStartZ = nil, nil
                    SetEntityVelocity(ped, 0.0, 0.0, 0.0)
                    local now = GetGameTimer()
                    if lastGood and now - lastFix > 30000 then
                        print(('[wasteland] fell through the map at %.1f %.1f %.1f: back to the last ground'):format(c.x, c.y, c.z))
                        lastFix = now
                        placeAndWatch(lastGood, true)
                    else
                        -- no good spot, or it happened again right away: a safe camp
                        print(('[wasteland] fell through the map again at %.1f %.1f %.1f: to a safe camp'):format(c.x, c.y, c.z))
                        lastFix, lastGood = now, nil
                        rescue('fell through the map again')
                        Citizen.Wait(5000)
                    end
                end
            end
        end
    end
end)
