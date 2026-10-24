-- wasteland_loot :: client/main.lua
-- Registers every container model (and dead zombies) with wasteland_target
-- ("Search ..."), plays the search (animation + progress bar; moving,
-- getting hurt or dying cancels it) and tells the server when it is done.
-- The server decides everything else.

local SCREEN = 'lootProgress'
local cfg = nil
local targetIds = {}
local active = nil   -- current search: { endsAt, start, health }
local ztEntity = {}  -- tree zone props: entity -> tree (the model option skips them)

local ANIMS = {
    bin = { dict = 'amb@prop_human_bum_bin@base', name = 'base', flag = 1 },
    search = { dict = 'mini@repair', name = 'fixing_a_ped', flag = 1 },
    kneel = { dict = 'amb@medic@standing@kneel@base', name = 'base', flag = 1 },
    chop = { dict = 'melee@large_wpn@streamed_core', name = 'ground_attack_on_spot', flag = 1 },
    hammer = { dict = 'amb@world_human_hammering@male@base', name = 'base', flag = 1 },
    -- Tree zones: swinging an axe (a hatchet in the right hand).
    axe = { dict = 'melee@hatchet@streamed_core', name = 'plyr_rear_takedown_b', flag = 1,
        prop = { model = 'w_me_hatchet', bone = 57005, pos = { 0.1, 0.0, 0.0 }, rot = { -80.0, 0.0, 0.0 } } },
}

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function targetRunning() return GetResourceState('wasteland_target') == 'started' end

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:loot:client:notice', function(message) notice(message) end)

-------------------------------------------------------------------------------
-- Targets
-------------------------------------------------------------------------------

local function isDeadZombie(entity)
    if not entity or entity == 0 or not IsPedDeadOrDying(entity, true) then return false end
    local ok, state = pcall(function() return Entity(entity).state end)
    return ok and state and state.wlZombie ~= nil
end

