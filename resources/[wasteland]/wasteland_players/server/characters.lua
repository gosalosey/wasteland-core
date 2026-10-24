-- wasteland_players :: server/characters.lua
-- Characters: listing, creation, loading, per-module data, saving,
-- unloading and deletion.
--
-- Save strategy (no silent loss, no in-memory fallback):
--   * write-through: create, delete and select write immediately; modules
--     call SaveCharacter after valuable changes and wait for the result
--   * periodic: every saveIntervalSeconds, all loaded characters are saved
--     (position, play time and changed data) in one transaction each
--   * on unload (drop, switch, shutdown): a final save. The account stays
--     locked until that save succeeds, so a reconnect can never load stale
--     data; failed final saves are retried until the database is back.
-- Functions that talk to the database must run in a thread.

local SQL = WLP.SQL
local Characters = {}
WLP.Characters = Characters

local function log() return WLP.M.log end

-------------------------------------------------------------------------------
-- Snapshots
-------------------------------------------------------------------------------

--- Where a loading character goes: its last known position, or - when it
--- has none that can be used (and is not brand new: new characters pick a
--- camp after the creator) - a random safe camp.
function Characters.spawnPosition(char)
    local p = char.position
    local usable = type(p) == 'table' and tonumber(p.x) and tonumber(p.y) and tonumber(p.z)
        and not (math.abs(p.x) < 1 and math.abs(p.y) < 1) and p.z > -100
    if usable then return p end
    local hasLook = false
    if GetResourceState('wasteland_appearance') == 'started' then
        local ok, look = pcall(function() return exports.wasteland_appearance:GetAppearance(char.id) end)
        hasLook = ok and look ~= nil
    end
    if not hasLook then return nil end
    return Characters.safeCamp(char)
end

