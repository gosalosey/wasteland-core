-- wasteland_quests :: client/main.lua
-- "Jobs" on every camp trader (wasteland_target), the job board screen,
-- the quest tracker on screen and map markers for quest places.
-- The server decides everything.

local BOARD, TRACKER = 'questBoard', 'questTracker'
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
    if not uiRunning() then return end
    if #list == 0 then
        if exports.wasteland_ui:IsOpen(TRACKER) then exports.wasteland_ui:Close(TRACKER) end
    elseif exports.wasteland_ui:IsOpen(TRACKER) then
        exports.wasteland_ui:Update(TRACKER, { quests = list })
    else
        exports.wasteland_ui:Open(TRACKER, { script = 'html/tracker.js', data = { quests = list }, focus = false, cursor = false })
    end
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
end)
