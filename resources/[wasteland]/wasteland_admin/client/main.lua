-- wasteland_admin :: client/main.lua
-- Opens the admin panel (F10 or /admin), forwards its actions to the
-- server (which checks the admin ACE for every one), and carries out what
-- the server orders: teleport, freeze, noclip, invisible, announcements.

local PANEL, BANNER = 'adminPanel', 'announce'
local noclip = false
local invisible = false

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end

local function say(message)
    if GetResourceState('chat') == 'started' then
        TriggerEvent('chat:addMessage', { args = { 'Admin', message } })
    else
        print('[admin] ' .. message)
    end
end

-------------------------------------------------------------------------------
-- Panel
-------------------------------------------------------------------------------

RegisterCommand('admin', function()
    if uiRunning() and exports.wasteland_ui:IsOpen(PANEL) then
        exports.wasteland_ui:Close(PANEL)
    else
        TriggerServerEvent('wasteland:admin:server:open')
    end
end, false)
RegisterKeyMapping('admin', 'Admin panel', 'keyboard', 'F10')

RegisterNetEvent('wasteland:admin:client:denied', function() say('You are not an admin.') end)

RegisterNetEvent('wasteland:admin:client:data', function(data)
    if not uiRunning() or type(data) ~= 'table' then return end
    data.self = { noclip = noclip, invisible = invisible, id = GetPlayerServerId(PlayerId()) }
    if exports.wasteland_ui:IsOpen(PANEL) then
        exports.wasteland_ui:Update(PANEL, { data = data })
    else
        exports.wasteland_ui:Open(PANEL, { script = 'html/admin.js', data = { data = data } })
    end
end)

RegisterNetEvent('wasteland:admin:client:result', function(r)
    if uiRunning() and exports.wasteland_ui:IsOpen(PANEL) then
        exports.wasteland_ui:Update(PANEL, { result = r })
    elseif type(r) == 'table' and r.message then
        say(r.message)
    end
end)

RegisterNetEvent('wasteland:admin:client:list', function(which, rows, serverNow)
    if uiRunning() and exports.wasteland_ui:IsOpen(PANEL) then
        exports.wasteland_ui:Update(PANEL, { list = { which = which, rows = rows, now = serverNow } })
    end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= PANEL then return end
    if action == 'close' then
        exports.wasteland_ui:Close(PANEL)
    elseif action == 'refresh' then
        TriggerServerEvent('wasteland:admin:server:open')
    elseif action == 'coords' then
        -- Your own position, straight from the game (nothing to ask the server).
        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)
        -- The prop or vehicle the camera faces (within 25 m): its model hash,
        -- to check loot props and such.
        local looking = nil
        local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
        local rx, rz = math.rad(rot.x), math.rad(rot.z)
        local dir = vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
        local probe = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, cam.x + dir.x * 25.0, cam.y + dir.y * 25.0,
            cam.z + dir.z * 25.0, 18, ped, 7)
        local _, hit, _, _, entity = GetShapeTestResult(probe)
        if hit == 1 and entity and entity ~= 0 then
            local kind = GetEntityType(entity)
            if kind >= 1 and kind <= 3 then
                local ok, model = pcall(GetEntityModel, entity)
                if ok and math.tointeger(model) then
                    local u = math.tointeger(model) & 0xffffffff -- signed, like GetHashKey
                    looking = { hash = u >= 0x80000000 and u - 0x100000000 or u, kind = ({ 'ped', 'vehicle', 'object' })[kind] }
                end
            end
        end
        exports.wasteland_ui:Update(PANEL, { coords = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(ped), looking = looking } })
    elseif action == 'list' and type(payload) == 'table' then
        TriggerServerEvent('wasteland:admin:server:list', tostring(payload.which))
    elseif action == 'act' and type(payload) == 'table' and type(payload.action) == 'string' then
        local args = type(payload.args) == 'table' and payload.args or {}
        if payload.action == 'vehicleFix' then
            -- The vehicle you sit in, or the nearest one within 8 m.
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh == 0 then
                local best = 8.0
                for _, v in ipairs(GetGamePool('CVehicle')) do
                    local d = #(GetEntityCoords(v) - GetEntityCoords(ped))
                    if d < best then veh, best = v, d end
                end
            end
            if veh ~= 0 and NetworkGetEntityIsNetworked(veh) then args.netId = NetworkGetNetworkIdFromEntity(veh) end
        end
        TriggerServerEvent('wasteland:admin:server:act', payload.action, args)
    end
end)

