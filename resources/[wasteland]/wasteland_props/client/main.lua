-- wasteland_props :: client/main.lua
-- Shows the saved props near you (spawned locally, not networked), and the
-- admin placer: /propplacer opens a panel (search a model or pick a preset,
-- list of nearby props). Placing: a see-through copy follows where you
-- look; mouse wheel turns it, arrows raise/lower/tilt, Enter or left click
-- places, Backspace or right click stops.

local SCREEN = 'propPlacer'
local all = {}            -- id -> prop from the server
local spawned = {}        -- id -> entity
local stream = 200.0
local presets, maxDist = {}, 30.0
local placing = nil       -- { model, hash, ghost, editId, heading, pitch, roll, lift, ground, collision }

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end

local function notify(msg, bad)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName((bad and '~r~' or '~g~') .. 'Props~s~: ' .. tostring(msg))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:props:client:notice', function(msg, bad) notify(msg, bad) end)

local function loadModel(model, ms)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + (ms or 3000)
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Citizen.Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

-------------------------------------------------------------------------------
-- Saved props near you
-------------------------------------------------------------------------------

local function despawn(id)
    local e = spawned[id]
    if e and DoesEntityExist(e) then DeleteEntity(e) end
    spawned[id] = nil
end

local function spawn(p)
    local hash = loadModel(p.model)
    if not hash then return end
    local e = CreateObjectNoOffset(hash, p.x, p.y, p.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not e or e == 0 then return end
    SetEntityRotation(e, p.rx, p.ry, p.rz, 2, true)
    SetEntityCoordsNoOffset(e, p.x, p.y, p.z, false, false, false)
    FreezeEntityPosition(e, true)
    SetEntityCollision(e, p.collision ~= false, p.collision ~= false)
    SetEntityInvincible(e, true)
    SetEntityLodDist(e, math.floor(stream))
    spawned[p.id] = e
end

RegisterNetEvent('wasteland:props:client:list', function(list, distance)
    for id in pairs(spawned) do despawn(id) end
    all = {}
    for _, p in ipairs(type(list) == 'table' and list or {}) do all[p.id] = p end
    stream = (tonumber(distance) or 200.0) + 0.0
end)

RegisterNetEvent('wasteland:props:client:set', function(p)
    if type(p) ~= 'table' or not p.id then return end
    despawn(p.id)
    all[p.id] = p
end)

RegisterNetEvent('wasteland:props:client:remove', function(id)
    despawn(id)
    all[id] = nil
end)

Citizen.CreateThread(function()
    Citizen.Wait(2000)
    TriggerServerEvent('wasteland:props:server:request')
    while true do
        local me = GetEntityCoords(PlayerPedId())
        for id, p in pairs(all) do
            local d = #(me - vector3(p.x, p.y, p.z))
            local editing = placing and placing.editId == id
            if d <= stream and not spawned[id] and not editing then spawn(p)
            elseif (d > stream + 20.0 or editing) and spawned[id] then despawn(id) end
        end
        Citizen.Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do despawn(id) end
    if placing and placing.ghost and DoesEntityExist(placing.ghost) then DeleteEntity(placing.ghost) end
    if uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
end)

-------------------------------------------------------------------------------
-- Panel
-------------------------------------------------------------------------------

local function nearby()
    local me = GetEntityCoords(PlayerPedId())
    local out = {}
    for id, p in pairs(all) do
        local d = #(me - vector3(p.x, p.y, p.z))
        if d <= 150.0 then out[#out + 1] = { id = id, model = p.model, dist = math.floor(d + 0.5) } end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    while #out > 60 do table.remove(out) end
    return out
end

local function validPresets()
    local out = {}
    for _, p in ipairs(presets) do
        local hash = GetHashKey(p.model)
        if IsModelInCdimage(hash) then out[#out + 1] = p end
    end
    return out
end

local function openPanel()
    if not uiRunning() then return end
    local data = { presets = validPresets(), nearby = nearby(), total = 0 }
    for _ in pairs(all) do data.total = data.total + 1 end
    if exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Update(SCREEN, data)
    else exports.wasteland_ui:Open(SCREEN, { script = 'html/props.js', data = data, focus = true, cursor = true }) end
end

local function closePanel()
    if uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
end

RegisterNetEvent('wasteland:props:client:open', function(info)
    presets = (type(info) == 'table' and type(info.presets) == 'table') and info.presets or {}
    maxDist = (type(info) == 'table' and tonumber(info.maxPlaceDistance)) or 30.0
    openPanel()
end)

RegisterCommand('propplacer', function()
    if placing then return end
    TriggerServerEvent('wasteland:props:server:open')
end, false)
TriggerEvent('chat:addSuggestion', '/propplacer', 'Admins: place, move and delete saved props')

-------------------------------------------------------------------------------
-- Placing
-------------------------------------------------------------------------------

local function rotToDir(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

-- Where the camera looks (ignoring you and the ghost), up to maxDist away.
local function aim(ignore)
    local from = GetGameplayCamCoord()
    local to = from + rotToDir(GetGameplayCamRot(2)) * (maxDist + 10.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, -1, ignore or PlayerPedId(), 7)
    local _, hit, pos, _, entity = GetShapeTestResult(ray)
    if hit == 1 then return pos, entity end
    return to, 0
end

local function propAt(entity)
    if not entity or entity == 0 then return nil end
    for id, e in pairs(spawned) do if e == entity then return id end end
    return nil
end

local function stopPlacing(reopen)
    if not placing then return end
    if placing.ghost and DoesEntityExist(placing.ghost) then DeleteEntity(placing.ghost) end
    SetModelAsNoLongerNeeded(placing.hash)
    placing = nil
    if reopen then openPanel() end
end

local function help(p)
    local lines = {
        ('~y~%s~s~%s'):format(p.model, p.editId and (' (moving #' .. p.editId .. ')') or ''),
        '~b~Mouse wheel~s~ turn   ~b~Shift~s~ fine   ~b~R~s~ reset',
        '~b~Up / Down~s~ raise / lower   ~b~Left / Right~s~ tilt   ~b~Z / X~s~ roll',
        ('~b~G~s~ snap to ground: %s   ~b~F~s~ collision: %s'):format(p.ground and 'on' or 'off', p.collision and 'on' or 'off'),
        '~b~Enter / Left click~s~ place   ~b~Delete~s~ remove the prop you aim at',
        '~b~Backspace / Right click~s~ stop',
    }
    SetTextFont(4); SetTextScale(0.0, 0.36); SetTextColour(255, 255, 255, 230); SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(table.concat(lines, '~n~'))
    EndTextCommandDisplayText(0.015, 0.30)
end

local BLOCK = { 24, 25, 14, 15, 16, 17, 37, 44, 45, 140, 141, 142, 143, 257, 263, 264, 172, 173, 174, 175, 177, 191, 194, 199, 200, 178, 47, 23, 20, 73, 23, 75, 241, 242, 81, 82, 99, 100, 115, 116, 261, 262 }

local function startPlacing(model, editId)
    if placing then stopPlacing(false) end
    local hash = loadModel(model)
    if not hash then notify(('"%s" is not a prop this game knows.'):format(tostring(model)), true); openPanel(); return end
    closePanel()
    local me = GetEntityCoords(PlayerPedId())
    local ghost = CreateObjectNoOffset(hash, me.x, me.y, me.z, false, false, false)
    SetEntityAlpha(ghost, 170, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    placing = { model = model, hash = hash, ghost = ghost, editId = editId, heading = GetEntityHeading(PlayerPedId()),
        pitch = 0.0, roll = 0.0, lift = 0.0, ground = true, collision = true }
    if editId and all[editId] then
        local p = all[editId]
        placing.heading, placing.pitch, placing.roll, placing.collision = p.rz, p.rx, p.ry, p.collision ~= false
    end
end

Citizen.CreateThread(function()
    while true do
        if not placing then Citizen.Wait(250) else
            Citizen.Wait(0)
            local p = placing
            for _, c in ipairs(BLOCK) do DisableControlAction(0, c, true) end
            local fine = IsDisabledControlPressed(0, 21) -- Shift
            local dt = GetFrameTime()
            if IsDisabledControlJustPressed(0, 241) then p.heading = p.heading + (fine and 1.0 or 7.5) end   -- wheel up
            if IsDisabledControlJustPressed(0, 242) then p.heading = p.heading - (fine and 1.0 or 7.5) end   -- wheel down
            local liftSpeed = fine and 0.15 or 1.0
            if IsDisabledControlPressed(0, 172) then p.lift = p.lift + liftSpeed * dt end   -- up
            if IsDisabledControlPressed(0, 173) then p.lift = p.lift - liftSpeed * dt end   -- down
            local tilt = (fine and 10.0 or 45.0) * dt
            if IsDisabledControlPressed(0, 174) then p.pitch = p.pitch - tilt end           -- left
            if IsDisabledControlPressed(0, 175) then p.pitch = p.pitch + tilt end           -- right
            if IsDisabledControlPressed(0, 20) then p.roll = p.roll - tilt end              -- Z
            if IsDisabledControlPressed(0, 73) then p.roll = p.roll + tilt end              -- X
            if IsControlJustPressed(0, 45) or IsDisabledControlJustPressed(0, 45) then    -- R
                p.pitch, p.roll, p.lift = 0.0, 0.0, 0.0
            end
            if IsDisabledControlJustPressed(0, 47) then p.ground = not p.ground end         -- G
            if IsDisabledControlJustPressed(0, 23) then p.collision = not p.collision end   -- F

            local pos, entity = aim(p.ghost)
            local x, y, z = pos.x, pos.y, pos.z
            SetEntityCoordsNoOffset(p.ghost, x, y, z, false, false, false)
            SetEntityRotation(p.ghost, p.pitch, p.roll, p.heading, 2, true)
            if p.ground and p.pitch == 0.0 and p.roll == 0.0 then
                PlaceObjectOnGroundProperly(p.ghost)
                local c = GetEntityCoords(p.ghost)
                z = c.z
            end
            z = z + p.lift
            SetEntityCoordsNoOffset(p.ghost, x, y, z, false, false, false)
            help(p)

            -- Delete what you aim at (a saved prop).
            if IsDisabledControlJustPressed(0, 178) then
                local id = propAt(entity)
                if id then TriggerServerEvent('wasteland:props:server:delete', id)
                else notify('Aim at a placed prop to remove it.', true) end
            end
            if IsDisabledControlJustPressed(0, 24) or IsDisabledControlJustPressed(0, 191) then
                if #(GetEntityCoords(PlayerPedId()) - vector3(x, y, z)) > maxDist then
                    notify('Too far away: come closer.', true)
                else
                    local r = GetEntityRotation(p.ghost, 2)
                    if p.editId then
                        TriggerServerEvent('wasteland:props:server:update', p.editId, x, y, z, r.x, r.y, r.z, p.collision)
                        stopPlacing(true)
                    else
                        TriggerServerEvent('wasteland:props:server:place', p.model, x, y, z, r.x, r.y, r.z, p.collision)
                    end
                end
            end
            if placing and (IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 25) or IsDisabledControlJustPressed(0, 194)) then
                stopPlacing(true)
            end
        end
    end
end)

-- Panel actions.
AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN then return end
    payload = type(payload) == 'table' and payload or {}
    if action == 'place' and type(payload.model) == 'string' then
        local m = payload.model:gsub('%s+', '')
        if m:match('^[%w_%-]+$') and #m <= 64 then startPlacing(m) else notify('Type a prop model name (letters, digits, _ and -).', true) end
    elseif action == 'edit' and all[tonumber(payload.id)] then
        startPlacing(all[tonumber(payload.id)].model, tonumber(payload.id))
    elseif action == 'delete' and tonumber(payload.id) then
        TriggerServerEvent('wasteland:props:server:delete', tonumber(payload.id))
        Citizen.SetTimeout(400, openPanel)
    elseif action == 'goto' and all[tonumber(payload.id)] then
        local p = all[tonumber(payload.id)]
        SetEntityCoords(PlayerPedId(), p.x + 1.5, p.y + 1.5, p.z + 0.5, false, false, false, false)
        Citizen.SetTimeout(300, openPanel)
    elseif action == 'refresh' then
        openPanel()
    elseif action == 'close' then
        closePanel()
    end
end)
