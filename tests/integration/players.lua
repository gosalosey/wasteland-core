-- wasteland_players: accounts, sessions, characters and persistence,
-- including reconnects, simultaneous sessions, database outages, resource
-- restarts and shutdown. Runs on the simulated server + MemoryDB.

local BASE = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = [[return { saveIntervalSeconds = 10, positionSampleSeconds = 1, sessionReleaseTimeoutSeconds = 3,
        restoreDelayMs = 200, maxCharacters = 2, maxCharacterDataBytes = 2048 }]],
}

-- Observer module: records players events and offers data helpers.
local OBSERVER = [[
UNLOAD_WRITE = false
Wasteland.DefineModule({ name = 'obs', version = '1.0.0', core = '^1.1.0', dependencies = { players = '^0.1.0' } })
AddEventHandler('wasteland:players:sessionStarted', function(src, accountId) track('session ' .. src .. ' ' .. accountId) end)
AddEventHandler('wasteland:players:sessionEnded', function(src, accountId) track('ended ' .. src .. ' ' .. accountId) end)
AddEventHandler('wasteland:players:characterLoaded', function(src, char, restored)
    track('loaded ' .. src .. ' ' .. char.id .. ' ' .. tostring(restored))
end)
AddEventHandler('wasteland:players:characterUnloading', function(src, char, reason)
    track('unloading ' .. tostring(src) .. ' ' .. char.id)
    if UNLOAD_WRITE then exports.wasteland_players:SetCharacterData(char.id, 'obs', { lastWords = 'bye' }) end
end)
AddEventHandler('wasteland:players:characterUnloaded', function(src, id) track('unloaded ' .. tostring(src) .. ' ' .. id) end)
exports('SetUnloadWrite', function(v) UNLOAD_WRITE = v end)
exports('Save', function(cid)
    exports.wasteland_players:SaveCharacter(cid, function(ok, err) track('saved ' .. cid .. ' ' .. tostring(ok) .. ' ' .. tostring(err)) end)
end)
]]

local function merge(a, b)
    local out = {}
    for k, v in pairs(a) do out[k] = v end
    for k, v in pairs(b or {}) do out[k] = v end
    return out
end

local function world(extra)
    local server = newServer({ config = merge(BASE, extra) })
    addModule(server, 'fx_obs', OBSERVER, { 'wasteland_players' })
    boot(server, { 'wasteland_players', 'fx_obs' })
    return server
end

local function join(server, opts)
    local id, err, conn = server:connectAndJoin(opts or { name = 'Alice', license = 'alice' })
    server:advance(200)
    return id, err, conn
end

local function cmd(server, id, line)
    server:command(id, line)
    server:advance(300)
end

