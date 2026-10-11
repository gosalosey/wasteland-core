-- wasteland_crafting :: client/main.lua
-- The crafting screen (key K, /craft, or the Crafting button in the
-- inventory) and the craft itself: animation + progress bar; moving,
-- getting hurt, dying or X cancels. The server decides everything.

local SCREEN, PROGRESS = 'crafting', 'craftProgress'
local ANIM = { dict = 'mini@repair', name = 'fixing_a_ped' }
local active = nil

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('wasteland:crafting:client:notice', function(m) notice(m) end)

local function canOpen()
    local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
    return ok and ready and not IsEntityDead(PlayerPedId()) and not IsPauseMenuActive()
end

local function isOpen() return uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) end
local function close() if isOpen() then exports.wasteland_ui:Close(SCREEN) end end

local function open()
    if not canOpen() then return end
    TriggerServerEvent('wasteland:crafting:server:open')
end

RegisterCommand('craft', function() if isOpen() then close() else open() end end, false)
RegisterKeyMapping('craft', 'Crafting: open / close', 'keyboard', 'K')

-- The inventory's Crafting button.
AddEventHandler('wasteland:crafting:client:open', function() open() end)

RegisterNetEvent('wasteland:crafting:client:screen', function(data)
    if type(data) ~= 'table' or not uiRunning() then return end
    if isOpen() then
        exports.wasteland_ui:Update(SCREEN, data)
    elseif not active then
        exports.wasteland_ui:Open(SCREEN, { script = 'html/crafting.js', data = data })
    end
    if active == nil and data.message and not isOpen() then notice(data.message) end
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= SCREEN then return end
    if action == 'close' then close()
    elseif action == 'craft' and type(payload) == 'table' and type(payload.recipe) == 'string' and not active then
        TriggerServerEvent('wasteland:crafting:server:craft', payload.recipe)
    end
end)

-------------------------------------------------------------------------------
-- The craft
-------------------------------------------------------------------------------

local function stop(cancelled)
    if not active then return end
    StopAnimTask(PlayerPedId(), ANIM.dict, ANIM.name, 1.0)
    active = nil
    if uiRunning() and exports.wasteland_ui:IsOpen(PROGRESS) then exports.wasteland_ui:Close(PROGRESS) end
    if cancelled then
        TriggerServerEvent('wasteland:crafting:server:cancel')
        notice('Crafting cancelled.')
    end
end

RegisterNetEvent('wasteland:crafting:client:cancel', function() stop(false) end)

RegisterNetEvent('wasteland:crafting:client:progress', function(p)
    if type(p) ~= 'table' or active then return end
    local ped = PlayerPedId()
    local seconds = tonumber(p.seconds) or 3
    close() -- the screen comes back with the result
    active = { endsAt = GetGameTimer() + seconds * 1000, start = GetEntityCoords(ped), health = GetEntityHealth(ped) }
    RequestAnimDict(ANIM.dict)
    local deadline = GetGameTimer() + 1000
    while not HasAnimDictLoaded(ANIM.dict) and GetGameTimer() < deadline do Citizen.Wait(0) end
    if active and HasAnimDictLoaded(ANIM.dict) then
        TaskPlayAnim(ped, ANIM.dict, ANIM.name, 4.0, -4.0, -1, 1, 0.0, false, false, false)
    end
    if uiRunning() then
        exports.wasteland_ui:Open(PROGRESS, { script = 'html/progress.js', focus = false, cursor = false,
            data = { label = p.label or 'Crafting', seconds = seconds } })
    end
    Citizen.CreateThread(function()
        while active do
            local me = PlayerPedId()
            if IsEntityDead(me) or #(GetEntityCoords(me) - active.start) > 1.2 or GetEntityHealth(me) < active.health
                or IsControlJustPressed(0, 73) then
                stop(true)
                return
            end
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
            if GetGameTimer() >= active.endsAt then
                stop(false)
                TriggerServerEvent('wasteland:crafting:server:finish')
                return
            end
            Citizen.Wait(0)
        end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then stop(false); close() end
end)
