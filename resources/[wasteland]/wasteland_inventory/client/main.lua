-- wasteland_inventory :: client/main.lua
-- Inventory screen (key TAB by default), hotbar keys 1-8, items on the
-- ground (props + "press E"), and worn clothing applied to the ped.
-- The server decides every change; this script shows its snapshots and
-- forwards requests.

local SCREEN = 'inventory'
local defs = nil          -- definitions payload from the server
local snapshot = nil      -- last sync payload
local drops = {}          -- { { id, x, y, z } }
local dropProps = {}      -- id -> local object handle
local lastEquipKey = nil  -- detects changes to worn items
local syncCount = 0       -- counts snapshots (waiting for the vicinity)

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

-- The worn backpack on the body (component 5). /backpack hides or shows it;
-- the choice is kept on this computer.
local bagShown = true
do
    local ok, v = pcall(GetResourceKvpString, 'backpackShown')
    if ok and v == 'no' then bagShown = false end
end

local function applyBag(ped, model, worn)
    local bag = worn.back
    local look = bagShown and bag and ((defs.bagLooks or {})[bag.name] or {})[model] or nil
    if look then SetPedComponentVariation(ped, 5, look[1], look[2], 0)
    else SetPedComponentVariation(ped, 5, 0, 0, 0) end
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
        -- An item without a look of its own for this body (given, looted,
        -- or made for the other body) shows the plain look.
        if item and not (meta and meta.model == model) then meta = (defs.plain or {})[model] end
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
    applyBag(ped, model, worn)
end

-- What is worn and how it looks: when this changes, the clothes are applied
-- again (a new item, or a new look for the same item, e.g. from a tailor).
local function equipKey()
    local parts = {}
    for slot, s in pairs(wornBySlot()) do parts[#parts + 1] = slot .. '=' .. s.uid .. ':' .. json.encode(s.metadata or {}) end
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
    syncCount = syncCount + 1
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

-- Health, wounds and the rest from wasteland_survival (nil if not running).
local function vitals()
    if GetResourceState('wasteland_survival') ~= 'started' then return nil end
    local ok, v = pcall(function() return exports.wasteland_survival:GetVitals() end)
    return ok and v or nil
end

local function openScreen(pickRepair)
    if not uiRunning() or not defs or not snapshot then return end
    if exports.wasteland_ui:IsOpen(SCREEN) then return end
    exports.wasteland_ui:Open(SCREEN, { script = 'html/inventory.js',
        data = { defs = defs, snapshot = snapshot, vitals = vitals(), pickRepair = pickRepair } })
    -- Keep the health panel current while the screen is open.
    Citizen.CreateThread(function()
        while isOpen() do
            Citizen.Wait(1000)
            if isOpen() then exports.wasteland_ui:Update(SCREEN, { vitals = vitals() }) end
        end
    end)
end

local function closeScreen()
    if not isOpen() then return end
    exports.wasteland_ui:Close(SCREEN)
    TriggerServerEvent('wasteland:inventory:server:closeAll')
end

-- The server opened something for us (admin view, stash): show the screen.
RegisterNetEvent('wasteland:inventory:client:open', function()
    Citizen.CreateThread(function()
        Citizen.Wait(100) -- the sync with the new inventory arrives first
        openScreen()
    end)
end)

local function canOpen()
    local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
    if not ok or not ready then return false end
    if GetResourceState('wasteland_appearance') == 'started' and exports.wasteland_appearance:IsEditing() then return false end
    return not IsPauseMenuActive()
end

-- Default key TAB. (The command name changed from wl_inventory so players
-- who already had the old I binding get the new default.)
-- Opening shows the vicinity: whatever lies on the ground within reach.
local function openWithVicinity()
    local before = syncCount
    TriggerServerEvent('wasteland:inventory:server:openNearby')
    Citizen.CreateThread(function()
        local waitUntil = GetGameTimer() + 600
        while syncCount == before and GetGameTimer() < waitUntil do Citizen.Wait(20) end
        if canOpen() then openScreen() end
    end)
end

RegisterCommand('wl_inventory_tab', function()
    if isOpen() then closeScreen() elseif canOpen() then openWithVicinity() end
end, false)
RegisterKeyMapping('wl_inventory_tab', 'Inventory: open / close', 'keyboard', 'TAB')

-- TAB is also GTA's weapon wheel; keep the wheel from opening. Disabling a
-- control only lasts one frame, so this has to run every frame.
Citizen.CreateThread(function()
    while true do
        DisableControlAction(0, 37, true) -- INPUT_SELECT_WEAPON (weapon wheel)
        Citizen.Wait(0)
    end
end)

for i = 1, 8 do
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
    sort = function(p) return 'sort', p.inv end,
    takeAll = function(p) return 'takeAll', p.inv end,
    equip = function(p) return 'equip', p.uid, p.from, p.slot end,
    unequip = function(p) return 'unequip', p.slot, p.to, p.x, p.y, p.rotated == true end,
    drop = function(p) return 'drop', p.uid, p.from, p.count end,
    use = function(p) return 'use', p.uid, p.from, type(p.target) == 'string' and p.target or nil end,
    setHotbar = function(p) return 'setHotbar', p.index, p.uid end,
}

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN then return end
    if action == 'close' then closeScreen(); return end
    if action == 'crafting' then
        -- The Crafting button: hand over to wasteland_crafting (if running).
        closeScreen()
        if GetResourceState('wasteland_crafting') == 'started' then TriggerEvent('wasteland:crafting:client:open') end
        return
    end
    if action == 'detach' and type(payload) == 'table' and type(payload.uid) == 'string' then
        -- weapon attachments belong to wasteland_weapons
        TriggerServerEvent('wasteland:weapons:server:detach', payload.uid)
        return
    end
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

