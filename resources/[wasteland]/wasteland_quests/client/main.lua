-- wasteland_quests :: client/main.lua
-- "Jobs" on every camp trader (wasteland_target), the job board screen,
-- the quest tracker on screen and map markers for quest places.
-- The server decides everything.

local BOARD, TRACKER, LOG, OFFER = 'questBoard', 'questTracker', 'questLog', 'questTutorial'
local showTracker
local tracked = {}        -- the active quests last sent (the tracker adds distances to them)
local hideTracker = false  -- the player hid the on-screen tracker (/quest -> Hide)
local givers = nil
local targetIds = {}
local blips = {}
local boardCamp = nil

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function targetRunning() return GetResourceState('wasteland_target') == 'started' end

-------------------------------------------------------------------------------
-- Jobs targets
-------------------------------------------------------------------------------

local function registerTargets()
    for _, id in ipairs(targetIds) do pcall(function() exports.wasteland_target:Remove(id) end) end
    targetIds = {}
    if not givers or not targetRunning() then return end
    for _, camp in ipairs(givers) do
        for _, c in ipairs(camp.traders) do
            -- A sphere around the trader's body (the ray hits the ped there).
            targetIds[#targetIds + 1] = exports.wasteland_target:AddSphere(vector3(c.x, c.y, c.z + 0.2), 1.3, {
                { label = 'Jobs', icon = '!', distance = 3.0,
                    onSelect = function() TriggerServerEvent('wasteland:quests:server:board', camp.id) end },
            })
        end
    end
end

RegisterNetEvent('wasteland:quests:client:givers', function(list)
    if type(list) ~= 'table' then return end
    givers = list
    registerTargets()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'wasteland_target' then registerTargets()
    elseif res == 'wasteland_camps' then TriggerServerEvent('wasteland:quests:server:givers') end
end)

-------------------------------------------------------------------------------
-- Board
-------------------------------------------------------------------------------

local function closeBoard()
    boardCamp = nil
    if uiRunning() and exports.wasteland_ui:IsOpen(BOARD) then exports.wasteland_ui:Close(BOARD) end
end

RegisterNetEvent('wasteland:quests:client:board', function(data)
    if type(data) ~= 'table' or not uiRunning() then return end
    boardCamp = data.camp
    if exports.wasteland_ui:IsOpen(BOARD) then
        exports.wasteland_ui:Update(BOARD, data)
    else
        exports.wasteland_ui:Open(BOARD, { script = 'html/board.js', data = data })
    end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= BOARD then return end
    if action == 'close' or not boardCamp then closeBoard(); return end
    if (action == 'accept' or action == 'abandon' or action == 'handIn') and type(payload) == 'table' and type(payload.quest) == 'string' then
        TriggerServerEvent('wasteland:quests:server:' .. action, boardCamp, payload.quest)
    end
end)

-------------------------------------------------------------------------------
-- Tracker and map markers
-------------------------------------------------------------------------------

-- Distance (m) from the player to the nearest of the camps a quest is handed in at.
local function nearestCamp(q, p)
    local best, bestD
    for _, c in ipairs(q.handIn or {}) do
        local d = #(p - vector3(c.x, c.y, c.z))
        if not bestD or d < bestD then best, bestD = c, d end
    end
    return best, bestD
end

local function trackerData()
    local p = GetEntityCoords(PlayerPedId())
    local now = GetCloudTimeAsInt()
    local out = {}
    for i, q in ipairs(tracked) do
        local c, d = nearestCamp(q, p)
        out[i] = { label = q.label, ready = q.ready, objectives = q.objectives,
            ago = q.startedAt and WLQ.Rules.duration(now - q.startedAt) or nil,
            handIn = c and { label = c.label, metres = math.floor(d) } or nil }
    end
    return { quests = out }
end

showTracker = function()
    if not uiRunning() then return end
    local open = exports.wasteland_ui:IsOpen(TRACKER)
    if #tracked == 0 or hideTracker then
        if open then exports.wasteland_ui:Close(TRACKER) end
    elseif open then
        exports.wasteland_ui:Update(TRACKER, trackerData())
    else
        exports.wasteland_ui:Open(TRACKER, { script = 'html/tracker.js', data = trackerData(), focus = false, cursor = false })
    end
end

local function clearBlips()
    for _, b in ipairs(blips) do RemoveBlip(b) end
    blips = {}
end

