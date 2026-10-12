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
