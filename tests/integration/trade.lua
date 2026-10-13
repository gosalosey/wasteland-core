-- wasteland_trade (server): ask, accept, offer, accept on both sides, the
-- swap (whole stacks keep their condition, part stacks split, cash),
-- changes take accepts back, nothing moves when it does not fit, distance.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('trading between players', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_trade' })
    local function player(license, first, x)
        local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
        server:advance(200)
        server:command(id, 'character create ' .. first .. ' Test'); server:advance(300)
        server:command(id, 'character select 1'); server:advance(500)
        server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
        server.players[id].coords = { x = x, y = 0.0, z = 30.0 }
        return id
    end
    local a = player('ta', 'Anna', 0.0)
    local b = player('tb', 'Bert', 1.5)
    local c = player('tc', 'Cleo', 40.0)
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local function last(id, ev) local l = server:clientEventsFor(id, ev); return l[#l] end
    local function note(id) return last(id, 'wasteland:trade:client:notice').args[1] end
    local function view(id) return last(id, 'wasteland:trade:client:view').args[1] end
    local function act(id, what, ...) server:clientEvent(id, 'wasteland:trade:server:' .. what, ...); server:advance(150) end
    local function stackOf(id, name)
        for _, s in ipairs(I('GetTradeable', id)) do if s.name == name then return s end end
    end

    I('ClearInventory', a); I('ClearInventory', b); server:advance(200)
    I('AddItem', a, 'weapon_pistol', 1, { durability = 300 })
    I('AddItem', a, 'bandage', 10)
    I('AddItem', b, 'cash', 500)
    server:advance(200)

    it('too far away: no request', function()
        act(a, 'request', c)
        expect(note(a)).toBe('Get closer to trade.')
    end)

    it('asking and accepting opens the window for both', function()
        act(a, 'request', b)
        local inv = last(b, 'wasteland:trade:client:invite').args[1]
        expect(inv.name).toBe('Anna Test')
        act(b, 'respond', a, true)
        expect(view(a).them.name).toBe('Bert Test')
        expect(view(b).them.name).toBe('Anna Test')
        expect(#view(a).me.items).toBe(2)
        expect(server:export('wasteland_trade', 'IsTrading', a)).toBe(true)
    end)

    it('offers show on both sides; a change takes both accepts back', function()
        local pistol, bandage = stackOf(a, 'weapon_pistol'), stackOf(a, 'bandage')
        act(a, 'offer', pistol.uid, 1)
        act(a, 'offer', bandage.uid, 4)
        expect(#view(b).them.offer).toBe(2)
        act(b, 'offer', stackOf(b, 'cash').uid, 300)
        act(a, 'ready', true)
        expect(view(b).them.ready).toBe(true)
        act(b, 'offer', stackOf(b, 'cash').uid, 250)
        expect(view(a).me.ready).toBe(false)
        expect(view(a).them.offer[1].count).toBe(250)
    end)

    it('both accept: everything swaps at once', function()
        act(a, 'ready', true)
        act(b, 'ready', true)
        expect(last(a, 'wasteland:trade:client:closed').args[1]).toBe('Trade done.')
        expect(I('GetItemCount', b, 'weapon_pistol')).toBe(1)
        expect(stackOf(b, 'weapon_pistol').durability).toBe(300)
        expect(I('GetItemCount', a, 'weapon_pistol')).toBe(0)
        expect(I('GetItemCount', a, 'bandage')).toBe(6)
        expect(I('GetItemCount', b, 'bandage')).toBe(4)
        expect(I('GetCash', a)).toBe(250)
        expect(I('GetCash', b)).toBe(250)
        expect(server:export('wasteland_trade', 'IsTrading', a)).toBe(false)
    end)

    it('nothing moves when the other side has no room', function()
        -- fill Bert's 6 x 4 pockets with non-stacking items
        I('ClearInventory', b); server:advance(100)
        for n = 1, 24 do I('AddItem', b, 'weapon_knuckle', 1) end
        I('AddItem', a, 'weapon_bat', 1); server:advance(200)
        act(a, 'request', b); act(b, 'respond', a, true)
        act(a, 'offer', stackOf(a, 'weapon_bat').uid, 1)
        act(a, 'ready', true); act(b, 'ready', true)
        expect(view(a).message).toContain('did not go through')
        expect(I('GetItemCount', a, 'weapon_bat')).toBe(1)
        expect(I('GetItemCount', b, 'weapon_bat')).toBe(0)
        expect(view(a).me.ready).toBe(false)
    end)

    it('walking away cancels the trade', function()
        server.players[b].coords = { x = 30.0, y = 0.0, z = 30.0 }
        server:advance(1200)
        expect(last(a, 'wasteland:trade:client:closed').args[1]).toContain('too far apart')
        expect(server:export('wasteland_trade', 'IsTrading', b)).toBe(false)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)
