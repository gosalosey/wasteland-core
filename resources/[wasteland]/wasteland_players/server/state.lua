-- wasteland_players :: server/state.lua
-- Shared state and small helpers for the players module.
--
-- Identity model:
--   account    one per Rockstar license (wl_accounts); persistent
--   session    one per connected player (keyed by server id `source`);
--              lives from accepted connection to drop
--   character  one of the account's slots (wl_characters); persistent.
--              At most one character is loaded per session.
-- Persistent APIs take a characterId; session APIs take a source.

WLP = WLP or {}

WLP.sessions = {}   -- [source] = session
WLP.byLicense = {}  -- [license] = session (incl. sessions still saving after a drop)
WLP.pending = {}    -- [license] = { accountId, name, expiresAt } accepted, not yet joined
WLP.loaded = {}     -- [characterId] = character (loaded in an active session)
WLP.unsaved = {}    -- [characterId] = character whose final save has not succeeded yet

WLP.M = nil         -- module handle (set at init)
WLP.cfg = nil       -- validated config (set at init)
WLP.token = nil     -- changes on every init/shutdown; threads exit when it changes

WLP.STATEBAG_KEY = 'wlCharacterId'
WLP.DATA_KEY_PATTERN = '^[a-z][a-z0-9_.:%-]*$'

function WLP.active()
    return WLP.M ~= nil and WLP.M.active and WLP.cfg ~= nil
end

function WLP.log()
    return WLP.M.log
end

--- Deep copy plain data (values that crossed an export are copies already,
--- but values we hand out must not alias our state).
function WLP.copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, val in pairs(v) do out[WLP.copy(k)] = WLP.copy(val) end
    return out
end

--- The configured identifier (e.g. "license:abc...") or nil.
function WLP.identifierOf(src)
    local kind = WLP.cfg and WLP.cfg.identifier or 'license'
    local id = GetPlayerIdentifierByType(tostring(src), kind)
    if id == nil or id == '' then return nil end
    -- Testing only (duplicateSession = 'test_second_account'): a second game
    -- on the same Rockstar account plays as a separate account ("...:test2"),
    -- so one person can test with two players.
    if WLP.cfg and WLP.cfg.duplicateSession == 'test_second_account' then
        local first = WLP.byLicense and WLP.byLicense[id]
        if first and first.source and first.source ~= tonumber(src) and WLP.isOnline(first.source) then
            return id .. ':test2'
        end
    end
    return id
end

--- Identifiers stored for admin lookup (never IP addresses).
function WLP.storedIdentifiers(src)
    local out = {}
    for _, id in ipairs(GetPlayerIdentifiers(tostring(src)) or {}) do
        if type(id) == 'string' and not id:match('^ip:') then out[#out + 1] = id end
    end
    table.sort(out)
    return table.concat(out, ',')
end

function WLP.isOnline(src)
    return src ~= nil and GetPlayerName(tostring(src)) ~= nil
end

--- Message to a player: chat when the CFX chat resource runs, else F8.
function WLP.notify(src, message)
    if not src or src <= 0 then
        print(message)
        return
    end
    if GetResourceState('chat') == 'started' then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Wasteland', message } })
    else
        TriggerClientEvent('wasteland:core:client:consoleOutput', src, { message })
    end
end

--- Validate a character name part. Returns cleaned name or nil, err.
function WLP.validateName(label, value)
    local n = WLP.cfg.names
    if type(value) ~= 'string' then return nil, label .. ' is required' end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if #value < n.minLength or #value > n.maxLength then
        return nil, string.format('%s must be %d to %d characters long', label, n.minLength, n.maxLength)
    end
    if not value:match(n.pattern) then
        return nil, label .. ' contains characters that are not allowed'
    end
    return value
end

--- Public, copy-safe description of a character.
function WLP.describe(char)
    return {
        id = char.id,
        slot = char.slot,
        firstName = char.firstName,
        lastName = char.lastName,
        source = char.source,
    }
end

return WLP