local function register()
    for _, id in ipairs(targetIds) do pcall(function() exports.wasteland_target:Remove(id) end) end
    targetIds = {}
    if not cfg or not targetRunning() then return end
    local function option(label)
        return { label = label, icon = '⌕', distance = 2.2,
            canInteract = function(entity) return active == nil and not ztEntity[entity] end,
            onSelect = function(data)
                if not data.entity then return end
                local p = GetEntityCoords(data.entity)
                TriggerServerEvent('wasteland:loot:server:start', GetEntityModel(data.entity), { x = p.x, y = p.y, z = p.z })
            end }
    end
    local names = cfg.names or {}
    for _, c in pairs(cfg.containers) do
        -- Props an admin named get their own option ("Search Old barrel").
        local plain = {}
        for _, m in ipairs(c.models or {}) do
            local n = type(m) == 'number' and names[tostring(m)]
            if n then
                targetIds[#targetIds + 1] = exports.wasteland_target:AddModel({ m }, { option((c.action or 'Search') .. ' ' .. n) })
            else
                plain[#plain + 1] = m
            end
        end
        if #plain > 0 then
            targetIds[#targetIds + 1] = exports.wasteland_target:AddModel(plain, { option((c.action or 'Search') .. ' ' .. c.label:lower()) })
        end
    end
    if cfg.containers.body then
        targetIds[#targetIds + 1] = exports.wasteland_target:AddGlobal('ped', {
            { label = 'Search body', icon = '⌕', distance = 2.2,
                canInteract = function(entity) return active == nil and isDeadZombie(entity) end,
                onSelect = function(data)
                    if data.entity and NetworkGetEntityIsNetworked(data.entity) then
                        TriggerServerEvent('wasteland:loot:server:body', NetworkGetNetworkIdFromEntity(data.entity))
                    end
                end },
        })
    end
end

RegisterNetEvent('wasteland:loot:client:config', function(c)
    if type(c) ~= 'table' then return end
    cfg = c
    register()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'wasteland_target' then register() end
end)

-------------------------------------------------------------------------------
-- Tree zones: the server says where the choppable trees stand; this client
-- spawns them (local props) when the player is near, puts each on the
-- ground, gives it a "Chop tree" target and a marker, and swaps it for a
-- stump once it is chopped down.
-------------------------------------------------------------------------------

local zt = nil          -- { trees, zones, models, stump, marker, blips, distance }
local ztById = {}       -- id -> tree { id, x, y, z, m, down, entity, shown, target, gz }
local ztBlips = {}
local SPAWN_RANGE, MARKER_RANGE = 160.0, 35.0

local function loadModel(name)
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Citizen.Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function despawnTree(t)
    if t.target then pcall(function() exports.wasteland_target:Remove(t.target) end) end
    if t.entity and DoesEntityExist(t.entity) then DeleteEntity(t.entity) end
    if t.entity then ztEntity[t.entity] = nil end
    t.entity, t.target, t.shown = nil, nil, nil
end

-- Ground under a tree spot (nil while the ground is not loaded, or in water).
local function groundAt(t)
    RequestCollisionAtCoord(t.x, t.y, t.z)
    for _, from in ipairs({ t.z + 60.0, t.z + 250.0, 1000.0 }) do
        local ok, gz = GetGroundZFor_3dCoord(t.x, t.y, from, false)
        if ok and gz ~= 0.0 then
            local wet, wz = GetWaterHeight(t.x, t.y, gz)
            if wet and wz > gz then return false end
            return gz
        end
    end
    return nil
end

local function chopOption(t)
    return { { label = 'Chop tree', icon = '🪓', distance = zt.distance or 3.5,
        canInteract = function() return active == nil and not t.down end,
        onSelect = function() TriggerServerEvent('wasteland:loot:server:chopzone', t.id, t.gz) end } }
end

local function spawnTree(t)
    if t.gz == nil then t.gz = groundAt(t) end
    if t.gz == nil then return end      -- ground not loaded yet: next pass
    if t.gz == false then t.shown = 'none'; return end
    local name = t.down and zt.stump or zt.models[t.m] or zt.models[1]
    if not name or name == '' then t.shown = 'none'; return end
    local hash = loadModel(name)
    if not hash and not t.down then hash = loadModel('prop_tree_pine_01') end
    if not hash then t.shown = 'none'; return end
    local e = CreateObject(hash, t.x, t.y, t.gz - 0.3, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not e or e == 0 then return end
    SetEntityHeading(e, (t.x * 37.0 + t.y * 11.0) % 360.0)
    FreezeEntityPosition(e, true)
    SetEntityLodDist(e, 500)
    t.entity, t.shown = e, t.down and 'stump' or 'tree'
    ztEntity[e] = t
    if not t.down and targetRunning() then
        t.target = exports.wasteland_target:AddEntity(e, chopOption(t))
    end
end

local function clearBlips()
    for _, b in ipairs(ztBlips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    ztBlips = {}
end

local function makeBlips()
    clearBlips()
    if not (zt and zt.blips) then return end
    for _, z in ipairs(zt.zones) do
        local area = AddBlipForRadius(z.x, z.y, z.z, z.radius + 0.0)
        SetBlipColour(area, 25); SetBlipAlpha(area, 90)
        local b = AddBlipForCoord(z.x, z.y, z.z)
        SetBlipSprite(b, 285) -- tree / lumber
        SetBlipColour(b, 25); SetBlipScale(b, 0.8); SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName('Lumber: ' .. z.label); EndTextCommandSetBlipName(b)
        ztBlips[#ztBlips + 1] = area; ztBlips[#ztBlips + 1] = b
    end
end

local function clearTrees()
    for _, t in pairs(ztById) do despawnTree(t) end
    ztById, ztEntity = {}, {}
end

RegisterNetEvent('wasteland:loot:client:trees', function(data)
    if type(data) ~= 'table' then return end
    clearTrees()
    zt = data.enabled and data or nil
    if zt then for _, t in ipairs(zt.trees) do ztById[t.id] = t end end
    makeBlips()
end)

RegisterNetEvent('wasteland:loot:client:treestate', function(id, down)
    local t = ztById[id]
    if not t then return end
    t.down = down == true
    if t.entity and not t.down and t.shown == 'stump' or t.entity and t.down and t.shown == 'tree' then despawnTree(t) end
    if t.shown == 'none' then t.shown = nil end
end)

-- wasteland_target restarted: the trees need their option again.
AddEventHandler('onClientResourceStart', function(res)
    if res ~= 'wasteland_target' then return end
    for _, t in pairs(ztById) do
        if t.entity and t.shown == 'tree' and not t.down then t.target = exports.wasteland_target:AddEntity(t.entity, chopOption(t)) end
    end
end)

-- Spawning / despawning by distance.
Citizen.CreateThread(function()
    while true do
        if zt then
            local p = GetEntityCoords(PlayerPedId())
            for _, t in pairs(ztById) do
                local near = (p.x - t.x) ^ 2 + (p.y - t.y) ^ 2 < SPAWN_RANGE * SPAWN_RANGE
                if near and not t.shown then spawnTree(t); Citizen.Wait(0)
                elseif not near and t.shown then despawnTree(t) end
            end
        end
        Citizen.Wait(1000)
    end
end)

-- Markers: a green arrow over each choppable tree close by.
Citizen.CreateThread(function()
    while true do
        local close = false
        if zt and zt.marker then
            local p = GetEntityCoords(PlayerPedId())
            for _, t in pairs(ztById) do
                if t.shown == 'tree' and not t.down then
                    local d2 = (p.x - t.x) ^ 2 + (p.y - t.y) ^ 2
                    if d2 < MARKER_RANGE * MARKER_RANGE then
                        close = true
                        DrawMarker(2, t.x, t.y, t.gz + 3.2, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.6, 0.6, 0.6,
                            60, 220, 90, 200, true, true, 2, false, nil, nil, false)
                        DrawMarker(25, t.x, t.y, t.gz + 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.6, 2.6, 1.0,
                            60, 220, 90, 120, false, false, 2, false, nil, nil, false)
                    end
                end
            end
        end
        Citizen.Wait(close and 0 or 750)
    end
end)

-------------------------------------------------------------------------------
-- Searching
-------------------------------------------------------------------------------

local function stop(cancelled)
    if not active then return end
    local ped = PlayerPedId()
    if active.anim then StopAnimTask(ped, active.anim.dict, active.anim.name, 1.0) end
    if active.prop and DoesEntityExist(active.prop) then DeleteEntity(active.prop) end
    active = nil
    if uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) then exports.wasteland_ui:Close(SCREEN) end
    if cancelled then
        TriggerServerEvent('wasteland:loot:server:cancel')
        notice('Search cancelled.')
    end
end

RegisterNetEvent('wasteland:loot:client:cancel', function() stop(false) end)

RegisterNetEvent('wasteland:loot:client:search', function(s)
    if type(s) ~= 'table' or active then return end
    local ped = PlayerPedId()
    local seconds = tonumber(s.seconds) or 3
    active = { endsAt = GetGameTimer() + seconds * 1000, start = GetEntityCoords(ped), health = GetEntityHealth(ped), armour = GetPedArmour(ped) }
    if type(s.face) == 'table' and tonumber(s.face.x) then -- face the tree first
        TaskTurnPedToFaceCoord(ped, s.face.x + 0.0, s.face.y + 0.0, s.face.z + 0.0, 700)
        Citizen.Wait(700)
        if not active then return end
        active.start = GetEntityCoords(ped)
    end
    local anim = ANIMS[s.anim] or ANIMS.search
    RequestAnimDict(anim.dict)
    local deadline = GetGameTimer() + 1000
    while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < deadline do Citizen.Wait(0) end
    if active and HasAnimDictLoaded(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.name, 4.0, -4.0, -1, anim.flag, 0.0, false, false, false)
        active.anim = anim
        local pr = anim.prop
        local hash = pr and loadModel(pr.model)
        if hash and active then
            local c = GetEntityCoords(ped)
            local obj = CreateObject(hash, c.x, c.y, c.z, false, false, false)
            SetModelAsNoLongerNeeded(hash)
            AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, pr.bone), pr.pos[1], pr.pos[2], pr.pos[3],
                pr.rot[1], pr.rot[2], pr.rot[3], true, true, false, true, 1, true)
            active.prop = obj
        end
    end
    if uiRunning() then
        exports.wasteland_ui:Open(SCREEN, { script = 'html/progress.js', focus = false, cursor = false,
            data = { label = s.label or 'Searching', seconds = seconds } })
    end
    Citizen.CreateThread(function()
        while active do
            local p = PlayerPedId()
            if IsEntityDead(p) or #(GetEntityCoords(p) - active.start) > 1.2 or GetEntityHealth(p) < active.health
                or GetPedArmour(p) < active.armour
                or IsControlJustPressed(0, 73) then -- X cancels too
                stop(true)
                return
            end
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true) -- no shooting while searching
            if GetGameTimer() >= active.endsAt then
                stop(false)
                TriggerServerEvent('wasteland:loot:server:finish')
                return
            end
            Citizen.Wait(0)
        end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then stop(false); clearTrees(); clearBlips() end
end)

Citizen.CreateThread(function()
    while true do
        local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
        if ok and ready then break end
        Citizen.Wait(1000)
    end
    TriggerServerEvent('wasteland:loot:server:config')
end)
