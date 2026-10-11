-- wasteland_players :: server/sessions.lua
-- Player sessions: connection admission (license, database, duplicate
-- sessions), joining, dropping and restoring sessions after this resource
-- restarts while players stay connected.
--
-- Simultaneous sessions for one account (same license) are never allowed
-- to overlap: with duplicateSession = 'kick_old' the old session is dropped
-- and the new connection waits until the old character's final save has
-- completed; with 'reject_new' the new connection is refused.

local SQL = WLP.SQL
local Characters = WLP.Characters
local Sessions = {}
WLP.Sessions = Sessions

local PENDING_TTL_MS = 120000

-- Admission checks other modules add (bans): [name] = { fn, owner }.
-- fn({ license, name, identifiers }) returns nil to allow or a message to refuse.
WLP.admissionChecks = WLP.admissionChecks or {}

local function runAdmissionChecks(src, license, name)
    local info = { license = license, name = name, identifiers = GetPlayerIdentifiers(tostring(src)) or {} }
    local names = {}
    for n in pairs(WLP.admissionChecks) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        local check = WLP.admissionChecks[n]
        if GetResourceState(check.owner) ~= 'started' then
            WLP.admissionChecks[n] = nil
        else
            local ok, refusal = pcall(check.fn, info)
            if not ok then
                WLP.M.log:error('admission check "%s" failed: %s (letting %s in)', n, tostring(refusal), tostring(name))
            elseif type(refusal) == 'string' and refusal ~= '' then
                WLP.M.log:info('admission check "%s" refused %s (%s)', n, tostring(name), license)
                return refusal
            end
        end
    end
    return nil
end

local function log() return WLP.M.log end

--- Upsert the account row and return its id (thread only).
function Sessions.upsertAccount(license, name, identifiers)
    local _, err = WDB.insert(SQL.upsertAccount, { license, name, identifiers })
    if err then return nil, err end
    local id, idErr = WDB.scalar(SQL.accountIdByLicense, { license })
    if idErr then return nil, idErr end
    if not id then return nil, 'account row missing after upsert' end
    return tonumber(id)
end

local function newSession(src, license, accountId, name)
    local session = {
        source = src, license = license, accountId = accountId, name = name,
        state = 'connected', joinedAt = GetGameTimer(), character = nil, busy = false,
    }
    WLP.sessions[src] = session
    WLP.byLicense[license] = session
    log():info('session started: player %d (%s), account %d', src, name, accountId)
    TriggerEvent('wasteland:players:sessionStarted', src, accountId)
    return session
end

--- Public, copy-safe description of a session.
function Sessions.describe(session)
    return {
        source = session.source, accountId = session.accountId, license = session.license,
        name = session.name, state = session.state,
        characterId = session.character and session.character.id or nil,
    }
end

-------------------------------------------------------------------------------
-- Connecting
-------------------------------------------------------------------------------

-- Wait until no session holds this license. Returns true or false on timeout.
local function waitForRelease(license, token, deferrals)
    local deadline = GetGameTimer() + WLP.cfg.sessionReleaseTimeoutSeconds * 1000
    local told = false
    while WLP.byLicense[license] ~= nil do
        if WLP.token ~= token then return false end
        if GetGameTimer() >= deadline then return false end
        if not told then
            deferrals.update('Saving your previous session, please wait...')
            told = true
        end
        Citizen.Wait(100)
    end
    return true
end

local function admit(src, name, deferrals, token)
    if not WLP.active() or WLP.token ~= token then
        return 'The server is starting up. Please try again in a moment.'
    end
    local license = WLP.identifierOf(src)
    if not license then
        return string.format('Could not verify your Rockstar account (%s identifier missing). Restart FiveM and try again.', WLP.cfg.identifier)
    end
    if not WDB.isUp() then
        return 'The server database is unavailable. Please try again in a few minutes.'
    end
    local refusal = runAdmissionChecks(src, license, name)
    if refusal then return refusal end

    local existing = WLP.byLicense[license]
    if existing and existing.source and not WLP.isOnline(existing.source) and existing.state ~= 'unloading' then
        -- Stale session (the player is gone but no drop event reached us).
        log():warn('account %d had a stale session (player %d is no longer online); closing it', existing.accountId, existing.source)
        Sessions.finish(existing, 'stale session')
    end
    if existing then
        if existing.source and WLP.isOnline(existing.source) and existing.state ~= 'unloading' then
            if WLP.cfg.duplicateSession == 'reject_new' then
                log():warn('refused second connection for account %d (%s): already connected as player %d', existing.accountId, name, existing.source)
                return 'This account is already connected to the server.'
            end
            log():warn('account %d (%s) connected again; dropping the previous session (player %d)', existing.accountId, name, existing.source)
            DropPlayer(tostring(existing.source), 'You connected to this server from another session.')
        end
        if not waitForRelease(license, token, deferrals) then
            if WLP.token ~= token then return 'The server is restarting. Please try again in a moment.' end
            return 'Your previous session is still being saved. Please try again in a minute.'
        end
    end

    deferrals.update('Loading your account...')
    local accountId, err = Sessions.upsertAccount(license, name, WLP.storedIdentifiers(src))
    if not accountId then
        log():error('could not load account for %s (%s): %s', name, license, tostring(err))
        return 'The server could not load your account. Please try again shortly.'
    end
    if WLP.token ~= token then return 'The server is restarting. Please try again in a moment.' end
    WLP.pending[license] = { accountId = accountId, name = name, expiresAt = GetGameTimer() + PENDING_TTL_MS }
    return nil
