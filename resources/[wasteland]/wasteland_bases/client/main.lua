-- wasteland_bases :: client/main.lua
-- Shows bases near you (local props, made when you come close and removed
-- when you leave), the placement preview, doors, the base screen (/base,
-- F7) and the interaction options (hold Left Alt).
--
-- Every piece is made of its `parts` (the props you see) and, for walls,
-- doors and gates, hidden solid panels that fill the wall exactly, so the
-- wall blocks whatever the props look like.

local Rules = WLB.Rules
local SCREEN = 'baseScreen'
local cfg = nil          -- from the server: grid, pieces, flag, ...
local bases = {}         -- id -> { id, x, y, z, heading, pieces = { [id] = info } }
local access = {}        -- base id -> true (ours or our group's)
local shown = {}         -- base id -> { flag = { objects, targets }, pieces = { [id] = spawned } }
local blips = {}         -- base id -> { blip, radius }
local placing = nil      -- the placement preview, when active
local preview = nil      -- admin preview objects
local lastView = nil

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function targetRunning() return GetResourceState('wasteland_target') == 'started' end
local function isOpen() return uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) end

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:bases:client:notice', function(m)
    notice(m)
    if isOpen() then exports.wasteland_ui:Update(SCREEN, { message = m }) end
end)

-------------------------------------------------------------------------------
-- Models
-------------------------------------------------------------------------------

local models = {}  -- name -> { hash, min, max } | false (not in the game)

local function model(name)
    local m = models[name]
    if m ~= nil then return m or nil end
    local hash = type(name) == 'number' and name or GetHashKey(name)
    if not IsModelInCdimage(hash) then
        print(('[wasteland_bases] model "%s" is not in the game; that part is skipped'):format(tostring(name)))
        models[name] = false
        return nil
    end
    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Citizen.Wait(0) end
    if not HasModelLoaded(hash) then return nil end
    local mn, mx = GetModelDimensions(hash)
    m = { hash = hash, min = mn, max = mx }
    models[name] = m
    return m
end

-- One prop, bottom on the piece's ground (part.z above it).
local function placeObject(m, piece, part, angle, hinge, ghost)
    local p = { x = part.x, y = part.y, z = (part.z or 0.0) - m.min.z, rz = part.rz }
    local x, y, z, h = Rules.partPosition(piece, p, angle, hinge, 0.0)
    return x, y, z, h
end

local function spawnObject(m, piece, part, angle, hinge, ghost)
    local x, y, z, h = placeObject(m, piece, part, angle, hinge)
    local o = CreateObjectNoOffset(m.hash, x, y, z, false, false, false)
    if not o or o == 0 then return nil end
    SetEntityRotation(o, part.rx or 0.0, part.ry or 0.0, h, 2, true)
    FreezeEntityPosition(o, true)
    SetEntityInvincible(o, true)
    if ghost then
        SetEntityAlpha(o, 160, false)
        SetEntityCollision(o, false, false)
    end
    return o
end

local function moveObject(o, m, piece, part, angle, hinge)
    local x, y, z, h = placeObject(m, piece, part, angle, hinge)
    SetEntityCoordsNoOffset(o, x, y, z, false, false, false)
    SetEntityRotation(o, part.rx or 0.0, part.ry or 0.0, h, 2, true)
end

-------------------------------------------------------------------------------
-- Hidden solid panels
-------------------------------------------------------------------------------

-- The solid model's size: width along its wider flat side, height.
local function solidSize()
    local m = model(cfg.solidModel)
    if not m then return nil end
    local wx, wy = m.max.x - m.min.x, m.max.y - m.min.y
    local turn = wy > wx and 90.0 or 0.0
    return m, math.max(wx, wy), m.max.z - m.min.z, turn
end

