-- wasteland_farming :: client/main.lua
-- Draws farm plots and their plants (spawned here, not networked), Left
-- Alt on a plot opens it (wasteland_target), and places a plot from the
-- item (a see-through copy follows where you look).

local SCREEN = 'farmPlot'
local cfg = nil
local plots = {}        -- id -> info from the server
local spawned = {}      -- id -> { obj, plants = { [slot] = entity }, targets, sig }
local placing = false

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end

local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(msg))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:farming:client:notice', function(msg) notify(msg) end)

local function loadModel(name)
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local untilT = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < untilT do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function rotate(x, y, heading)
    local r = math.rad(heading)
    return x * math.cos(r) - y * math.sin(r), x * math.sin(r) + y * math.cos(r)
end

local function spots(size)
    local out = {}
    for i = 0, size - 1 do
        for j = 0, size - 1 do out[#out + 1] = { x = -size / 2 + 0.5 + i, y = -size / 2 + 0.5 + j, z = 0.3 } end
    end
    return out
end

local function modelFor(slot)
    if not slot then return nil end
    local m = cfg.stages[slot.stage]
    if slot.stage == 'ripe' then m = (m or 'wl_farm_plant_ripe_%s'):format(slot.color or 'green') end
    return m
end

local function despawn(id)
    local e = spawned[id]
    if not e then return end
    if e.targets and GetResourceState('wasteland_target') == 'started' then
        for _, t in ipairs(e.targets) do pcall(function() exports.wasteland_target:Remove(t) end) end
    end
    for _, ent in pairs(e.plants) do if DoesEntityExist(ent) then DeleteEntity(ent) end end
    if DoesEntityExist(e.obj) then DeleteEntity(e.obj) end
    spawned[id] = nil
end

local function plantsFor(p, e)
    for _, ent in pairs(e.plants) do if DoesEntityExist(ent) then DeleteEntity(ent) end end
    e.plants = {}
    local list = spots(p.size)
    for i, slot in pairs(p.slots) do
        local model = slot and modelFor(slot)
        local spot = list[i]
        if model and spot then
            local hash = loadModel(model)
            if hash then
                local ox, oy = rotate(spot.x, spot.y, p.heading)
                local ent = CreateObjectNoOffset(hash, p.coords.x + ox, p.coords.y + oy, p.coords.z + spot.z, false, false, false)
                SetEntityHeading(ent, (p.heading + i * 47) % 360.0)
                FreezeEntityPosition(ent, true)
                SetEntityCollision(ent, false, false)
                SetModelAsNoLongerNeeded(hash)
                e.plants[i] = ent
            end
        end
    end
end

local function signature(p)
    local parts = {}
    for i, s in pairs(p.slots) do parts[#parts + 1] = i .. '=' .. (s and (s.crop .. s.stage) or '-') end
    table.sort(parts)
    return table.concat(parts, ',')
end

local function spawn(p)
    local kind = cfg.plots[p.kind]
    local hash = kind and loadModel(kind.model)
    if not hash then return end
    local obj = CreateObjectNoOffset(hash, p.coords.x, p.coords.y, p.coords.z, false, false, false)
    SetEntityHeading(obj, p.heading)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    local e = { obj = obj, plants = {}, sig = signature(p) }
    if GetResourceState('wasteland_target') == 'started' then
        e.targets = { exports.wasteland_target:AddEntity(obj, {
            { label = 'Open farm plot', icon = '❀', distance = 3.0,
                onSelect = function() TriggerServerEvent('wasteland:farming:server:open', p.id) end },
        }) }
    end
    spawned[p.id] = e
    plantsFor(p, e)
end

RegisterNetEvent('wasteland:farming:client:sync', function(c, list)
    for id in pairs(spawned) do despawn(id) end
    plots = {}
    cfg = c
    for _, p in ipairs(type(list) == 'table' and list or {}) do plots[p.id] = p end
end)

RegisterNetEvent('wasteland:farming:client:plot', function(p)
    if type(p) ~= 'table' or not p.id then return end
    plots[p.id] = p
    local e = spawned[p.id]
    if e then
        local sig = signature(p)
        if sig ~= e.sig then e.sig = sig; plantsFor(p, e) end
    end
end)

RegisterNetEvent('wasteland:farming:client:remove', function(id)
    plots[id] = nil
    despawn(id)
end)

-- Show the plots near the player.
Citizen.CreateThread(function()
    Wait(2500)
    TriggerServerEvent('wasteland:farming:server:sync')
    while true do
        if cfg then
            local me = GetEntityCoords(PlayerPedId())
            local r = cfg.streamDistance or 150.0
            for id, p in pairs(plots) do
                local d = #(me - vector3(p.coords.x, p.coords.y, p.coords.z))
                if d <= r and not spawned[id] then spawn(p)
                elseif d > r + 20.0 and spawned[id] then despawn(id) end
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do despawn(id) end
    if uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
end)

-------------------------------------------------------------------------------
-- The plot screen
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:farming:client:view', function(v)
    if not uiRunning() or type(v) ~= 'table' then return end
    if exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Update(SCREEN, v)
    else exports.wasteland_ui:Open(SCREEN, { script = 'html/farm.js', data = v, focus = true, cursor = true }) end
end)

RegisterNetEvent('wasteland:farming:client:closeView', function()
    if uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN then return end
    payload = type(payload) == 'table' and payload or {}
    local id, slot = tonumber(payload.id), tonumber(payload.slot)
    if action == 'close' then
        exports.wasteland_ui:Close(SCREEN)
    elseif action == 'plant' and id and slot and type(payload.crop) == 'string' then
        TriggerServerEvent('wasteland:farming:server:plant', id, slot, payload.crop)
    elseif action == 'water' and id then
        TriggerServerEvent('wasteland:farming:server:water', id)
    elseif action == 'harvest' and id and slot then
        TriggerServerEvent('wasteland:farming:server:harvest', id, slot)
    elseif action == 'pull' and id and slot then
        TriggerServerEvent('wasteland:farming:server:pull', id, slot)
    elseif action == 'pickup' and id then
        TriggerServerEvent('wasteland:farming:server:pickup', id)
    elseif action == 'refresh' and id then
        TriggerServerEvent('wasteland:farming:server:open', id)
    end
end)

-------------------------------------------------------------------------------
-- Placing a plot (from its item)
-------------------------------------------------------------------------------

local function rotToDir(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

RegisterNetEvent('wasteland:farming:client:place', function(kindKey)
    if placing or not cfg then return end
    local kind = cfg.plots[kindKey]
    local hash = kind and loadModel(kind.model)
    if not hash then notify('That farm plot cannot be shown right now.'); return end
    if uiRunning() and exports.wasteland_ui:IsOpen('inventory') then pcall(function() exports.wasteland_inventory:Close() end) end
    placing = true
    local ped = PlayerPedId()
    local start = GetEntityCoords(ped)
    local ghost = CreateObjectNoOffset(hash, start.x, start.y, start.z, false, false, false)
    SetEntityAlpha(ghost, 160, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    local heading = GetEntityHeading(ped)
    Citizen.CreateThread(function()
        while placing do
            Wait(0)
            for _, c in ipairs({ 24, 25, 14, 15, 16, 17, 37, 44, 140, 141, 142, 177, 194, 200 }) do DisableControlAction(0, c, true) end
            if IsDisabledControlJustPressed(0, 14) then heading = (heading - 15.0) % 360.0 end
            if IsDisabledControlJustPressed(0, 15) then heading = (heading + 15.0) % 360.0 end
            local from = GetGameplayCamCoord()
            local to = from + rotToDir(GetGameplayCamRot(2)) * 10.0
            local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, -1, ghost, 7)
            local _, hit, pos = GetShapeTestResult(ray)
            local at = hit == 1 and pos or to
            SetEntityCoordsNoOffset(ghost, at.x, at.y, at.z, false, false, false)
            SetEntityHeading(ghost, heading)
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(('%s~n~~INPUT_CONTEXT~ place   ~INPUT_FRONTEND_RRIGHT~ cancel~n~Wheel: turn'):format(kind.label))
            EndTextCommandDisplayHelp(0, false, false, -1)
            if IsControlJustReleased(0, 38) then
                if hit == 1 and #(GetEntityCoords(ped) - at) <= 7.5 then
                    TriggerServerEvent('wasteland:farming:server:place', kindKey, at.x, at.y, at.z, heading)
                    placing = false
                else
                    notify('Aim at the ground (or a floor) close to you.')
                end
            end
            if IsDisabledControlJustReleased(0, 177) or IsDisabledControlJustReleased(0, 194) or IsDisabledControlJustReleased(0, 200) or IsEntityDead(ped) then
                placing = false
                notify('Placing cancelled.')
            end
        end
        if DoesEntityExist(ghost) then DeleteEntity(ghost) end
    end)
end)
