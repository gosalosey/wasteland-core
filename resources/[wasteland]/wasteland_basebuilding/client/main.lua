-- wasteland_basebuilding :: client/main.lua
-- Shows bases (local props near you), placement with snapping, doors (E),
-- Left Alt options on pieces and cupboards, the build menu, the cupboard
-- screen, the lockpick minigame and raid detection (explosions, melee).
-- Ported from sbb-basebuilding; every decision is the server's.

local SCREEN = 'bbScreen'
local LOCKPICK = 'bbLockpick'
local cfg = nil
local cupboardCache, propCache = {}, {}      -- id -> data (coords as vector3)
local spawnedCupboards, spawnedProps = {}, {} -- id -> { obj, targets }
local myBlips = {}
local isPlacing, picking = false, false
local warnedModels = {}
local KEY_E, KEY_BACK = 38, 194
local WALL_LIKE = { wall = true, doorway = true, windowframe = true, halfwall = true }

local meleeWeapons = {}
for _, w in ipairs({ 'WEAPON_UNARMED', 'WEAPON_HAMMER', 'WEAPON_CROWBAR', 'WEAPON_BAT', 'WEAPON_MACHETE', 'WEAPON_KNIFE',
    'WEAPON_HATCHET', 'WEAPON_BATTLEAXE', 'WEAPON_WRENCH', 'WEAPON_KNUCKLE', 'WEAPON_SWITCHBLADE' }) do meleeWeapons[GetHashKey(w)] = true end

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function targetRunning() return GetResourceState('wasteland_target') == 'started' end
local function isOpen(s) return uiRunning() and exports.wasteland_ui:IsOpen(s) end

local function notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:basebuilding:client:notice', function(m)
    notify(m)
    if isOpen(SCREEN) then exports.wasteland_ui:Update(SCREEN, { message = m }) end
end)

local function vec(c) return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0) end

local function DrawText3D(coords, text)
    local onScreen, sx, sy = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx, sy)
end

local function RequestModelHash(model)
    if not IsModelInCdimage(model) then
        if not warnedModels[model] then
            warnedModels[model] = true
            print(('[wasteland_basebuilding] model %s is not in the game: is the props pack (sinor-buildingProps-v2) running?'):format(tostring(model)))
        end
        return false
    end
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(10) end
    return HasModelLoaded(model)
end

local function DoorOpenHeading(data)
    local piece = cfg.pieces[data.piece]
    local offset = (piece and piece.openAngleOffset) or 90.0
    return (data.heading + offset) % 360.0
end

-------------------------------------------------------------------------------
-- Model dimensions (for snapping)
-------------------------------------------------------------------------------

local modelDimsCache = {}

-- Measured fresh each time: a streamed model's collision can still be
-- loading, and an early, too-small box would otherwise stick.
local function CacheModelDims(model)
    local min, max = GetModelDimensions(model)
    local size = max - min
    if size.x < 0.01 or size.y < 0.01 or size.z < 0.01 then
        size = vector3(size.x < 0.01 and 3.0 or size.x, size.y < 0.01 and 3.0 or size.y, size.z < 0.01 and 3.0 or size.z)
        min, max = size / -2.0, size / 2.0
    end
    modelDimsCache[model] = { size = size, min = min, max = max }
end

local function GetModelDims(model)
    return modelDimsCache[model] or { size = vector3(2.0, 2.0, 2.0), min = vector3(-1.0, -1.0, -1.0), max = vector3(1.0, 1.0, 1.0) }
end

local function RotateOffset(offset, headingDeg)
    local rad = math.rad(headingDeg)
    local c, s = math.cos(rad), math.sin(rad)
    return vector3(offset.x * c - offset.y * s, offset.x * s + offset.y * c, offset.z)
end

local function cacheAllModels()
    local seen = {}
    for _, piece in pairs(cfg.pieces) do
        if not seen[piece.model] then
            seen[piece.model] = true
            local hash = GetHashKey(piece.model)
            if RequestModelHash(hash) then
                CacheModelDims(hash)
                SetModelAsNoLongerNeeded(hash)
            end
        end
    end
end

