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
local propOfEntity = {}                        -- entity -> piece id (shelter checks)
local myBlips = {}
local isPlacing, picking = false, false
local movingId = nil -- the placed piece being moved (hidden; not a snap anchor)
local StartPlacement   -- defined below (used by the Left Alt Move option above it)
local PoweredAt        -- (coords) -> boolean: a running generator powers this spot (set below)
local showRange = {}   -- generator id -> true: draw its power range (Left Alt option)
local restingOn = nil  -- the bed this player lies on
local warnedModels = {}
local KEY_E, KEY_BACK = 38, 194
local WALL_LIKE = { wall = true, doorway = true, windowframe = true, halfwall = true }
local CEILING_LIKE = { ceiling = true, hatch = true } -- placed (snapped) like a ceiling

local meleeWeapons = {}
for _, w in ipairs({ 'WEAPON_UNARMED', 'WEAPON_HAMMER', 'WEAPON_CROWBAR', 'WEAPON_BAT', 'WEAPON_MACHETE', 'WEAPON_KNIFE',
    'WEAPON_HATCHET', 'WEAPON_BATTLEAXE', 'WEAPON_WRENCH', 'WEAPON_KNUCKLE', 'WEAPON_SWITCHBLADE' }) do meleeWeapons[GetHashKey(w)] = true end

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
TriggerEvent('chat:addSuggestion', '/adminbuild', 'Admins: build, upgrade and repair for free (turn on / off)')
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

