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
    elseif action == 'list' and type(payload) == 'table' then
        TriggerServerEvent('wasteland:admin:server:list', tostring(payload.which))
    elseif action == 'act' and type(payload) == 'table' and type(payload.action) == 'string' then
        TriggerServerEvent('wasteland:admin:server:act', payload.action, type(payload.args) == 'table' and payload.args or {})
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
