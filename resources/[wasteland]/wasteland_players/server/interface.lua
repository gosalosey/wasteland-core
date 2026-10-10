-- wasteland_players :: server/interface.lua
-- Player-facing actions (list / create / select / delete characters),
-- reachable through:
--   * the chat command `/character ...` (name: players.commandName); this is
--     the interim interface until the UI arrives in Milestone 3
--   * guarded net events wasteland:players:server:* for that UI
-- and the server exports other modules use.

local Characters = WLP.Characters
local Sessions = WLP.Sessions
local Interface = {}
WLP.Interface = Interface

local function log() return WLP.M.log end

local function cmd() return '/' .. (WLP.cfg and WLP.cfg.commandName or 'character') end

local function reply(session, action, ok, message)
    WLP.notify(session.source, message)
    TriggerClientEvent('wasteland:players:client:result', session.source, { action = action, ok = ok, message = message })
end

-- Run one action for a session in a thread, one action at a time per player.
local function run(src, action, fn)
    local session = WLP.sessions[src]
    if not session then
        WLP.notify(src, 'Your session is not ready yet. Please wait a moment.')
        return
    end
    if session.busy then
        reply(session, action, false, 'Please wait, your previous request is still running.')
        return
    end
    session.busy = true
    Citizen.CreateThread(function()
        local ok, err = pcall(fn, session)
        session.busy = false
        if not ok then
            log():error('%s for player %d failed: %s', action, src, tostring(err))
            reply(session, action, false, 'Something went wrong. Please try again.')
        end
    end)
end

local function formatPlayTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    return string.format('%dh %02dm', h, m)
end

-------------------------------------------------------------------------------
-- Actions (all run inside `run`, so they may wait on the database)
-------------------------------------------------------------------------------

