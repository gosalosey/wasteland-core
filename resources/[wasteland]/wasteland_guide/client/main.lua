-- wasteland_guide :: client/main.lua
-- The survivor's guide screen (F2 or /guide) and the "milestone done"
-- message.

local SCREEN = 'guideScreen'
local view = nil
local keyBound = false

local function uiRunning() return GetResourceState('wasteland_ui') == 'started' end
local function isOpen() return uiRunning() and exports.wasteland_ui:IsOpen(SCREEN) end

local function openGuide()
    if not uiRunning() then return end
    if isOpen() then exports.wasteland_ui:Close(SCREEN); return end
    TriggerServerEvent('wasteland:guide:server:view')
    exports.wasteland_ui:Open(SCREEN, { script = 'html/guide.js', data = { view = view } })
end

RegisterCommand('guide', openGuide, false)

RegisterNetEvent('wasteland:guide:client:view', function(v)
    if type(v) ~= 'table' then return end
    view = v
    if not keyBound then
        keyBound = true
        RegisterKeyMapping('guide', "Survivor's guide: open", 'keyboard', type(v.key) == 'string' and v.key or 'F2')
    end
    if isOpen() then exports.wasteland_ui:Update(SCREEN, { view = v }) end
end)

RegisterNetEvent('wasteland:guide:client:milestone', function(label)
    PlaySoundFrontend(-1, 'CHALLENGE_UNLOCKED', 'HUD_AWARDS', true)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName('~g~Milestone:~s~ ' .. tostring(label) .. '  ~c~(F2: guide)')
    EndTextCommandThefeedPostTicker(true, true)
end)

AddEventHandler('wasteland:ui:client:action', function(screen, action)
    if screen == SCREEN and action == 'close' then exports.wasteland_ui:Close(SCREEN) end
end)