-- With wasteland_target running, bags are searched through the target
-- (hold Left Alt, look at the bag); otherwise with the "Press E" prompt.
local dropTargets = {}   -- drop id -> target registration id
local function targetRunning() return GetResourceState('wasteland_target') == 'started' end

local function syncDropTargets()
    if not targetRunning() then dropTargets = {}; return end
    local wanted = {}
    for _, d in ipairs(drops) do wanted[d.id] = d end
    for id, tid in pairs(dropTargets) do
        if not wanted[id] then
            exports.wasteland_target:Remove(tid)
            dropTargets[id] = nil
        end
    end
    for id, d in pairs(wanted) do
        if not dropTargets[id] then
            -- Bag props have no collision, so the target is a small sphere
            -- where the bag lies.
            dropTargets[id] = exports.wasteland_target:AddSphere(vector3(d.x, d.y, d.z), 0.9, {
                { label = d.label and ('Search ' .. d.label) or 'Search', icon = '⌕', distance = 2.5,
                    onSelect = function() if canOpen() and not isOpen() then searchDrop(d) end end },
            })
        end
    end
end

AddEventHandler('onClientResourceStart', function(res)
    if res == 'wasteland_target' then dropTargets = {}; syncDropTargets() end
end)
AddEventHandler('onClientResourceStop', function(res)
    if res == 'wasteland_target' then dropTargets = {} end
end)

