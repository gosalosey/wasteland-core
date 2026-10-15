-- wasteland_skills :: client/main.lua
-- The skills screen (/skills, F9), level-up messages, and the bonuses only
-- the game can apply: stamina (fitness) and melee damage (combat). Reports
-- sprinting time for fitness XP.

local SCREEN = 'skillsScreen'
local view = nil

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function isOpen() return uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) end

local function notice(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, false)
end

local function bonusOf(skill, key)
    for _, s in ipairs(view and view.skills or {}) do
        if s.name == skill then return (s.bonus and s.bonus[key]) or 0 end
    end
    return 0
end

RegisterNetEvent('wasteland:skills:client:view', function(v)
    if type(v) ~= 'table' then return end
    view = v
    SetPlayerMeleeWeaponDamageModifier(PlayerId(), 1.0 + bonusOf('combat', 'meleeDamage'))
    if isOpen() then exports.wasteland_ui:Update(SCREEN, { view = v }) end
end)

RegisterNetEvent('wasteland:skills:client:notice', function(msg) notice(tostring(msg)) end)

RegisterNetEvent('wasteland:skills:client:levelUp', function(_, label, level)
    PlaySoundFrontend(-1, 'RANK_UP', 'HUD_AWARDS', true)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(string.format('~g~%s~s~ level ~g~%d', label, level))
    EndTextCommandThefeedPostTicker(true, true)
end)

local function openScreen()
    if not uiRunning() then return end
    if isOpen() then exports.wasteland_ui:Close(SCREEN); return end
    TriggerServerEvent('wasteland:skills:server:view')
    exports.wasteland_ui:Open(SCREEN, { script = 'html/skills.js', data = { view = view } })
end

RegisterCommand('skills', openScreen, false)
RegisterKeyMapping('skills', 'Skills: open', 'keyboard', 'F9')

AddEventHandler('wasteland:ui:client:action', function(screen, action)
    if screen == SCREEN and action == 'close' then exports.wasteland_ui:Close(SCREEN) end
end)

-- Sprinting: fitness XP (reported once a minute) and stamina that lasts
-- longer (a little stamina back every second while sprinting).
Citizen.CreateThread(function()
    local sprinted, lastReport = 0.0, GetGameTimer()
    while true do
        Citizen.Wait(1000)
        local ped = PlayerPedId()
        if IsPedSprinting(ped) and not IsPedInAnyVehicle(ped, false) then
            sprinted = sprinted + 1.0
            local b = bonusOf('fitness', 'stamina')
            if b > 0 then RestorePlayerStamina(PlayerId(), 0.1 * b) end
        end
        if GetGameTimer() - lastReport >= 60000 then
            if sprinted >= 1 then TriggerServerEvent('wasteland:skills:server:sprint', math.min(sprinted, 60.0)) end
            sprinted, lastReport = 0.0, GetGameTimer()
        end
    end
end)

--- GetSkillLevel(skill) -> level (1 when unknown)   (other client scripts)
exports('GetSkillLevel', function(skill)
    for _, s in ipairs(view and view.skills or {}) do if s.name == skill then return s.level end end
    return 1
end)
