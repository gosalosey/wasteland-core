-- wasteland_appearance (server side) and the players changes for the UI:
-- when the creator opens, validation of submitted looks, storage, applying
-- on load, the admin reopen command, and guarded events.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { saveIntervalSeconds = 10, restoreDelayMs = 200, maxCharacters = 2 }',
    ['appearance.lua'] = 'return { blockedClothing = { mp_m_freemode_01 = { [11] = { 55 } } } }',
}

local function world(extra)
    local cfg = {}
    for k, v in pairs(CFG) do cfg[k] = v end
    for k, v in pairs(extra or {}) do cfg[k] = v end
    local server = newServer({ config = cfg })
    boot(server, { 'wasteland_players', 'wasteland_appearance' })
    return server
end

local function join(server, license)
    local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
    server:advance(200)
    return id
end

local function cmd(server, src, line) server:command(src, line); server:advance(300) end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end

-- Join, create and play a character; returns the server id.
local function playing(server, license)
    local id = join(server, license or 'alice')
    cmd(server, id, 'character create John Doe')
    cmd(server, id, 'character select 1')
    return id
end

-- A valid appearance, built by the real shared definitions.
local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model), env.WLA
end

local function save(server, id, appearance)
    server:clientEvent(id, 'wasteland:appearance:server:save', appearance)
    server:advance(300)
end

local function stored(server, characterId)
    local row = server.db.backend.data.wl_character_data[characterId .. '|appearance']
    return row and server.json.decode(row.data) or nil
end

