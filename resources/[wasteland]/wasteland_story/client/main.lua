-- wasteland_story :: client/main.lua
-- The story NPCs (spawned near the player), story items and notes on the
-- current step (only this player sees them), the objective blip, and the
-- screens: dialogue, note, journal, tracker and banners. The server decides.

local state = nil          -- the server's view (see server view())
local npcs = {}            -- id -> { ped, target }
local prop = nil           -- { stepId, obj, target }
local blips = {}
local DIALOGUE, NOTE, JOURNAL, TRACKER, BANNER = 'storyDialogue', 'storyNote', 'storyJournal', 'storyTracker', 'storyBanner'
local SPAWN_RANGE = 150.0

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function targetRunning() return GetResourceState('wasteland_target') == 'started' end

local function notice(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(msg))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:story:client:notice', function(m) notice(m) end)

local function loadModel(name)
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local untilT = GetGameTimer() + 4000
    while not HasModelLoaded(hash) and GetGameTimer() < untilT do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function ground(c)
    RequestCollisionAtCoord(c.x, c.y, c.z)
    local ok, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 3.0, false)
    return ok and z or c.z
end

local function open(screen, script, data, focus)
    if not uiRunning() then return end
    exports.wasteland_ui:Open(screen, { script = script, data = data, focus = focus, cursor = focus })
end
local function close(screen)
    if uiRunning() and exports.wasteland_ui:IsOpen(screen) then exports.wasteland_ui:Close(screen) end
end

-------------------------------------------------------------------------------
-- NPCs
-------------------------------------------------------------------------------

local function removeNpc(id)
    local n = npcs[id]
    if not n then return end
    if n.target then pcall(function() exports.wasteland_target:Remove(n.target) end) end
    if DoesEntityExist(n.ped) then DeleteEntity(n.ped) end
    npcs[id] = nil
end

local function spawnNpc(n)
    local hash = loadModel(n.model)
    if not hash then return end
    local z = ground(n.coords)
    local ped = CreatePed(4, hash, n.coords.x, n.coords.y, z, n.coords.heading or 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return end
    SetEntityInvincible(ped, true); FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true); SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false); SetPedFleeAttributes(ped, 0, false)
    if n.scenario then TaskStartScenarioInPlace(ped, n.scenario, 0, true) end
    local e = { ped = ped }
    if targetRunning() then
        e.target = exports.wasteland_target:AddEntity(ped, { { label = 'Talk to ' .. n.name, icon = '💬', distance = 3.0,
            onSelect = function() TriggerServerEvent('wasteland:story:server:talk', n.id) end } })
    end
    npcs[n.id] = e
end

-------------------------------------------------------------------------------
-- The story item / note of the current step
-------------------------------------------------------------------------------

local function removeProp()
    if not prop then return end
    if prop.target then pcall(function() exports.wasteland_target:Remove(prop.target) end) end
    if prop.obj and DoesEntityExist(prop.obj) then DeleteEntity(prop.obj) end
    prop = nil
end

