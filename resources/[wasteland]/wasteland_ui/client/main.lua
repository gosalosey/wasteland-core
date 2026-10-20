-- wasteland_ui :: client/main.lua
-- Screen manager between Lua modules and the NUI page (html/).
--
-- A module opens a screen it owns; the screen's script lives in the
-- module's own resource (listed under `files`) and is loaded by the shell:
--     exports.wasteland_ui:Open('characterSelect', {
--         script = 'html/characters.js',   -- path inside the calling resource
--         data = { ... },                   -- passed to the screen's mount()
--         focus = true, cursor = true,      -- NUI keyboard / mouse focus
--     })
-- Actions from the screen arrive as a client event:
--     AddEventHandler('wasteland:ui:client:action', function(screen, action, payload) ... end)
-- NUI input is untrusted like any client input: anything with value must go
-- to the server through a guarded net event (M.netEvent).

local RESOURCE = GetCurrentResourceName()
local SCREEN_PATTERN = '^[%a][%w_]*$'

local screens = {}    -- [name] = { owner, focus, cursor }
local shellReady = false
local queue = {}

local function send(msg)
    msg.wl = true
    if shellReady then
        SendNUIMessage(msg)
    else
        queue[#queue + 1] = msg
    end
end

local function refreshFocus()
    local focus, cursor = false, false
    for _, s in pairs(screens) do
        if s.focus then focus = true end
        if s.cursor then cursor = true end
    end
    SetNuiFocus(focus, focus and cursor)
end

RegisterNUICallback('ready', function(_, cb)
    shellReady = true
    for _, msg in ipairs(queue) do SendNUIMessage(msg) end
    queue = {}
    cb({ ok = true })
end)

-- The page could not show a screen (its script did not load): forget it,
-- so focus is given back and its owner opens it again on its next update.
RegisterNUICallback('failed', function(data, cb)
    local name = type(data) == 'table' and data.screen
    if type(name) == 'string' and screens[name] then
        print(('[wasteland_ui] screen "%s" could not be shown; closed it'):format(name))
        screens[name] = nil
        refreshFocus()
        TriggerEvent('wasteland:ui:client:failed', name)
    end
    cb({ ok = true })
end)

RegisterNUICallback('action', function(data, cb)
    if type(data) ~= 'table' or type(data.screen) ~= 'string' or type(data.action) ~= 'string' then
        cb({ ok = false, error = 'bad request' })
        return
    end
    if not screens[data.screen] then
        cb({ ok = false, error = 'screen is not open' })
        return
    end
    TriggerEvent('wasteland:ui:client:action', data.screen, data.action, data.payload)
    cb({ ok = true })
end)

-- Script errors inside screens are printed in F8 so they can be reported.
RegisterNUICallback('log', function(data, cb)
    if type(data) == 'table' then
        print(string.format('[wasteland_ui] %s: %s', tostring(data.level or 'info'), tostring(data.message)))
    end
    cb({ ok = true })
end)

--- Open (or replace) a screen. Returns true or false, err.
exports('Open', function(name, opts)
    opts = opts or {}
    if type(name) ~= 'string' or not name:match(SCREEN_PATTERN) then
        return false, 'screen name must match [A-Za-z][A-Za-z0-9_]*'
    end
    local owner = GetInvokingResource() or RESOURCE
    local existing = screens[name]
    if existing and existing.owner ~= owner then
        return false, string.format('screen "%s" belongs to %s', name, existing.owner)
    end
    if type(opts.script) ~= 'string' or opts.script:find('..', 1, true) or not opts.script:match('^[%w_/%-%.]+%.js$') then
        return false, 'opts.script must be a .js path inside the calling resource'
    end
    screens[name] = { owner = owner, focus = opts.focus ~= false, cursor = opts.cursor ~= false }
    send({
        type = 'open', screen = name,
        script = string.format('https://cfx-nui-%s/%s', owner, opts.script),
        data = opts.data,
    })
    refreshFocus()
    return true
end)

--- Send new data to an open screen (its update() is called).
exports('Update', function(name, data)
    if not screens[name] then return false, 'screen is not open' end
    send({ type = 'update', screen = name, data = data })
    return true
end)

--- Close a screen. Only its owner may close it.
exports('Close', function(name)
    local s = screens[name]
    if not s then return true end
    local owner = GetInvokingResource() or RESOURCE
    if s.owner ~= owner then return false, string.format('screen "%s" belongs to %s', name, s.owner) end
    screens[name] = nil
    send({ type = 'close', screen = name })
    refreshFocus()
    return true
end)

exports('IsOpen', function(name)
    return screens[name] ~= nil
end)

--- Change focus while a screen stays open (e.g. let the player look around).
exports('SetFocus', function(name, focus, cursor)
    local s = screens[name]
    if not s then return false, 'screen is not open' end
    s.focus, s.cursor = focus == true, cursor == true
    refreshFocus()
    return true
end)

AddEventHandler('onResourceStop', function(res)
    if res == RESOURCE then
        SetNuiFocus(false, false)
        return
    end
    local closed = false
    for name, s in pairs(screens) do
        if s.owner == res then
            screens[name] = nil
            send({ type = 'close', screen = name })
            closed = true
        end
    end
    if closed then refreshFocus() end
end)