Citizen.CreateThread(function()
    local sinceProps = 0
    local lastDrops = nil
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        sinceProps = sinceProps + 1
        if sinceProps >= 4 then
            sinceProps = 0
            updateProps(pos)
        end
        if drops ~= lastDrops then
            lastDrops = drops
            syncDropTargets()
        end
        local near = (#drops > 0 and not targetRunning()) and nearestDrop(pos) or nil
        if near and not isOpen() and canOpen() then
            -- Only while standing at a drop: draw the prompt every frame.
            local deadline = GetGameTimer() + 500
            local searched = false
            while GetGameTimer() < deadline do
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('Press ~INPUT_PICKUP~ to search')
                EndTextCommandDisplayHelp(0, false, false, -1)
                if IsControlJustReleased(0, 38) then
                    searchDrop(near)
                    searched = true
                    break
                end
                Citizen.Wait(0)
            end
            -- Always yield here: breaking out and looping straight back would
            -- see the same key press again in the same frame, search again
            -- forever and freeze the game (and flood the server).
            Citizen.Wait(searched and 1000 or 0)
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

-------------------------------------------------------------------------------
-- Hotbar on screen (/hotbar shows or hides it; kept on this computer)
-------------------------------------------------------------------------------

local HOTBAR = 'hotbarHud'
local hotbarShown = true
do
    local ok, v = pcall(GetResourceKvpString, 'hotbarShown')
    if ok and v == 'no' then hotbarShown = false end
end

local function hotbarData()
    if not snapshot or not defs or type(snapshot.hotbar) ~= 'table' then return nil end
    local byUid = {}
    for _, inv in ipairs(snapshot.inventories or {}) do
        for _, s in ipairs(inv.items or {}) do byUid[s.uid] = s end
    end
    local slots = {}
    for i = 1, 8 do
        local uid = snapshot.hotbar[i]
        local s = uid and byUid[uid]
        local d = s and defs.items and defs.items[s.name]
        if d then
            local cond = nil
            if (d.durability or 0) > 0 then
                local cur = s.metadata and tonumber(s.metadata.durability) or d.durability
                cond = math.max(0, math.min(1, cur / d.durability))
            end
            slots[i] = { key = i, label = d.label, image = d.image, count = s.count, cond = cond, color = d.color,
                cash = s.name == defs.cashItem }
        else
            slots[i] = { key = i }
        end
    end
    return { slots = slots }
end

local function hotbarVisible()
    if not hotbarShown or not uiRunning() or isOpen() or not snapshot then return false end
    local ped = PlayerPedId()
    return not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) and not IsPauseMenuActive()
end

Citizen.CreateThread(function()
    local lastJson = nil
    while true do
        Citizen.Wait(250)
        if hotbarVisible() then
            local data = hotbarData()
            if data then
                local j = json.encode(data)
                if not exports.wasteland_ui:IsOpen(HOTBAR) then
                    exports.wasteland_ui:Open(HOTBAR, { script = 'html/hotbar.js', data = data, focus = false, cursor = false })
                    lastJson = j
                elseif j ~= lastJson then
                    exports.wasteland_ui:Update(HOTBAR, data)
                    lastJson = j
                end
            end
        elseif uiRunning() and exports.wasteland_ui:IsOpen(HOTBAR) then
            exports.wasteland_ui:Close(HOTBAR)
            lastJson = nil
        end
    end
end)

RegisterCommand('hotbar', function()
    hotbarShown = not hotbarShown
    SetResourceKvp('hotbarShown', hotbarShown and 'yes' or 'no')
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(hotbarShown and 'Hotbar shown. Type /hotbar to hide it.' or 'Hotbar hidden. Type /hotbar to show it.')
    EndTextCommandThefeedPostTicker(false, false)
end, false)

RegisterCommand('backpack', function()
    bagShown = not bagShown
    SetResourceKvp('backpackShown', bagShown and 'yes' or 'no')
    applyClothing()
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(bagShown and 'Backpack shown. Type /backpack to hide it.' or 'Backpack hidden. Type /backpack to show it.')
    EndTextCommandThefeedPostTicker(false, false)
end, false)
TriggerEvent('chat:addSuggestion', '/backpack', 'Show or hide your worn backpack on your character')

--- ApplyClothing() - put the worn items' looks on the ped again (after a preview).
exports('ApplyClothing', function() applyClothing() end)

--- GetClothingInfo() -> { model, parts = { [slot] = { { key, component | prop } } },
---   worn = { [slot] = { uid, name, look = { [key] = { drawable, texture } } } } } | nil
--- (the tailor: what can be restyled and how it looks now)
exports('GetClothingInfo', function()
    if not defs or not snapshot then return nil end
    local ped = PlayerPedId()
    local model = MODELS[GetEntityModel(ped)]
    if not model then return nil end
    local naked = (defs.naked or {})[model] or {}
    local out = {}
    for slot, item in pairs(wornBySlot()) do
        local parts = (defs.clothingParts or {})[slot]
        if parts then
            local meta = item.metadata
            if not (meta and meta.model == model) then meta = (defs.plain or {})[model] or {} end
            local look = {}
            for _, part in ipairs(parts) do
                local v = meta[part.key] or (part.component and naked[part.key]) or nil
                look[part.key] = v and { v[1], v[2] } or nil
            end
            out[slot] = { uid = item.uid, name = item.name, look = look }
        end
    end
    return { model = model, parts = defs.clothingParts, worn = out }
end)

-- A repair item used from the hotbar: open the inventory with the list of
-- what it can repair.
RegisterNetEvent('wasteland:inventory:client:pickRepair', function(uid)
    if type(uid) ~= 'string' then return end
    if isOpen() then exports.wasteland_ui:Update(SCREEN, { pickRepair = uid })
    elseif canOpen() then openScreen(uid) end
end)

