-- wasteland_groups :: client/main.lua
-- /group (or F6) opens the group screen. Map markers for the other members
-- of your group (positions come from the server every few seconds).

local SCREEN = 'groupScreen'
local blips = {}     -- characterId -> blip
local lastView = nil

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function isOpen() return uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) end

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:groups:client:notice', function(m)
    notice(m)
    if isOpen() then exports.wasteland_ui:Update(SCREEN, { message = m }) end
end)

-------------------------------------------------------------------------------
-- The screen
-------------------------------------------------------------------------------

-- Players near you, for the invite list (server id and name).
local function nearby()
    local out = {}
    local me = GetEntityCoords(PlayerPedId())
    for _, pl in ipairs(GetActivePlayers()) do
        if pl ~= PlayerId() then
            local ped = GetPlayerPed(pl)
            local d = #(GetEntityCoords(ped) - me)
            if d < 40.0 then out[#out + 1] = { server = GetPlayerServerId(pl), name = GetPlayerName(pl), distance = math.floor(d) } end
        end
    end
    table.sort(out, function(a, b) return a.distance < b.distance end)
    return out
end

local function openScreen()
    if not uiRunning() then return end
    if isOpen() then exports.wasteland_ui:Close(SCREEN); return end
    TriggerServerEvent('wasteland:groups:server:view')
    exports.wasteland_ui:Open(SCREEN, { script = 'html/group.js', data = { view = lastView, nearby = nearby(), loading = lastView == nil } })
end

RegisterCommand('group', openScreen, false)
RegisterKeyMapping('group', 'Group: open', 'keyboard', 'F6')

RegisterNetEvent('wasteland:groups:client:view', function(v)
    lastView = v
    if isOpen() then exports.wasteland_ui:Update(SCREEN, { view = v, nearby = nearby() }) end
end)

local ACTIONS = {
    create = function(p) TriggerServerEvent('wasteland:groups:server:create', tostring(p.name or '')) end,
    invite = function(p) local id = math.tointeger(tonumber(p.server)); if id then TriggerServerEvent('wasteland:groups:server:invite', id) end end,
    accept = function(p) TriggerServerEvent('wasteland:groups:server:respond', math.tointeger(tonumber(p.group)) or 0, true) end,
    decline = function(p) TriggerServerEvent('wasteland:groups:server:respond', math.tointeger(tonumber(p.group)) or 0, false) end,
    leave = function() TriggerServerEvent('wasteland:groups:server:leave') end,
    kick = function(p) TriggerServerEvent('wasteland:groups:server:kick', math.tointeger(tonumber(p.id)) or 0) end,
    promote = function(p) TriggerServerEvent('wasteland:groups:server:promote', math.tointeger(tonumber(p.id)) or 0) end,
    disband = function() TriggerServerEvent('wasteland:groups:server:disband') end,
    rename = function(p) TriggerServerEvent('wasteland:groups:server:rename', tostring(p.name or '')) end,
    refresh = function() TriggerServerEvent('wasteland:groups:server:view') end,
}

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN then return end
    if action == 'close' then exports.wasteland_ui:Close(SCREEN); return end
    local fn = ACTIONS[action]
    if fn then fn(type(payload) == 'table' and payload or {}) end
end)

-------------------------------------------------------------------------------
-- Map markers
-------------------------------------------------------------------------------

local function clearBlips()
    for _, b in pairs(blips) do RemoveBlip(b) end
    blips = {}
end

RegisterNetEvent('wasteland:groups:client:positions', function(data)
    if type(data) ~= 'table' then clearBlips(); return end
    local seen = {}
    for _, m in ipairs(data.members or {}) do
        seen[m.id] = true
        local b = blips[m.id]
        if not b or not DoesBlipExist(b) then
            b = AddBlipForCoord(m.x + 0.0, m.y + 0.0, m.z + 0.0)
            SetBlipSprite(b, 1)
            SetBlipScale(b, 0.85)
            SetBlipAsShortRange(b, false)
            SetBlipCategory(b, 7)
            blips[m.id] = b
        end
        SetBlipCoords(b, m.x + 0.0, m.y + 0.0, m.z + 0.0)
        SetBlipColour(b, m.dead and 1 or (m.leader and 5 or 3)) -- red: down, yellow: leader, blue: member
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(string.format('%s (%s)%s', m.name, data.group or 'group', m.dead and ' - down' or ''))
        EndTextCommandSetBlipName(b)
    end
    for id, b in pairs(blips) do
        if not seen[id] then RemoveBlip(b); blips[id] = nil end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearBlips()
    if isOpen() then exports.wasteland_ui:Close(SCREEN) end
end)