-- Every message shown to a player (chat is not running in tests, so they
-- arrive as F8 console output).
local function messages(server, id)
    local out = {}
    for _, e in ipairs(server:clientEventsFor(id, 'wasteland:core:client:consoleOutput')) do
        for _, l in ipairs(e.args[1]) do out[#out + 1] = l end
    end
    return out
end

local function last(list) return list[#list] end
local function obs(server) return server:export('fx_obs', 'Calls') end
local function P(server, fn, ...) return server:export('wasteland_players', fn, ...) end
local function chars(server) return server.db.backend.data.wl_characters end
local function dataRow(server, cid, key) return server.db.backend.data.wl_character_data[cid .. '|' .. key] end

-- Alice joins, creates "John Doe" and plays it.
local function playing(extra)
    local server = world(extra)
    local id = join(server)
    cmd(server, id, 'character create John Doe')
    cmd(server, id, 'character select 1')
    server:clientEvent(id, 'wasteland:players:server:placed') -- the client placed the ped
    return server, id
end

describe('players module startup', function()
    it('applies its three migrations once', function()
        local server = world()
        expect(states(server).players).toBe('running')
        local versions = {}
        for _, m in ipairs(server.db.backend.data.wl_migrations) do
            if m.module_name == 'players' then versions[#versions + 1] = m.version end
        end
        expect(versions).toEqual({ 1, 2, 3 })
        local ddl = #server.db.backend.ddl
        server:restart('wasteland_players')
        server:advance(3000)
        expect(states(server).players).toBe('running')
        expect(#server.db.backend.ddl).toBe(ddl)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('connecting', function()
    it('creates the account and a session, storing identifiers except the IP', function()
        local server = world()
        local id = join(server, { name = 'Alice', license = 'alice', identifiers = { 'ip:1.2.3.4', 'discord:42' } })
        expect(id).toBe(1)
        local account = server.db.backend.data.wl_accounts[1]
        expect(account.license).toBe('license:alice')
        expect(account.identifiers).toBe('discord:42,license:alice')
        local s = P(server, 'GetSession', id)
        expect(s.accountId).toBe(1)
        expect(s.state).toBe('connected')
        expect(obs(server)).toContain('session 1 1')
        expect(last(messages(server, id))).toContain('You have no characters. Create one with: /character create')
    end)

    it('refuses players without a license identifier', function()
        local server = world()
        local id, err = join(server, { name = 'Nobody', license = false })
        expect(id).toBe(nil)
        expect(err).toContain('Could not verify your Rockstar account')
    end)

    it('refuses connections while the database is down', function()
        local server = world()
        server.db.hang = true
        server:advance(4000)
        local id, err = join(server)
        expect(id).toBe(nil)
        expect(err).toContain('database is unavailable')
    end)

    it('updates the name of a returning account instead of creating a new one', function()
        local server = world()
        local id = join(server)
        server:dropPlayer(id); server:advance(500)
        join(server, { name = 'Alice2', license = 'alice' })
        local count = 0
        for _ in pairs(server.db.backend.data.wl_accounts) do count = count + 1 end
        expect(count).toBe(1)
        expect(server.db.backend.data.wl_accounts[1].name).toBe('Alice2')
    end)
end)

describe('characters', function()
    local server = world()
    local id = join(server)

    it('creates characters in the lowest free slot with validated names', function()
        cmd(server, id, 'character create John Doe')
        expect(last(messages(server, id))).toBe('Created John Doe in slot 1. Play it with: /character select 1')
        cmd(server, id, 'character create J0hn Doe')
        expect(last(messages(server, id))).toContain('First name contains characters that are not allowed')
        cmd(server, id, 'character create X Doe')
        expect(last(messages(server, id))).toContain('First name must be 2 to 20 characters long')
        cmd(server, id, "character create Mary-Jane O'Neil")
        expect(last(messages(server, id))).toContain("Created Mary-Jane O'Neil in slot 2")
    end)

    it('enforces the slot limit', function()
        cmd(server, id, 'character create Third One')
        expect(last(messages(server, id))).toContain('maximum of 2 character(s)')
    end)

    it('lists characters', function()
        cmd(server, id, 'character list')
        local m = messages(server, id)
        expect(m).toContain('Your characters (2 of 2):')
        expect(m).toContain('  [1] John Doe - played 0h 00m')
    end)

    it('loads a character: events, exports, state bag and spawn position', function()
        cmd(server, id, 'character select 1')
        server:clientEvent(id, 'wasteland:players:server:placed') -- the client placed the ped
        expect(last(messages(server, id))).toBe('You are now playing John Doe.')
        expect(obs(server)).toContain('loaded 1 1 false')
        expect(P(server, 'GetCharacterId', id)).toBe(1)
        expect(P(server, 'GetSourceByCharacterId', 1)).toBe(id)
        expect(P(server, 'IsCharacterLoaded', id)).toBe(true)
        expect(server.players[id].state.wlCharacterId).toBe(1)
        local ev = last(server:clientEventsFor(id, 'wasteland:players:client:characterLoaded'))
        expect(ev.args[1].position.x).toBe(318.27)
        expect(ev.args[1].firstName).toBe('John')
    end)

    it('refuses to reselect or delete the active character', function()
        cmd(server, id, 'character select 1')
        server:clientEvent(id, 'wasteland:players:server:placed') -- the client placed the ped
        expect(last(messages(server, id))).toContain('already playing John Doe')
        cmd(server, id, 'character delete 1 John')
        expect(last(messages(server, id))).toContain('cannot delete the character you are playing')
    end)

    it('deletes only after the first name is confirmed (soft delete)', function()
        cmd(server, id, 'character delete 2')
        expect(last(messages(server, id))).toContain("confirm with: /character delete 2 Mary-Jane")
        cmd(server, id, 'character delete 2 mary-jane')
        expect(last(messages(server, id))).toContain("Deleted Mary-Jane O'Neil")
        local row = chars(server)[2]
        expect(row.deleted_at ~= nil).toBe(true)
        expect(row.slot).toBe(nil)
        cmd(server, id, 'character create New Person')
        expect(last(messages(server, id))).toContain('in slot 2')
    end)

    it('switches characters, saving the previous one first', function()
        P(server, 'SetCharacterData', 1, 'notes', { text = 'switch' })
        cmd(server, id, 'character select 2')
        server:clientEvent(id, 'wasteland:players:server:placed') -- the client placed the ped
        expect(last(messages(server, id))).toBe('You are now playing New Person.')
        expect(obs(server)).toContain('unloaded 1 1')
        expect(dataRow(server, 1, 'notes').data).toBe('{"text":"switch"}')
        expect(P(server, 'GetCharacterId', id)).toBe(3)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('character data', function()
    local server, id = playing()

    it('stores per-module values and returns copies', function()
        expect(P(server, 'SetCharacterData', 1, 'survival', { hunger = 80, thirst = 60 })).toBe(true)
        local v = P(server, 'GetCharacterData', 1, 'survival')
        expect(v.hunger).toBe(80)
    end)

    it('rejects bad keys, oversized values and unloaded characters', function()
        local ok1, e1 = P(server, 'SetCharacterData', 1, 'Bad Key', 1)
        expect(ok1).toBe(false); expect(e1).toContain('data key must match')
        local ok2, e2 = P(server, 'SetCharacterData', 1, 'big', { blob = string.rep('x', 3000) })
        expect(ok2).toBe(false); expect(e2).toContain('the limit is 2048')
        local ok3, e3 = P(server, 'SetCharacterData', 99, 'x', 1)
        expect(ok3).toBe(false); expect(e3).toContain('not loaded')
    end)

    it('writes through on SaveCharacter and reports the result', function()
        server:export('fx_obs', 'Save', 1)
        server:advance(300)
        expect(obs(server)).toContain('saved 1 true nil')
        expect(dataRow(server, 1, 'survival').data).toBe('{"hunger":80,"thirst":60}')
    end)

    it('saves position and play time periodically', function()
        server.players[id].coords = { x = 10.5, y = 20.25, z = 30.0 }
        server.players[id].heading = 90.0
        server:advance(10500)
        local row = chars(server)[1]
        expect(row.pos_x).toBe(10.5)
        expect(row.heading).toBe(90.0)
        expect(row.play_seconds > 0).toBe(true)
    end)

    it('removes a key that was set to nil', function()
        P(server, 'SetCharacterData', 1, 'survival', nil)
        server:export('fx_obs', 'Save', 1)
        server:advance(300)
        expect(dataRow(server, 1, 'survival')).toBe(nil)
    end)

    it('reports a failed write-through save to the caller', function()
        server.db.backend.failPattern = 'wl_character_data'
        P(server, 'SetCharacterData', 1, 'x', 1)
        server:export('fx_obs', 'Save', 1)
        server:advance(300)
        expect(last(obs(server))).toContain('saved 1 false')
        server.db.backend.failPattern = nil
    end)
end)

describe('leaving and reconnecting', function()
    local server, id = playing()
    P(server, 'SetCharacterData', 1, 'survival', { hunger = 42 })
    server:export('fx_obs', 'SetUnloadWrite', true)
    server.players[id].coords = { x = 1.0, y = 2.0, z = 3.0 }
    server:advance(1100) -- position sample

    it('saves on drop, including data modules write while it unloads', function()
        server:dropPlayer(id, 'Exiting')
        server:advance(500)
        expect(obs(server)).toContain('unloading 1 1')
        expect(obs(server)).toContain('unloaded 1 1')
        expect(obs(server)).toContain('ended 1 1')
        expect(chars(server)[1].pos_x).toBe(1.0)
        expect(dataRow(server, 1, 'survival').data).toBe('{"hunger":42}')
        expect(dataRow(server, 1, 'obs').data).toBe('{"lastWords":"bye"}')
        expect(P(server, 'GetSession', id)).toBe(nil)
    end)

    it('lets the player back in and restores the saved state', function()
        local id2 = join(server)
        expect(id2).toBe(2)
        cmd(server, id2, 'character select 1')
        server:clientEvent(id2, 'wasteland:players:server:placed') -- the client placed the ped
        expect(P(server, 'GetCharacterData', 1, 'survival').hunger).toBe(42)
        local ev = last(server:clientEventsFor(id2, 'wasteland:players:client:characterLoaded'))
        expect(ev.args[1].position.x).toBe(1.0)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('simultaneous sessions', function()
    it('kick_old: drops the old session, saves it, then admits the new one', function()
        local server, id = playing()
        P(server, 'SetCharacterData', 1, 'survival', { hunger = 7 })
        local id2, err, conn = join(server, { name = 'Alice', license = 'alice' })
        expect(err).toBe(nil)
        expect(server.dropped[1].id).toBe(id)
        expect(server.dropped[1].reason).toContain('another session')
        expect(conn.updates).toContain('Saving your previous session, please wait...')
        expect(dataRow(server, 1, 'survival').data).toBe('{"hunger":7}')
        expect(P(server, 'GetSession', id2).accountId).toBe(1)
        expect(P(server, 'GetSession', id)).toBe(nil)
    end)

    it('reject_new: refuses the second connection and keeps the first', function()
        local server, id = playing({ ['players.lua'] = 'return { duplicateSession = "reject_new", maxCharacters = 2 }' })
        local id2, err = join(server, { name = 'Alice', license = 'alice' })
        expect(id2).toBe(nil)
        expect(err).toContain('already connected')
        expect(P(server, 'GetCharacterId', id)).toBe(1)
        expect(#server.dropped).toBe(0)
    end)

    it('keeps the account locked while a final save is failing, then releases it', function()
        local server, id = playing()
        P(server, 'SetCharacterData', 1, 'survival', { hunger = 99 })
        server.db.backend.failPattern = 'UPDATE wl_characters SET pos_x'
        server:dropPlayer(id)
        server:advance(500)
        expect(#server:lines('final save pending, account locked until it succeeds')).toBe(1)
        local status = server:export('wasteland_core', 'GetModuleStatus', 'players')
        expect(status.health).toBe('degraded')
        expect(status.healthDetail).toContain('1 character(s) waiting for their final save')

        local _, err, conn = join(server)
        expect(err).toContain('still being saved')
        expect(conn.updates).toContain('Saving your previous session, please wait...')

        server.db.backend.failPattern = nil
        server:advance(10500) -- next periodic run retries
        expect(#server:lines('character 1 saved after an earlier failure')).toBe(1)
        expect(server:export('wasteland_core', 'GetModuleStatus', 'players').health).toBe('ok')
        expect(dataRow(server, 1, 'survival').data).toBe('{"hunger":99}')
        local id3 = join(server)
        expect(id3 ~= nil).toBe(true)
    end)
end)

describe('database outage while playing', function()
    local server, id = playing()
    server.db.hang = true
    server:advance(4000)

    it('marks players degraded and refuses database work with a clear message', function()
        local s = server:export('wasteland_core', 'GetModuleStatus', 'players')
        expect(s.health).toBe('degraded')
        expect(s.healthDetail).toContain('database unavailable')
        cmd(server, id, 'character create Other Guy')
        expect(last(messages(server, id))).toContain('Could not create the character')
    end)

    it('skips periodic saves while down and saves everyone when it is back', function()
        P(server, 'SetCharacterData', 1, 'survival', { hunger = 5 })
        server:advance(10000)
        expect(#server:lines('periodic save skipped for 1 character(s): database unavailable') > 0).toBe(true)
        server.db.hang = false
        server:advance(3000)
        expect(server:export('wasteland_core', 'GetModuleStatus', 'players').health).toBe('ok')
        expect(dataRow(server, 1, 'survival').data).toBe('{"hunger":5}')
    end)
end)

describe('restart wasteland_players while players stay connected', function()
    local server, id = playing()
    P(server, 'SetCharacterData', 1, 'survival', { hunger = 11 })
    server:restart('wasteland_players')
    server:advance(2000)

    it('issues final saves, then restores sessions and characters', function()
        expect(#server:lines('issued final saves for 1 character(s) (resource_stop)')).toBe(1)
        expect(states(server).players).toBe('running')
        expect(P(server, 'GetCharacterId', id)).toBe(1)
        expect(P(server, 'GetCharacterData', 1, 'survival').hunger).toBe(11)
        expect(#server:lines('restored 1 session(s) (1 character(s)) after a restart')).toBe(1)
    end)

    it('restarts dependent module resources (observer) and tells them about the restore', function()
        expect(server.resources.fx_obs.state).toBe('started')
        expect(obs(server)).toContain('loaded 1 1 true')
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('restart wasteland_database while players stay connected', function()
    it('brings players back and restores the character', function()
        local server, id = playing()
        P(server, 'SetCharacterData', 1, 'survival', { hunger = 3 })
        server:restart('wasteland_database')
        server:advance(4000)
        expect(states(server).database).toBe('running')
        expect(states(server).players).toBe('running')
        expect(P(server, 'GetCharacterId', id)).toBe(1)
        expect(P(server, 'GetCharacterData', 1, 'survival').hunger).toBe(3)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('server shutdown announced by txAdmin', function()
    it('issues final saves for every loaded character', function()
        local server = playing()
        P(server, 'SetCharacterData', 1, 'survival', { hunger = 1 })
        server:txAdminShutdown()
        server:advance(500)
        expect(#server:lines('issued final saves for 1 character(s) (server_shutdown)')).toBe(1)
        expect(dataRow(server, 1, 'survival').data).toBe('{"hunger":1}')
    end)
end)

describe('net events for the character UI', function()
    local server = world()
    local id = join(server)

    it('answers requestCharacters with the list', function()
        server:clientEvent(id, 'wasteland:players:server:requestCharacters')
        server:advance(300)
        local ev = last(server:clientEventsFor(id, 'wasteland:players:client:characters'))
        expect(ev.args[1].maxCharacters).toBe(2)
        expect(#ev.args[1].characters).toBe(0)
    end)

    it('creates and selects through validated events', function()
        server:clientEvent(id, 'wasteland:players:server:createCharacter', 'Ann', 'Lee')
        server:advance(300)
        server:advance(2000) -- rate limit: strict events refill slowly
        server:clientEvent(id, 'wasteland:players:server:selectCharacter', 1)
        server:advance(300)
        expect(P(server, 'GetCharacterId', id)).toBe(1)
        local r = last(server:clientEventsFor(id, 'wasteland:players:client:result'))
        expect(r.args[1].action).toBe('select')
        expect(r.args[1].ok).toBe(true)
    end)

    it('rejects malformed payloads before they reach the module', function()
        server:advance(4000)
        server:clientEvent(id, 'wasteland:players:server:selectCharacter', 'one')
        server:clientEvent(id, 'wasteland:players:server:createCharacter', { evil = true }, 'x')
        expect(#server:lines('rejected "wasteland:players:server:selectCharacter" from player 1 (payload)')).toBe(1)
        expect(#server:lines('rejected "wasteland:players:server:createCharacter" from player 1 (payload)')).toBe(1)
    end)

    it('allows one request at a time per player', function()
        server:advance(4000)
        server:command(id, 'character list')
        server:command(id, 'character list')
        server:advance(300)
        expect(messages(server, id)).toContain('Please wait, your previous request is still running.')
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('admission checks from other modules', function()
    local server = world()
    addModule(server, 'fx_gate', [[
Wasteland.DefineModule({ name = 'gate', version = '1.0.0', core = '^1.1.0', dependencies = { players = '^0.1.0' },
    onInit = function()
        exports.wasteland_players:RegisterAdmissionCheck('gate', function(info)
            if info.license == 'license:blocked' then return 'Not today.' end
            if info.license == 'license:crash' then error('oops') end
            return nil
        end)
    end })
]], { 'wasteland_players' })
    server:start('fx_gate')
    server:advance(100)

    it('refuses with the message the check returns', function()
        local id, err = server:connectAndJoin({ name = 'B', license = 'blocked' })
        expect(id).toBe(nil)
        expect(err).toBe('Not today.')
    end)
    it('lets players in when a check breaks (and logs it)', function()
        local id = server:connectAndJoin({ name = 'C', license = 'crash' })
        expect(id ~= nil).toBe(true)
        expect(#server:lines('admission check "gate" failed') > 0).toBe(true)
    end)
    it('drops the check when its resource stops', function()
        server:stop('fx_gate')
        local id = server:connectAndJoin({ name = 'B', license = 'blocked' })
        expect(id ~= nil).toBe(true)
    end)
end)

describe('positions only after the client placed the character', function()
    local server = newServer({ config = { ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
        ['players.lua'] = 'return { saveIntervalSeconds = 10, restoreDelayMs = 200 }' } })
    boot(server, { 'wasteland_players' })
    local id = server:connectAndJoin({ name = 'P-race', license = 'race' })
    server:advance(200)
    server.players[id].coords = { x = 100.0, y = 200.0, z = 30.0 }
    server:command(id, 'character create Race Test'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)

    it('the spot the game spawned the ped at is never saved', function()
        server.players[id].coords = { x = -802.3, y = 175.0, z = 72.8 } -- a map spawn point before placing
        server:advance(10500)
        for _, r in pairs(server.db.backend.data.wl_characters) do expect(r.pos_x == -802.3).toBe(false) end
    end)

    it('after "placed" the position counts', function()
        server.players[id].coords = { x = 55.0, y = 66.0, z = 31.0 }
        server:clientEvent(id, 'wasteland:players:server:placed'); server:advance(100)
        server:advance(10500)
        local found = false
        for _, r in pairs(server.db.backend.data.wl_characters) do if r.pos_x == 55.0 then found = true end end
        expect(found).toBe(true)
    end)
end)

describe('testing with two games on one Rockstar account', function()
    local server = newServer({ config = {
        ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
        ['players.lua'] = "return { restoreDelayMs = 200, duplicateSession = 'test_second_account' }",
    } })
    boot(server, { 'wasteland_players' })

    it('the second game joins as a separate account; the first stays online', function()
        local a = server:connectAndJoin({ name = 'Jay', license = 'license:same' })
        server:advance(300)
        local b = server:connectAndJoin({ name = 'Jay', license = 'license:same' })
        server:advance(300)
        expect(a ~= nil and b ~= nil).toBe(true)
        expect(server.players[a] ~= nil and not server.players[a].dropped).toBe(true)
        local licenses = {}
        for _, row in pairs(server.db.backend.data.wl_accounts) do licenses[#licenses + 1] = row.license end
        table.sort(licenses)
        expect(table.concat(licenses, ',')).toBe('license:license:same,license:license:same:test2')
        server:command(b, 'character create Second Player'); server:advance(300)
        server:command(b, 'character select 1'); server:advance(500)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)