-- Ladder hatches (pieces with `ladder`): the opening and the foot of the
-- ladder, in the piece's own space (its origin is the ceiling's underside).
local LADDER = { hole = vector3(1.3, -1.3, 0.2), top = vector3(1.3, -0.35, 0.2), foot = vector3(1.3, -1.15, -3.0) }

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
            print(("[wasteland_basebuilding] model %s is not in the game: is the building props pack running? (basebuilding.lua: propsResource and the pieces' model names)"):format(tostring(model)))
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
    for pid, data in pairs(propCache) do
      if pid ~= movingId then
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
                elseif pieceKey ~= 'foundation' and not CEILING_LIKE[pieceKey] then
                    zOffset = dims.max.z + (-newDims.min.z) - overlap
                end
                for _, e in ipairs({
                    { off = vector3(0.0, frontDist, zOffset), angle = 0.0 },
                    { off = vector3(rightDist, 0.0, zOffset), angle = 90.0 },
                    { off = vector3(0.0, -backDist, zOffset), angle = 180.0 },
                    { off = vector3(-leftDist, 0.0, zOffset), angle = 270.0 },
                }) do
                    candidates[#candidates + 1] = { coords = data.coords + RotateOffset(e.off, data.heading),
                        heading = (data.heading + e.angle + flip) % 360.0, priority = CEILING_LIKE[pieceKey] and 1 or 2 }
                end
            elseif mode == 'chain' then
                local rightWidth = dims.max.x + (-newDims.min.x) - overlap
                local leftWidth = (-dims.min.x) + newDims.max.x - overlap
                candidates[#candidates + 1] = { coords = data.coords + RotateOffset(vector3(rightWidth, 0.0, 0.0), data.heading), heading = data.heading, priority = 1 }
                candidates[#candidates + 1] = { coords = data.coords + RotateOffset(vector3(-leftWidth, 0.0, 0.0), data.heading), heading = data.heading, priority = 1 }
            elseif mode == 'top' then
                if CEILING_LIKE[pieceKey] then
                    -- on top of a wall: a spot on each side of it (which side is
                    -- the room depends on how the wall was turned); the closer wins
                    for _, side in ipairs({ -1.0, 1.0 }) do
                        local localOffset = vector3(0.0, side * newDims.size.y / 2.0, dims.max.z - overlap)
                        candidates[#candidates + 1] = { coords = data.coords + RotateOffset(localOffset, data.heading), heading = data.heading, priority = 1 }
                    end
                else
                    local localOffset = vector3(0.0, 0.0, dims.max.z - overlap)
                    candidates[#candidates + 1] = { coords = data.coords + RotateOffset(localOffset, data.heading), heading = data.heading, priority = 1 }
                end
            elseif mode == 'exact' then
                local centerOffset = vector3((newDims.min.x + newDims.max.x) / 2.0, 0.0, 0.0)
                candidates[#candidates + 1] = { coords = data.coords - RotateOffset(centerOffset, data.heading), heading = data.heading, priority = 1 }
            end
        end
      end
    end
    return candidates
end

-- Slivers left after snapping: model boxes are not exactly the visible
-- pieces, so a snapped piece can stand a few cm off its neighbour. Short
-- rays go out from each side (and down from the bottom) of the piece at
-- `coords`; where another piece's real surface is that close, the piece is
-- moved onto it. -> world offset (vector3)
local function GapFill(pieceKey, coords, heading, ghost)
    local maxGap = cfg.placement.autoFillGap or 0.15
    if maxGap <= 0 then return vector3(0.0, 0.0, 0.0) end
    local d = GetModelDims(GetHashKey(cfg.pieces[pieceKey].model))
    local inset = 0.05
    local function probe(from, dir)
        local a = coords + RotateOffset(from, heading)
        local b = a + dir * (inset + maxGap)
        local ray = StartExpensiveSynchronousShapeTestLosProbe(a.x, a.y, a.z, b.x, b.y, b.z, 16, ghost, 7)
        local _, hit, at = GetShapeTestResult(ray)
        if hit ~= 1 or not at then return nil end
        local gap = #(at - a) - inset
        if gap > 0.005 and gap <= maxGap then return gap end
        return nil
    end
    -- the smallest gap seen through a face (points spread over it)
    local function face(axis, sign)
        local dir = RotateOffset(axis == 'x' and vector3(sign, 0.0, 0.0) or vector3(0.0, sign, 0.0), heading)
        local best
        for _, u in ipairs({ 0.2, 0.5, 0.8 }) do
            for _, v in ipairs({ 0.25, 0.75 }) do
                local z = d.min.z + d.size.z * v
                local from
                if axis == 'x' then
                    from = vector3((sign > 0 and d.max.x or d.min.x) - sign * inset, d.min.y + d.size.y * u, z)
                else
                    from = vector3(d.min.x + d.size.x * u, (sign > 0 and d.max.y or d.min.y) - sign * inset, z)
                end
                local g = probe(from, dir)
                if g and (not best or g < best) then best = g end
            end
        end
        return best, dir
    end
    local offset = vector3(0.0, 0.0, 0.0)
    for _, axis in ipairs({ 'x', 'y' }) do
        local gp, dp = face(axis, 1.0)
        local gn, dn = face(axis, -1.0)
        -- a gap on one side only (both sides: it sits between two pieces; leave it)
        if gp and not gn then offset = offset + dp * gp
        elseif gn and not gp then offset = offset + dn * gn end
    end
    -- standing a little above what is under it (a ceiling on walls, a wall on a foundation)
    local best
    for _, u in ipairs({ 0.2, 0.5, 0.8 }) do
        for _, v in ipairs({ 0.2, 0.5, 0.8 }) do
            local g = probe(vector3(d.min.x + d.size.x * u, d.min.y + d.size.y * v, d.min.z + inset), vector3(0.0, 0.0, -1.0))
            if g and (not best or g < best) then best = g end
        end
    end
    if best then offset = offset + vector3(0.0, 0.0, -best) end
    return offset
end

-------------------------------------------------------------------------------
-- Barbed wire on top of external walls: touching it hurts (the server checks)
-------------------------------------------------------------------------------

local function wireLocal(data, at)
    local d = at - data.coords
    local h = math.rad(data.heading or 0.0)
    return d.x * math.cos(h) + d.y * math.sin(h), -d.x * math.sin(h) + d.y * math.cos(h), d.z
end

Citizen.CreateThread(function()
    while true do
        local sleep = 1000
        if cfg then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            for id, data in pairs(propCache) do
                local piece = cfg.pieces[data.piece]
                if piece and piece.wireDamage and #(pos.xy - data.coords.xy) < 6.0
                    and not (piece.needsPower and not (PoweredAt and PoweredAt(data.coords))) then
                    sleep = 200
                    local lx, ly, lz = wireLocal(data, pos)
                    -- the ped's position is about 1 m above its feet: hands reach above
                    if math.abs(lx) <= 2.05 and math.abs(ly) <= (piece.wireReach or 0.75)
                        and lz + 0.9 >= (piece.wireFrom or 3.5) and lz - 1.0 <= (piece.wireTo or 4.7) then
                        TriggerServerEvent('wasteland:basebuilding:server:wire', id)
                        sleep = 1000
                        break
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- Sparks at a spot (electric fence contact).
local function sparks(at)
    RequestNamedPtfxAsset('core')
    local until_ = GetGameTimer() + 500
    while not HasNamedPtfxAssetLoaded('core') and GetGameTimer() < until_ do Wait(0) end
    if not HasNamedPtfxAssetLoaded('core') then return end
    UseParticleFxAssetNextCall('core')
    StartParticleFxNonLoopedAtCoord('ent_brk_sparking_wires', at.x, at.y, at.z, 0.0, 0.0, 0.0, 1.2, false, false, false)
end

-- Shocked by an electric fence: sparks, a jolt and a short stagger.
RegisterNetEvent('wasteland:basebuilding:client:shocked', function(id)
    local ped = PlayerPedId()
    local at = GetEntityCoords(ped)
    Citizen.CreateThread(function() sparks(at) end)
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.4)
    if not IsPedInAnyVehicle(ped, false) then SetPedToRagdoll(ped, 900, 1200, 0, false, false, false) end
end)

--- Sparks(coords): for other scripts (zombies touching a live fence)
exports('Sparks', function(c) if type(c) == 'table' or type(c) == 'vector3' then Citizen.CreateThread(function() sparks(vector3(c.x, c.y, c.z)) end) end end)

RegisterNetEvent('wasteland:basebuilding:client:wireHurt', function(amount)
    ApplyDamageToPed(PlayerPedId(), math.floor(tonumber(amount) or 0), false)
end)

-------------------------------------------------------------------------------
-- Ladder hatches: E at the foot of the ladder climbs up, E at the opening climbs down
-------------------------------------------------------------------------------

local climbing = false
local function climbTo(spot, heading)
    climbing = true
    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        DoScreenFadeOut(250)
        while not IsScreenFadedOut() do Wait(0) end
        RequestCollisionAtCoord(spot.x, spot.y, spot.z)
        SetEntityCoords(ped, spot.x, spot.y, spot.z, false, false, false, false)
        SetEntityHeading(ped, heading)
        Wait(300)
        DoScreenFadeIn(250)
        climbing = false
    end)
end

Citizen.CreateThread(function()
    while true do
        local sleep = 700
        if cfg and not isPlacing and not climbing then
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
                local pos = GetEntityCoords(ped)
                for _, data in pairs(propCache) do
                    local piece = cfg.pieces[data.piece]
                    if piece and piece.ladder and #(pos.xy - data.coords.xy) < 4.0 then
                        sleep = 0
                        local foot = data.coords + RotateOffset(LADDER.foot, data.heading)
                        local hole = data.coords + RotateOffset(LADDER.hole, data.heading)
                        local up = #(pos.xy - foot.xy) < 1.0 and math.abs((pos.z - 1.0) - foot.z) < 1.2
                        local down = #(pos.xy - hole.xy) < 1.1 and math.abs((pos.z - 1.0) - hole.z) < 1.2
                        if up or down then
                            DrawText3D((up and foot or hole) + vector3(0.0, 0.0, 1.2), up and '[E] Climb up' or '[E] Climb down')
                            if IsControlJustReleased(0, KEY_E) then
                                if up then
                                    local top = data.coords + RotateOffset(LADDER.top, data.heading)
                                    climbTo(top + vector3(0.0, 0.0, 1.0), (data.heading + 180.0) % 360.0)
                                else
                                    climbTo(foot + vector3(0.0, 0.0, 1.0), data.heading % 360.0)
                                end
                            end
                            break
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

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
    local pdata = not isCupboard and propCache[id] or nil
    local gp = pdata and cfg.pieces[pdata.piece]
    if gp and gp.bed then
        opts[#opts + 1] = { label = 'Lie down and rest', icon = '☾', distance = d,
            canInteract = function() return not restingOn end,
            onSelect = function() TriggerServerEvent('wasteland:basebuilding:server:rest', id, true) end }
    end
    if gp and gp.generator then
        opts[#opts + 1] = { label = 'Turn on / off', icon = '⏻', distance = d,
            onSelect = function() TriggerServerEvent('wasteland:basebuilding:server:generator', id) end }
        if not gp.generator.unlimited then
            opts[#opts + 1] = { label = 'Add fuel (jerry can)', icon = '⛽', distance = d,
                onSelect = function() TriggerServerEvent('wasteland:basebuilding:server:generatorFuel', id) end }
        end
        opts[#opts + 1] = { label = 'Show / hide power range', icon = '◎', distance = d,
            onSelect = function()
                showRange[id] = not showRange[id] or nil
                notify(showRange[id] and ('Power range shown (%d m): lights and electric fences inside it get power.'):format(math.floor(gp.generator.powerRadius))
                    or 'Power range hidden.')
            end }
        opts[#opts + 1] = { label = 'Check fuel', icon = '◔', distance = d,
            onSelect = function()
                local p = propCache[id]
                if p and gp.generator.unlimited then notify(('Unlimited power, %s.'):format(p.is_open and 'running' or 'off'))
                elseif p then notify(('Fuel: %.1f / %d L, %s.'):format(p.fuel or 0, gp.generator.tankLitres, p.is_open and 'running' or 'off')) end
            end }
    end
    if isCupboard then
        opts[#opts + 1] = { label = 'Move', icon = '✥', distance = d,
            canInteract = function() return not isPlacing and cupboardCache[id] ~= nil end,
            onSelect = function() StartPlacement(cfg.cupboardPiece, id, true) end }
    else
        opts[#opts + 1] = { label = 'Move', icon = '✥', distance = d,
            canInteract = function() return not isPlacing and propCache[id] ~= nil end,
            onSelect = function() local p = propCache[id]; if p then StartPlacement(p.piece, id) end end }
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
    -- A tiny fixed nudge per piece (under 1 cm, from its id): two pieces never
    -- share a surface exactly, so overlapping faces do not flicker (z-fighting).
    local n = tonumber(data.id) or id
    at = at + vector3(((n * 7) % 5) * 0.002, ((n * 13) % 5) * 0.002, ((n * 3) % 5) * 0.002)
    local obj = spawnObject(data.model, at, heading)
    if not obj then return end
    local scaled = cfg.pieces[data.piece] and cfg.pieces[data.piece].scale
    if scaled then scaleEntity(obj, scaled) end
    spawnedProps[id] = { obj = obj, targets = addTargets(obj, id, false) }
    propOfEntity[obj] = id
end

local function DespawnProp(id)
    local e = spawnedProps[id]
    if e then
        propOfEntity[e.obj] = nil
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
RegisterNetEvent('wasteland:basebuilding:client:cupboardMoved', function(id, patch)
    local c = cupboardCache[id]
    if not c or type(patch) ~= 'table' then return end
    c.coords, c.heading = vec(patch.coords), patch.heading
    DespawnCupboard(id)
    SpawnCupboard(id)
end)
RegisterNetEvent('wasteland:basebuilding:client:propAdded', function(p) storeProp(p) end)
RegisterNetEvent('wasteland:basebuilding:client:propRemoved', function(id) propCache[id] = nil; DespawnProp(id) end)
RegisterNetEvent('wasteland:basebuilding:client:power', function(id, patch)
    local data = propCache[id]
    if not data or type(patch) ~= 'table' then return end
    data.is_open, data.fuel = patch.is_open == true, tonumber(patch.fuel) or 0
end)

-- Lights: lit while a running generator is within its power radius.
local function powered(at)
    for _, d in pairs(propCache) do
        local piece = cfg.pieces[d.piece]
        if piece and piece.generator and d.is_open and ((d.fuel or 0) > 0 or piece.generator.unlimited) and #(d.coords - at) <= piece.generator.powerRadius then return true end
    end
    return false
end

Citizen.CreateThread(function()
    local lit = {}
    local nextCheck = 0
    while true do
        if not cfg then Wait(1000) else
            local t = GetGameTimer()
            if t >= nextCheck then
                nextCheck = t + 1000
                lit = {}
                local me = GetEntityCoords(PlayerPedId())
                for _, d in pairs(propCache) do
                    local piece = cfg.pieces[d.piece]
                    if piece and piece.light and #(d.coords - me) < 120.0 and powered(d.coords) then
                        local l = piece.light
                        lit[#lit + 1] = { at = d.coords + vector3(0.0, 0.0, l.height), r = l.color[1], g = l.color[2], b = l.color[3],
                            range = l.range, intensity = l.intensity }
                    end
                end
            end
            for _, l in ipairs(lit) do
                DrawLightWithRange(l.at.x, l.at.y, l.at.z, l.r, l.g, l.b, l.range, l.intensity)
            end
            Wait(#lit > 0 and 0 or 500)
        end
    end
end)

PoweredAt = powered

-- Lying in a bed: on top of the mattress, an idle sleeping animation; moving,
-- X or being hurt gets you up (and tells the server).
-- lying flat on the back, no built-in offset (the animation's root is at the floor)
local REST_DICT, REST_ANIM = 'amb@world_human_sunbathe@male@back@base', 'base'
local function getUp(silent)
    if not restingOn then return end
    TriggerServerEvent('wasteland:basebuilding:server:rest', restingOn, false)
    restingOn = nil
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    if not silent then notify('You get up.') end
end

RegisterNetEvent('wasteland:basebuilding:client:rest', function(id)
    local data = propCache[id]
    if not data then return end
    local ped = PlayerPedId()
    RequestAnimDict(REST_DICT)
    local untilT = GetGameTimer() + 2000
    while not HasAnimDictLoaded(REST_DICT) and GetGameTimer() < untilT do Wait(0) end
    local piece = cfg.pieces[data.piece]
    local lie = (piece and piece.bed and piece.bed.lie) or { x = 0.0, y = 0.0, up = 0.47, turn = 270.0 }
    -- the ped's position is about 1 m above its feet; the animation lies at the feet
    local at = data.coords + RotateOffset(vector3(lie.x or 0.0, lie.y or 0.0, 0.0), data.heading) + vector3(0.0, 0.0, (lie.up or 0.47) + 1.0)
    SetEntityCoordsNoOffset(ped, at.x, at.y, at.z, false, false, false)
    SetEntityHeading(ped, (data.heading + (lie.turn or 270.0)) % 360.0)
    FreezeEntityPosition(ped, true) -- held on the mattress while resting
    TaskPlayAnim(ped, REST_DICT, REST_ANIM, 2.0, 2.0, -1, 1, 0, false, false, false)
    restingOn = id
    notify('Resting: you heal slowly and the infection eases. Move or press X to get up.')
    Citizen.CreateThread(function()
        local health = GetEntityHealth(ped)
        while restingOn == id do
            Wait(0)
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
            local moving = IsControlPressed(0, 32) or IsControlPressed(0, 33) or IsControlPressed(0, 34) or IsControlPressed(0, 35) or IsControlPressed(0, 22)
            local now = GetEntityHealth(ped)
            if moving or IsControlJustPressed(0, 73) or IsEntityDead(ped) or now < health - 1 or not propCache[id] then
                getUp(IsEntityDead(ped))
                break
            end
            health = math.max(health, now)
            if not IsEntityPlayingAnim(ped, REST_DICT, REST_ANIM, 3) then TaskPlayAnim(ped, REST_DICT, REST_ANIM, 2.0, 2.0, -1, 1, 0, false, false, false) end
        end
    end)
end)

-- The power range of generators the player chose to see: a ring on the ground
-- (green while running, grey while off) and a label over the generator.
Citizen.CreateThread(function()
    while true do
        if not cfg or not next(showRange) then Wait(500) else
            for id in pairs(showRange) do
                local d = propCache[id]
                local piece = d and cfg.pieces[d.piece]
                if not piece or not piece.generator then
                    showRange[id] = nil
                else
                    local r = piece.generator.powerRadius
                    local on = d.is_open and ((d.fuel or 0) > 0 or piece.generator.unlimited)
                    local c = on and { 90, 220, 110 } or { 170, 170, 160 }
                    DrawMarker(1, d.coords.x, d.coords.y, d.coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r * 2.0, r * 2.0, 2.2,
                        c[1], c[2], c[3], 45, false, false, 2, false, nil, nil, false)
                    DrawMarker(25, d.coords.x, d.coords.y, d.coords.z + 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r * 2.0, r * 2.0, 1.0,
                        c[1], c[2], c[3], 160, false, false, 2, false, nil, nil, false)
                    DrawText3D(d.coords + vector3(0.0, 0.0, 1.6), ('Power range %d m (%s)'):format(math.floor(r), on and 'on' or 'off'))
                end
            end
            Wait(0)
        end
    end
end)

RegisterNetEvent('wasteland:basebuilding:client:propMoved', function(id, patch)
    local data = propCache[id]
    if not data or type(patch) ~= 'table' then return end
    data.coords, data.heading, data.cupboard_id, data.is_open = vec(patch.coords), patch.heading, patch.cupboard_id, false
    DespawnProp(id)
    SpawnProp(id)
end)
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

StartPlacement = function(pieceKey, moveId, moveCupboard)
    local piece = cfg.pieces[pieceKey]
    if not piece or isPlacing then return end
    -- Moving a placed piece (or the tool cupboard): hide it while its see-through copy is moved.
    local movingObj = nil
    if moveId then
        movingId = not moveCupboard and moveId or nil
        local list = moveCupboard and spawnedCupboards or spawnedProps
        movingObj = list[moveId] and list[moveId].obj or nil
        if movingObj and DoesEntityExist(movingObj) then SetEntityVisible(movingObj, false, false); SetEntityCollision(movingObj, false, false) end
    end
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
    -- Arrow keys slide the piece (on top of where it snapped): Ctrl for fine steps.
    local nudge, arrowHeldSince = vector3(0.0, 0.0, 0.0), {}
    local fill = vector3(0.0, 0.0, 0.0) -- sliver closed automatically at the snapped spot

    local function cleanup()
        if DoesEntityExist(ghost) then DeleteEntity(ghost) end
        isPlacing = false
        if movingObj and DoesEntityExist(movingObj) then SetEntityVisible(movingObj, true, false); SetEntityCollision(movingObj, true, true) end
        movingId = nil
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
            local dt = GetFrameTime()
            local shift, ctrl = IsDisabledControlPressed(0, 21), IsDisabledControlPressed(0, 36)
            if shift then
                -- Shift + Left/Right: turn freely; Shift + Up/Down: raise / lower slowly
                local fine = P.fineRotateSpeed * dt
                if IsDisabledControlPressed(0, 174) then heading = (heading - fine) % 360.0 end
                if IsDisabledControlPressed(0, 175) then heading = (heading + fine) % 360.0 end
                local lift = (P.fineHeightSpeed or 0.15) * dt
                if IsDisabledControlPressed(0, 172) then heightOffset = heightOffset + lift end
                if IsDisabledControlPressed(0, 173) then heightOffset = heightOffset - lift end
            else
                -- Arrows: slide left / right / away / toward you (as the camera
                -- looks). Ctrl: fine - a tap moves 1 cm, holding creeps slowly.
                local camH = math.rad(GetGameplayCamRot(2).z)
                local fwd = vector3(-math.sin(camH), math.cos(camH), 0.0)
                local right = vector3(math.cos(camH), math.sin(camH), 0.0)
                for control, dir in pairs({ [172] = fwd, [173] = -fwd, [174] = -right, [175] = right }) do
                    if IsDisabledControlPressed(0, control) then
                        local t0 = arrowHeldSince[control]
                        if not t0 then
                            arrowHeldSince[control] = GetGameTimer()
                            if ctrl then nudge = nudge + dir * 0.01 end
                        elseif not ctrl then
                            nudge = nudge + dir * 1.5 * dt
                        elseif GetGameTimer() - t0 > 300 then
                            nudge = nudge + dir * 0.08 * dt
                        end
                        if not ctrl and not t0 then nudge = nudge + dir * 1.5 * dt end
                    else
                        arrowHeldSince[control] = nil
                    end
                end
            end

            local didSnap = false
            if snapEnabled and candidates then
                local raw = vector3(target.x, target.y, target.z)
                local best, bestDist, bestPrio = nil, nil, nil
                -- Ceilings: aim anywhere under (or at) the spot it would cover; the
                -- distance is measured flat, since you look at walls or the floor.
                local flat = CEILING_LIKE[pieceKey] or (cfg.pieces[pieceKey] and cfg.pieces[pieceKey].family == 'ceiling')
                local reach = P.snapDistance
                if flat then
                    local d = GetModelDims(GetHashKey(cfg.pieces[pieceKey].model))
                    reach = math.max(P.snapDistance, math.min(d.size.x, d.size.y) / 2.0 + 0.5)
                end
                for _, cand in ipairs(candidates) do
                    local dist = flat and (#(raw.xy - cand.coords.xy) + 0.1 * math.abs(raw.z - cand.coords.z)) or #(raw - cand.coords)
                    if dist <= reach then
                        local prio = cand.priority or 2
                        if not bestPrio or prio < bestPrio or (prio == bestPrio and dist < bestDist) then best, bestDist, bestPrio = cand, dist, prio end
                    end
                end
                if best then
                    local key = ('%.2f,%.2f,%.2f'):format(best.coords.x, best.coords.y, best.coords.z)
                    if key ~= lastKey then
                        heading, heightOffset, lastKey, nudge = best.heading, 0.0, key, vector3(0.0, 0.0, 0.0)
                        fill = GapFill(pieceKey, best.coords, best.heading, ghost)
                    end
                    placeCoords = vector3(best.coords.x + fill.x + nudge.x, best.coords.y + fill.y + nudge.y, best.coords.z + fill.z + heightOffset)
                    didSnap = true
                end
            end
            if not didSnap then
                if lastKey then nudge = vector3(0.0, 0.0, 0.0) end
                lastKey = nil
                placeCoords = vector3(target.x + nudge.x, target.y + nudge.y, target.z + heightOffset)
            end
            SetEntityCoordsNoOffset(ghost, placeCoords.x, placeCoords.y, placeCoords.z, false, false, false)
            SetEntityHeading(ghost, heading)
            if piece.scale then scaleEntity(ghost, piece.scale) end
            local rampHelp = pieceKey == 'ramp' and ('~n~R: %s   Q: %s'):format(rampOpts.rampFlip and 'facing down' or 'facing up',
                rampOpts.rampLevel == 'top' and 'on top of the foundation' or 'up onto the foundation') or ''
            help(('%s%s~n~~INPUT_CONTEXT~ place   ~INPUT_FRONTEND_RRIGHT~ cancel~n~Wheel: turn 45   Arrows: move   Ctrl+arrows: fine move~n~Shift+Left/Right: turn freely   Shift+Up/Down or Shift+wheel: height   Tab: snapping %s~n~Ctrl+wheel: close gaps (%.2f)%s'):format(
                piece.label, didSnap and ' (snapped)' or '', snapEnabled and 'on' or 'off', overlap, rampHelp))

            if IsDisabledControlJustReleased(0, KEY_E) then
                if moveId and moveCupboard then
                    TriggerServerEvent('wasteland:basebuilding:server:moveCupboard', moveId, placeCoords.x, placeCoords.y, placeCoords.z, heading)
                elseif moveId then
                    TriggerServerEvent('wasteland:basebuilding:server:move', moveId, placeCoords.x, placeCoords.y, placeCoords.z, heading)
                else
                    TriggerServerEvent('wasteland:basebuilding:server:place', pieceKey, placeCoords.x, placeCoords.y, placeCoords.z, heading)
                end
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
        elseif piece and piece.wireDamage and #(d.coords - at) <= (radius or 10.0) + 3.0
            and not (piece.needsPower and not (PoweredAt and PoweredAt(d.coords))) then
            -- barbed wire on a wall: only its strip along the top hurts
            out[#out + 1] = { id = id, x = d.coords.x, y = d.coords.y, z = d.coords.z, damage = piece.wireDamage, slow = 1.0,
                shock = piece.shock or nil,
                wire = { heading = d.heading or 0.0, half = 2.05, reach = piece.wireReach or 0.75,
                    from = piece.wireFrom or 3.5, to = piece.wireTo or 4.7 } }
        end
    end
    return out
end)

-------------------------------------------------------------------------------
-- Shelter: under a roof you built (a ceiling, a ladder hatch, a foundation of
-- the floor above, stairs) no rain falls on you, you dry off, and the cold of
-- the rain does not reach you (wasteland_survival asks IsSheltered).
-------------------------------------------------------------------------------

local sheltered = false
local rainy = false   -- the server's weather was rainy when we went under the roof
local ROOF = { ceiling = true, hatch = true, foundation = true, stairs = true }
local RAINY = {}
for _, w in ipairs({ 'RAIN', 'THUNDER', 'CLEARING' }) do RAINY[GetHashKey(w)] = true end

-- Is the server's weather rainy? (the weather types, not the override we set)
local function rainyWeather()
    local a, b, mix = GetWeatherTypeTransition()
    return RAINY[a] == true or (RAINY[b] == true and (mix or 0) > 0.1)
end

-- Is a roof piece over the ped? No ray needed: inside the piece's footprint
-- (turned with it) and above the ped's head, within a storey or two.
local function roofAbove(ped)
    local pos = GetEntityCoords(ped)
    local feet = pos.z - 1.0
    for _, data in pairs(propCache) do
        local piece = cfg.pieces[data.piece]
        local family = piece and (piece.family or data.piece)
        if piece and (ROOF[family] or ROOF[data.piece]) and #(pos.xy - data.coords.xy) < 6.0 then
            local dz = data.coords.z - feet
            if dz > 1.6 and dz < 9.0 then
                local hash = GetHashKey(data.model)
                if not modelDimsCache[hash] then CacheModelDims(hash) end
                local dims = GetModelDims(hash)
                local d = pos - data.coords
                local h = math.rad(data.heading or 0.0)
                local lx = d.x * math.cos(h) + d.y * math.sin(h)
                local ly = -d.x * math.sin(h) + d.y * math.cos(h)
                if lx >= dims.min.x - 0.1 and lx <= dims.max.x + 0.1 and ly >= dims.min.y - 0.1 and ly <= dims.max.y + 0.1 then
                    return true
                end
            end
        end
    end
    return false
end

Citizen.CreateThread(function()
    while true do
        Wait(500)
        if cfg then
            local ped = PlayerPedId()
            local now = not IsPedInAnyVehicle(ped, false) and roofAbove(ped)
            if now and not sheltered then
                -- note the weather as we go in (the override hides it while inside)
                rainy = rainyWeather()
            end
            if now ~= sheltered then
                sheltered = now
                if not sheltered then
                    -- back to the server's weather (the world module re-applies it)
                    SetRainLevel(-1.0)
                    ClearOverrideWeather()
                    if GetResourceState('wasteland_world') == 'started' then
                        pcall(function() exports.wasteland_world:ReapplyWeather() end)
                    end
                end
            end
            if sheltered and GetResourceState('wasteland_world') == 'started' then
                -- the server's weather now (it may start or stop raining while we are inside)
                local ok, name = pcall(function() return exports.wasteland_world:GetWeather() end)
                if ok and type(name) == 'string' then
                    local was = rainy
                    rainy = RAINY[GetHashKey(name)] == true
                    if was and not rainy then ClearOverrideWeather(); pcall(function() exports.wasteland_world:ReapplyWeather() end) end
                end
            end
            if sheltered then
                -- only for this player while under the roof: an overcast sky
                -- instead of rain (no drops, no ripples, no wet floor). Set every
                -- tick, so a weather change from the server cannot bring rain in.
                if rainy then
                    SetOverrideWeather('OVERCAST')
                    SetRainLevel(0.0)
                end
                ClearPedWetness(ped)
                SetPedWetnessHeight(ped, 0.0)
            end
        end
    end
end)

--- IsSheltered() -> boolean: the player stands under a roof built with base building
exports('IsSheltered', function() return sheltered end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and sheltered then SetRainLevel(-1.0); ClearOverrideWeather() end
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
