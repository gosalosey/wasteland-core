-- wasteland_appearance :: server/main.lua
-- Module "appearance": decides when the character creator opens, validates
-- and stores the result (character data key "appearance"), and sends the
-- stored appearance to the client whenever a character is loaded.
--
-- A player may only submit an appearance when the server opened the
-- creator for them: for a new character (no appearance yet) or when an
-- admin reopened it. Everything submitted is validated (WLA.validate).

local PLAYERS = 'wasteland_players'
local DATA_KEY = 'appearance'

local creatorOpen = {}  -- [characterId] = { source, reason = 'new' | 'admin' }
local commandRegistered = false
local M

local function players() return exports[PLAYERS] end

local function getAppearance(characterId)
    local value, err = players():GetCharacterData(characterId, DATA_KEY)
    if err then return nil, err end
    return value
end

--- Send the client what it needs for its loaded character: the creator
--- (no appearance yet) or the stored appearance to apply.
local function sendTo(src, characterId)
    local appearance, err = getAppearance(characterId)
    if err then
        M.log:error('could not read appearance of character %d: %s', characterId, tostring(err))
        return
    end
    if appearance == nil then
        creatorOpen[characterId] = { source = src, reason = 'new' }
        TriggerClientEvent('wasteland:appearance:client:openCreator', src, { reason = 'new', cancellable = false })
    else
        TriggerClientEvent('wasteland:appearance:client:apply', src, appearance)
    end
end

-- Also for characters restored after a players restart: this resource's
-- client restarted with it and needs the look again (for later respawns).
-- Re-applying is harmless: the model is unchanged, so the ped is not reset.
AddEventHandler('wasteland:players:characterLoaded', function(src, character)
    if not M or not M.active or type(character) ~= 'table' then return end
    sendTo(src, character.id)
end)

AddEventHandler('wasteland:players:characterUnloading', function(_, character)
    if type(character) == 'table' then creatorOpen[character.id] = nil end
end)

--- The admin command: reopen the creator for a player.
local function adminReopen(src, args)
    local cfg = M.config
    if src ~= 0 and not IsPlayerAceAllowed(tostring(src), cfg.adminAce) then
        M.log:warn('player %d tried "%s" without the %s ACE', src, cfg.commandName, cfg.adminAce)
        return
    end
    local target = tonumber(args[1])
    local reply = function(msg)
        if src == 0 then print(msg) else TriggerClientEvent('wasteland:core:client:consoleOutput', src, { msg }) end
    end
    if not target then reply(string.format('usage: %s <server id>', cfg.commandName)); return end
    local characterId = players():GetCharacterId(target)
    if not characterId then reply(string.format('player %d has no loaded character', target)); return end
    local appearance = getAppearance(characterId)
    creatorOpen[characterId] = { source = target, reason = 'admin' }
    TriggerClientEvent('wasteland:appearance:client:openCreator', target, { reason = 'admin', cancellable = true, current = appearance })
    M.log:info('%s reopened the appearance creator for player %d (character %d)',
        src == 0 and 'console' or ('player ' .. src), target, characterId)
    reply(string.format('Opened the appearance creator for player %d.', target))
end

M = Wasteland.DefineModule({
    name = 'appearance',
    version = '0.1.0',
    description = 'Character creator: face, hair, overlays and starter clothing',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', ui = '^0.1.0' },
    config = {
        file = 'appearance.lua',
        optional = true,
        schema = {
            type = 'table',
            fields = {
                commandName = { type = 'string', default = 'appearance', pattern = '^[a-z][a-z0-9_]*$', maxLength = 32,
                    description = 'Admin command that reopens the creator for a player.' },
                adminAce = { type = 'string', default = 'wasteland.admin', minLength = 1,
                    description = 'ACE needed for the admin command.' },
                blockedClothing = {
                    type = 'map', default = {},
                    keys = { type = 'enum', values = WLA.MODELS },
                    values = { type = 'map', keys = { type = 'integer', min = 0, max = 11 },
                        values = { type = 'array', items = { type = 'integer', min = 0, max = 1023 } } },
                    description = 'Clothing drawables players may not pick, per model and component id.',
                },
            },
        },
    },
    onInit = function(M)
        creatorOpen = {}
        if not commandRegistered then
            -- FiveM commands cannot be unregistered; register once per resource start.
            RegisterCommand(M.config.commandName, function(src, args) adminReopen(tonumber(src) or 0, args) end, false)
            commandRegistered = true
        end
        -- Players already playing when this module (re)starts.
        for _, c in ipairs(players():GetOnlineCharacters()) do
            if c.source then sendTo(c.source, c.id) end
        end
        return true
    end,
    onShutdown = function()
        creatorOpen = {}
    end,
})

-------------------------------------------------------------------------------
-- Net events
-------------------------------------------------------------------------------

M.netEvent('wasteland:appearance:server:request', { rateLimit = { burst = 3, perSecond = 0.2 } }, function(src)
    local characterId = players():GetCharacterId(src)
    if characterId then sendTo(src, characterId) end
end)

M.netEvent('wasteland:appearance:server:save', {
    args = { WLA.SCHEMA },
    rateLimit = { burst = 3, perSecond = 0.5 },
}, function(src, submitted)
    local characterId = players():GetCharacterId(src)
    local open = characterId and creatorOpen[characterId]
    if not open or open.source ~= src then
        M.log:warn('player %d submitted an appearance without an open creator; ignored', src)
        TriggerClientEvent('wasteland:appearance:client:saveFailed', src, 'The character creator is not open.')
        return
    end
    local appearance, err = WLA.validate(Wasteland.Schema(), submitted, M.config.blockedClothing)
    if not appearance then
        M.log:warn('player %d submitted an invalid appearance: %s', src, err)
        TriggerClientEvent('wasteland:appearance:client:saveFailed', src, 'This look cannot be saved: ' .. err)
        return
    end
    local ok, setErr = players():SetCharacterData(characterId, DATA_KEY, appearance)
    if not ok then
        TriggerClientEvent('wasteland:appearance:client:saveFailed', src, 'Could not store the look: ' .. tostring(setErr))
        return
    end
    players():SaveCharacter(characterId, function(saved, saveErr)
        if not saved then
            M.log:error('could not save the appearance of character %d: %s', characterId, tostring(saveErr))
            TriggerClientEvent('wasteland:appearance:client:saveFailed', src, 'The server could not save your look. Please try again.')
            return
        end
        creatorOpen[characterId] = nil
        M.log:info('player %d saved the appearance of character %d (%s)', src, characterId, open.reason)
        TriggerClientEvent('wasteland:appearance:client:saved', src, appearance)
    end)
end)

M.netEvent('wasteland:appearance:server:cancel', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    local characterId = players():GetCharacterId(src)
    local open = characterId and creatorOpen[characterId]
    if not open or open.source ~= src then return end
    if open.reason == 'new' then
        -- A new character must have a look; reopen instead.
        TriggerClientEvent('wasteland:appearance:client:openCreator', src, { reason = 'new', cancellable = false })
        return
    end
    creatorOpen[characterId] = nil
    sendTo(src, characterId) -- back to the stored look
end)

-------------------------------------------------------------------------------
-- Exports
-------------------------------------------------------------------------------

--- GetAppearance(characterId) -> appearance (copy) | nil
exports('GetAppearance', function(characterId)
    if not M.active then return nil end
    return getAppearance(tonumber(characterId) or -1)
end)
