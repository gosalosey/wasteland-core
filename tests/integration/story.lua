-- wasteland_story (server): Act I played through, step by step: talking,
-- choices that need items, visiting, collecting, reading, kills near a
-- place, defending, flags, the ending and its rewards, the journal.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('story: Patient Zero, act I', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_story' })
    local id = server:connectAndJoin({ name = 'P-story', license = 'story' })
    server:advance(200)
    server.players[id].coords = { x = 1840.0, y = 3680.0, z = 34.3 }
    server:command(id, 'character create Ellie Test'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)

    local function last(ev) local l = server:clientEventsFor(id, ev); return l[#l] end
    local function state() return last('wasteland:story:client:state').args[1] end
    local function step() local s = state().step; return s and s.id end
    local function at(x, y, z) server.players[id].coords = { x = x, y = y, z = z }; server:advance(50) end
    local function ev(name, ...) server:clientEvent(id, 'wasteland:story:server:' .. name, ...); server:advance(150) end
    local function count(item) return server:export('wasteland_inventory', 'GetItemCount', id, item) end
    local function give(item, n) server:export('wasteland_inventory', 'AddItem', id, item, n or 1); server:advance(100) end

    it('runs; a new character gets the intro and starts with Hollis', function()
        expect(states(server).story).toBe('running')
        expect(last('wasteland:story:client:intro').args[1].title).toBe('Patient Zero')
        expect(step()).toBe('static')
        expect(state().step.type).toBe('talk')
    end)

    it('talking needs you next to the NPC; the dialogue has lines and choices', function()
        at(1700.0, 3600.0, 34.3)
        ev('talk', 'hollis')
        expect(last('wasteland:story:client:dialogue')).toBe(nil)
        at(1855.5, 3688.0, 34.3)
        ev('talk', 'hollis')
        local d = last('wasteland:story:client:dialogue').args[1]
        expect(d.npc).toBe('Hollis'); expect(#d.lines).toBe(3); expect(d.choices[1].id).toBe('go')
        ev('choose', 'go')
        expect(step()).toBe('crash_site')
    end)

    it('visit, collect and read at the crash', function()
        at(1731.0, 3301.0, 41.2); server:advance(1100)
        expect(step()).toBe('courier_case')
        at(1736.0, 3297.0, 41.2)
        ev('collect', 'courier_case')
        expect(count('story_courier_case')).toBe(1)
        expect(step()).toBe('flight_log')
        at(1739.0, 3294.5, 41.2)
        ev('read', 'flight_log')
        expect(last('wasteland:story:client:note').args[1].title).toBe('Flight log, Courier Lazarus-9')
        expect(step()).toBe('hollis_case')
    end)

    it('a choice that needs an item takes it', function()
        at(1855.5, 3688.0, 34.3)
        ev('choose', 'give')
        expect(count('story_courier_case')).toBe(0)
        expect(step()).toBe('clinic_nest')
    end)

    it('kills only count near the clinic', function()
        local env = server.resources.wasteland_story.env
        for _ = 1, 3 do env.TriggerEvent('wasteland:zombies:died', 'u', 'walker', nil, id, { x = 0.0, y = 0.0, z = 0.0 }) end
        server:advance(100)
        expect(state().step.progress).toBe(0)
        for _ = 1, 8 do env.TriggerEvent('wasteland:zombies:died', 'u', 'walker', nil, id, { x = -250.0, y = 6330.0, z = 32.4 }) end
        server:advance(100)
        expect(step()).toBe('ward_journal')
        at(-252.0, 6324.0, 32.4)
        ev('read', 'ward_journal')
        expect(step()).toBe('tomas')
    end)

    it('Tomas: mercy needs antibiotics; then he gives the keycard', function()
        at(2432.0, 4972.0, 46.8)
        ev('talk', 'tomas')
        ev('choose', 'mercy')
        expect(last('wasteland:story:client:reply').args[1].keep).toBe(true)
        expect(step()).toBe('tomas')
        give('antibiotics', 1)
        ev('choose', 'mercy')
        expect(count('story_keycard')).toBe(1); expect(count('antibiotics')).toBe(0)
        expect(step()).toBe('lab_gate')
    end)

    it('defending: hold the gate area (with the keycard) for the whole time', function()
        at(3619.0, 3731.0, 28.7)
        server:advance(45000)
        expect(state().step.progress >= 40).toBe(true)
        server:advance(50000)
        expect(step()).toBe('lazarus')
        expect(count('story_keycard')).toBe(1) -- carried, not taken
    end)

    it('the sample and the last recording', function()
        at(3612.0, 3727.0, 28.7)
        ev('collect', 'lazarus')
        expect(count('story_lazarus_sample')).toBe(1)
        at(3610.5, 3725.5, 28.7)
        ev('read', 'ward_recording')
        expect(step()).toBe('the_choice')
    end)

    it('the ending: sharing the vial gives the serum and ends the act', function()
        at(1855.5, 3688.0, 34.3)
        ev('talk', 'hollis')
        local lines = last('wasteland:story:client:dialogue').args[1].lines
        local joined = ''
        for _, l in ipairs(lines) do joined = joined .. l.text end
        expect(joined:find('Reyes kid', 1, true)).toBe(nil) -- not ruthless
        ev('choose', 'share')
        expect(count('lazarus_serum')).toBe(3)
        expect(count('story_lazarus_sample')).toBe(0)
        local done = last('wasteland:story:client:stepDone').args[1]
        expect(done.ending.title).toBe('A Cure, Maybe'); expect(done.actDone).toBe(true)
    end)

    it('Act II starts after the ending card (intro, Hollis again)', function()
        server:advance(8200)
        expect(state().subtitle).toBe('Act II: The Company')
        expect(step()).toBe('convoy')
        expect(last('wasteland:story:client:intro').args[1].subtitle).toBe('Act II: The Company')
    end)

    it('Act II reacts to Act I (shared the vial), and plays through to its ending', function()
        at(1855.5, 3688.0, 34.3)
        ev('talk', 'hollis')
        local text = ''
        for _, l in ipairs(last('wasteland:story:client:dialogue').args[1].lines) do text = text .. l.text end
        expect(text:find('Our medic is gone', 1, true) ~= nil).toBe(true)
        expect(text:find('Remember Crane', 1, true)).toBe(nil)
        ev('choose', 'go')
        at(1985.0, 3053.0, 47.2); server:advance(1100)
        expect(step()).toBe('guards')
        local env = server.resources.wasteland_story.env
        for _ = 1, 10 do env.TriggerEvent('wasteland:zombies:died', 'u', 'walker', nil, id, { x = 1985.0, y = 3050.0, z = 47.2 }) end
        server:advance(100)
        at(1991.0, 3049.0, 47.2); ev('collect', 'manifest')
        expect(count('story_manifest')).toBe(1)
        at(1993.0, 3051.5, 47.2); ev('read', 'manifest_read')
        expect(step()).toBe('rook')
        at(-1582.0, 2786.0, 17.0)
        ev('talk', 'rook'); ev('choose', 'codes')
        expect(step()).toBe('lighthouse')
        at(3426.0, 5174.0, 7.4); server:advance(122000)
        expect(step()).toBe('crane_log')
        at(3420.0, 5168.0, 7.4); ev('read', 'crane_log')
        at(1855.5, 3688.0, 34.3)
        ev('talk', 'hollis')
        text = ''
        for _, l in ipairs(last('wasteland:story:client:dialogue').args[1].lines) do text = text .. l.text end
        expect(text:find('left him bleeding', 1, true) ~= nil).toBe(true)
        ev('choose', 'warn')
        expect(count('armor_plate')).toBe(1)
        expect(last('wasteland:story:client:stepDone').args[1].ending.title).toBe('Every Channel')
        expect(state().done).toBe(true)   -- every act done: the tracker goes
    end)

    it('the journal tells both acts, with what you chose and the endings', function()
        ev('journal')
        local j = last('wasteland:story:client:journal').args[1]
        local headers, endings, all = 0, 0, ''
        for _, e in ipairs(j.entries) do
            if e.header then headers = headers + 1 end
            if e.ending then endings = endings + 1 end
            all = all .. (e.text or '')
        end
        expect(headers).toBe(2); expect(endings).toBe(2)
        expect(all:find('eased his fever', 1, true) ~= nil).toBe(true)
        expect(all:find('left him there', 1, true) ~= nil).toBe(true)
        expect(j.ending.title).toBe('Every Channel')
        expect(#server:lines('raised:')).toBe(0)
    end)
end)