-------------------------------------------------------------------------------
-- World tools: waypoint, spectate, overlays
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:admin:client:tpWaypoint', function()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then say('Set a waypoint on the map first.'); return end
    local c = GetBlipInfoIdCoord(blip)
    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        local entity = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped
        -- Find the ground: load the area, then probe from high up.
        for _, z in ipairs({ 1000.0, 600.0, 300.0, 150.0, 60.0, 0.0 }) do
            SetEntityCoordsNoOffset(entity, c.x, c.y, z, false, false, false)
            RequestCollisionAtCoord(c.x, c.y, z)
            Citizen.Wait(80)
            local found, ground = GetGroundZFor_3dCoord(c.x, c.y, z, false)
            if found then
                SetEntityCoordsNoOffset(entity, c.x, c.y, ground + 1.0, false, false, false)
                return
            end
        end
        SetEntityCoordsNoOffset(entity, c.x, c.y, 100.0, false, false, false)
    end)
end)

local spectating = nil -- { target, back }
RegisterNetEvent('wasteland:admin:client:spectate', function(on, target, coords)
    local ped = PlayerPedId()
    if on then
        if not spectating then spectating = { back = GetEntityCoords(ped) } end
        spectating.target = target
        Citizen.CreateThread(function()
            -- Get near them (invisible, frozen) so their ped is streamed in.
            SetEntityVisible(ped, false, false)
            SetEntityCollision(ped, false, false)
            FreezeEntityPosition(ped, true)
            SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z - 10.0, false, false, false)
            local deadline = GetGameTimer() + 3000
            local player = GetPlayerFromServerId(target)
            while (player == -1 or not DoesEntityExist(GetPlayerPed(player))) and GetGameTimer() < deadline do
                Citizen.Wait(100)
                player = GetPlayerFromServerId(target)
            end
            if player == -1 then say('Could not find that player.'); return end
            NetworkSetInSpectatorMode(true, GetPlayerPed(player))
        end)
    elseif spectating then
        NetworkSetInSpectatorMode(false, ped)
        SetEntityCoordsNoOffset(ped, spectating.back.x, spectating.back.y, spectating.back.z, false, false, false)
        FreezeEntityPosition(ped, false)
        SetEntityCollision(ped, true, true)
        SetEntityVisible(ped, not invisible, false)
        spectating = nil
    end
end)

local overlays = {}    -- name -> data (or true)

RegisterNetEvent('wasteland:admin:client:overlay', function(name, on, data)
    overlays[name] = on and (data or true) or nil
end)

local function label3d(x, y, z, text, r, g, b)
    SetDrawOrigin(x, y, z, 0)
    SetTextScale(0.0, 0.28)
    SetTextFont(4)
    SetTextColour(r or 230, g or 230, b or 220, 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

Citizen.CreateThread(function()
    while true do
        if next(overlays) == nil then
            Citizen.Wait(500)
        else
            local me = GetEntityCoords(PlayerPedId())
            if overlays.zombies then
                for _, ped in ipairs(GetGamePool('CPed')) do
                    local ok, st = pcall(function() return Entity(ped).state.wlZombie end)
                    if ok and st and #(GetEntityCoords(ped) - me) < 80.0 then
                        local mode = GetResourceState('wasteland_zombies') == 'started' and exports.wasteland_zombies:GetZombieMode(ped) or nil
                        local c = GetEntityCoords(ped)
                        local dead = IsPedDeadOrDying(ped, true)
                        label3d(c.x, c.y, c.z + 1.1, string.format('%s · %s%s', st.kind or '?', dead and 'dead' or (mode or 'remote'),
                            NetworkHasControlOfEntity(ped) and '' or ' (other client)'), dead and 150 or 255, dead and 150 or 120, dead and 150 or 100)
                    end
                end
            end
            if overlays.vehicles then
                for _, veh in ipairs(GetGamePool('CVehicle')) do
                    local ok, st = pcall(function() return Entity(veh).state.wlVeh end)
                    if ok and st and #(GetEntityCoords(veh) - me) < 120.0 then
                        local c = GetEntityCoords(veh)
                        local p = st.parts or {}
                        label3d(c.x, c.y, c.z + 1.4, string.format('%s · fuel %.0f · eng %d · bat %s · parts %s · wheels %d%s', st.id,
                            st.fuel or 0, math.floor(GetVehicleEngineHealth(veh)), p.battery and 'y' or 'n', p.engine and 'y' or 'n',
                            p.wheels or 0, st.locked and ' · locked' or ''), 150, 220, 255)
                    end
                end
                local data = type(overlays.vehicles) == 'table' and overlays.vehicles or {}
                for i, s in ipairs(data.spawnPoints or {}) do
                    if #(vector3(s.x, s.y, s.z) - me) < 300.0 then
                        DrawMarker(1, s.x, s.y, s.z - 1.0, 0, 0, 0, 0, 0, 0, 3.0, 3.0, 1.5, 80, 160, 255, 90, false, false, 2, false, nil, nil, false)
                        label3d(s.x, s.y, s.z + 1.0, 'wreck spawn #' .. i, 150, 200, 255)
                    end
                end
            end
            if overlays.camps and type(overlays.camps) == 'table' then
                for _, camp in ipairs(overlays.camps.camps or {}) do
                    local c = camp.coords
                    if #(vector3(c.x, c.y, c.z) - me) < camp.radius + 300.0 then
                        DrawMarker(1, c.x, c.y, c.z - 20.0, 0, 0, 0, 0, 0, 0, camp.radius * 2.0, camp.radius * 2.0, 60.0,
                            127, 199, 90, 40, false, false, 2, false, nil, nil, false)
                        label3d(c.x, c.y, c.z + 3.0, camp.label .. string.format(' · %d m', math.floor(camp.radius)), 127, 199, 90)
                    end
                end
            end
            if overlays.loot and type(overlays.loot) == 'table' then
                for typeName, info in pairs(overlays.loot.containers or {}) do
                    for _, model in ipairs(info.models or {}) do
                        local hash = type(model) == 'number' and model or GetHashKey(model)
                        local obj = GetClosestObjectOfType(me.x, me.y, me.z, 30.0, hash, false, false, false)
                        if obj ~= 0 then
                            local c = GetEntityCoords(obj)
                            label3d(c.x, c.y, c.z + 1.2, string.format('%s (%s)', info.label, typeName), 230, 200, 120)
                        end
                    end
                end
            end
            Citizen.Wait(0)
        end
    end
end)

-------------------------------------------------------------------------------
-- Orders from the server
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:admin:client:teleport', function(c)
    if type(c) ~= 'table' then return end
    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        local entity = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped
        RequestCollisionAtCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
        SetEntityCoordsNoOffset(entity, c.x + 0.0, c.y + 0.0, c.z + 0.0, false, false, false)
        local deadline = GetGameTimer() + 3000
        while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() < deadline do Citizen.Wait(0) end
    end)
