-- wasteland_loot :: client/main.lua
-- Registers every container model (and dead zombies) with wasteland_target
-- ("Search ..."), plays the search (animation + progress bar; moving,
-- getting hurt or dying cancels it) and tells the server when it is done.
-- The server decides everything else.

local SCREEN = 'lootProgress'
local cfg = nil
local targetIds = {}
local active = nil   -- current search: { endsAt, start, health }

local ANIMS = {
    bin = { dict = 'amb@prop_human_bum_bin@base', name = 'base', flag = 1 },
    search = { dict = 'mini@repair', name = 'fixing_a_ped', flag = 1 },
    kneel = { dict = 'amb@medic@standing@kneel@base', name = 'base', flag = 1 },
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
    for _, c in pairs(cfg.containers) do
        if c.models and #c.models > 0 then
            targetIds[#targetIds + 1] = exports.wasteland_target:AddModel(c.models, {
                { label = 'Search ' .. c.label:lower(), icon = '⌕', distance = 2.2,
                    canInteract = function() return active == nil end,
                    onSelect = function(data)
                        if not data.entity then return end
                        local p = GetEntityCoords(data.entity)
                        TriggerServerEvent('wasteland:loot:server:start', GetEntityModel(data.entity), { x = p.x, y = p.y, z = p.z })
                    end },
            })
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
-- Searching
-------------------------------------------------------------------------------

local function stop(cancelled)
    if not active then return end
    local ped = PlayerPedId()
    if active.anim then StopAnimTask(ped, active.anim.dict, active.anim.name, 1.0) end
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
    active = { endsAt = GetGameTimer() + seconds * 1000, start = GetEntityCoords(ped), health = GetEntityHealth(ped) }
    local anim = ANIMS[s.anim] or ANIMS.search
    RequestAnimDict(anim.dict)
    local deadline = GetGameTimer() + 1000
    while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < deadline do Citizen.Wait(0) end
    if active and HasAnimDictLoaded(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.name, 4.0, -4.0, -1, anim.flag, 0.0, false, false, false)
        active.anim = anim
    end
    if uiRunning() then
        exports.wasteland_ui:Open(SCREEN, { script = 'html/progress.js', focus = false, cursor = false,
            data = { label = s.label or 'Searching', seconds = seconds } })
    end
    Citizen.CreateThread(function()
        while active do
            local p = PlayerPedId()
            if IsEntityDead(p) or #(GetEntityCoords(p) - active.start) > 1.2 or GetEntityHealth(p) < active.health
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
    if res == GetCurrentResourceName() then stop(false) end
end)

Citizen.CreateThread(function()
    while true do
        local ok, ready = pcall(function() return exports.wasteland_players:IsReady() end)
        if ok and ready then break end
        Citizen.Wait(1000)
    end
    TriggerServerEvent('wasteland:loot:server:config')
end)