RegisterNetEvent('wasteland:quests:client:tracker', function(list)
    if type(list) ~= 'table' then return end
    clearBlips()
    local routed = false
    for _, q in ipairs(list) do
        for _, o in ipairs(q.objectives or {}) do
            if o.coords and not o.done then
                local b = AddBlipForCoord(o.coords.x + 0.0, o.coords.y + 0.0, o.coords.z + 0.0)
                SetBlipSprite(b, 280)
                SetBlipColour(b, 5)
                SetBlipScale(b, 0.9)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName('Job: ' .. q.label)
                EndTextCommandSetBlipName(b)
                if not routed then
                    SetBlipRoute(b, true)
                    SetBlipRouteColour(b, 5)
                    routed = true
                end
                blips[#blips + 1] = b
            end
        end
    end
    tracked = list
    showTracker()
end)

-------------------------------------------------------------------------------
-- Start-up; the board closes when you walk away
-------------------------------------------------------------------------------

Citizen.CreateThread(function()
    while true do
        local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
        if ok and ready then break end
        Citizen.Wait(1000)
    end
    TriggerServerEvent('wasteland:quests:server:givers')
    TriggerServerEvent('wasteland:quests:server:tracker')
    while true do
        Citizen.Wait(500)
        if boardCamp and givers then
            local p = GetEntityCoords(PlayerPedId())
            local near = false
            for _, camp in ipairs(givers) do
                if camp.id == boardCamp then
                    for _, c in ipairs(camp.traders) do
                        if #(p - vector3(c.x, c.y, c.z)) < 6.0 then near = true end
                    end
                end
            end
            if not near then closeBoard() end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearBlips()
    closeBoard()
    if uiRunning() and exports.wasteland_ui:IsOpen(TRACKER) then exports.wasteland_ui:Close(TRACKER) end
    if uiRunning() and exports.wasteland_ui:IsOpen(LOG) then exports.wasteland_ui:Close(LOG) end
end)

-------------------------------------------------------------------------------
-- /quest (and J): everything you are working on and how to finish it
-------------------------------------------------------------------------------

local function openLog()
    if not uiRunning() then return end
    local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
    if not (ok and ready) then return end
    TriggerServerEvent('wasteland:quests:server:log')
end

RegisterCommand('quest', function()
    if uiRunning() and exports.wasteland_ui:IsOpen(LOG) then exports.wasteland_ui:Close(LOG) else openLog() end
end, false)
RegisterKeyMapping('quest', 'Quests: what you are doing and how (open / close)', 'keyboard', 'J')

RegisterNetEvent('wasteland:quests:client:log', function(d)
    if type(d) ~= 'table' or not uiRunning() then return end
    local p = GetEntityCoords(PlayerPedId())
    for _, q in ipairs(d.quests or {}) do
        for _, c in ipairs(q.handIn or {}) do c.metres = math.floor(#(p - vector3(c.x, c.y, c.z))) end
        table.sort(q.handIn or {}, function(a, b) return a.metres < b.metres end)
        q.ago = q.startedAt and WLQ.Rules.duration(d.now - q.startedAt) or nil
    end
    d.trackerHidden = hideTracker
    if exports.wasteland_ui:IsOpen(LOG) then exports.wasteland_ui:Update(LOG, d)
    else exports.wasteland_ui:Open(LOG, { script = 'html/log.js', data = d }) end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action)
    if screen ~= LOG then return end
    if action == 'close' then exports.wasteland_ui:Close(LOG)
    elseif action == 'toggleTracker' then
        hideTracker = not hideTracker
        SetResourceKvpInt('wl_quest_tracker_hidden', hideTracker and 1 or 0)
        showTracker()
        openLog()
    end
end)

-- The tracker's distances and "taken ... ago" keep up as you move.
Citizen.CreateThread(function()
    hideTracker = GetResourceKvpInt('wl_quest_tracker_hidden') == 1
    while true do
        Citizen.Wait(2000)
        if #tracked > 0 and not hideTracker and uiRunning() and exports.wasteland_ui:IsOpen(TRACKER) then
            exports.wasteland_ui:Update(TRACKER, trackerData())
        end
    end
end)

-------------------------------------------------------------------------------
-- The tutorial: the offer (Start / No thanks), notices, /tutorial
-------------------------------------------------------------------------------

local function notice(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(msg))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:quests:client:notice', function(m) notice(m) end)
RegisterNetEvent('wasteland:quests:client:ready', function()
    PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end)

local function closeOffer()
    if uiRunning() and exports.wasteland_ui:IsOpen(OFFER) then exports.wasteland_ui:Close(OFFER) end
end

RegisterNetEvent('wasteland:quests:client:tutorialOffer', function(d)
    if type(d) ~= 'table' or not uiRunning() then return end
    d.mode = 'offer'
    if exports.wasteland_ui:IsOpen(OFFER) then exports.wasteland_ui:Update(OFFER, d)
    else exports.wasteland_ui:Open(OFFER, { script = 'html/tutorial.js', data = d }) end
end)

RegisterNetEvent('wasteland:quests:client:tutorialDone', function(d)
    if type(d) ~= 'table' or not uiRunning() then return end
    d.mode = 'done'
    PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true)
    if exports.wasteland_ui:IsOpen(OFFER) then exports.wasteland_ui:Update(OFFER, d)
    else exports.wasteland_ui:Open(OFFER, { script = 'html/tutorial.js', data = d }) end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action)
    if screen ~= OFFER then return end
    closeOffer()
    if action == 'start' or action == 'skip' then TriggerServerEvent('wasteland:quests:server:tutorial', action) end
end)

RegisterCommand('tutorial', function(_, args)
    TriggerServerEvent('wasteland:quests:server:tutorialCommand', args[1] == 'stop' and 'stop' or '')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then closeOffer() end
end)