local function spawnProp(s)
    local hash = loadModel(s.prop or 'prop_ld_case_01') or loadModel('prop_ld_case_01')
    if not hash then return end
    local z = ground(s.coords)
    local obj = CreateObject(hash, s.coords.x, s.coords.y, z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    PlaceObjectOnGroundProperly(obj); FreezeEntityPosition(obj, true)
    prop = { stepId = s.id, obj = obj, z = z }
    if targetRunning() then
        local event = s.type == 'read' and 'wasteland:story:server:read' or 'wasteland:story:server:collect'
        prop.target = exports.wasteland_target:AddEntity(obj, { { label = s.label or 'Pick up', icon = s.type == 'read' and '📄' or '✋',
            distance = 2.5, onSelect = function() TriggerServerEvent(event, s.id) end } })
    end
end

-------------------------------------------------------------------------------
-- Blips, tracker
-------------------------------------------------------------------------------

local function clearBlips()
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end

local function makeBlips()
    clearBlips()
    local s = state and state.step
    if not s or not s.coords then return end
    if (s.type == 'kill' or s.type == 'defend' or s.type == 'visit') and s.radius and s.radius > 10 then
        local area = AddBlipForRadius(s.coords.x, s.coords.y, s.coords.z, s.radius + 0.0)
        SetBlipColour(area, 5); SetBlipAlpha(area, 80)
        blips[#blips + 1] = area
    end
    local b = AddBlipForCoord(s.coords.x, s.coords.y, s.coords.z)
    SetBlipSprite(b, 280); SetBlipColour(b, 5); SetBlipScale(b, 0.9)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName((state.title or 'Story') .. ': ' .. (s.title or ''))
    EndTextCommandSetBlipName(b)
    blips[#blips + 1] = b
end

local function trackerData()
    if not state then return nil end
    local s = state.step
    local line
    if s then
        if s.type == 'kill' then line = string.format('%d / %d killed%s', s.progress or 0, s.count or 0, s.where and (' at ' .. s.where) or '')
        elseif s.type == 'defend' then line = string.format('Held %d / %d s', s.progress or 0, s.seconds or 0) end
    end
    return { title = state.title, chapter = s and string.format('%d / %d  %s', state.stepNo, state.steps, s.title or '') or nil,
        objective = s and s.objective or (state.ending and state.ending.title) or nil, progress = line, done = state.done }
end

local function updateTracker()
    if not uiRunning() then return end
    local d = trackerData()
    if not d then close(TRACKER); return end
    if exports.wasteland_ui:IsOpen(TRACKER) then exports.wasteland_ui:Update(TRACKER, d)
    else open(TRACKER, 'html/tracker.js', d, false) end
end

RegisterNetEvent('wasteland:story:client:state', function(v)
    if type(v) ~= 'table' then return end
    local oldStep = state and state.step and state.step.id
    state = v
    if not v.step or v.step.id ~= oldStep then removeProp() end
    -- NPCs that are no longer part of the story for us go
    local want = {}
    for _, n in ipairs(v.npcs or {}) do want[n.id] = true end
    for id in pairs(npcs) do if not want[id] then removeNpc(id) end end
    makeBlips()
    updateTracker()
end)

-------------------------------------------------------------------------------
-- Screens
-------------------------------------------------------------------------------

local talking = false
RegisterNetEvent('wasteland:story:client:dialogue', function(d)
    if type(d) ~= 'table' then return end
    talking = true
    open(DIALOGUE, 'html/dialogue.js', d, true)
end)

RegisterNetEvent('wasteland:story:client:reply', function(r)
    if type(r) ~= 'table' then return end
    if r.close and not r.text then talking = false; close(DIALOGUE); return end
    if uiRunning() and exports.wasteland_ui:IsOpen(DIALOGUE) then exports.wasteland_ui:Update(DIALOGUE, { reply = r.text, keep = r.keep, done = r.done }) end
end)

RegisterNetEvent('wasteland:story:client:note', function(n)
    if type(n) == 'table' then open(NOTE, 'html/note.js', n, true) end
end)

RegisterNetEvent('wasteland:story:client:journal', function(j)
    if type(j) == 'table' then open(JOURNAL, 'html/journal.js', j, true) end
end)

local function banner(d)
    open(BANNER, 'html/banner.js', d, false)
    Citizen.SetTimeout(6500, function() close(BANNER) end)
end

RegisterNetEvent('wasteland:story:client:intro', function(i)
    if type(i) == 'table' then banner({ kicker = 'A new story', title = i.title, subtitle = i.subtitle, text = i.text }) end
end)

RegisterNetEvent('wasteland:story:client:stepDone', function(d)
    if type(d) ~= 'table' then return end
    PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true)
    if d.ending then
        banner({ kicker = 'The end of the act', title = d.ending.title, text = d.ending.text })
    else
        banner({ kicker = 'Journal updated', title = d.title, subtitle = d.next and ('Next: ' .. d.next) or nil, small = true })
    end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen == DIALOGUE then
        if action == 'choose' and type(payload) == 'table' and type(payload.id) == 'string' then
            if payload.id == '_bye' then talking = false; close(DIALOGUE)
            else TriggerServerEvent('wasteland:story:server:choose', payload.id) end
        elseif action == 'close' then talking = false; close(DIALOGUE) end
    elseif (screen == NOTE or screen == JOURNAL) and action == 'close' then
        close(screen)
    end
end)

RegisterCommand('journal', function() TriggerServerEvent('wasteland:story:server:journal') end, false)

-------------------------------------------------------------------------------
-- Spawning near the player; a marker over the story item
-------------------------------------------------------------------------------

Citizen.CreateThread(function()
    while true do
        if state then
            local me = GetEntityCoords(PlayerPedId())
            for _, n in ipairs(state.npcs or {}) do
                local d = #(me - vector3(n.coords.x, n.coords.y, n.coords.z))
                if d < SPAWN_RANGE and not npcs[n.id] then spawnNpc(n)
                elseif d > SPAWN_RANGE + 30 and npcs[n.id] then removeNpc(n.id) end
            end
            local s = state.step
            if s and (s.type == 'collect' or s.type == 'read') and s.coords then
                local d = #(me - vector3(s.coords.x, s.coords.y, s.coords.z))
                if d < SPAWN_RANGE and not prop then spawnProp(s)
                elseif d > SPAWN_RANGE + 30 and prop then removeProp() end
            end
        end
        Wait(1000)
    end
end)

Citizen.CreateThread(function()
    while true do
        local drew = false
        if prop and prop.obj and DoesEntityExist(prop.obj) then
            local c = GetEntityCoords(prop.obj)
            if #(GetEntityCoords(PlayerPedId()) - c) < 40.0 then
                drew = true
                DrawMarker(2, c.x, c.y, c.z + 0.9, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.3, 0.3, 0.3, 240, 200, 60, 200, true, true, 2, false, nil, nil, false)
            end
        end
        Wait(drew and 0 or 500)
    end
end)

Citizen.CreateThread(function()
    while true do
        local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
        if ok and ready then break end
        Wait(1000)
    end
    TriggerServerEvent('wasteland:story:server:state')
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'wasteland_target' then
        for id in pairs(npcs) do removeNpc(id) end
        removeProp()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(npcs) do removeNpc(id) end
    removeProp(); clearBlips()
    for _, s in ipairs({ DIALOGUE, NOTE, JOURNAL, TRACKER, BANNER }) do close(s) end
end)