Citizen.CreateThread(function()
    Citizen.Wait(2000)
    TriggerEvent('chat:addSuggestion', '/group', 'Your group: create, invite, members (also F6)')
end)

-------------------------------------------------------------------------------
-- Calls for help: /help [what is wrong], /accepthelp [id], /cancelhelp
-------------------------------------------------------------------------------

RegisterCommand('help', function(_, args) TriggerServerEvent('wasteland:groups:server:help', table.concat(args or {}, ' ')) end, false)
RegisterCommand('accepthelp', function(_, args) TriggerServerEvent('wasteland:groups:server:acceptHelp', math.tointeger(tonumber(args and args[1])) or nil) end, false)
RegisterCommand('cancelhelp', function() TriggerServerEvent('wasteland:groups:server:cancelHelp') end, false)

local function areaName(c)
    local zone = GetNameOfZone(c.x + 0.0, c.y + 0.0, c.z + 0.0)
    local label = zone and GetLabelText(zone) or nil
    if not label or label == 'NULL' then return 'somewhere out there' end
    return label
end

-- Everyone: an announcement (the caller only gets their own confirmation).
RegisterNetEvent('wasteland:groups:client:helpCall', function(c)
    if type(c) ~= 'table' or c.from == GetPlayerServerId(PlayerId()) then return end
    local where = areaName(c.coords)
    local what = (c.message and c.message ~= '') and (': "' .. c.message .. '"') or ''
    PlaySoundFrontend(-1, 'Event_Message_Purple', 'GTAO_FM_Events_Soundset', true)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(string.format('~r~HELP!~s~ %s needs help near ~y~%s~s~%s~n~Type ~g~/accepthelp~s~ to get a route to them.',
        tostring(c.name), where, what))
    EndTextCommandThefeedPostTicker(true, true)
    if GetResourceState('chat') == 'started' then
        TriggerEvent('chat:addMessage', { color = { 220, 60, 60 }, args = { 'HELP', string.format('%s needs help near %s%s - /accepthelp',
            tostring(c.name), where, what) } })
    end
end)

-- A helper: a red blip with a GPS route that follows the caller.
local helpBlip, helpId = nil, nil
RegisterNetEvent('wasteland:groups:client:helpRoute', function(r)
    if type(r) ~= 'table' or type(r.coords) ~= 'table' then return end
    if helpBlip and DoesBlipExist(helpBlip) then RemoveBlip(helpBlip) end
    helpBlip = AddBlipForCoord(r.coords.x + 0.0, r.coords.y + 0.0, r.coords.z + 0.0)
    SetBlipSprite(helpBlip, 280)
    SetBlipColour(helpBlip, 1)
    SetBlipScale(helpBlip, 1.0)
    SetBlipRoute(helpBlip, true)
    SetBlipRouteColour(helpBlip, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Needs help: ' .. tostring(r.name))
    EndTextCommandSetBlipName(helpBlip)
    helpId = r.id
    if not r.update then notice(string.format('Route set to %s (red on the map). It follows them while they call.', tostring(r.name))) end
end)

RegisterNetEvent('wasteland:groups:client:helpEnded', function(id, why)
    if id ~= helpId then return end
    if helpBlip and DoesBlipExist(helpBlip) then RemoveBlip(helpBlip) end
    helpBlip, helpId = nil, nil
    notice(why == 'cancelled' and 'They are safe now: the call for help was called off.' or 'The call for help ended.')
end)

-- Arrived: the route goes when you are close.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        if helpBlip and DoesBlipExist(helpBlip) and #(GetEntityCoords(PlayerPedId()) - GetBlipCoords(helpBlip)) < 15.0 then
            RemoveBlip(helpBlip)
            helpBlip, helpId = nil, nil
            notice('You reached them.')
        end
    end
end)
