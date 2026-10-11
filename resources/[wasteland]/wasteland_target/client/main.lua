-- wasteland_target :: client/main.lua
-- Target system: hold Left Alt, look at something, choose what to do.
-- Other resources register targets (models, entities, network ids, every
-- ped / vehicle / object / player, sphere and box zones) with options;
-- each option runs a function (onSelect), a client event or a server event.
-- Registrations belong to the resource that made them and disappear when it
-- stops. Anything with value must still be checked by the server.
--
--   local id = exports.wasteland_target:AddModel({ 'prop_dumpster_01a' }, {
--       { label = 'Search', icon = '🔍', distance = 2.0,
--         canInteract = function(entity, distance, coords) return true end,
--         onSelect = function(data) print(data.entity, data.coords) end },
--   })
--   exports.wasteland_target:Remove(id)

local Match = WLT.Match
local SCREEN = 'target'
local RAY_LENGTH = 12.0
local RAY_FLAGS = 1 + 2 + 4 + 8 + 16  -- world, vehicles, peds, ragdolls, objects

local registrations = {}   -- id -> registration (see shared/match.lua) + owner
local nextId = 0
local holding = false
local current = {}         -- options on screen: list of { reg, option, index }
local selected = 1
local currentHit = nil
local lastKey = nil

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end

-------------------------------------------------------------------------------
-- Registration (exports)
-------------------------------------------------------------------------------

local function add(kind, fields, options)
    local opts, err = Match.options(options)
    if not opts then
        print(('[wasteland_target] %s: %s'):format(GetInvokingResource() or '?', err))
        return nil
    end
    nextId = nextId + 1
    local r = { id = nextId, kind = kind, options = opts, owner = GetInvokingResource() or GetCurrentResourceName() }
    for k, v in pairs(fields) do r[k] = v end
    registrations[nextId] = r
    return nextId
end

exports('AddModel', function(models, options)
    return add('model', { models = Match.models(models, GetHashKey) }, options)
end)

exports('AddEntity', function(entity, options)
    if type(entity) ~= 'number' or entity == 0 then return nil end
    return add('entity', { entity = entity }, options)
end)

exports('AddNetId', function(netId, options)
    if type(netId) ~= 'number' then return nil end
    return add('net', { netId = netId }, options)
end)

-- kind: 'ped' | 'vehicle' | 'object' | 'player'
exports('AddGlobal', function(kind, options)
    if kind ~= 'ped' and kind ~= 'vehicle' and kind ~= 'object' and kind ~= 'player' then return nil end
    return add('global', { global = kind }, options)
end)

exports('AddSphere', function(coords, radius, options)
    if type(coords) ~= 'table' and type(coords) ~= 'vector3' then return nil end
    return add('zone', { zone = { shape = 'sphere', coords = { x = coords.x, y = coords.y, z = coords.z }, radius = tonumber(radius) or 1.0 } }, options)
end)

exports('AddBox', function(coords, size, heading, options)
    if (type(coords) ~= 'table' and type(coords) ~= 'vector3') or type(size) ~= 'table' then return nil end
    return add('zone', { zone = { shape = 'box', coords = { x = coords.x, y = coords.y, z = coords.z },
        size = { x = size.x or size[1], y = size.y or size[2], z = size.z or size[3] }, heading = tonumber(heading) or 0.0 } }, options)
end)

exports('Remove', function(id)
    if registrations[id] then registrations[id] = nil; return true end
    return false
end)

exports('IsTargeting', function() return holding end)

AddEventHandler('onResourceStop', function(res)
    for id, r in pairs(registrations) do
        if r.owner == res then registrations[id] = nil end
    end
    if res == GetCurrentResourceName() and uiRunning() then exports.wasteland_ui:Close(SCREEN) end
end)

-------------------------------------------------------------------------------
-- What the player looks at
-------------------------------------------------------------------------------

local function cameraRay()
    local from = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(z) * math.abs(math.cos(x)), math.cos(z) * math.abs(math.cos(x)), math.sin(x))
    local to = from + dir * RAY_LENGTH
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, RAY_FLAGS, PlayerPedId(), 4)
    local _, hit, endCoords, _, entity = GetShapeTestResult(handle)
    return hit == 1 or hit == true, endCoords, entity
end