describe('appearance module startup', function()
    it('runs with its dependencies (ui is started automatically)', function()
        local server = world()
        local s = states(server)
        expect(s.ui).toBe('running')
        expect(s.appearance).toBe('running')
        expect(#server.scriptErrors).toBe(0)
    end)
    it('ships defaults that pass its own validation, for both models', function()
        local Schema = loadCoreFiles({ 'shared/util.lua', 'shared/schema.lua' }).WL.Schema
        for _, model in ipairs({ 'mp_m_freemode_01', 'mp_f_freemode_01' }) do
            local a, WLA = defaults(model)
            local clean, err = WLA.validate(Schema, a, {})
            expect(err).toBe(nil)
            expect(clean.model).toBe(model)
        end
    end)
end)

describe('new character: the creator opens and the look is saved', function()
    local server = world()
    local id = playing(server)
    local good = defaults('mp_f_freemode_01')

    it('opens the creator (not cancellable) when a character without a look loads', function()
        local open = last(events(server, id, 'wasteland:appearance:client:openCreator'))
        expect(open ~= nil).toBe(true)
        expect(open.args[1].reason).toBe('new')
        expect(open.args[1].cancellable).toBe(false)
        expect(#events(server, id, 'wasteland:appearance:client:apply')).toBe(0)
    end)

    it('rejects invalid looks with a reason and stores nothing', function()
        local function rejected(mutate, needle)
            local a = defaults('mp_m_freemode_01')
            mutate(a)
            server:advance(2000) -- stay under the save rate limit (burst 3, 0.5/s)
            save(server, id, a)
            local fail = last(events(server, id, 'wasteland:appearance:client:saveFailed'))
            expect(fail ~= nil).toBe(true)
            expect(fail.args[1]).toContain(needle)
            expect(stored(server, 1)).toBe(nil)
        end
        rejected(function(a) a.components[1] = { id = 1, drawable = 0, texture = 0 } end, 'clothing slot 1 cannot be changed')
        rejected(function(a) a.components[2] = { id = 11, drawable = 1, texture = 0 } end, 'clothing slot 11 appears twice')
        rejected(function(a) a.components[1] = { id = 11, drawable = 55, texture = 0 } end, 'not available')
        rejected(function(a) a.props[1] = { id = 6, drawable = 0, texture = 0 } end, 'accessory slot 6')
    end)

    it('the guard drops malformed payloads before the module sees them', function()
        local a = defaults('mp_m_freemode_01')
        a.model = 'a_c_chimp'
        server:advance(3000)
        save(server, id, a)
        server:advance(3000)
        local b = defaults('mp_m_freemode_01')
        b.features = { 1, 2 }
        save(server, id, b)
        server:advance(3000)
        save(server, id, 'not a table')
        expect(#server:lines('rejected "wasteland:appearance:server:save" from player 1 (payload)')).toBe(1)
        expect(stored(server, 1)).toBe(nil)
    end)

    it('stores a valid look, confirms it, and closes the creator', function()
        server:advance(3000)
        save(server, id, good)
        local saved = last(events(server, id, 'wasteland:appearance:client:saved'))
        expect(saved ~= nil).toBe(true)
        local s = stored(server, 1)
        expect(s.model).toBe('mp_f_freemode_01')
        expect(#s.features).toBe(20)
        expect(#s.overlays).toBe(13)
        expect(#server:lines('player 1 saved the appearance of character 1 (new)')).toBe(1)
    end)

    it('refuses a second save once the creator is closed', function()
        server:advance(3000)
        local a = defaults('mp_m_freemode_01')
        save(server, id, a)
        expect(last(events(server, id, 'wasteland:appearance:client:saveFailed')).args[1]).toContain('not open')
        expect(stored(server, 1).model).toBe('mp_f_freemode_01')
    end)

    it('applies the stored look when the character is loaded again', function()
        server:dropPlayer(id); server:advance(500)
        local id2 = join(server, 'alice')
        cmd(server, id2, 'character select 1')
        local apply = last(events(server, id2, 'wasteland:appearance:client:apply'))
        expect(apply.args[1].model).toBe('mp_f_freemode_01')
        expect(#events(server, id2, 'wasteland:appearance:client:openCreator')).toBe(0)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('admin reopen command', function()
    local server = world()
    local id = playing(server)
    save(server, id, defaults('mp_m_freemode_01'))

    it('is refused for players without the ACE', function()
        local other = playing(server, 'bob')
        server:clearOutput()
        cmd(server, other, 'appearance ' .. id)
        expect(#server:lines('tried "appearance" without the wasteland.admin ACE')).toBe(1)
    end)

    it('opens a cancellable creator with the current look from the console', function()
        cmd(server, 0, 'appearance ' .. id)
        local open = last(events(server, id, 'wasteland:appearance:client:openCreator'))
        expect(open.args[1].reason).toBe('admin')
        expect(open.args[1].cancellable).toBe(true)
        expect(open.args[1].current.model).toBe('mp_m_freemode_01')
    end)

    it('cancel goes back to the stored look and closes the creator', function()
        server:clientEvent(id, 'wasteland:appearance:server:cancel')
        server:advance(300)
        expect(last(events(server, id, 'wasteland:appearance:client:apply')).args[1].model).toBe('mp_m_freemode_01')
        server:advance(3000)
        save(server, id, defaults('mp_f_freemode_01'))
        expect(last(events(server, id, 'wasteland:appearance:client:saveFailed')).args[1]).toContain('not open')
    end)

    it('lets an ACE holder reopen it and the player save a new look', function()
        server.aces['2|wasteland.admin'] = true
        cmd(server, 2, 'appearance ' .. id)
        server:advance(3000)
        save(server, id, defaults('mp_f_freemode_01'))
        expect(stored(server, 1).model).toBe('mp_f_freemode_01')
        expect(#server:lines('player 1 saved the appearance of character 1 (admin)')).toBe(1)
    end)

    it('explains bad arguments', function()
        server:clearOutput()
        cmd(server, 0, 'appearance')
        cmd(server, 0, 'appearance 99')
        expect(#server:lines('usage: appearance <server id>')).toBe(1)
        expect(#server:lines('player 99 has no loaded character')).toBe(1)
    end)
end)

describe('resource restarts and requests', function()
    local server = world()
    local id = playing(server)
    save(server, id, defaults('mp_m_freemode_01'))

    it('sends the look again to a character restored after a players restart', function()
        local before = #events(server, id, 'wasteland:appearance:client:apply')
        server:restart('wasteland_players')
        server:advance(3000)
        expect(states(server).appearance).toBe('running')
        local after = events(server, id, 'wasteland:appearance:client:apply')
        expect(#after > before).toBe(true)
        expect(last(after).args[1].model).toBe('mp_m_freemode_01')
        -- the creator is not reopened: the character has a look
        expect(#events(server, id, 'wasteland:appearance:client:openCreator')).toBe(1)
    end)

    it('answers an explicit request with the stored look', function()
        local before = #events(server, id, 'wasteland:appearance:client:apply')
        server:clientEvent(id, 'wasteland:appearance:server:request')
        server:advance(100)
        expect(#events(server, id, 'wasteland:appearance:client:apply')).toBe(before + 1)
    end)

    it('exports GetAppearance', function()
        expect(server:export('wasteland_appearance', 'GetAppearance', 1).model).toBe('mp_m_freemode_01')
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('players changes for the character screen', function()
    local server = world()
    local id = join(server, 'carol')

    it('requestCharacters (from the screen) sends the list without chat lines', function()
        local chatBefore = #events(server, id, 'wasteland:core:client:consoleOutput')
        server:clientEvent(id, 'wasteland:players:server:requestCharacters')
        server:advance(300)
        expect(#events(server, id, 'wasteland:core:client:consoleOutput')).toBe(chatBefore)
        expect(#events(server, id, 'wasteland:players:client:characters') >= 2).toBe(true)
    end)

    it('the create result carries the new slot and character id', function()
        server:clientEvent(id, 'wasteland:players:server:createCharacter', 'Ann', 'Lee')
        server:advance(300)
        local r = last(events(server, id, 'wasteland:players:client:result'))
        expect(r.args[1].action).toBe('create')
        expect(r.args[1].slot).toBe(1)
        expect(r.args[1].characterId).toBe(1)
    end)
end)