--- A random safe camp to put a character at, or nil (camps not running).
function Characters.safeCamp(char)
    if GetResourceState('wasteland_camps') ~= 'started' then return nil end
    local ok, camps = pcall(function() return exports.wasteland_camps:GetCamps() end)
    if not ok or type(camps) ~= 'table' then return nil end
    local safe = {}
    for _, c in ipairs(camps) do if c.safe and c.coords then safe[#safe + 1] = c end end
    if #safe == 0 then return nil end
    local c = safe[math.random(1, #safe)]
    log():info('character %d sent to %s (no usable position)', char.id, tostring(c.label))
    return { x = c.coords.x, y = c.coords.y, z = c.coords.z, heading = 0.0 }
end

--- Sample the ped position into the character (only while the player is
--- online and has a ped; a dropped player keeps the last sample).
function Characters.samplePosition(char)
    if not WLP.cfg.savePosition or not char.source then return false end
    -- Not before the client put the ped at the saved spot: until then the
    -- ped stands wherever the game spawned it, and that must not be saved.
    if not char.placed and GetGameTimer() < (char.placedBy or 0) then return false end
    local ped = GetPlayerPed(tostring(char.source))
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local c = GetEntityCoords(ped)
    if not c then return false end
    local x, y, z = tonumber(c.x), tonumber(c.y), tonumber(c.z)
    if not x or not y or not z or (x == 0 and y == 0 and z == 0) then return false end
    char.position = { x = x, y = y, z = z, heading = tonumber(GetEntityHeading(ped)) or 0.0 }
    return true
end

function Characters.playSeconds(char)
    local elapsed = math.floor((GetGameTimer() - char.loadedAt) / 1000)
    if elapsed < 0 then elapsed = 0 end
    return char.basePlaySeconds + elapsed
end

-------------------------------------------------------------------------------
-- Saving
-------------------------------------------------------------------------------

--- Save a character (position, play time, changed data) atomically.
--- Waits for an in-flight save of the same character first. Returns ok, err.
function Characters.save(char, reason)
    while char.saving do Citizen.Wait(50) end
    char.saving = true
    if char.source then Characters.samplePosition(char) end
    local pos = char.position or {}
    local statements = {
        { SQL.saveCharacter, { pos.x, pos.y, pos.z, pos.heading, Characters.playSeconds(char), char.id } },
    }
    local keys = {}
    for key in pairs(char.dirty) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local encoded = char.encoded[key]
        if encoded == nil then
            statements[#statements + 1] = { SQL.deleteCharacterData, { char.id, key } }
        else
            statements[#statements + 1] = { SQL.upsertCharacterData, { char.id, key, encoded } }
        end
        char.dirty[key] = nil
    end
    local ok, err = WDB.transaction(statements)
    if not ok then
        -- Changes made during the save are dirty again anyway; restore ours.
        for _, key in ipairs(keys) do char.dirty[key] = true end
        char.saving = false
        log():error('could not save character %d (%s %s, %s): %s', char.id, char.firstName, char.lastName, tostring(reason), tostring(err))
        return false, err
    end
    char.lastSavedAt = GetGameTimer()
    char.saving = false
    log():debug('saved character %d (%s, %d data key(s))', char.id, tostring(reason), #keys)
    return true
end

--- Fire-and-forget final save used when the module is shutting down and
--- cannot wait. Results are logged by wasteland_database on failure.
function Characters.saveWithoutWaiting(char)
    if char.source then Characters.samplePosition(char) end
    local pos = char.position or {}
    local statements = {
        { SQL.saveCharacter, { pos.x, pos.y, pos.z, pos.heading, Characters.playSeconds(char), char.id } },
    }
    for key in pairs(char.dirty) do
        local encoded = char.encoded[key]
        if encoded == nil then
            statements[#statements + 1] = { SQL.deleteCharacterData, { char.id, key } }
        else
            statements[#statements + 1] = { SQL.upsertCharacterData, { char.id, key, encoded } }
        end
    end
    local id, name = char.id, char.firstName .. ' ' .. char.lastName
    local ok, err = pcall(function()
        exports[WDB.RESOURCE]:Transaction(statements, function(saved, saveErr)
            if not saved then
                print(string.format('^1[Wasteland] [ERROR] [players] final save of character %d (%s) failed: %s^7', id, name, tostring(saveErr)))
            end
        end)
    end)
    return ok, err
end

--- Show pending final saves in the module health (status table).
function Characters.reportUnsaved()
    local n = 0
    for _ in pairs(WLP.unsaved) do n = n + 1 end
    if n > 0 then
        WLP.M.setHealth('degraded', string.format('%d character(s) waiting for their final save (accounts locked)', n))
    elseif WDB.isUp() then
        WLP.M.setHealth('ok')
    end
    return n
end

--- Retry final saves that failed (database was down). Returns remaining count.
function Characters.retryUnsaved()
    local ids = {}
    for id in pairs(WLP.unsaved) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local char = WLP.unsaved[id]
        if char and Characters.save(char, 'retry') then
            WLP.unsaved[id] = nil
            log():info('character %d saved after an earlier failure', id)
            Characters.finishUnload(char)
        end
    end
    if #ids > 0 then return Characters.reportUnsaved() end
    return 0
end

-------------------------------------------------------------------------------
-- Listing and creation
-------------------------------------------------------------------------------

--- Characters of an account: list of { id, slot, firstName, lastName, playSeconds, createdAt, lastPlayed }.
function Characters.list(accountId)
    local rows, err = WDB.query(SQL.listCharacters, { accountId })
    if err then return nil, err end
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = tonumber(r.id), slot = tonumber(r.slot),
            firstName = r.first_name, lastName = r.last_name,
            playSeconds = tonumber(r.play_seconds) or 0,
            createdAt = tonumber(r.created_at), lastPlayed = tonumber(r.last_played),
        }
    end
    return out
end

--- Create a character in the lowest free slot. Returns character summary or nil, err.
function Characters.create(session, firstName, lastName)
    local first, e1 = WLP.validateName('First name', firstName)
    if not first then return nil, e1 end
    local last, e2 = WLP.validateName('Last name', lastName)
    if not last then return nil, e2 end
    local list, err = Characters.list(session.accountId)
    if not list then return nil, 'database error: ' .. tostring(err) end
    if #list >= WLP.cfg.maxCharacters then
        return nil, string.format('you already have the maximum of %d character(s)', WLP.cfg.maxCharacters)
    end
    local used = {}
    for _, c in ipairs(list) do if c.slot then used[c.slot] = true end end
    local slot = 1
    while used[slot] do slot = slot + 1 end
    local spawn = WLP.cfg.defaultSpawn
    local id, insertErr = WDB.insert(SQL.insertCharacter, {
        session.accountId, slot, first, last, spawn.x, spawn.y, spawn.z, WLP.cfg.defaultHeading,
    })
    if insertErr or not id then return nil, 'could not create the character: ' .. tostring(insertErr or 'no id returned') end
    log():info('account %d (%s) created character %d "%s %s" in slot %d', session.accountId, session.name, id, first, last, slot)
    return { id = tonumber(id), slot = slot, firstName = first, lastName = last }
end

-------------------------------------------------------------------------------
-- Loading and unloading
-------------------------------------------------------------------------------

--- Load a character into a session. Returns character or nil, err.
function Characters.load(session, characterId, opts)
    opts = opts or {}
    if WLP.unsaved[characterId] then
        return nil, 'this character is still being saved from your previous session; try again shortly'
    end
    if WLP.loaded[characterId] then
        return nil, 'this character is already loaded'
    end
    local row, err = WDB.single(SQL.loadCharacter, { characterId, session.accountId })
    if err then return nil, 'database error: ' .. tostring(err) end
    if not row then return nil, 'character not found' end
    local dataRows, dataErr = WDB.query(SQL.loadCharacterData, { characterId })
    if dataErr then return nil, 'database error: ' .. tostring(dataErr) end
    local char = {
        id = tonumber(row.id), accountId = tonumber(row.account_id), slot = tonumber(row.slot),
        firstName = row.first_name, lastName = row.last_name,
        basePlaySeconds = tonumber(row.play_seconds) or 0,
        loadedAt = GetGameTimer(),
        data = {}, encoded = {}, dirty = {},
        source = session.source,
        -- After a resource restart the player never left the world: their
        -- ped is where they really are. Otherwise wait for the client.
        placed = opts.restored == true,
        placedBy = GetGameTimer() + 60000, -- a client that never answers: sample after a minute anyway
    }
    if row.pos_x ~= nil and row.pos_y ~= nil and row.pos_z ~= nil then
        char.position = { x = tonumber(row.pos_x), y = tonumber(row.pos_y), z = tonumber(row.pos_z), heading = tonumber(row.heading) or 0.0 }
    end
    for _, d in ipairs(dataRows) do
        local okDecode, value = pcall(json.decode, d.data)
        if not okDecode then
            log():error('character %d: stored data "%s" is not valid JSON (%s); refusing to load the character', characterId, tostring(d.data_key), tostring(value))
            return nil, string.format('stored data "%s" is damaged; ask an admin to restore it from a backup', tostring(d.data_key))
        end
        char.data[d.data_key] = value
        char.encoded[d.data_key] = d.data
    end
    local _, touchErr = WDB.update(SQL.touchCharacter, { characterId })
    if touchErr then return nil, 'database error: ' .. tostring(touchErr) end

    WLP.loaded[char.id] = char
    session.character = char
    session.state = 'active'
    -- Replicated to the player's own client, so a client that restarts with
    -- the resource knows its character is about to be restored.
    Player(session.source).state:set(WLP.STATEBAG_KEY, char.id, true)
    log():info('player %d (%s) loaded character %d "%s %s"%s', session.source, session.name, char.id,
        char.firstName, char.lastName, opts.restored and ' (restored after a resource restart)' or '')
    TriggerEvent('wasteland:players:characterLoaded', session.source, WLP.describe(char), opts.restored == true)
    TriggerClientEvent('wasteland:players:client:characterLoaded', session.source, {
        id = char.id, slot = char.slot, firstName = char.firstName, lastName = char.lastName,
        position = Characters.spawnPosition(char), restored = opts.restored == true,
        -- another module (the spawn choice) places them: the client waits
        hold = char.holdPlacement == true and not opts.restored,
    })
    return char
end

--- Final bookkeeping once a character's last save succeeded.
function Characters.finishUnload(char)
    TriggerEvent('wasteland:players:characterUnloaded', char.lastSource, char.id, char.unloadReason)
    local session = char.lastSession
    if session and session.state == 'unloading' and session.source == nil then
        -- The player already left; the account can now connect again.
        if WLP.byLicense[session.license] == session then WLP.byLicense[session.license] = nil end
        log():debug('released account %d after the final save', session.accountId)
    end
end

--- Unload the session's character: notify modules, final save. The
--- character is removed from the session at once; if the save fails it is
--- kept in WLP.unsaved and retried. Returns ok, err (err = save failed).
function Characters.unload(session, reason)
    local char = session.character
    if not char then return true end
    TriggerEvent('wasteland:players:characterUnloading', char.source, WLP.describe(char), reason)
    session.character = nil
    if session.state == 'active' then session.state = 'connected' end
    WLP.loaded[char.id] = nil
    if char.source then Characters.samplePosition(char) end
    char.lastSource, char.lastSession, char.unloadReason = char.source, session, reason
    char.source = nil
    if WLP.isOnline(session.source) then
        Player(session.source).state:set(WLP.STATEBAG_KEY, nil, true)
    end
    WLP.unsaved[char.id] = char
    local ok, err = Characters.save(char, 'unload: ' .. tostring(reason))
    if ok then
        WLP.unsaved[char.id] = nil
        log():info('character %d "%s %s" unloaded (%s)', char.id, char.firstName, char.lastName, tostring(reason))
        Characters.finishUnload(char)
        return true
    end
    log():error('character %d "%s %s" could not be saved on unload (%s); it will be retried and the account stays locked until it succeeds',
        char.id, char.firstName, char.lastName, tostring(reason))
    Characters.reportUnsaved()
    return false, err
end

--- Soft-delete one of the account's characters (not the loaded one).
function Characters.delete(session, characterId)
    if session.character and session.character.id == characterId then
        return nil, 'you cannot delete the character you are playing; switch characters first'
    end
    local affected, err = WDB.update(SQL.softDeleteCharacter, { characterId, session.accountId })
    if err then return nil, 'database error: ' .. tostring(err) end
    if not affected or affected < 1 then return nil, 'character not found' end
    log():info('account %d (%s) deleted character %d', session.accountId, session.name, characterId)
    return true
end

-------------------------------------------------------------------------------
-- Per-module character data
-------------------------------------------------------------------------------

function Characters.getData(characterId, key)
    local char = WLP.loaded[characterId]
    if not char then return nil, 'character is not loaded' end
    return WLP.copy(char.data[key])
end

--- Set data for a loaded character. Marked dirty; written by the next save
--- (call SaveCharacter for write-through). nil removes the key.
function Characters.setData(characterId, key, value)
    if type(key) ~= 'string' or #key > 64 or not key:match(WLP.DATA_KEY_PATTERN) then
        return false, 'data key must match [a-z][a-z0-9_.:-]* (max 64 characters)'
    end
    local char = WLP.loaded[characterId]
    if not char then return false, 'character is not loaded' end
    if value == nil then
        char.data[key], char.encoded[key] = nil, nil
        char.dirty[key] = true
        return true
    end
    local okEncode, encoded = pcall(json.encode, value)
    if not okEncode or type(encoded) ~= 'string' then
        return false, 'value cannot be stored as JSON: ' .. tostring(encoded)
    end
    if #encoded > WLP.cfg.maxCharacterDataBytes then
        return false, string.format('value is %d bytes; the limit is %d (players.maxCharacterDataBytes)', #encoded, WLP.cfg.maxCharacterDataBytes)
    end
    char.data[key] = WLP.copy(value)
    char.encoded[key] = encoded
    char.dirty[key] = true
    return true
end

return Characters