local function look()
    local ped = PlayerPedId()
    local hit, coords, entity = cameraRay()
    if not hit then return nil end
    local info = { coords = { x = coords.x, y = coords.y, z = coords.z } }
    info.distance = #(GetEntityCoords(ped) - coords)
    -- The ray also returns handles for map pieces (buildings, terrain) that
    -- are not script entities; reading their model throws in the game. Only
    -- peds (1), vehicles (2) and objects (3) count as entities.
    local t = 0
    if entity and entity ~= 0 then
        local okType, kind = pcall(GetEntityType, entity)
        t = okType and kind or 0
    end
    if (t == 1 or t == 2 or t == 3) and DoesEntityExist(entity) then
        info.entity = entity
        local okModel, model = pcall(GetEntityModel, entity)
        info.model = okModel and model or nil
        info.type = (t == 1 and (IsPedAPlayer(entity) and 'player' or 'ped')) or (t == 2 and 'vehicle') or 'object'
        if NetworkGetEntityIsNetworked(entity) then info.netId = NetworkGetNetworkIdFromEntity(entity) end
    end
    return info
end

local function allowed(hit)
    return function(_, option)
        if type(option.canInteract) ~= 'function' and type(option.canInteract) ~= 'table' then return true end
        return option.canInteract(hit.entity, hit.distance, hit.coords) and true or false
    end
end

-------------------------------------------------------------------------------
-- Screen
-------------------------------------------------------------------------------

local function show()
    if not uiRunning() then return end
    local labels = {}
    for i, c in ipairs(current) do labels[i] = { label = c.option.label, icon = c.option.icon } end
    local data = { active = holding, options = labels, selected = selected }
    if exports.wasteland_ui:IsOpen(SCREEN) then
        exports.wasteland_ui:Update(SCREEN, data)
    else
        exports.wasteland_ui:Open(SCREEN, { script = 'html/target.js', data = data, focus = false, cursor = false })
    end
end

local function hide()
    if uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
end

local function choose()
    local c = current[selected]
    if not c then return end
    local hit = currentHit or {}
    local o = c.option
    local data = { entity = hit.entity, netId = hit.netId, coords = hit.coords, distance = hit.distance, model = hit.model,
        args = o.args, name = o.name, zone = c.reg.kind == 'zone' and c.reg.id or nil }
    if o.onSelect then
        local ok, err = pcall(o.onSelect, data)
        if not ok then print(('[wasteland_target] option "%s" (%s) failed: %s'):format(o.label, c.reg.owner, tostring(err))) end
    end
    if o.event then TriggerEvent(o.event, data) end
    if o.serverEvent then TriggerServerEvent(o.serverEvent, { netId = hit.netId, coords = hit.coords, args = o.args }) end
end

local function canTarget()
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) or IsPauseMenuActive() or IsNuiFocused() then return false end
    local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
    return not ok or ready -- without wasteland_players: always
end

local CONTROLS = { 24, 25, 140, 141, 142, 257, 263, 264, 14, 15, 16, 17, 37, 38, 44 }

local function run()
    local sinceScan = 1000
    while holding do
        if not canTarget() then break end
        for _, c in ipairs(CONTROLS) do DisableControlAction(0, c, true) end
        sinceScan = sinceScan + GetFrameTime() * 1000
        if sinceScan >= 100 then
            sinceScan = 0
            currentHit = look()
            current = currentHit and Match.collect(registrations, currentHit, allowed(currentHit)) or {}
            if selected > #current then selected = 1 end
            local key = tostring(currentHit and currentHit.entity) .. ':' .. #current
            for _, c in ipairs(current) do key = key .. ':' .. c.reg.id .. '.' .. c.index end
            if key ~= lastKey then
                lastKey = key
                show()
            end
        end
        if #current > 0 then
            local moved = false
            if IsDisabledControlJustPressed(0, 14) then selected = selected % #current + 1; moved = true end      -- wheel down
            if IsDisabledControlJustPressed(0, 15) then selected = (selected - 2) % #current + 1; moved = true end -- wheel up
            if moved then show() end
            if IsDisabledControlJustPressed(0, 24) or IsDisabledControlJustPressed(0, 38) then
                choose()
                break
            end
        end
        Citizen.Wait(0)
    end
    holding = false
    current, currentHit, lastKey, selected = {}, nil, nil, 1
    hide()
end

RegisterCommand('+wl_target', function()
    if holding or not canTarget() then return end
    holding = true
    selected = 1
    show()
    Citizen.CreateThread(run)
end, false)
RegisterCommand('-wl_target', function() holding = false end, false)
RegisterKeyMapping('+wl_target', 'Target: look and interact (hold)', 'keyboard', 'LMENU')
