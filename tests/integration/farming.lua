-- wasteland_farming (server): craftable plots placed anywhere, planting,
-- watering, growing (only while watered), harvesting, picking up.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['farming.lua'] = [[return {
        tickSeconds = 6, maxWaterMinutes = 10, seedBackChance = 0,
        rainCatcher = { capacityLitres = 2, litresPerMinute = 5, litresPerBottle = 0.5 },
        plots = { small = { label = 'Small farm plot', item = 'farm_plot_small', model = 'wl_farm_plot_small', size = 1, waterPerBottle = 2 },
                  medium = { label = 'Medium farm plot', item = 'farm_plot_medium', model = 'wl_farm_plot_medium', size = 2, waterPerBottle = 2 } },
        stages = { sprout = 'a', young = 'b', grown = 'c', ripe = 'd_%s' },
        crops = { lettuce = { label = 'Lettuce', seed = 'seeds_lettuce', produce = 'lettuce', minutes = 0.3, yield = { 2, 2 }, color = 'green' } },
    }]],
}

local function teachDatabase(server)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_farming/server/sql.lua', 't', env))()
    local SQL, db = env.WLF.SQL, server.db.backend
    db.data.wl_farm_plots = {}
    local nextId = 0
    db:on(SQL.select, function(d)
        local rows = {}
        for _, r in pairs(d.data.wl_farm_plots) do rows[#rows + 1] = r end
        return rows
    end)
    db:on(SQL.insert, function(d, p)
        nextId = nextId + 1
        d.data.wl_farm_plots[nextId] = { id = nextId, owner_id = p[1], size = p[2], x = p[3], y = p[4], z = p[5], heading = p[6], water = 0, slots = p[7] }
        return { insertId = nextId, affectedRows = 1 }
    end)
    db:on(SQL.update, function(d, p)
        local r = d.data.wl_farm_plots[p[3]]
        if r then r.water, r.slots = p[1], p[2] end
        return { affectedRows = 1 }
    end)
    db:on(SQL.delete, function(d, p)
        d.data.wl_farm_plots[p[1]] = nil
        return { affectedRows = 1 }
    end)
    db.data.wl_farm_catchers = {}
    local nextC = 0
    db:on(SQL.catcherSelect, function(d)
        local rows = {}
        for _, r in pairs(d.data.wl_farm_catchers) do rows[#rows + 1] = r end
        return rows
    end)
    db:on(SQL.catcherInsert, function(d, p)
        nextC = nextC + 1
        d.data.wl_farm_catchers[nextC] = { id = nextC, owner_id = p[1], x = p[2], y = p[3], z = p[4], heading = p[5], litres = 0 }
        return { insertId = nextC, affectedRows = 1 }
    end)
    db:on(SQL.catcherUpdate, function(d, p)
        local r = d.data.wl_farm_catchers[p[2]]
        if r then r.litres = p[1] end
        return { affectedRows = 1 }
    end)
    db:on(SQL.catcherDelete, function(d, p)
        d.data.wl_farm_catchers[p[1]] = nil
        return { affectedRows = 1 }
    end)
end

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('farming', function()
    local server = newServer({ config = CFG })
    teachDatabase(server)
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_world', 'wasteland_farming' })
    local id = server:connectAndJoin({ name = 'P-farm', license = 'farm' })
    server:advance(200)
    server:command(id, 'character create Fern Grower'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
    server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local function last(ev) local l = server:clientEventsFor(id, ev); return l[#l] end
    local function note() local e = last('wasteland:farming:client:notice'); return e and e.args[1] end
    local function act(what, ...) server:clientEvent(id, 'wasteland:farming:server:' .. what, ...); server:advance(300) end
    local plot

    it('runs; a plot from its item is placed (the item is used up)', function()
        expect(states(server).farming).toBe('running')
        I('AddItem', id, 'farm_plot_small', 1); server:advance(100)
        act('place', 'small', 2.0, 0.0, 30.0, 0.0)
        plot = last('wasteland:farming:client:plot').args[1]
        expect(plot.size).toBe(1)
        expect(I('GetItemCount', id, 'farm_plot_small')).toBe(0)
        server:advance(1100)
        act('place', 'small', 2.0, 3.0, 30.0, 0.0)
        expect(note()).toContain('You need a')
    end)

    it('plants a seed; it does not grow while the soil is dry', function()
        I('AddItem', id, 'seeds_lettuce', 2); server:advance(100)
        act('plant', plot.id, 1, 'lettuce')
        expect(I('GetItemCount', id, 'seeds_lettuce')).toBe(1)
        local v = last('wasteland:farming:client:view').args[1]
        expect(v.slots[1].label).toBe('Lettuce'); expect(v.slots[1].stage).toBe('sprout')
        server:advance(13000)
        act('open', plot.id)
        expect(last('wasteland:farming:client:view').args[1].slots[1].progress).toBe(0)
        act('harvest', plot.id, 1)
        expect(note()).toContain('not ripe')
    end)

    it('a water bottle waters it; it grows and ripens; harvesting gives the food', function()
        I('AddItem', id, 'water_bottle', 1); server:advance(100)
        local bottles = I('GetItemCount', id, 'water_bottle')
        act('water', plot.id)
        expect(I('GetItemCount', id, 'water_bottle')).toBe(bottles - 1)
        expect(last('wasteland:farming:client:view').args[1].water).toBe(2)
        server:advance(25000) -- a tick is 6 s = 0.1 minute of growing; 0.3 to ripen
        act('open', plot.id)
        local s = last('wasteland:farming:client:view').args[1].slots[1]
        expect(s.stage).toBe('ripe'); expect(s.minutesLeft).toBe(0)
        act('harvest', plot.id, 1)
        expect(I('GetItemCount', id, 'lettuce')).toBe(2)
        expect(note()).toContain('You harvest 2')
    end)

    it('plots are kept across a restart; the owner picks up an empty one and gets the item back', function()
        server:restart('wasteland_farming'); server:advance(3000)
        expect(states(server).farming).toBe('running')
        local sync = last('wasteland:farming:client:sync')
        expect(#sync.args[2]).toBe(1)
        act('pickup', plot.id)
        expect(I('GetItemCount', id, 'farm_plot_small')).toBe(1)
        expect(next(server.db.backend.data.wl_farm_plots)).toBe(nil)
        expect(#server.scriptErrors).toBe(0)
    end)

    it('rain catcher: placed outdoors, fills only while it rains, emptied into water bottles', function()
        server:export('wasteland_world', 'SetWeather', 'CLEAR')
        I('AddItem', id, 'rain_catcher', 1); server:advance(100)
        act('place', 'catcher', -2.0, 0.0, 30.0, 0.0)
        local c = last('wasteland:farming:client:catcher').args[1]
        expect(c.litres).toBe(0)
        expect(I('GetItemCount', id, 'rain_catcher')).toBe(0)
        server:advance(13000)
        act('catcherCollect', c.id)
        expect(note()).toContain('not enough water')       -- no rain, no water
        server:export('wasteland_world', 'SetWeather', 'RAIN')
        server:advance(13000)                               -- 5 L a minute: 0.5 L a 6 s tick, capped at 2 L
        local bottles = I('GetItemCount', id, 'water_bottle')
        act('catcherCollect', c.id)
        expect(note()).toContain('You fill')
        expect(I('GetItemCount', id, 'water_bottle') > bottles).toBe(true)
        server:export('wasteland_world', 'SetWeather', 'CLEAR')
        act('catcherPickup', c.id)
        expect(I('GetItemCount', id, 'rain_catcher')).toBe(1)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