-- Candidate snap positions for `pieceKey` against every known piece.
-- opts.rampLevel: 'ground' (beside the foundation, its top level with the
-- foundation's top: walk up onto it) or 'top' (standing on the foundation);
-- opts.rampFlip: turned round (up <-> down).
local function GetSnapCandidates(pieceKey, overlap, opts)
    opts = opts or {}
    local P = cfg.placement
    overlap = overlap or P.snapOverlap
    local rules = cfg.snapRules[pieceKey]
    if not rules or #rules == 0 then return nil end
    local ruleByAnchor = {}
    for _, r in ipairs(rules) do ruleByAnchor[r.anchor] = r.mode end

    local newPiece = cfg.pieces[pieceKey]
    if newPiece then CacheModelDims(GetHashKey(newPiece.model)) end
    local newDims = newPiece and GetModelDims(GetHashKey(newPiece.model)) or { size = vector3(2.0, 2.0, 2.0), min = vector3(-1.0, -1.0, -1.0), max = vector3(1.0, 1.0, 1.0) }

    local candidates = {}
    for _, data in pairs(propCache) do
        local anchorConf = cfg.pieces[data.piece]
        local family = anchorConf and (anchorConf.family or data.piece)
        local mode = family and ruleByAnchor[family]
        if mode then
            local anchorHash = GetHashKey(data.model)
            CacheModelDims(anchorHash)
            local dims = GetModelDims(anchorHash)
            if mode == 'edge' then
                -- How far from the anchor's pivot the new piece's pivot goes,
                -- for an anchor face `face` metres out. After turning into
                -- place the new piece's local +Y points outward (or -Y when
                -- turned round), so its near face is -min.y and its outer
                -- face max.y (swapped when turned round).
                local flip = P.wallFacesOutward and 0.0 or 180.0
                local turned = not P.wallFacesOutward
                if pieceKey == 'ramp' and opts.rampFlip then flip, turned = flip + 180.0, not turned end
                local near = turned and newDims.max.y or -newDims.min.y
                local outer = turned and -newDims.min.y or newDims.max.y
                local inside = false
                if WALL_LIKE[pieceKey] and P.wallsInset ~= false then
                    -- walls stand ON the edge, their outer face flush with it: at a
                    -- corner two walls overlap instead of leaving a gap
                    inside = true
                elseif pieceKey == 'ramp' and opts.rampLevel == 'top' then
                    inside = true -- lying on the foundation, flush with its edge
                end
                local function out(face)
                    if inside then return face - outer end
                    return face + near - overlap
                end
                local frontDist, backDist = out(dims.max.y), out(-dims.min.y)
                local rightDist, leftDist = out(dims.max.x), out(-dims.min.x)
                local zOffset = 0.0
                if pieceKey == 'ramp' then
                    if opts.rampLevel == 'top' then
                        zOffset = dims.max.z + (-newDims.min.z) - overlap
                    else
                        zOffset = dims.max.z - newDims.max.z -- its top level with the foundation's top
                    end
                elseif pieceKey ~= 'foundation' and pieceKey ~= 'ceiling' then
                    zOffset = dims.max.z + (-newDims.min.z) - overlap
                end
                for _, e in ipairs({
                    { off = vector3(0.0, frontDist, zOffset), angle = 0.0 },
                    { off = vector3(rightDist, 0.0, zOffset), angle = 90.0 },
                    { off = vector3(0.0, -backDist, zOffset), angle = 180.0 },
                    { off = vector3(-leftDist, 0.0, zOffset), angle = 270.0 },
                }) do
                    candidates[#candidates + 1] = { coords = data.coords + RotateOffset(e.off, data.heading),
                        heading = (data.heading + e.angle + flip) % 360.0, priority = (pieceKey == 'ceiling') and 1 or 2 }
                end
            elseif mode == 'chain' then
                local rightWidth = dims.max.x + (-newDims.min.x) - overlap
                local leftWidth = (-dims.min.x) + newDims.max.x - overlap
                candidates[#candidates + 1] = { coords = data.coords + RotateOffset(vector3(rightWidth, 0.0, 0.0), data.heading), heading = data.heading, priority = 1 }
                candidates[#candidates + 1] = { coords = data.coords + RotateOffset(vector3(-leftWidth, 0.0, 0.0), data.heading), heading = data.heading, priority = 1 }
            elseif mode == 'top' then
                local localOffset
                if pieceKey == 'ceiling' then
                    localOffset = vector3(0.0, -newDims.size.y / 2.0, dims.max.z - overlap)
                else
                    localOffset = vector3(0.0, 0.0, dims.max.z - overlap)
                end
                candidates[#candidates + 1] = { coords = data.coords + RotateOffset(localOffset, data.heading), heading = data.heading, priority = 1 }
            elseif mode == 'exact' then
                local centerOffset = vector3((newDims.min.x + newDims.max.x) / 2.0, 0.0, 0.0)
                candidates[#candidates + 1] = { coords = data.coords - RotateOffset(centerOffset, data.heading), heading = data.heading, priority = 1 }
            end
        end
    end
    return candidates
end

-------------------------------------------------------------------------------
-- Left Alt options on pieces and cupboards
-------------------------------------------------------------------------------

local function costText(cost)
    local names = {}
    for item in pairs(cost or {}) do names[#names + 1] = item end
    table.sort(names)
    local parts = {}
    for _, item in ipairs(names) do parts[#parts + 1] = cost[item] .. 'x ' .. item:gsub('_', ' ') end
    return table.concat(parts, ', ')
end

local function addTargets(obj, id, isCupboard)
    if not targetRunning() then return {} end
    local d = cfg.targetDistance
    local opts = {}
    if isCupboard then
        opts[#opts + 1] = { label = 'Tool cupboard', icon = '⌂', distance = d,
            onSelect = function() TriggerServerEvent('wasteland:basebuilding:server:cupboard', id) end }
        opts[#opts + 1] = { label = 'Supplies (upkeep)', icon = '▤', distance = d,
            onSelect = function() TriggerServerEvent('wasteland:basebuilding:server:supplies', id) end }
    else
        local data = propCache[id]
        local cat = data and data.category
        if cat == 'stash' then
            opts[#opts + 1] = { label = 'Open storage', icon = '▤', distance = d,
                onSelect = function() TriggerServerEvent('wasteland:basebuilding:server:stash', id) end }
        end
        if cfg.lockpick and (cat == 'door' or cat == 'garage' or cat == 'stash') then
            opts[#opts + 1] = { label = 'Lockpick', icon = '⌕', distance = d,
                onSelect = function() if not picking then TriggerServerEvent('wasteland:basebuilding:server:lockpick', id) end end }
        end
        opts[#opts + 1] = { label = 'Check health', icon = '♥', distance = d,
            onSelect = function()
                local p = propCache[id]
                if p then notify(('Health: %d / %d'):format(p.health, p.max_health)) end
            end }
        local up = data and cfg.upgrades[data.piece]
        local nextPiece = up and cfg.pieces[up.next]
        if nextPiece then
            opts[#opts + 1] = { label = ('Upgrade to %s (%s)'):format(nextPiece.label, costText(up.cost)), icon = '⇑', distance = d,
                canInteract = function() local p = propCache[id]; return p ~= nil and cfg.upgrades[p.piece] ~= nil end,
                onSelect = function() TriggerServerEvent('wasteland:basebuilding:server:upgrade', id) end }
        end
        local rc = data and cfg.raid.repairCost[data.material]
        opts[#opts + 1] = { label = rc and ('Repair (%dx %s)'):format(rc.count, rc.item:gsub('_', ' ')) or 'Repair', icon = '⚒', distance = d,
            canInteract = function() local p = propCache[id]; return p ~= nil and p.health < p.max_health end,
            onSelect = function() TriggerServerEvent('wasteland:basebuilding:server:repair', id) end }
    end
    opts[#opts + 1] = { label = 'Remove', icon = '✕', distance = d,
        onSelect = function() TriggerServerEvent(isCupboard and 'wasteland:basebuilding:server:removeCupboard' or 'wasteland:basebuilding:server:remove', id) end }
    return { exports.wasteland_target:AddEntity(obj, opts) }
end

local function removeTargets(list)
    if not targetRunning() then return end
    for _, t in ipairs(list or {}) do pcall(function() exports.wasteland_target:Remove(t) end) end
end

-------------------------------------------------------------------------------
-- Spawning near the player
-------------------------------------------------------------------------------

-- Draw a prop `s` times bigger: its matrix vectors stretched (the look only;
-- collision stays the model's own).
local function scaleEntity(obj, s)
    if not s or s == 1.0 or not DoesEntityExist(obj) then return end
    -- read and written back in the same order (forward, right, up, position)
    local forward, right, up, at = GetEntityMatrix(obj)
    SetEntityMatrix(obj, forward.x * s, forward.y * s, forward.z * s, right.x * s, right.y * s, right.z * s,
        up.x * s, up.y * s, up.z * s, at.x, at.y, at.z)
end

local function spawnObject(model, coords, heading)
    local hash = GetHashKey(model)
    if not RequestModelHash(hash) then return nil end
    local obj = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(obj, heading)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    SetModelAsNoLongerNeeded(hash)
    return obj
end

local function SpawnCupboard(id)
    if spawnedCupboards[id] then return end
    local data = cupboardCache[id]
    local piece = data and cfg.pieces[cfg.cupboardPiece]
    if not piece then return end
    local obj = spawnObject(piece.model, data.coords, data.heading)
    if not obj then return end
    spawnedCupboards[id] = { obj = obj, targets = addTargets(obj, id, true) }
end

local function DespawnCupboard(id)
    local e = spawnedCupboards[id]
    if e then
        removeTargets(e.targets)
        if DoesEntityExist(e.obj) then DeleteEntity(e.obj) end
    end
    spawnedCupboards[id] = nil
end

-- Garage doors roll up instead of swinging: how far up (metres) when open.
-- basebuilding.lua piece `openLift`, or the door's own height less a little.
local function garageLift(data)
    local piece = cfg.pieces[data.piece]
    if piece and tonumber(piece.openLift) then return tonumber(piece.openLift) end
    local hash = GetHashKey(data.model)
    CacheModelDims(hash)
    return math.max(0.5, GetModelDims(hash).size.z - 0.3)
end

local function SpawnProp(id)
    if spawnedProps[id] then return end
    local data = propCache[id]
    if not data then return end
    local heading, at = data.heading, data.coords
    if data.category == 'door' and data.is_open then heading = DoorOpenHeading(data) end
    if data.category == 'garage' and data.is_open then
        RequestModelHash(GetHashKey(data.model))
        at = data.coords + vector3(0.0, 0.0, garageLift(data))
    end
    local obj = spawnObject(data.model, at, heading)
    if not obj then return end
    local scaled = cfg.pieces[data.piece] and cfg.pieces[data.piece].scale
    if scaled then scaleEntity(obj, scaled) end
    spawnedProps[id] = { obj = obj, targets = addTargets(obj, id, false) }
end

local function DespawnProp(id)
    local e = spawnedProps[id]
    if e then
        removeTargets(e.targets)
        if DoesEntityExist(e.obj) then DeleteEntity(e.obj) end
    end
    spawnedProps[id] = nil
end

Citizen.CreateThread(function()
    while true do
        if cfg then
            local pos = GetEntityCoords(PlayerPedId())
            local r = cfg.streamRadius
            for id, data in pairs(cupboardCache) do
                local dist = #(pos - data.coords)
                if dist <= r and not spawnedCupboards[id] then SpawnCupboard(id)
                elseif dist > r + 20.0 and spawnedCupboards[id] then DespawnCupboard(id) end
            end
            for id, data in pairs(propCache) do
                local dist = #(pos - data.coords)
                if dist <= r and not spawnedProps[id] then SpawnProp(id)
                elseif dist > r + 20.0 and spawnedProps[id] then DespawnProp(id) end
            end
        end
        Wait(2000)
    end
end)

-------------------------------------------------------------------------------
-- Map markers for bases you may use
-------------------------------------------------------------------------------

local function clearBlips() for id, b in pairs(myBlips) do RemoveBlip(b); myBlips[id] = nil end end

local function setMine(list)
    clearBlips()
    for _, id in ipairs(list or {}) do
        local data = cupboardCache[id]
        if data then
            local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
            SetBlipSprite(blip, 40)
            SetBlipColour(blip, 3)
            SetBlipScale(blip, 0.9)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('My Base')
            EndTextCommandSetBlipName(blip)
            myBlips[id] = blip
        end
    end
end

-------------------------------------------------------------------------------
-- From the server
-------------------------------------------------------------------------------

local function storeCupboard(c)
    c.coords = vec(c.coords)
    -- the zombie-free zone: when it ends on this game's clock (nil = over, -1 = never)
    if c.safeLeft and c.safeLeft > 0 then c.safeEndsAt = GetGameTimer() + c.safeLeft * 1000
    elseif c.safeLeft == -1 then c.safeEndsAt = -1 end
    cupboardCache[c.id] = c
end

local function safeActive(c)
    return c.safeEndsAt == -1 or (c.safeEndsAt ~= nil and GetGameTimer() < c.safeEndsAt)
end
local function storeProp(p)
    p.coords = vec(p.coords)
    local piece = cfg and cfg.pieces[p.piece]
    if piece then p.model = piece.model end -- the model this game has (altModels)
    propCache[p.id] = p
end

RegisterNetEvent('wasteland:basebuilding:client:sync', function(data)
    if type(data) ~= 'table' then return end
    for id in pairs(spawnedCupboards) do DespawnCupboard(id) end
    for id in pairs(spawnedProps) do DespawnProp(id) end
    cupboardCache, propCache = {}, {}
    local first = cfg == nil and data.config ~= nil
    if data.config then
        cfg = data.config
        -- a piece whose model this game lacks uses the first of its altModels it has
        for _, piece in pairs(cfg.pieces) do
            if piece.altModels and #piece.altModels > 0 and not IsModelInCdimage(GetHashKey(piece.model)) then
                for _, m in ipairs(piece.altModels) do
                    if IsModelInCdimage(GetHashKey(m)) then piece.model = m; break end
                end
            end
        end
    end
    for _, c in ipairs(data.cupboards or {}) do storeCupboard(c) end
    for _, p in ipairs(data.props or {}) do storeProp(p) end
    if data.mine then setMine(data.mine) end
    if first then Citizen.CreateThread(cacheAllModels) end
end)

RegisterNetEvent('wasteland:basebuilding:client:mine', function(list) setMine(list) end)
RegisterNetEvent('wasteland:basebuilding:client:cupboardAdded', function(c) storeCupboard(c) end)
RegisterNetEvent('wasteland:basebuilding:client:cupboardRemoved', function(id)
    cupboardCache[id] = nil
    DespawnCupboard(id)
    if myBlips[id] then RemoveBlip(myBlips[id]); myBlips[id] = nil end
end)
RegisterNetEvent('wasteland:basebuilding:client:cupboardHealth', function(id, health) if cupboardCache[id] then cupboardCache[id].health = health end end)
RegisterNetEvent('wasteland:basebuilding:client:propAdded', function(p) storeProp(p) end)
RegisterNetEvent('wasteland:basebuilding:client:propRemoved', function(id) propCache[id] = nil; DespawnProp(id) end)
RegisterNetEvent('wasteland:basebuilding:client:propHealth', function(id, health) if propCache[id] then propCache[id].health = health end end)
RegisterNetEvent('wasteland:basebuilding:client:propUpgraded', function(id, patch)
    local data = propCache[id]
    if not data then return end
    for k, v in pairs(patch) do data[k] = v end
    DespawnProp(id)
    SpawnProp(id)
end)

RegisterNetEvent('wasteland:basebuilding:client:door', function(id, isOpen)
    local data = propCache[id]
    if not data then return end
    data.is_open = isOpen
    local e = spawnedProps[id]
    if not e or not DoesEntityExist(e.obj) then return end
    if data.category == 'garage' then
        -- roll up / down, about a second
        local fromZ = GetEntityCoords(e.obj).z
        local toZ = data.coords.z + (isOpen and garageLift(data) or 0.0)
        Citizen.CreateThread(function()
            for i = 1, 30 do
                if not DoesEntityExist(e.obj) then return end
                local z = fromZ + (toZ - fromZ) * (i / 30)
                SetEntityCoordsNoOffset(e.obj, data.coords.x, data.coords.y, z, false, false, false)
                SetEntityHeading(e.obj, data.heading)
                Wait(33)
            end
        end)
        return
    end
    local from = GetEntityHeading(e.obj)
    local to = isOpen and DoorOpenHeading(data) or data.heading
    local piece = cfg and cfg.pieces[data.piece]
    local through = piece and piece.passThrough
    Citizen.CreateThread(function()
        -- a gate swings through players and vehicles instead of shoving them
        if through then SetEntityCollision(e.obj, false, false) end
        local steps = through and 30 or 8
        for i = 1, steps do
            if not DoesEntityExist(e.obj) then return end
            local diff = ((to - from + 540.0) % 360.0) - 180.0
            SetEntityHeading(e.obj, (from + diff * (i / steps)) % 360.0)
            Wait(25)
        end
        if through and DoesEntityExist(e.obj) then
            -- solid again once nobody is standing or parked inside it
            local until_ = GetGameTimer() + 15000
            while GetGameTimer() < until_ do
                local ped = PlayerPedId()
                local veh = GetVehiclePedIsIn(ped, false)
                if not IsEntityTouchingEntity(e.obj, ped) and (veh == 0 or not IsEntityTouchingEntity(e.obj, veh)) then break end
                Wait(200)
            end
            if DoesEntityExist(e.obj) then SetEntityCollision(e.obj, true, true) end
        end
    end)
end)

Citizen.CreateThread(function() TriggerServerEvent('wasteland:basebuilding:server:sync') end)

-------------------------------------------------------------------------------
-- Screens: build menu and cupboard
-------------------------------------------------------------------------------

local screenMode = nil

local function showScreen(data)
    if not uiRunning() then return end
    if isOpen(SCREEN) then exports.wasteland_ui:Update(SCREEN, data)
    else exports.wasteland_ui:Open(SCREEN, { script = 'html/build.js', data = data }) end
end

RegisterNetEvent('wasteland:basebuilding:client:build', function(view)
    if isPlacing or not cfg then return end
    if isOpen('inventory') then exports.wasteland_ui:Close('inventory') end
    screenMode = 'build'
    showScreen({ mode = 'build', build = view })
end)

RegisterNetEvent('wasteland:basebuilding:client:cupboard', function(view)
    screenMode = 'cupboard'
    showScreen({ mode = 'cupboard', cupboard = view })
end)

local StartPlacement

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    payload = type(payload) == 'table' and payload or {}
    if screen == LOCKPICK then
        if not picking then return end
        picking = false
        exports.wasteland_ui:Close(LOCKPICK)
        TriggerServerEvent('wasteland:basebuilding:server:lockpickResult', action == 'result' and payload.success == true)
        return
    end
    if screen ~= SCREEN then return end
    if action == 'close' then exports.wasteland_ui:Close(SCREEN); return end
    if action == 'place' and type(payload.key) == 'string' then
        exports.wasteland_ui:Close(SCREEN)
        StartPlacement(payload.key)
    elseif action == 'authorize' then
        local target = math.tointeger(tonumber(payload.server))
        if target then TriggerServerEvent('wasteland:basebuilding:server:authorize', payload.cupboard, target) end
    elseif action == 'revoke' then
        TriggerServerEvent('wasteland:basebuilding:server:revoke', payload.cupboard, math.tointeger(tonumber(payload.id)) or 0)
    elseif action == 'supplies' then
        exports.wasteland_ui:Close(SCREEN)
        TriggerServerEvent('wasteland:basebuilding:server:supplies', payload.cupboard)
    elseif action == 'repairAll' then
        TriggerServerEvent('wasteland:basebuilding:server:repairAll', payload.cupboard)
    elseif action == 'removeCupboard' then
        exports.wasteland_ui:Close(SCREEN)
        TriggerServerEvent('wasteland:basebuilding:server:removeCupboard', payload.cupboard)
    end
end)

-------------------------------------------------------------------------------
-- Placement
-------------------------------------------------------------------------------

-- Snap overlap per piece: Ctrl+wheel tunes it and it is remembered on this
-- computer; basebuilding.lua placement.overlap = { piece = metres } sets the
-- default for everyone (/bbsnap lists what you tuned, to copy in there).
local function overlapFor(key)
    local saved = GetResourceKvpString('bb_overlap_' .. key)
    if saved and tonumber(saved) then return tonumber(saved) end
    local per = cfg.placement.overlap
    if type(per) == 'table' and tonumber(per[key]) then return tonumber(per[key]) end
    return cfg.placement.snapOverlap
end

local function saveOverlap(key, value)
    SetResourceKvp('bb_overlap_' .. key, ('%.2f'):format(value))
end

RegisterCommand('bbsnap', function(_, args)
    if not cfg then return end
    if args[1] == 'reset' then
        for key in pairs(cfg.pieces) do DeleteResourceKvp('bb_overlap_' .. key) end
        notify('Snap overlaps back to the defaults.')
        return
    end
    local parts = {}
    for key in pairs(cfg.pieces) do
        local saved = GetResourceKvpString('bb_overlap_' .. key)
        if saved then parts[#parts + 1] = key .. ' = ' .. saved end
    end
    table.sort(parts)
    local text = #parts > 0 and ('Your snap overlaps: ' .. table.concat(parts, ', ')) or 'You have not tuned any snap overlap (Ctrl+wheel while placing).'
    notify(text)
    print('[wasteland_basebuilding] ' .. text)
    print('[wasteland_basebuilding] For everyone: basebuilding.lua placement.overlap = { ' .. table.concat(parts, ', ') .. ' }')
end, false)

local function RotationToDirection(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

StartPlacement = function(pieceKey)
    local piece = cfg.pieces[pieceKey]
    if not piece or isPlacing then return end
    local model = GetHashKey(piece.model)
    if not RequestModelHash(model) then notify('That piece cannot be shown: is the building props pack installed?'); return end
    local P = cfg.placement
    isPlacing = true
    local ped = PlayerPedId()
    local start = GetEntityCoords(ped)
    local ghost = CreateObject(model, start.x, start.y, start.z, false, false, false)
    SetEntityAlpha(ghost, 150, false)
    SetEntityCollision(ghost, false, false)
    SetModelAsNoLongerNeeded(model)

    local heading, heightOffset, placeCoords = GetEntityHeading(ped), 0.0, start
    local snapEnabled = true
    local overlap = overlapFor(pieceKey)
    local rampOpts = { rampLevel = 'ground', rampFlip = false }
    local candidates = cfg.snapRules[pieceKey] and GetSnapCandidates(pieceKey, overlap, rampOpts) or nil
    local lastRefresh, lastKey = GetGameTimer(), nil

    local function cleanup()
        if DoesEntityExist(ghost) then DeleteEntity(ghost) end
        isPlacing = false
    end

    Citizen.CreateThread(function()
        while isPlacing do
            for _, c in ipairs({ 14, 15, 16, 17, 24, 25, 36, 37, 38, 44, 45, 140, 141, 142, 172, 173, 174, 175, 177, 194, 199, 200 }) do DisableControlAction(0, c, true) end
            local camCoord = GetGameplayCamCoord()
            local destination = camCoord + RotationToDirection(GetGameplayCamRot(2)) * P.maxPlaceDistance
            local ray = StartExpensiveSynchronousShapeTestLosProbe(camCoord.x, camCoord.y, camCoord.z, destination.x, destination.y, destination.z, 1 + 16, ped, 7)
            local _, hit, endCoords = GetShapeTestResult(ray)
            local target = hit == 1 and endCoords or destination

            if IsDisabledControlJustPressed(0, 37) then -- Tab: snapping on / off
                snapEnabled = not snapEnabled
                notify(snapEnabled and 'Snapping on' or 'Snapping off')
            end
            if candidates and IsDisabledControlPressed(0, 36) then -- Ctrl + wheel: snap overlap (remembered per piece)
                local step = IsDisabledControlPressed(0, 21) and 0.5 or 0.05
                local changed = false
                if IsDisabledControlJustPressed(0, 14) then overlap = overlap + step; changed = true end
                if IsDisabledControlJustPressed(0, 15) then overlap = overlap - step; changed = true end
                if changed then
                    saveOverlap(pieceKey, overlap)
                    candidates = GetSnapCandidates(pieceKey, overlap, rampOpts)
                    notify(('Snap overlap for %s: %.2f (remembered; /bbsnap lists them)'):format(piece.label, overlap))
                end
            end
            if pieceKey == 'ramp' and candidates then
                if IsDisabledControlJustPressed(0, 45) then -- R: up <-> down
                    rampOpts.rampFlip = not rampOpts.rampFlip
                    candidates, lastKey = GetSnapCandidates(pieceKey, overlap, rampOpts), nil
                elseif IsDisabledControlJustPressed(0, 44) then -- Q: ground level <-> on top of the foundation
                    rampOpts.rampLevel = rampOpts.rampLevel == 'top' and 'ground' or 'top'
                    candidates, lastKey = GetSnapCandidates(pieceKey, overlap, rampOpts), nil
                end
            end
            local t = GetGameTimer()
            if snapEnabled and candidates and t - lastRefresh > 300 then
                candidates = GetSnapCandidates(pieceKey, overlap, rampOpts)
                lastRefresh = t
            end
            if not IsDisabledControlPressed(0, 36) then
                if IsDisabledControlPressed(0, 21) then -- Shift + wheel: height
                    if IsDisabledControlJustPressed(0, 14) then heightOffset = heightOffset + P.heightStep end
                    if IsDisabledControlJustPressed(0, 15) then heightOffset = heightOffset - P.heightStep end
                else -- wheel: turn
                    if IsDisabledControlJustPressed(0, 14) then heading = (heading + P.rotateStep) % 360.0 end
                    if IsDisabledControlJustPressed(0, 15) then heading = (heading - P.rotateStep) % 360.0 end
                end
            end
            local fine = P.fineRotateSpeed * GetFrameTime()
            if IsDisabledControlPressed(0, 174) then heading = (heading - fine) % 360.0 end
            if IsDisabledControlPressed(0, 175) then heading = (heading + fine) % 360.0 end
            -- Up / Down arrows: raise / lower slowly (fine height)
            local lift = (P.fineHeightSpeed or 0.15) * GetFrameTime()
            if IsDisabledControlPressed(0, 172) then heightOffset = heightOffset + lift end
            if IsDisabledControlPressed(0, 173) then heightOffset = heightOffset - lift end

            local didSnap = false
            if snapEnabled and candidates then
                local raw = vector3(target.x, target.y, target.z)
                local best, bestDist, bestPrio = nil, nil, nil
                for _, cand in ipairs(candidates) do
                    local dist = #(raw - cand.coords)
                    if dist <= P.snapDistance then
                        local prio = cand.priority or 2
                        if not bestPrio or prio < bestPrio or (prio == bestPrio and dist < bestDist) then best, bestDist, bestPrio = cand, dist, prio end
                    end
                end
                if best then
                    local key = ('%.2f,%.2f,%.2f'):format(best.coords.x, best.coords.y, best.coords.z)
                    if key ~= lastKey then heading, heightOffset, lastKey = best.heading, 0.0, key end
                    placeCoords = vector3(best.coords.x, best.coords.y, best.coords.z + heightOffset)
                    didSnap = true
                end
            end
            if not didSnap then
                lastKey = nil
                placeCoords = vector3(target.x, target.y, target.z + heightOffset)
            end
            SetEntityCoordsNoOffset(ghost, placeCoords.x, placeCoords.y, placeCoords.z, false, false, false)
            SetEntityHeading(ghost, heading)
            if piece.scale then scaleEntity(ghost, piece.scale) end
            local rampHelp = pieceKey == 'ramp' and ('~n~R: %s   Q: %s'):format(rampOpts.rampFlip and 'facing down' or 'facing up',
                rampOpts.rampLevel == 'top' and 'on top of the foundation' or 'up onto the foundation') or ''
            help(('%s%s~n~~INPUT_CONTEXT~ place   ~INPUT_FRONTEND_RRIGHT~ cancel~n~Wheel: turn 45   Left/Right: turn freely~n~Up/Down: raise/lower   Shift+wheel: height   Tab: snapping %s~n~Ctrl+wheel: close gaps (%.2f)%s'):format(
                piece.label, didSnap and ' (snapped)' or '', snapEnabled and 'on' or 'off', overlap, rampHelp))

            if IsDisabledControlJustReleased(0, KEY_E) then
                TriggerServerEvent('wasteland:basebuilding:server:place', pieceKey, placeCoords.x, placeCoords.y, placeCoords.z, heading)
                cleanup()
                return
            end
            if IsDisabledControlJustReleased(0, KEY_BACK) or IsDisabledControlJustReleased(0, 177) or IsPedDeadOrDying(ped, true) then
                cleanup()
                notify('Placement cancelled.')
                return
            end
            Wait(0)
        end
    end)
end

-------------------------------------------------------------------------------
-- Lockpick minigame
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:basebuilding:client:lockpick', function(p)
    if not uiRunning() or picking then return end
    picking = true
    exports.wasteland_ui:Open(LOCKPICK, { script = 'html/lockpick.js', focus = true, cursor = false, data = p })
end)

-------------------------------------------------------------------------------
-- Doors: E when you stand next to one
-------------------------------------------------------------------------------

Citizen.CreateThread(function()
    while true do
        local sleep = 800
        if cfg and not isPlacing then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local inVehicle = IsPedInAnyVehicle(ped, false)
            -- the nearest door in reach (gates reach further, and from a vehicle)
            local best, bestDist
            for id, data in pairs(propCache) do
                if data.category == 'door' or data.category == 'garage' then
                    local piece = cfg.pieces[data.piece]
                    local far = piece and piece.interactDistance
                    if not inVehicle or far then
                        local d = #(pos - data.coords)
                        if d <= (far or cfg.interact.distance) and (not bestDist or d < bestDist) then best, bestDist = id, d end
                    end
                end
            end
            if best then
                local data = propCache[best]
                sleep = 0
                DrawText3D(data.coords + vector3(0.0, 0.0, 1.0), ('[E] %s'):format(data.is_open and 'Close' or 'Open'))
                -- in a vehicle E is the horn (86)
                local pressed = IsControlJustReleased(0, KEY_E) or (inVehicle and IsControlJustReleased(0, 86))
                if pressed and not (uiRunning() and exports.wasteland_ui:IsOpen('inventory')) then
                    TriggerServerEvent('wasteland:basebuilding:server:door', best)
                end
            end
        end
        Wait(sleep)
    end
end)

-------------------------------------------------------------------------------
-- Raids: explosions near pieces, melee on wood
-------------------------------------------------------------------------------

local blastCooldown = {}

Citizen.CreateThread(function()
    while true do
        Wait(250)
        if cfg and cfg.raid.enabled then
            local t = GetGameTimer()
            local function check(id, coords, material, isCupboard)
                local key = (isCupboard and 'c' or 'p') .. id
                if blastCooldown[key] and t - blastCooldown[key] < 2000 then return end
                local rules = cfg.raid.explosionDamage[material]
                if not rules then return end
                for kind in pairs(rules) do
                    local k = tonumber(kind)
                    if k and IsExplosionInSphere(k, coords.x, coords.y, coords.z, cfg.raid.explosionRadius) then
                        blastCooldown[key] = t
                        TriggerServerEvent('wasteland:basebuilding:server:explosion', id, k, { x = coords.x, y = coords.y, z = coords.z }, isCupboard)
                        return
                    end
                end
            end
            for id in pairs(spawnedProps) do
                local d = propCache[id]
                if d then check(id, d.coords, d.material, false) end
            end
            for id in pairs(spawnedCupboards) do
                local d = cupboardCache[id]
                if d then check(id, d.coords, 'wood', true) end
            end
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(0)
        if not (cfg and cfg.raid.enabled and cfg.raid.melee) then
            Wait(2000)
        elseif IsControlJustPressed(0, 24) and not isPlacing then
            local ped = PlayerPedId()
            if meleeWeapons[GetSelectedPedWeapon(ped)] then
                local pos = GetEntityCoords(ped)
                for id, data in pairs(propCache) do
                    if data.material == 'wood' and #(pos - data.coords) <= 3.0 then
                        TriggerServerEvent('wasteland:basebuilding:server:melee', id)
                        break
                    end
                end
            end
        end
    end
end)

--- GetBarricadesNear(coords, radius) -> list of { id, x, y, z, material }
--- (wasteland_zombies: walls, doors and gates zombies may attack; open doors
--- and materials zombies cannot hurt are left out)
exports('GetBarricadesNear', function(coords, radius)
    local out = {}
    local zb = cfg and cfg.zombieBarricades
    if not zb or not coords then return out end
    local at = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    for id, d in pairs(propCache) do
        local piece = cfg.pieces[d.piece]
        local family = piece and piece.family or d.piece
        if zb.families[family] and not d.is_open and (tonumber(zb.damage[d.material]) or 0) > 0
            and #(d.coords - at) <= (radius or 15.0) then
            out[#out + 1] = { id = id, x = d.coords.x, y = d.coords.y, z = d.coords.z, material = d.material }
        end
    end
    return out
end)

--- IsInBaseZone(coords) -> boolean   (near a tool cupboard: zombies keep out)
exports('IsInBaseZone', function(coords)
    local r = cfg and cfg.safeRadius
    if not r or r <= 0 or not coords then return false end
    local p = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    for _, c in pairs(cupboardCache) do
        if #(p - c.coords) <= r and safeActive(c) then return true end
    end
    return false
end)

--- GetDefensesNear(coords, radius) -> list of { id, x, y, z, damage, slow, touch }
--- (wasteland_zombies: barbed wire and spikes hurt zombies that walk into them)
exports('GetDefensesNear', function(coords, radius)
    local out = {}
    if not cfg or not coords then return out end
    local at = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    for id, d in pairs(propCache) do
        local piece = cfg.pieces[d.piece]
        if piece and piece.contactDamage and #(d.coords - at) <= (radius or 10.0) then
            out[#out + 1] = { id = id, x = d.coords.x, y = d.coords.y, z = d.coords.z, damage = piece.contactDamage,
                slow = piece.slow or 1.0, touch = piece.touchRadius or 1.8 }
        end
    end
    return out
end)

-------------------------------------------------------------------------------
-- The zombie-free zone round a new cupboard: a green ring and a countdown
-------------------------------------------------------------------------------

local function feed(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(true, true)
end

RegisterNetEvent('wasteland:basebuilding:client:safeZoneStarted', function(minutes, radius)
    PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true)
    if minutes and minutes > 0 then
        feed(string.format('~g~Safe zone active~s~: zombies stay out of %d m round your cupboard for ~g~%d minutes~s~. '
            .. 'After that they can come in and attack - build your defenses!', math.floor(radius or 0), minutes))
    else
        feed(string.format('~g~Safe zone active~s~: zombies stay out of %d m round your cupboard.', math.floor(radius or 0)))
    end
end)

RegisterNetEvent('wasteland:basebuilding:client:safeZoneEnded', function(id)
    local c = cupboardCache[id]
    if c then c.safeEndsAt = nil end
end)

local function drawTimer(text)
    SetTextFont(4); SetTextScale(0.0, 0.5); SetTextColour(120, 230, 140, 230)
    SetTextOutline(); SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.04)
end

Citizen.CreateThread(function()
    while true do
        local sleep = 1000
        local r = cfg and cfg.safeRadius
        if r and r > 0 then
            local me = GetEntityCoords(PlayerPedId())
            local shown = false
            for _, c in pairs(cupboardCache) do
                if safeActive(c) then
                    local d = #(me - c.coords)
                    if d <= r + 60.0 then
                        sleep = 0
                        -- the protected area, on the ground
                        DrawMarker(1, c.coords.x, c.coords.y, c.coords.z - 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            r * 2.0, r * 2.0, 1.6, 60, 210, 90, 45, false, false, 2, false, nil, nil, false)
                        if d <= r + 15.0 and not shown and c.safeEndsAt ~= -1 then
                            shown = true
                            local left = math.max(0, math.floor((c.safeEndsAt - GetGameTimer()) / 1000))
                            drawTimer(string.format('Base safe zone: %02d:%02d left', math.floor(left / 60), left % 60))
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(spawnedCupboards) do DespawnCupboard(id) end
    for id in pairs(spawnedProps) do DespawnProp(id) end
    clearBlips()
    if isOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
    if isOpen(LOCKPICK) then exports.wasteland_ui:Close(LOCKPICK) end
end)