end

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    if not WLP.active() then return end -- module down: core status shows why
    deferrals.defer()
    local token = WLP.token
    Citizen.CreateThread(function()
        Citizen.Wait(0)
        deferrals.update('Checking your account...')
        local ok, rejection = pcall(admit, src, name, deferrals, token)
        if not ok then
            WLP.M.log:error('error while admitting %s: %s', tostring(name), tostring(rejection))
            rejection = 'The server could not process your connection. Please try again.'
        end
        -- FiveM accepts only done() with NO argument: done(nil) rejects the
        -- player with "Unknown error" (runtime finding R2.5).
        if rejection then
            deferrals.done(rejection)
        else
            deferrals.done()
        end
    end)
end)

-------------------------------------------------------------------------------
-- Joining and dropping
-------------------------------------------------------------------------------

--- Create the session for a joined player (thread only).
function Sessions.start(src)
    local license = WLP.identifierOf(src)
    if not license then
        log():error('player %d joined without a %s identifier; no session', src, WLP.cfg.identifier)
        return nil
    end
    local name = GetPlayerName(tostring(src)) or ('player ' .. src)
    local p = WLP.pending[license]
    WLP.pending[license] = nil
    if p and p.expiresAt < GetGameTimer() then p = nil end
    local accountId = p and p.accountId or nil
    if not accountId then
        local err
        accountId, err = Sessions.upsertAccount(license, name, WLP.storedIdentifiers(src))
        if not accountId then
            log():error('could not create a session for player %d (%s): %s', src, name, tostring(err))
            return nil
        end
    end
    local existing = WLP.byLicense[license]
    if existing and existing ~= WLP.sessions[src] then
        log():error('player %d (%s) joined while account %d still has a session (player %s, %s); refusing',
            src, name, accountId, tostring(existing.source), existing.state)
        DropPlayer(tostring(src), 'Your previous session is still active. Please reconnect in a minute.')
        return nil
    end
    return newSession(src, license, accountId, name)
end

AddEventHandler('playerJoining', function()
    local src = tonumber(source)
    if not src or not WLP.active() then return end
    local token = WLP.token
    Citizen.CreateThread(function()
        if WLP.token ~= token then return end
        local session = Sessions.start(src)
        if session then WLP.Interface.welcome(session) end
    end)
end)

--- End a session (player left). Thread only.
function Sessions.finish(session, reason)
    session.state = 'unloading'
    WLP.sessions[session.source] = nil
    local src = session.source
    session.source = nil
    if session.character then session.character.source = src end
    local ok = Characters.unload(session, reason)
    if ok and WLP.byLicense[session.license] == session then
        WLP.byLicense[session.license] = nil
    end
    log():info('session ended: player %d (%s), account %d (%s)%s', src, session.name, session.accountId, tostring(reason),
        ok and '' or '; final save pending, account locked until it succeeds')
    TriggerEvent('wasteland:players:sessionEnded', src, session.accountId, reason)
end

AddEventHandler('playerDropped', function(reason)
    local src = tonumber(source)
    local session = src and WLP.sessions[src]
    if not session then return end
    Citizen.CreateThread(function()
        Sessions.finish(session, 'dropped: ' .. tostring(reason))
    end)
end)

-------------------------------------------------------------------------------
-- Restore after a resource restart
-------------------------------------------------------------------------------

--- Rebuild sessions for players who stayed connected while this resource
--- restarted, and reload their character (remembered in a player state
--- bag, which outlives the resource). Thread only.
function Sessions.restore(token)
    local players = GetPlayers()
    if #players == 0 then return 0 end
    local restoreList = {}
    for _, s in ipairs(players) do
        local src = tonumber(s)
        if src and not WLP.sessions[src] then
            local session = Sessions.start(src)
            if session then
                local charId = tonumber(Player(src).state[WLP.STATEBAG_KEY])
                restoreList[#restoreList + 1] = { session = session, charId = charId }
            end
            if WLP.token ~= token then return 0 end
        end
    end
    local withCharacter = 0
    for _, r in ipairs(restoreList) do if r.charId then withCharacter = withCharacter + 1 end end
    if withCharacter > 0 and WLP.cfg.restoreDelayMs > 0 then
        -- Give the final saves issued by the previous instance time to land
        -- before reading the same rows back.
        Citizen.Wait(WLP.cfg.restoreDelayMs)
        if WLP.token ~= token then return 0 end
    end
    local restored = 0
    for _, r in ipairs(restoreList) do
        if r.charId and WLP.isOnline(r.session.source) then
            local char, err = Characters.load(r.session, r.charId, { restored = true })
            if char then
                restored = restored + 1
            else
                log():error('could not restore character %d for player %d: %s', r.charId, r.session.source, tostring(err))
                Player(r.session.source).state:set(WLP.STATEBAG_KEY, nil, true)
                WLP.notify(r.session.source, 'Your character could not be reloaded: ' .. tostring(err))
            end
        elseif not r.charId then
            WLP.Interface.welcome(r.session)
        end
    end
    log():info('restored %d session(s) (%d character(s)) after a restart', #restoreList, restored)
    return restored
end

return Sessions