-- Panels filling a box { x (middle), z (bottom), w, h } of the piece's own frame.
local function panelParts(box)
    local m, pw, ph, turn = solidSize()
    if not m or pw <= 0.05 or ph <= 0.05 then return {} end
    local cols = math.max(1, math.ceil(box.w / pw - 0.05))
    local rows = math.max(1, math.ceil(box.h / ph - 0.05))
    local out = {}
    for c = 0, cols - 1 do
        local cx = box.x
        if cols > 1 then cx = box.x - box.w / 2 + pw / 2 + c * (box.w - pw) / (cols - 1) end
        for r = 0, rows - 1 do
            local cz = box.z
            if rows > 1 then cz = box.z + r * (box.h - ph) / (rows - 1) end
            out[#out + 1] = { x = cx, y = 0.0, z = cz, rz = turn }
        end
    end
    return out, m
end

-- Solid boxes for a wall piece: a full wall, or around a door opening
-- (the leaf gets its own panels that swing with it).
local function solidBoxes(def)
    local w, h = cfg.grid, cfg.wallHeight
    if not def.door then return { { x = 0.0, z = 0.0, w = w, h = h } }, nil end
    local d = def.door
    local left, right = d.hinge, d.hinge + d.width
    local boxes = {}
    if left > -w / 2 + 0.05 then boxes[#boxes + 1] = { x = (-w / 2 + left) / 2, z = 0.0, w = left + w / 2, h = h } end
    if right < w / 2 - 0.05 then boxes[#boxes + 1] = { x = (right + w / 2) / 2, z = 0.0, w = w / 2 - right, h = h } end
    if d.height < h - 0.05 then boxes[#boxes + 1] = { x = (left + right) / 2, z = d.height, w = d.width, h = h - d.height } end
    return boxes, { x = (left + right) / 2, z = 0.0, w = d.width, h = d.height }
end

-------------------------------------------------------------------------------
-- Pieces in the world
-------------------------------------------------------------------------------

local function removeTargets(list)
    if not targetRunning() then return end
    for _, id in ipairs(list or {}) do pcall(function() exports.wasteland_target:Remove(id) end) end
end

local function deleteObjects(list)
    for _, o in ipairs(list or {}) do if DoesEntityExist(o) then DeleteObject(o) end end
end

local function despawnPiece(s)
    if not s then return end
    removeTargets(s.targets)
    deleteObjects(s.objects)
    for _, l in ipairs(s.leaves or {}) do if DoesEntityExist(l.object) then DeleteObject(l.object) end end
end

local function setDoor(s, open)
    if not s or not s.def.door then return end
    local angle = open and 90.0 or 0.0
    for _, l in ipairs(s.leaves) do
        if DoesEntityExist(l.object) then moveObject(l.object, l.model, s.info, l.part, angle, s.def.door.hinge) end
    end
    s.open = open
end

local function pieceOptions(baseId, info, def)
    local mine = function() return access[baseId] == true end
    local opts = {}
    if def.door then
        opts[#opts + 1] = { label = 'Open / close', icon = '⇆', distance = 3.0, canInteract = mine,
            onSelect = function() TriggerServerEvent('wasteland:bases:server:door', info.id) end }
    end
    if def.stash then
        opts[#opts + 1] = { label = def.produces and 'Take water' or 'Open ' .. def.label:lower(), icon = '▤', distance = 3.0, canInteract = mine,
            onSelect = function() TriggerServerEvent('wasteland:bases:server:open', info.id) end }
    end
    if def.station then
        opts[#opts + 1] = { label = 'Craft', icon = '⚒', distance = 3.0, canInteract = mine,
            onSelect = function() ExecuteCommand('craft') end }
    end
    opts[#opts + 1] = { label = 'Demolish ' .. def.label:lower(), icon = '✕', distance = 4.0, canInteract = mine,
        onSelect = function() TriggerServerEvent('wasteland:bases:server:demolish', info.id) end }
    return opts
end

local function spawnPiece(baseId, info)
    local def = cfg and cfg.pieces[info.kind]
    if not def then return nil end
    local s = { info = info, def = def, objects = {}, leaves = {}, targets = {}, open = false }
    for _, part in ipairs(def.parts) do
        local m = model(part.model)
        if m then
            local o = spawnObject(m, info, part)
            if o then
                if part.door then s.leaves[#s.leaves + 1] = { object = o, model = m, part = part, visible = true }
                else s.objects[#s.objects + 1] = o end
            end
        end
    end
    local visible = {}
    for _, o in ipairs(s.objects) do visible[#visible + 1] = o end
    for _, l in ipairs(s.leaves) do visible[#visible + 1] = l.object end
    if def.slot == 'edge' then
        local boxes, leaf = solidBoxes(def)
        for _, box in ipairs(boxes) do
            local parts, m = panelParts(box)
            for _, part in ipairs(parts) do
                local o = spawnObject(m, info, part)
                if o then SetEntityVisible(o, false, false); s.objects[#s.objects + 1] = o end
            end
        end
        if leaf then
            local parts, m = panelParts(leaf)
            for _, part in ipairs(parts) do
                local o = spawnObject(m, info, part)
                if o then SetEntityVisible(o, false, false); s.leaves[#s.leaves + 1] = { object = o, model = m, part = part } end
            end
        end
    end
    if targetRunning() then
        local opts = pieceOptions(baseId, info, def)
        for _, o in ipairs(visible) do s.targets[#s.targets + 1] = exports.wasteland_target:AddEntity(o, opts) end
    end
    if info.open then setDoor(s, true) end
    return s
end

local function spawnFlag(b)
    local f = { objects = {}, targets = {} }
    for _, part in ipairs(cfg.flag.parts) do
        local m = model(part.model)
        local o = m and spawnObject(m, b, part)
        if o then f.objects[#f.objects + 1] = o end
    end
    if targetRunning() then
        local mine = function() return access[b.id] == true end
        local opts = {
            { label = 'Base', icon = '⌂', distance = 3.0, canInteract = mine, onSelect = function() ExecuteCommand(cfg.command) end },
            { label = 'Upkeep box', icon = '▤', distance = 3.0, canInteract = mine,
                onSelect = function() TriggerServerEvent('wasteland:bases:server:box', b.id) end },
        }
        for _, o in ipairs(f.objects) do f.targets[#f.targets + 1] = exports.wasteland_target:AddEntity(o, opts) end
    end
    return f
end

local function showBase(b)
    local sh = { flag = spawnFlag(b), pieces = {} }
    shown[b.id] = sh
    for id, info in pairs(b.pieces) do
        if not shown[b.id] then return end
        sh.pieces[id] = spawnPiece(b.id, info)
        Citizen.Wait(0)
    end
end

local function hideBase(id)
    local sh = shown[id]
    if not sh then return end
    shown[id] = nil
    removeTargets(sh.flag.targets)
    deleteObjects(sh.flag.objects)
    for _, s in pairs(sh.pieces) do despawnPiece(s) end
end

local function hideAll() for id in pairs(shown) do hideBase(id) end end

-------------------------------------------------------------------------------
-- Map markers for our base
-------------------------------------------------------------------------------

local function clearBlip(id)
    local bl = blips[id]
    if not bl then return end
    RemoveBlip(bl.blip)
    RemoveBlip(bl.radius)
    blips[id] = nil
end

local function refreshBlips()
    for id in pairs(blips) do if not (access[id] and bases[id]) then clearBlip(id) end end
    for id in pairs(access) do
        local b = bases[id]
        if b and not blips[id] and cfg then
            local blip = AddBlipForCoord(b.x + 0.0, b.y + 0.0, b.z + 0.0)
            SetBlipSprite(blip, 40)
            SetBlipColour(blip, 2)
            SetBlipScale(blip, 0.9)
            SetBlipAsShortRange(blip, false)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('Your base')
            EndTextCommandSetBlipName(blip)
            local radius = AddBlipForRadius(b.x + 0.0, b.y + 0.0, b.z + 0.0, cfg.claimRadius + 0.0)
            SetBlipColour(radius, 2)
            SetBlipAlpha(radius, 70)
            blips[id] = { blip = blip, radius = radius }
        end
    end
end

-------------------------------------------------------------------------------
-- From the server
-------------------------------------------------------------------------------

local function store(info)
    local b = { id = info.id, x = info.x, y = info.y, z = info.z, heading = info.heading, pieces = {} }
    for _, p in ipairs(info.pieces or {}) do b.pieces[p.id] = p end
    return b
end

RegisterNetEvent('wasteland:bases:client:all', function(data)
    if type(data) ~= 'table' then return end
    hideAll()
    if data.config then cfg = data.config end
    bases = {}
    for _, info in ipairs(data.bases or {}) do bases[info.id] = store(info) end
    refreshBlips()
end)

RegisterNetEvent('wasteland:bases:client:base', function(info)
    if type(info) ~= 'table' then return end
    hideBase(info.id)
    bases[info.id] = store(info)
    refreshBlips()
end)

RegisterNetEvent('wasteland:bases:client:baseRemoved', function(id)
    hideBase(id)
    bases[id] = nil
    clearBlip(id)
end)

RegisterNetEvent('wasteland:bases:client:access', function(list)
    access = {}
    for _, id in ipairs(list or {}) do access[id] = true end
    refreshBlips()
end)

RegisterNetEvent('wasteland:bases:client:piece', function(baseId, info)
    local b = bases[baseId]
    if not b or type(info) ~= 'table' then return end
    b.pieces[info.id] = info
    local sh = shown[baseId]
    if sh then
        despawnPiece(sh.pieces[info.id])
        sh.pieces[info.id] = spawnPiece(baseId, info)
    end
end)

RegisterNetEvent('wasteland:bases:client:removed', function(baseId, pieceId)
    local b = bases[baseId]
    if b then b.pieces[pieceId] = nil end
    local sh = shown[baseId]
    if sh then despawnPiece(sh.pieces[pieceId]); sh.pieces[pieceId] = nil end
end)

RegisterNetEvent('wasteland:bases:client:door', function(pieceId, open)
    for baseId, b in pairs(bases) do
        local info = b.pieces[pieceId]
        if info then
            info.open = open
            local sh = shown[baseId]
            if sh then setDoor(sh.pieces[pieceId], open) end
            return
        end
    end
end)

-- Show the bases near us; remove the ones we left.
Citizen.CreateThread(function()
    TriggerServerEvent('wasteland:bases:server:sync')
    while true do
        Citizen.Wait(1000)
        if cfg then
            local c = GetEntityCoords(PlayerPedId())
            local near, far = cfg.streamDistance ^ 2, (cfg.streamDistance + 30.0) ^ 2
            for id, b in pairs(bases) do
                local d = (b.x - c.x) ^ 2 + (b.y - c.y) ^ 2
                if d < near and not shown[id] then showBase(b)
                elseif d > far and shown[id] then hideBase(id) end
            end
        end
    end
end)

-------------------------------------------------------------------------------
-- Placement preview
-------------------------------------------------------------------------------

local function help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function lookPoint()
    local cam = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local to = cam + dir * 14.0
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1, PlayerPedId(), 7)
    local _, hit, where = GetShapeTestResult(ray)
    if hit == 1 then return where end
    return nil
end

-- Our base whose claim holds the point.
local function myBaseAt(x, y)
    for id in pairs(access) do
        local b = bases[id]
        if b and Rules.inClaim(b, x, y, cfg.claimRadius) then return b end
    end
    return nil
end

local function stopPlacing()
    if not placing then return end
    for _, g in ipairs(placing.ghosts) do if DoesEntityExist(g.object) then DeleteObject(g.object) end end
    placing = nil
end

local function startPlacing(kind)
    stopPlacing()
    if not cfg then return end
    local parts = kind == 'flag' and cfg.flag.parts or (cfg.pieces[kind] and cfg.pieces[kind].parts)
    if not parts then return end
    if uiRunning() and exports.wasteland_ui:IsOpen('inventory') then exports.wasteland_ui:Close('inventory') end
    local def = kind ~= 'flag' and cfg.pieces[kind] or nil
    local p = { kind = kind, def = def, ghosts = {}, turn = 0.0, heading = GetEntityHeading(PlayerPedId()) }
    local here = GetEntityCoords(PlayerPedId())
    for _, part in ipairs(parts) do
        local m = model(part.model)
        local o = m and spawnObject(m, { x = here.x, y = here.y, z = here.z - 50.0, heading = 0.0 }, part, nil, nil, true)
        if o then p.ghosts[#p.ghosts + 1] = { object = o, model = m, part = part } end
    end
    placing = p
    Citizen.CreateThread(function()
        while placing == p do
            Citizen.Wait(0)
            for _, c in ipairs({ 24, 25, 37, 38, 44, 140, 141, 142, 177, 191, 199, 200, 257, 263 }) do DisableControlAction(0, c, true) end
            local edge = def and def.slot == 'edge'
            if IsDisabledControlJustPressed(0, 38) then
                if edge then p.turn = (p.turn + 90.0) % 360.0 else p.heading = (p.heading + 15.0) % 360.0 end
            elseif IsDisabledControlJustPressed(0, 44) then
                if edge then p.turn = (p.turn + 270.0) % 360.0 else p.heading = (p.heading + 345.0) % 360.0 end
            end
            local hit = lookPoint()
            local pose, ok, why = nil, false, 'Look at the ground'
            if hit then
                local ped = GetEntityCoords(PlayerPedId())
                if kind == 'flag' then
                    pose = { x = hit.x, y = hit.y, z = hit.z, heading = p.heading }
                    ok = #(hit - ped) < 8.0
                    why = ok and nil or 'Too far away'
                else
                    local b = myBaseAt(hit.x, hit.y)
                    if not b then
                        pose = { x = hit.x, y = hit.y, z = hit.z, heading = p.heading }
                        why = 'Outside your base\'s claim'
                    elseif edge then
                        local s = Rules.snapEdge(b, hit.x, hit.y, cfg.grid, p.turn)
                        pose = { x = s.x, y = s.y, z = hit.z, heading = s.heading }
                        ok = Rules.inClaim(b, s.x, s.y, cfg.claimRadius) and #(vector3(s.x, s.y, hit.z) - ped) < 12.0
                        why = ok and nil or 'Too far away'
                    else
                        pose = { x = hit.x, y = hit.y, z = hit.z, heading = p.heading }
                        ok = #(hit - ped) < 12.0
                        why = ok and nil or 'Too far away'
                    end
                end
            end
            for _, g in ipairs(p.ghosts) do
                if pose then
                    moveObject(g.object, g.model, pose, g.part)
                    SetEntityAlpha(g.object, ok and 170 or 70, false)
                end
            end
            local name = kind == 'flag' and cfg.flag.label or def.label
            help(string.format('%s~n~~INPUT_CONTEXT~ / ~INPUT_COVER~ turn~n~~INPUT_ATTACK~ place   ~INPUT_AIM~ stop%s',
                name, why and ('~n~~r~' .. why) or ''))
            if IsDisabledControlJustPressed(0, 24) and pose then
                if not ok then
                    notice(why or 'You cannot build there.')
                elseif kind == 'flag' then
                    TriggerServerEvent('wasteland:bases:server:placeFlag', pose.x, pose.y, pose.z, pose.heading)
                    stopPlacing()
                else
                    TriggerServerEvent('wasteland:bases:server:build', kind, pose.x, pose.y, pose.z, edge and p.turn or p.heading)
                end
            elseif IsDisabledControlJustPressed(0, 25) or IsDisabledControlJustPressed(0, 177) or IsPedDeadOrDying(PlayerPedId(), true)
                or IsPedInAnyVehicle(PlayerPedId(), false) then
                stopPlacing()
            end
        end
    end)
end

RegisterNetEvent('wasteland:bases:client:placeFlag', function() startPlacing('flag') end)

-------------------------------------------------------------------------------
-- The base screen
-------------------------------------------------------------------------------

local function openScreen()
    if not uiRunning() then return end
    if isOpen() then exports.wasteland_ui:Close(SCREEN); return end
    TriggerServerEvent('wasteland:bases:server:view')
    exports.wasteland_ui:Open(SCREEN, { script = 'html/base.js', data = { view = lastView } })
end

RegisterNetEvent('wasteland:bases:client:view', function(v)
    lastView = v
    if isOpen() then exports.wasteland_ui:Update(SCREEN, { view = v }) end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN then return end
    payload = type(payload) == 'table' and payload or {}
    if action == 'close' then exports.wasteland_ui:Close(SCREEN)
    elseif action == 'build' and type(payload.kind) == 'string' then
        exports.wasteland_ui:Close(SCREEN)
        startPlacing(payload.kind)
    elseif action == 'box' and lastView and lastView.base then
        exports.wasteland_ui:Close(SCREEN)
        TriggerServerEvent('wasteland:bases:server:box', lastView.base.id)
    elseif action == 'abandon' then
        TriggerServerEvent('wasteland:bases:server:abandon')
    elseif action == 'refresh' then
        TriggerServerEvent('wasteland:bases:server:view')
    end
end)

Citizen.CreateThread(function()
    while not cfg do Citizen.Wait(500) end
    RegisterCommand(cfg.command, openScreen, false)
    RegisterKeyMapping(cfg.command, 'Base: build', 'keyboard', 'F7')
    TriggerEvent('chat:addSuggestion', '/' .. cfg.command, 'Your base: build walls, doors, storage (also F7)')
end)

-------------------------------------------------------------------------------
-- Admin preview: every piece in a row in front of you, named, for 2 minutes
-------------------------------------------------------------------------------

local function clearPreview()
    if not preview then return end
    for _, s in ipairs(preview.pieces) do despawnPiece(s.spawned) end
    preview = nil
end

RegisterNetEvent('wasteland:bases:client:preview', function()
    clearPreview()
    if not cfg then return end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    local fwd = vector3(-math.sin(math.rad(h)), math.cos(math.rad(h)), 0.0)
    local right = vector3(math.cos(math.rad(h)), math.sin(math.rad(h)), 0.0)
    local kinds = {}
    for kind in pairs(cfg.pieces) do kinds[#kinds + 1] = kind end
    table.sort(kinds)
    local p = { pieces = {}, untilAt = GetGameTimer() + 120000 }
    preview = p
    Citizen.CreateThread(function()
        for i, kind in ipairs(kinds) do
            local at = c + fwd * 6.0 + right * ((i - 1) - (#kinds - 1) / 2) * (cfg.grid + 1.0)
            local found, gz = GetGroundZFor_3dCoord(at.x, at.y, at.z + 5.0, false)
            local info = { id = -i, kind = kind, x = at.x, y = at.y, z = found and gz or c.z - 1.0, heading = h }
            p.pieces[#p.pieces + 1] = { info = info, spawned = spawnPiece(0, info) }
        end
        while preview == p and GetGameTimer() < p.untilAt do
            Citizen.Wait(0)
            for _, s in ipairs(p.pieces) do
                local i = s.info
                local onScreen, sx, sy = World3dToScreen2d(i.x, i.y, i.z + 3.4)
                if onScreen then
                    SetTextScale(0.3, 0.3)
                    SetTextFont(4)
                    SetTextCentre(true)
                    SetTextOutline()
                    BeginTextCommandDisplayText('STRING')
                    AddTextComponentSubstringPlayerName(i.kind)
                    EndTextCommandDisplayText(sx, sy)
                end
            end
        end
        if preview == p then clearPreview() end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopPlacing()
    clearPreview()
    hideAll()
    for id in pairs(blips) do clearBlip(id) end
    if isOpen() then exports.wasteland_ui:Close(SCREEN) end
end)
