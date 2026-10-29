-- wasteland_survivors (server): survivors spawn at spots a player found,
-- killing zombies near one earns a reward when you talk to them (once),
-- item-for-item trades, hurting one turns it (and those close by) on you,
-- zombie hits and voice lines go to the right games.

local function shipped(name, from, to)
    local f = assert(io.open(RESOURCES .. '/wasteland_config/config/' .. name, 'r'))
    local text = f:read('a')
    f:close()
    for i = 1, #from do text = text:gsub(from[i], to[i], 1) end
    return text
end

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['survivors.lua'] = shipped('survivors.lua', { 'everySeconds = 45,', 'chance = 0.5,' }, { 'everySeconds = 2,', 'chance = 1.0,' }),
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('survivors', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survivors' })
    local function player(license, first, x)
        local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
        server:advance(200)
        server:command(id, 'character create ' .. first .. ' Test'); server:advance(300)
        server:command(id, 'character select 1'); server:advance(500)
        server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
        server.players[id].coords = { x = x, y = 0.0, z = 30.0 }
        return id
    end
    local a = player('sa', 'Sam', 0.0)
    local b = player('sb', 'Bo', 2.0)
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local function last(id, ev) local l = server:clientEventsFor(id, ev); return l[#l] end
    local function note(id) local e = last(id, 'wasteland:survivors:client:notice'); return e and e.args[1] or '' end
    local function act(id, what, ...) server:clientEvent(id, 'wasteland:survivors:server:' .. what, ...); server:advance(150) end
    local function carried(id)
        local n = 0
        for _, name in ipairs({ 'ammo_12g', 'ammo_308', 'bandage', 'painkillers', 'canned_beans', 'water_bottle', 'scrap_metal',
            'duct_tape', 'gun_parts', 'antibiotics' }) do n = n + (I('GetItemCount', id, name) or 0) end
        return n
    end
    I('ClearInventory', a); I('ClearInventory', b); server:advance(200)

    local s
    it('runs; a survivor is spawned at a spot a player found', function()
        expect(states(server).survivors).toBe('running')
        server:advance(2500)
        local who = last(a, 'wasteland:survivors:client:findSpots') and a or b
        expect(last(who, 'wasteland:survivors:client:findSpots') ~= nil).toBe(true)
        act(who, 'spots', { { x = 5.0, y = 0.0, z = 30.0 }, { x = 150.0, y = 0.0, z = 30.0 } }) -- the first is too close
        local list = server:entityList('wlSurvivor')
        expect(#list).toBe(1)
        expect(list[1].coords.x).toBe(150.0)
        expect(type(list[1].state.wlSurvivor.name)).toBe('string')
        expect(#list[1].state.wlSurvivor.hostile).toBe(0)
        -- bring it over for the rest
        s = list[1]
        s.coords = { x = 1.0, y = 1.0, z = 30.0 }
    end)

    it('talking before helping: what they want', function()
        act(a, 'talk', s.netId)
        expect(note(a)).toContain('kill 2 more zombies')
    end)

    it('zombies killed near them by a player count; then the reward, once', function()
        local before = carried(a)
        server:triggerEvent('wasteland_zombies', 'wasteland:zombies:died', 9001, 'walker', 'reported', a, { x = 4.0, y = 0.0, z = 30.0 })
        server:triggerEvent('wasteland_zombies', 'wasteland:zombies:died', 9002, 'walker', 'reported', a, { x = 900.0, y = 0.0, z = 30.0 }) -- far: no
        server:advance(100)
        act(a, 'talk', s.netId)
        expect(note(a)).toContain('kill 1 more zombie')
        server:triggerEvent('wasteland_zombies', 'wasteland:zombies:died', 9003, 'walker', 'reported', a, { x = 4.0, y = 0.0, z = 30.0 })
        server:advance(100)
        expect(note(a)).toContain('Come talk to me')
        act(a, 'talk', s.netId)
        expect(note(a)).toContain('gives you')
        expect(carried(a) > before).toBe(true)
        act(a, 'talk', s.netId)
        expect(note(a)).toContain('already gave you')
    end)

    it('trading: their offers; items are needed; the swap; how many are left', function()
        act(a, 'openTrade', s.netId)
        local view = last(a, 'wasteland:survivors:client:trade').args[2]
        expect(#view.offers).toBe(3)
        local o = view.offers[1]
        I('ClearInventory', a); server:advance(100)
        act(a, 'barter', s.netId, 1)
        expect(last(a, 'wasteland:survivors:client:trade').args[2].message).toContain('You need')
        I('AddItem', a, o.give.name, o.give.count); server:advance(100)
        act(a, 'barter', s.netId, 1)
        local v2 = last(a, 'wasteland:survivors:client:trade').args[2]
        expect(v2.ok).toBe(true)
        expect(v2.offers[1].left).toBe(o.left - 1)
        expect(I('GetItemCount', a, o.give.name)).toBe(0)
        expect(I('GetItemCount', a, o.get.name)).toBe(o.get.count)
        -- trading needs the window open with that survivor
        act(b, 'barter', s.netId, 1)
        expect(last(b, 'wasteland:survivors:client:trade') == nil).toBe(true)
    end)

    it('hurting one turns it and the survivors close by on you, not the far ones', function()
        local near = server:export('wasteland_survivors', 'SpawnSurvivor', { x = 10.0, y = 0.0, z = 30.0 })
        local far = server:export('wasteland_survivors', 'SpawnSurvivor', { x = 300.0, y = 0.0, z = 30.0 })
        act(b, 'attacked', s.netId)
        expect(s.state.wlSurvivor.hostile[1]).toBe(b)
        local function ent(net) for _, e in ipairs(server:entityList('wlSurvivor')) do if e.netId == net then return e end end end
        expect(ent(near).state.wlSurvivor.hostile[1]).toBe(b)
        expect(#ent(far).state.wlSurvivor.hostile).toBe(0)
        expect(note(b)).toContain('turn on you')
        act(b, 'talk', s.netId)
        expect(note(b)).toContain('wants nothing to do with you')
        act(b, 'openTrade', s.netId)
        expect(last(b, 'wasteland:survivors:client:trade') == nil).toBe(true)
        -- still friendly with the other player
        act(a, 'talk', s.netId)
        expect(note(a)).toContain('already gave you')
    end)

    it('a zombie hit goes to the game running the survivor', function()
        server:triggerEvent('wasteland_zombies', 'wasteland:zombies:hitPed', s.netId, 8, 7001)
        server:advance(50)
        local e = last(s.owner, 'wasteland:survivors:client:damage')
        expect(e.args[1]).toBe(s.netId); expect(e.args[2]).toBe(8)
    end)

    it('calls for help: only from the game running it, heard by players close by', function()
        local owner = s.owner
        local other = owner == a and b or a
        local n0 = #server:clientEventsFor(other, 'wasteland:survivors:client:say')
        act(other, 'say', s.netId, 'help')
        expect(#server:clientEventsFor(other, 'wasteland:survivors:client:say')).toBe(n0)
        act(owner, 'say', s.netId, 'help')
        local e = last(other, 'wasteland:survivors:client:say')
        expect(e.args[1]).toBe(s.netId); expect(e.args[2]).toBe('help')
        local n1 = #server:clientEventsFor(other, 'wasteland:survivors:client:say')
        act(owner, 'say', s.netId, 'help') -- too soon again
        expect(#server:clientEventsFor(other, 'wasteland:survivors:client:say')).toBe(n1)
    end)

    it('a stop removes them all', function()
        server:stop('wasteland_survivors'); server:advance(200)
        expect(#server:entityList('wlSurvivor')).toBe(0)
    end)
end)