function Interface.listCharacters(session)
    local list = Characters.list(session.accountId)
    if not list then
        reply(session, 'list', false, 'Could not load your characters (database unavailable).')
        return
    end
    local activeId = session.character and session.character.id or nil
    TriggerClientEvent('wasteland:players:client:characters', session.source, {
        characters = list, maxCharacters = WLP.cfg.maxCharacters, activeId = activeId,
    })
    if #list == 0 then
        reply(session, 'list', true, string.format('You have no characters. Create one with: %s create <first name> <last name>', cmd()))
        return
    end
    local lines = { string.format('Your characters (%d of %d):', #list, WLP.cfg.maxCharacters) }
    for _, c in ipairs(list) do
        lines[#lines + 1] = string.format('  [%d] %s %s - played %s%s', c.slot, c.firstName, c.lastName,
            formatPlayTime(c.playSeconds), c.id == activeId and ' (playing)' or '')
    end
    lines[#lines + 1] = string.format('Play one with: %s select <slot>', cmd())
    for _, l in ipairs(lines) do WLP.notify(session.source, l) end
    TriggerClientEvent('wasteland:players:client:result', session.source, { action = 'list', ok = true, message = lines[1] })
end

function Interface.createCharacter(session, firstName, lastName)
    local char, err = Characters.create(session, firstName, lastName)
    if not char then
        reply(session, 'create', false, 'Could not create the character: ' .. tostring(err))
        return
    end
    reply(session, 'create', true, string.format('Created %s %s in slot %d. Play it with: %s select %d',
        char.firstName, char.lastName, char.slot, cmd(), char.slot))
end

function Interface.selectCharacter(session, slot)
    local list = Characters.list(session.accountId)
    if not list then
        reply(session, 'select', false, 'Could not load your characters (database unavailable).')
        return
    end
    local target
    for _, c in ipairs(list) do if c.slot == slot then target = c end end
    if not target then
        reply(session, 'select', false, string.format('You have no character in slot %d. See %s list', slot, cmd()))
        return
    end
    if session.character and session.character.id == target.id then
        reply(session, 'select', false, string.format('You are already playing %s %s.', target.firstName, target.lastName))
        return
    end
    if session.character then
        local saved = Characters.unload(session, 'switch character')
        if not saved then
            reply(session, 'select', false, 'Your current character could not be saved, so you cannot switch right now. Please try again shortly.')
            return
        end
    end
    session.state = 'loading'
    local char, loadErr = Characters.load(session, target.id)
    if not char then
        session.state = 'connected'
        reply(session, 'select', false, 'Could not load the character: ' .. tostring(loadErr))
        return
    end
    reply(session, 'select', true, string.format('You are now playing %s %s.', char.firstName, char.lastName))
end

function Interface.deleteCharacter(session, slot, confirmFirstName)
    if not WLP.cfg.allowCharacterDeletion then
        reply(session, 'delete', false, 'Deleting characters is disabled on this server.')
        return
    end
    local list = Characters.list(session.accountId)
    if not list then
        reply(session, 'delete', false, 'Could not load your characters (database unavailable).')
        return
    end
    local target
    for _, c in ipairs(list) do if c.slot == slot then target = c end end
    if not target then
        reply(session, 'delete', false, string.format('You have no character in slot %d.', slot))
        return
    end
    if type(confirmFirstName) ~= 'string' or confirmFirstName:lower() ~= target.firstName:lower() then
        reply(session, 'delete', false, string.format('To delete %s %s, confirm with: %s delete %d %s',
            target.firstName, target.lastName, cmd(), slot, target.firstName))
        return
    end
    local ok, delErr = Characters.delete(session, target.id)
    if not ok then
        reply(session, 'delete', false, 'Could not delete the character: ' .. tostring(delErr))
        return
    end
    reply(session, 'delete', true, string.format('Deleted %s %s.', target.firstName, target.lastName))
end

--- Greeting after joining: show the character list.
function Interface.welcome(session)
    if not session or not WLP.sessions[session.source] then return end
    if session.busy then return end
    session.busy = true
    local ok, err = pcall(Interface.listCharacters, session)
    session.busy = false
    if not ok then log():error('welcome for player %d failed: %s', session.source, tostring(err)) end
end

-------------------------------------------------------------------------------
-- Chat command
-------------------------------------------------------------------------------

local HELP = {
    '%s list                       show your characters',
    '%s create <first> <last>      create a character',
    '%s select <slot>              play a character',
    '%s delete <slot> <first name> delete a character (asks for confirmation)',
}

local function consoleSessions()
    local ids = {}
    for src in pairs(WLP.sessions) do ids[#ids + 1] = src end
    table.sort(ids)
    local lines = { string.format('%d session(s):', #ids) }
    for _, src in ipairs(ids) do
        local s = WLP.sessions[src]
        local c = s.character
        lines[#lines + 1] = string.format('  player %d  %-20s account %-6d %-10s %s', src, s.name, s.accountId, s.state,
            c and string.format('character %d %s %s', c.id, c.firstName, c.lastName) or '-')
    end
    local pending = 0
    for _ in pairs(WLP.unsaved) do pending = pending + 1 end
    if pending > 0 then lines[#lines + 1] = string.format('%d character(s) waiting for their final save', pending) end
    return lines
end

function Interface.registerCommand(name)
    RegisterCommand(name, function(source, args)
        local src = tonumber(source) or 0
        local sub = args[1] and args[1]:lower() or 'list'
        if src == 0 then
            if sub == 'sessions' then
                for _, l in ipairs(consoleSessions()) do print(l) end
            else
                print(string.format('usage (console): %s sessions', name))
            end
            return
        end
        if not WLP.active() then
            WLP.notify(src, 'Characters are unavailable right now (the players module is not running).')
            return
        end
        if sub == 'list' then
            run(src, 'list', Interface.listCharacters)
        elseif sub == 'create' then
            run(src, 'create', function(session) Interface.createCharacter(session, args[2], args[3]) end)
        elseif sub == 'select' then
            local slot = math.tointeger(tonumber(args[2]))
            if not slot then WLP.notify(src, string.format('usage: /%s select <slot>', name)); return end
            run(src, 'select', function(session) Interface.selectCharacter(session, slot) end)
        elseif sub == 'delete' then
            local slot = math.tointeger(tonumber(args[2]))
            if not slot then WLP.notify(src, string.format('usage: /%s delete <slot> <first name>', name)); return end
            run(src, 'delete', function(session) Interface.deleteCharacter(session, slot, args[3]) end)
        else
            for _, l in ipairs(HELP) do WLP.notify(src, string.format(l, '/' .. name)) end
        end
    end, false)
end

-------------------------------------------------------------------------------
-- Guarded net events (for the UI)
-------------------------------------------------------------------------------

function Interface.registerNetEvents(M)
    local nameNode = { type = 'string', required = true, minLength = 1, maxLength = 32 }
    local slotNode = { type = 'integer', required = true, min = 1, max = 10 }
    local strict = { burst = 3, perSecond = 0.5 }

    M.netEvent('wasteland:players:server:requestCharacters', { rateLimit = { burst = 5, perSecond = 1 } }, function(src)
        run(src, 'list', Interface.listCharacters)
    end)
    M.netEvent('wasteland:players:server:createCharacter', { args = { nameNode, nameNode }, rateLimit = strict }, function(src, first, last)
        run(src, 'create', function(session) Interface.createCharacter(session, first, last) end)
    end)
    M.netEvent('wasteland:players:server:selectCharacter', { args = { slotNode }, rateLimit = strict }, function(src, slot)
        run(src, 'select', function(session) Interface.selectCharacter(session, slot) end)
    end)
    M.netEvent('wasteland:players:server:deleteCharacter', { args = { slotNode, nameNode }, rateLimit = strict }, function(src, slot, confirm)
        run(src, 'delete', function(session) Interface.deleteCharacter(session, slot, confirm) end)
    end)
end

-------------------------------------------------------------------------------
-- Exports (players api 0.1). Sessions take a server id; persistent data
-- takes a characterId.
-------------------------------------------------------------------------------

local function inactive() return not WLP.active() end

--- GetSession(source) -> { source, accountId, license, name, state, characterId } | nil
exports('GetSession', function(src)
    if inactive() then return nil end
    local s = WLP.sessions[tonumber(src) or -1]
    return s and Sessions.describe(s) or nil
end)

--- GetCharacter(source) -> { id, slot, firstName, lastName, source } | nil
exports('GetCharacter', function(src)
    if inactive() then return nil end
    local s = WLP.sessions[tonumber(src) or -1]
    return s and s.character and WLP.describe(s.character) or nil
end)

--- GetCharacterId(source) -> characterId | nil
exports('GetCharacterId', function(src)
    if inactive() then return nil end
    local s = WLP.sessions[tonumber(src) or -1]
    return s and s.character and s.character.id or nil
end)

--- GetSourceByCharacterId(characterId) -> source | nil
exports('GetSourceByCharacterId', function(characterId)
    if inactive() then return nil end
    local c = WLP.loaded[tonumber(characterId) or -1]
    return c and c.source or nil
end)

--- GetOnlineCharacters() -> list of { id, slot, firstName, lastName, source }
exports('GetOnlineCharacters', function()
    local out = {}
    if inactive() then return out end
    for _, c in pairs(WLP.loaded) do out[#out + 1] = WLP.describe(c) end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)

--- GetCharacterData(characterId, key) -> value | nil, err
exports('GetCharacterData', function(characterId, key)
    if inactive() then return nil, 'players module is not running' end
    return Characters.getData(tonumber(characterId) or -1, key)
end)

--- SetCharacterData(characterId, key, value) -> ok, err   (saved by the next save)
exports('SetCharacterData', function(characterId, key, value)
    if inactive() then return false, 'players module is not running' end
    return Characters.setData(tonumber(characterId) or -1, key, value)
end)

--- SaveCharacter(characterId, cb?) -> ok, err (dispatch); cb(ok, err) after the write
exports('SaveCharacter', function(characterId, cb)
    local function answer(ok, err)
        if cb then
            local okCb, cbErr = pcall(cb, ok, err)
            if not okCb then log():warn('SaveCharacter callback failed: %s', tostring(cbErr)) end
        end
    end
    if inactive() then answer(false, 'players module is not running'); return false, 'players module is not running' end
    local char = WLP.loaded[tonumber(characterId) or -1]
    if not char then answer(false, 'character is not loaded'); return false, 'character is not loaded' end
    local requestedBy = GetInvokingResource() or 'unknown'
    Citizen.CreateThread(function()
        local ok, err = Characters.save(char, 'requested by ' .. requestedBy)
        answer(ok, err)
    end)
    return true
end)

--- IsCharacterLoaded(source) -> boolean
exports('IsCharacterLoaded', function(src)
    if inactive() then return false end
    local s = WLP.sessions[tonumber(src) or -1]
    return s ~= nil and s.character ~= nil
end)

return Interface
