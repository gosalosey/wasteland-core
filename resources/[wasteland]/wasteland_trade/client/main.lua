-- wasteland_trade :: client/main.lua
-- "Trade" on another player (hold Left Alt), the request popup and the
-- trade window. Every decision is the server's.

local SCREEN = 'tradeScreen'
local invite = nil

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function isOpen() return uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) end

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:trade:client:notice', function(m) notice(m) end)

local function show(data)
    if not uiRunning() then return end
    if isOpen() then exports.wasteland_ui:Update(SCREEN, data)
    else exports.wasteland_ui:Open(SCREEN, { script = 'html/trade.js', data = data }) end
end

-- Someone asks to trade: a small popup with Accept / Decline.
RegisterNetEvent('wasteland:trade:client:invite', function(info)
    if type(info) ~= 'table' then return end
    invite = info
    notice(info.name .. ' wants to trade with you.')
    show({ invite = info })
    local mine = info
    Citizen.SetTimeout((info.seconds or 30) * 1000, function()
        if invite == mine then
            invite = nil
            if isOpen() then exports.wasteland_ui:Close(SCREEN) end
        end
    end)
end)

RegisterNetEvent('wasteland:trade:client:view', function(v)
    invite = nil
    show({ view = v })
end)

RegisterNetEvent('wasteland:trade:client:closed', function(message)
    if isOpen() then exports.wasteland_ui:Close(SCREEN) end
    if message then notice(message) end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN then return end
    payload = type(payload) == 'table' and payload or {}
    if action == 'accept' and invite then
        TriggerServerEvent('wasteland:trade:server:respond', invite.from, true)
        invite = nil
    elseif action == 'decline' then
        if invite then TriggerServerEvent('wasteland:trade:server:respond', invite.from, false) end
        invite = nil
        exports.wasteland_ui:Close(SCREEN)
    elseif action == 'offer' then
        local n = math.tointeger(tonumber(payload.count)) or 0
        if type(payload.uid) == 'string' then TriggerServerEvent('wasteland:trade:server:offer', payload.uid, math.max(0, n)) end
    elseif action == 'ready' then
        TriggerServerEvent('wasteland:trade:server:ready', payload.ready == true)
    elseif action == 'cancel' or action == 'close' then
        TriggerServerEvent('wasteland:trade:server:cancel')
        exports.wasteland_ui:Close(SCREEN)
    end
end)

-- "Trade" when looking at another player
Citizen.CreateThread(function()
    while GetResourceState('wasteland_target') ~= 'started' do Citizen.Wait(1000) end
    exports.wasteland_target:AddGlobal('player', {
        { label = 'Trade', icon = '⇄', distance = 3.0,
            onSelect = function(data)
                local pl = data and data.entity and NetworkGetPlayerIndexFromPed(data.entity)
                if pl and pl ~= -1 then TriggerServerEvent('wasteland:trade:server:request', GetPlayerServerId(pl)) end
            end },
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and isOpen() then exports.wasteland_ui:Close(SCREEN) end
end)
