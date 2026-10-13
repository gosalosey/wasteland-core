-- wasteland_emotes :: client/main.lua
-- Emotes: F4 opens the menu, /e <name> plays one, /e c stops it, /e alone
-- opens the menu. X puts your hands up (again: down). Whole-body emotes
-- stop when you walk; none play in a vehicle, while dead or falling.
-- Animations are networked by the game, so everyone sees them.

local MENU = 'emoteMenu'
local playing = nil      -- the emote being played
local handsUp = false
local HANDS = { dict = 'missminuteman_1ig_2', anim = 'handsup_base' }

-- Progress bars and minigames of other modules use X too (to cancel).
local BUSY_SCREENS = { 'vehProgress', 'lootProgress', 'craftProgress', 'vehLockpick', 'huntProgress' }

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end

local function busy()
    if not uiRunning() then return false end
    for _, s in ipairs(BUSY_SCREENS) do
        if exports.wasteland_ui:IsOpen(s) then return true end
    end
    return false
end

-- Can the player do an emote right now? true or false, reason.
local function canEmote(ped)
    if IsEntityDead(ped) then return false, 'You cannot do that while dead.' end
    if IsPedInAnyVehicle(ped, true) then return false, 'Get out of the vehicle first.' end
    if IsPedSwimming(ped) or IsPedFalling(ped) or IsPedRagdoll(ped) or IsPedClimbing(ped) then return false, 'Not right now.' end
    return true
end

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local untilT = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < untilT do Citizen.Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function upperBody(e) return e.dict ~= nil and (e.flag or 0) >= 16 end

local function stopEmote(quiet)
    local ped = PlayerPedId()
    if playing then
        -- Scenarios and whole-body animations: clear the task; upper-body
        -- ones just stop (so walking is not interrupted).
        if upperBody(playing) then StopAnimTask(ped, playing.dict, playing.anim, 2.0) else ClearPedTasks(ped) end
        playing = nil
    end
    if handsUp then
        StopAnimTask(ped, HANDS.dict, HANDS.anim, 2.0)
        handsUp = false
    end
    if not quiet then notice('Emote stopped.') end
end

local function playEmote(e)
    local ped = PlayerPedId()
    local ok, why = canEmote(ped)
    if not ok then notice(why); return end
    if e.name == 'handsup' then ExecuteCommand('handsup'); return end
    stopEmote(true)
    if e.scenario then
        TaskStartScenarioInPlace(ped, e.scenario, 0, true)
    else
        if not loadDict(e.dict) then notice('That emote could not be loaded.'); return end
        TaskPlayAnim(ped, e.dict, e.anim, 3.0, 3.0, -1, e.flag or 1, 0, false, false, false)
        RemoveAnimDict(e.dict)
    end
    playing = e
    local started = GetGameTimer()
    Citizen.CreateThread(function()
        while playing == e do
            Citizen.Wait(0)
            local me = PlayerPedId()
            if not canEmote(me) then playing = nil; ClearPedTasks(me); return end
            -- Walking stops a whole-body emote.
            if not upperBody(e) and GetGameTimer() - started > 500 and (IsControlPressed(0, 32) or IsControlPressed(0, 33)
                or IsControlPressed(0, 34) or IsControlPressed(0, 35) or IsControlPressed(0, 22)) then
                stopEmote(true)
                return
            end
            -- A one-off animation that finished.
            if e.dict and GetGameTimer() - started > 800 and not IsEntityPlayingAnim(me, e.dict, e.anim, 3) then
                if playing == e then playing = nil end
                return
            end
        end
    end)
end

-------------------------------------------------------------------------------
-- /e and the F4 menu
-------------------------------------------------------------------------------

local function openMenu()
    if not uiRunning() then notice('The emote menu is not available.'); return end
    if exports.wasteland_ui:IsOpen(MENU) then exports.wasteland_ui:Close(MENU); return end
    local list = {}
    for _, e in ipairs(WLE.EMOTES) do list[#list + 1] = { name = e.name, label = e.label, cat = e.cat } end
    exports.wasteland_ui:Open(MENU, { script = 'html/emotes.js', data = { emotes = list, categories = WLE.CATEGORIES,
        playing = playing and playing.name or (handsUp and 'handsup' or nil) } })
end

RegisterCommand('e', function(_, args)
    local name = args[1] and args[1]:lower() or nil
    if not name or name == 'list' or name == 'menu' then openMenu(); return end
    if name == 'c' or name == 'cancel' or name == 'stop' then stopEmote(false); return end
    local e = WLE.BY_NAME[name]
    if not e then notice('No emote "' .. name .. '". Press F4 or type /e for the list.'); return end
    playEmote(e)
end, false)

RegisterCommand('emotemenu', function() openMenu() end, false)
RegisterKeyMapping('emotemenu', 'Emotes: open the menu', 'keyboard', 'F4')

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= MENU then return end
    if action == 'close' then exports.wasteland_ui:Close(MENU)
    elseif action == 'stop' then exports.wasteland_ui:Close(MENU); stopEmote(false)
    elseif action == 'play' and type(payload) == 'table' and WLE.BY_NAME[payload.name] then
        exports.wasteland_ui:Close(MENU)
        playEmote(WLE.BY_NAME[payload.name])
    end
end)

Citizen.CreateThread(function()
    Citizen.Wait(1000)
    TriggerEvent('chat:addSuggestion', '/e', 'Play an emote (F4 shows them all)', {
        { name = 'emote', help = 'e.g. wave, sit, smoke - or c to stop' },
    })
    TriggerEvent('chat:addSuggestion', '/hotbar', 'Show or hide the hotbar on screen')
end)

-------------------------------------------------------------------------------
-- Hands up (X)
-------------------------------------------------------------------------------

RegisterCommand('handsup', function()
    local ped = PlayerPedId()
    if handsUp then
        StopAnimTask(ped, HANDS.dict, HANDS.anim, 2.0)
        handsUp = false
        return
    end
    if busy() or (uiRunning() and exports.wasteland_ui:IsOpen(MENU)) then return end
    local ok = canEmote(ped)
    if not ok then return end
    stopEmote(true)
    if not loadDict(HANDS.dict) then return end
    TaskPlayAnim(ped, HANDS.dict, HANDS.anim, 3.0, 3.0, -1, 49, 0, false, false, false)
    handsUp = true
    Citizen.CreateThread(function()
        while handsUp do
            Citizen.Wait(0)
            local me = PlayerPedId()
            -- No shooting or punching with your hands up.
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true); DisableControlAction(0, 141, true); DisableControlAction(0, 142, true)
            if not canEmote(me) then handsUp = false; return end
            if not IsEntityPlayingAnim(me, HANDS.dict, HANDS.anim, 3) then
                TaskPlayAnim(me, HANDS.dict, HANDS.anim, 3.0, 3.0, -1, 49, 0, false, false, false)
            end
        end
    end)
end, false)
RegisterKeyMapping('handsup', 'Hands up / down', 'keyboard', 'X')

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if playing or handsUp then stopEmote(true) end
    if uiRunning() and exports.wasteland_ui:IsOpen(MENU) then exports.wasteland_ui:Close(MENU) end
end)