end)

RegisterNetEvent('wasteland:admin:client:freeze', function(on)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, on == true)
    if on then say('An admin froze you.') else say('You can move again.') end
end)

RegisterNetEvent('wasteland:admin:client:invisible', function(on)
    invisible = on == true
    local ped = PlayerPedId()
    SetEntityVisible(ped, not invisible, false)
    SetEntityAlpha(ped, invisible and 100 or 255, false) -- you still see yourself faintly
end)

-- Noclip: fly with W/A/S/D, Space up, Ctrl down, Shift faster.
RegisterNetEvent('wasteland:admin:client:noclip', function(on)
    noclip = on == true
    local ped = PlayerPedId()
    if not noclip then
        SetEntityCollision(ped, true, true)
        FreezeEntityPosition(ped, false)
        SetEntityInvincible(ped, false)
        return
    end
    Citizen.CreateThread(function()
        SetEntityInvincible(ped, true)
        while noclip do
            ped = PlayerPedId()
            FreezeEntityPosition(ped, true)
            SetEntityCollision(ped, false, false)
            local pos = GetEntityCoords(ped)
            local rot = GetGameplayCamRot(2)
            local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
            local fx, fy, fz = -math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)
            local rx, ry = math.cos(yaw), math.sin(yaw)
            local speed = IsControlPressed(0, 21) and 2.5 or 0.6 -- shift
            local dx, dy, dz = 0.0, 0.0, 0.0
            if IsControlPressed(0, 32) then dx, dy, dz = dx + fx, dy + fy, dz + fz end -- W
            if IsControlPressed(0, 33) then dx, dy, dz = dx - fx, dy - fy, dz - fz end -- S
            if IsControlPressed(0, 34) then dx, dy = dx - rx, dy - ry end              -- A
            if IsControlPressed(0, 35) then dx, dy = dx + rx, dy + ry end              -- D
            if IsControlPressed(0, 22) then dz = dz + 1.0 end                          -- space
            if IsControlPressed(0, 36) then dz = dz - 1.0 end                          -- ctrl
            SetEntityCoordsNoOffset(ped, pos.x + dx * speed, pos.y + dy * speed, pos.z + dz * speed, true, true, true)
            SetEntityHeading(ped, rot.z)
            Citizen.Wait(0)
        end
    end)
end)

RegisterNetEvent('wasteland:admin:client:announce', function(a)
    if type(a) ~= 'table' or type(a.text) ~= 'string' then return end
    say(string.format('%s (%s)', a.text, tostring(a.by)))
    if not uiRunning() then return end
    exports.wasteland_ui:Open(BANNER, { script = 'html/announce.js', data = a, focus = false, cursor = false })
    Citizen.SetTimeout(10000, function()
        if uiRunning() then exports.wasteland_ui:Close(BANNER) end
    end)
end)
