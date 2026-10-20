-- wasteland_moonshine (server): a still placed from its item, brewing a
-- flavour (ingredients taken), collecting jars, drinking -> drunk and the
-- Zombie Blind meter (masked when full, smelled again below the line).

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['moonshine.lua'] = [[return {
        brewSeconds = 4, jarsPerRun = 3,
        base = { { name = 'sugar', count = 2 }, { name = 'water_bottle', count = 1 } },
        flavours = { corn = { label = 'Corn moonshine', item = 'moonshine_corn', crop = 'corn', count = 4 } },
        drink = { health = 3, infection = 3, thirst = 4, drunk = 18, blind = 50 },
        soberPerMinute = 6, blindPerMinute = 600, unmaskBelow = 40,
    }]],
}

local function teachDatabase(server)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_moonshine/server/sql.lua', 't', env))()
    local SQL, db = env.WLM.SQL, server.db.backend
    db.data.wl_moonshine_stills = {}
    local nextId = 0
    db:on(SQL.select, function(d)
        local rows = {}
        for _, r in pairs(d.data.wl_moonshine_stills) do rows[#rows + 1] = r end
        return rows
    end)
    db:on(SQL.insert, function(d, p)
        nextId = nextId + 1
        d.data.wl_moonshine_stills[nextId] = { id = nextId, owner_id = p[1], x = p[2], y = p[3], z = p[4], heading = p[5], brew = p[6] }
        return { insertId = nextId, affectedRows = 1 }
    end)
    db:on(SQL.update, function(d, p)
        local r = d.data.wl_moonshine_stills[p[2]]
        if r then r.brew = p[1] end
        return { affectedRows = 1 }
    end)
    db:on(SQL.delete, function(d, p)
        d.data.wl_moonshine_stills[p[1]] = nil
        return { affectedRows = 1 }
    end)
end

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('moonshine', function()
    local server = newServer({ config = CFG })
    teachDatabase(server)
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_moonshine' })
    local id = server:connectAndJoin({ name = 'P-shine', license = 'shine' })
    server:advance(200)
    server:command(id, 'character create Hank Still'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
    server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local function last(ev) local l = server:clientEventsFor(id, ev); return l[#l] end
    local function note() local e = last('wasteland:moonshine:client:notice'); return e and e.args[1] end
    local function act(what, ...) server:clientEvent(id, 'wasteland:moonshine:server:' .. what, ...); server:advance(300) end
    local function drink(item)
        for _, st in ipairs(I('GetInventory', 'player:1').items) do
            if st.name == item then server:clientEvent(id, 'wasteland:inventory:server:use', st.uid, 'player:1'); server:advance(300); return end
        end
    end
    local still

    it('runs; a still from its item is placed (the item is used up)', function()
        expect(states(server).moonshine).toBe('running')
        I('AddItem', id, 'moonshine_still', 1); server:advance(100)
        act('place', 2.0, 0.0, 30.0, 0.0)
        still = last('wasteland:moonshine:client:still').args[1]
        expect(still.id).toBe(1)
        expect(I('GetItemCount', id, 'moonshine_still')).toBe(0)
    end)

    it('will not brew without the ingredients; with them it takes them and runs', function()
        act('brew', still.id, 'corn')
        expect(note()).toContain('You need')
        I('AddItem', id, 'corn', 4); I('AddItem', id, 'sugar', 2); I('AddItem', id, 'water_bottle', 1); server:advance(100)
        local bottles = I('GetItemCount', id, 'water_bottle')
        act('brew', still.id, 'corn')
        expect(I('GetItemCount', id, 'corn')).toBe(0)
        expect(I('GetItemCount', id, 'sugar')).toBe(0)
        expect(I('GetItemCount', id, 'water_bottle')).toBe(bottles - 1)
        expect(last('wasteland:moonshine:client:view').args[1].brewing.label).toBe('Corn moonshine')
        act('collect', still.id)
        expect(note()).toContain('not done')
    end)

    it('when done, the jars are collected', function()
        server:advance(7000)
        act('collect', still.id)
        expect(I('GetItemCount', id, 'moonshine_corn')).toBe(3)
    end)

    it('brews several runs at once: ingredients and jars times the runs, a little longer', function()
        I('AddItem', id, 'corn', 12); I('AddItem', id, 'sugar', 6); I('AddItem', id, 'water_bottle', 3); server:advance(100)
        act('open', still.id)
        local fl = last('wasteland:moonshine:client:view').args[1].flavours[1]
        expect(fl.most >= 3).toBe(true)
        act('brew', still.id, 'corn', 3)
        expect(I('GetItemCount', id, 'corn')).toBe(0)
        expect(I('GetItemCount', id, 'sugar')).toBe(0)
        expect(last('wasteland:moonshine:client:view').args[1].brewing.runs).toBe(3)
        server:advance(4000)                                -- 4 s x (1 + 2 x 0.5) = 8 s: not yet
        act('collect', still.id)
        expect(note()).toContain('not done')
        server:advance(6000)
        act('collect', still.id)
        expect(I('GetItemCount', id, 'moonshine_corn')).toBe(12) -- 3 + 3 runs x 3 jars
        I('RemoveItem', id, 'moonshine_corn', 9); server:advance(100)
    end)

    it('drinking fills the meter; full = zombies cannot smell you; it drains and they can again', function()
        drink('moonshine_corn')
        expect(I('GetItemCount', id, 'moonshine_corn')).toBe(2)
        local s = last('wasteland:moonshine:client:state').args[1]
        expect(s.blind).toBe(50); expect(s.masked).toBe(false); expect(s.drunk).toBe(18)
        expect(server:export('wasteland_moonshine', 'IsMasked', id)).toBe(false)
        drink('moonshine_corn')
        expect(server:export('wasteland_moonshine', 'IsMasked', id)).toBe(true)
        expect(note()).toContain('cannot smell you')
        server:advance(8000) -- 600 a minute: 10 every second
        expect(server:export('wasteland_moonshine', 'IsMasked', id)).toBe(false)
        expect(last('wasteland:moonshine:client:state').args[1].masked).toBe(false)
    end)

    it('stills are kept across a restart; the owner picks up an empty one', function()
        server:restart('wasteland_moonshine'); server:advance(3000)
        expect(states(server).moonshine).toBe('running')
        expect(#last('wasteland:moonshine:client:sync').args[2]).toBe(1)
        act('pickup', still.id)
        expect(I('GetItemCount', id, 'moonshine_still')).toBe(1)
        expect(next(server.db.backend.data.wl_moonshine_stills)).toBe(nil)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
