-- wasteland_inventory :: client/main.lua
-- Inventory screen (key I by default), hotbar keys 1-5, items on the
-- ground (props + "press E"), and worn clothing applied to the ped.
-- The server decides every change; this script shows its snapshots and
-- forwards requests.

local SCREEN = 'inventory'
local defs = nil          -- definitions payload from the server
local snapshot = nil      -- last sync payload
local drops = {}          -- { { id, x, y, z } }
local dropProps = {}      -- id -> local object handle
local lastEquipKey = nil  -- detects changes to worn items

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function isOpen() return uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) end

local function notify(message, isError)
    if isOpen() then
        exports.wasteland_ui:Update(SCREEN, { [isError and 'error' or 'notice'] = message })
    elseif GetResourceState('chat') == 'started' then
        TriggerEvent('chat:addMessage', { args = { 'Inventory', message } })
    else
        print('[inventory] ' .. message)
    end
end

-------------------------------------------------------------------------------
-- Worn clothing
-------------------------------------------------------------------------------

local MODELS = {
    [GetHashKey('mp_m_freemode_01')] = 'mp_m_freemode_01',
    [GetHashKey('mp_f_freemode_01')] = 'mp_f_freemode_01',
}

local function wornBySlot()
    local out = {}
    if not snapshot then return out end
    for _, inv in ipairs(snapshot.inventories) do
        if inv.id == snapshot.equip then
            for _, s in ipairs(inv.items) do if s.slot then out[s.slot] = s end end
        end
    end
    return out
end

local function applyClothing()
    if not defs or not snapshot then return end
    if GetResourceState('wasteland_appearance') == 'started' and exports.wasteland_appearance:IsEditing() then return end
    local ped = PlayerPedId()
    local model = MODELS[GetEntityModel(ped)]
    if not model then return end -- not a freemode ped: clothing cannot apply
    local naked = (defs.naked or {})[model] or {}
    local worn = wornBySlot()
    for slot, parts in pairs(defs.clothingParts or {}) do
        local item = worn[slot]
        local meta = item and item.metadata or nil
        if meta and meta.model ~= model then meta = nil end -- made for the other body
        for _, part in ipairs(parts) do
            local value = meta and meta[part.key] or nil
            if part.component then
                value = value or naked[part.key]
                if value then SetPedComponentVariation(ped, part.component, value[1], value[2], 0) end
            elseif value then
                SetPedPropIndex(ped, part.prop, value[1], value[2], true)
            else
                ClearPedProp(ped, part.prop)
            end
        end
    end
end

local function equipKey()
    local parts = {}
    for slot, s in pairs(wornBySlot()) do parts[#parts + 1] = slot .. '=' .. s.uid end
    table.sort(parts)
    return table.concat(parts, ',')
end

-- The appearance module (re)applied the body (load, respawn): clothes on top.
AddEventHandler('wasteland:appearance:client:applied', function() applyClothing() end)

-------------------------------------------------------------------------------
-- Server events
-------------------------------------------------------------------------------

RegisterNetEvent('wasteland:inventory:client:definitions', function(payload)
    if type(payload) ~= 'table' then return end
    defs = payload
    if isOpen() then exports.wasteland_ui:Update(SCREEN, { defs = defs }) end
end)

RegisterNetEvent('wasteland:inventory:client:sync', function(payload)
    if type(payload) ~= 'table' then return end
    snapshot = payload
    if isOpen() then exports.wasteland_ui:Update(SCREEN, { snapshot = snapshot }) end
    local key = equipKey()
    if key ~= lastEquipKey then
        lastEquipKey = key
        applyClothing()
    end
end)

RegisterNetEvent('wasteland:inventory:client:error', function(message) notify(tostring(message), true) end)
RegisterNetEvent('wasteland:inventory:client:notice', function(message) notify(tostring(message), false) end)

RegisterNetEvent('wasteland:inventory:client:drops', function(list)
    if type(list) == 'table' then drops = list end
end)

-------------------------------------------------------------------------------
-- Screen
-------------------------------------------------------------------------------

local function openScreen()
    if not uiRunning() or not defs or not snapshot then return end
    if exports.wasteland_ui:IsOpen(SCREEN) then return end
    exports.wasteland_ui:Open(SCREEN, { script = 'html/inventory.js', data = { defs = defs, snapshot = snapshot } })
end

local function closeScreen()
    if not isOpen() then return end
    exports.wasteland_ui:Close(SCREEN)
    for _, id in ipairs((snapshot and snapshot.secondary) or {}) do
        TriggerServerEvent('wasteland:inventory:server:close', id)
    end
end

local function canOpen()
    local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
    if not ok or not ready then return false end
    if GetResourceState('wasteland_appearance') == 'started' and exports.wasteland_appearance:IsEditing() then return false end
    return not IsPauseMenuActive()
end

RegisterCommand('wl_inventory', function()
    if isOpen() then closeScreen() elseif canOpen() then openScreen() end
end, false)
RegisterKeyMapping('wl_inventory', 'Inventory: open / close', 'keyboard', 'I')

for i = 1, 5 do
    RegisterCommand('wl_hotbar_' .. i, function()
        if canOpen() and not isOpen() then TriggerServerEvent('wasteland:inventory:server:useHotbar', i) end
    end, false)
    RegisterKeyMapping('wl_hotbar_' .. i, 'Inventory: use hotbar slot ' .. i, 'keyboard', tostring(i))
end

-- Screen actions -> guarded server events (the server validates everything).
local OPS = {
    move = function(p) return 'move', p.uid, p.from, p.to, p.x, p.y, p.rotated == true end,
    merge = function(p) return 'merge', p.uid, p.from, p.target, p.to, p.count end,
    split = function(p) return 'split', p.uid, p.from, p.count end,
    equip = function(p) return 'equip', p.uid, p.from, p.slot end,
    unequip = function(p) return 'unequip', p.slot, p.to, p.x, p.y, p.rotated == true end,
    drop = function(p) return 'drop', p.uid, p.from, p.count end,
    use = function(p) return 'use', p.uid, p.from end,
    setHotbar = function(p) return 'setHotbar', p.index, p.uid end,
}

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN then return end
    if action == 'close' then closeScreen(); return end
    local build = OPS[action]
    if not build or type(payload) ~= 'table' then return end
    local args = table.pack(build(payload))
    TriggerServerEvent('wasteland:inventory:server:' .. args[1], table.unpack(args, 2, args.n))
end)

-------------------------------------------------------------------------------
-- Items on the ground
-------------------------------------------------------------------------------

local DROP_MODEL = GetHashKey('prop_cs_heist_bag_02')
local RENDER_DISTANCE = 60.0
local INTERACT_DISTANCE = 2.0

local function updateProps(pos)
    local wanted = {}
    for _, d in ipairs(drops) do
        if #(pos - vector3(d.x, d.y, d.z)) < RENDER_DISTANCE then wanted[d.id] = d end
    end
    for id, obj in pairs(dropProps) do
        if not wanted[id] then
            DeleteObject(obj)
            dropProps[id] = nil
        end
    end
    for id, d in pairs(wanted) do
        if not dropProps[id] then
            RequestModel(DROP_MODEL)
            local deadline = GetGameTimer() + 3000
            while not HasModelLoaded(DROP_MODEL) and GetGameTimer() < deadline do Citizen.Wait(0) end
            if HasModelLoaded(DROP_MODEL) then
                local obj = CreateObjectNoOffset(DROP_MODEL, d.x, d.y, d.z, false, false, false)
                PlaceObjectOnGroundProperly(obj)
                FreezeEntityPosition(obj, true)
                SetEntityCollision(obj, false, false)
                dropProps[id] = obj
            end
        end
    end
end

local function nearestDrop(pos)
    local best, bestDist = nil, INTERACT_DISTANCE
    for _, d in ipairs(drops) do
        local dist = #(pos - vector3(d.x, d.y, d.z))
        if dist < bestDist then best, bestDist = d, dist end
    end
    return best
end

local function searchDrop(drop)
    TriggerServerEvent('wasteland:inventory:server:openDrop', drop.id)
    Citizen.CreateThread(function()
        local waitUntil = GetGameTimer() + 2000
        while GetGameTimer() < waitUntil do
            if snapshot and snapshot.secondary and #snapshot.secondary > 0 then break end
            Citizen.Wait(50)
        end
        openScreen()
    end)
end

Citizen.CreateThread(function()
    local sinceProps = 0
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        sinceProps = sinceProps + 1
        if sinceProps >= 4 then
            sinceProps = 0
            updateProps(pos)
        end
        local near = (#drops > 0) and nearestDrop(pos) or nil
        if near and not isOpen() and canOpen() then
            -- Only while standing at a drop: draw the prompt every frame.
            local deadline = GetGameTimer() + 500
            while GetGameTimer() < deadline do
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('Press ~INPUT_PICKUP~ to search')
                EndTextCommandDisplayHelp(0, false, false, -1)
                if IsControlJustReleased(0, 38) then
                    searchDrop(near)
                    break
                end
                Citizen.Wait(0)
            end
        else
            Citizen.Wait(500)
        end
    end
end)

-------------------------------------------------------------------------------
-- Start-up
-------------------------------------------------------------------------------

-- Ask for definitions, drops and inventory once the character is placed
-- (also when this resource restarts while playing).
Citizen.CreateThread(function()
    while true do
        local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
        if ok and ready then break end
        Citizen.Wait(500)
    end
    TriggerServerEvent('wasteland:inventory:server:request')
end)

-- Without the appearance module nobody re-applies the body after a
-- respawn; put the clothes back ourselves.
AddEventHandler('playerSpawned', function()
    if GetResourceState('wasteland_appearance') ~= 'started' then applyClothing() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, obj in pairs(dropProps) do DeleteObject(obj) end
end)
