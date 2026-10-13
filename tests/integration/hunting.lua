-- wasteland_hunting (server): animals spawn near players, harvesting a dead
-- animal with a blade (also any animal), campfire (matches + firewood, owner
-- picks it up, burns out), cooking a chosen number of raw meat.

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
    ['hunting.lua'] = shipped('hunting.lua', { 'everySeconds = 20,', 'burnMinutes = 30,' }, { 'everySeconds = 5,', 'burnMinutes = 2,' }),
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('hunting', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_hunting' })
    local function player(license, first, x)
        local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
        server:advance(200)
        server:command(id, 'character create ' .. first .. ' Test'); server:advance(300)
        server:command(id, 'character select 1'); server:advance(500)
        server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
        server.players[id].coords = { x = x, y = 0.0, z = 30.0 }
        return id
    end
    local a = player('ha', 'Hank', 0.0)
    local b = player('hb', 'Bea', 2.0)
    local env = server.resources.wasteland_hunting.env
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local function last(id, ev) local l = server:clientEventsFor(id, ev); return l[#l] end
    local function note(id) return last(id, 'wasteland:hunting:client:notice').args[1] end
    local function act(id, what, ...) server:clientEvent(id, 'wasteland:hunting:server:' .. what, ...); server:advance(150) end
    I('ClearInventory', a); I('ClearInventory', b); server:advance(200)

    it('runs; animals are spawned at spots a player found', function()
        expect(states(server).hunting).toBe('running')
        server:advance(5500)
        local ask = last(a, 'wasteland:hunting:client:findSpots') or last(b, 'wasteland:hunting:client:findSpots')
        expect(ask ~= nil).toBe(true)
        local who = last(a, 'wasteland:hunting:client:findSpots') and a or b
        act(who, 'spots', { { x = 120.0, y = 0.0, z = 30.0 }, { x = 5.0, y = 0.0, z = 30.0 } }) -- the second is too close
        expect(#server:entityList('wlAnimal')).toBe(1)
        expect(server:export('wasteland_hunting', 'GetAnimalCount')).toBe(1)
    end)

    local carcass
    it('a dead animal needs a blade to harvest', function()
        carcass = server:entityList('wlAnimal')[1]
        carcass.health, carcass.coords = 0, { x = 1.0, y = 1.0, z = 30.0 }
        act(a, 'harvest', carcass.netId)
        expect(note(a)).toBe('You need a knife (or another blade) to harvest it.')
    end)

    it('with a knife: a few seconds, then raw meat; the carcass goes', function()
        I('AddItem', a, 'weapon_knife', 1); server:advance(100)
        act(a, 'harvest', carcass.netId)
        expect(last(a, 'wasteland:hunting:client:harvesting').args[1]).toBe(6)
        act(a, 'harvestDone') -- too early: nothing
        expect(I('GetItemCount', a, 'raw_meat')).toBe(0)
        act(a, 'harvest', carcass.netId)
        server:advance(6100)
        act(a, 'harvestDone')
        expect(I('GetItemCount', a, 'raw_meat') >= 1).toBe(true)
        expect(note(a)).toContain('You got')
        act(b, 'harvest', carcass.netId)
        expect(note(b)).toBe('Someone already harvested this.')
        server:advance(3100)
        expect(#server:entityList('wlAnimal')).toBe(0)
    end)

    it('any animal can be harvested, also ones this module did not spawn', function()
        local cow = env.CreatePed(28, env.GetHashKey('a_c_cow'), 1.0, -1.0, 30.0, 0.0, true, true)
        server:entity(cow).health = 0
        local before = I('GetItemCount', a, 'raw_meat')
        act(a, 'harvest', server:entity(cow).netId)
        server:advance(6100)
        act(a, 'harvestDone')
        expect(I('GetItemCount', a, 'raw_meat') > before).toBe(true)
        -- a dead person is not an animal
        local man = env.CreatePed(4, env.GetHashKey('a_m_m_hillbilly_01'), 1.0, -1.5, 30.0, 0.0, true, true)
        server:entity(man).health = 0
        act(a, 'harvest', server:entity(man).netId)
        expect(note(a)).toBe('There is nothing to harvest.')
    end)

    local fire
    it('a campfire needs matches and firewood; using it asks where to put it', function()
        I('AddItem', a, 'campfire', 1); server:advance(100)
        act(a, 'placeFire', 1.0, 1.0, 30.0)
        expect(note(a)).toBe('You need 1 x Matches to light a campfire (you have 0).')
        I('AddItem', a, 'matches', 3); I('AddItem', a, 'firewood', 2); server:advance(100)
        local kit
        for _, s in ipairs(I('GetTradeable', a)) do if s.name == 'campfire' then kit = s end end
        server:clientEvent(a, 'wasteland:inventory:server:use', kit.uid, kit.inventoryId); server:advance(200)
        expect(last(a, 'wasteland:hunting:client:placeFire') ~= nil).toBe(true)
        act(a, 'placeFire', 1.0, 1.0, 30.0)
        fire = nil
        for _, e in ipairs(server:entityList('wlCampfire')) do fire = e end
        expect(fire ~= nil).toBe(true)
        expect(I('GetItemCount', a, 'campfire')).toBe(0)
        expect(I('GetItemCount', a, 'matches')).toBe(2)
        expect(I('GetItemCount', a, 'firewood')).toBe(0)
    end)

    it('cooks as many as chosen, one after another', function()
        local raw = I('GetItemCount', a, 'raw_meat')
        I('AddItem', a, 'raw_meat', 5 - raw); server:advance(100)
        act(a, 'openCook', fire.netId)
        local screen = last(a, 'wasteland:hunting:client:cookScreen').args[1]
        expect(screen.items[1].item).toBe('raw_meat'); expect(screen.items[1].have).toBe(5)
        act(a, 'cook', fire.netId, 'raw_meat', 3)
        server:advance(5600) -- 5 s a piece (checked every half second)
        expect(I('GetItemCount', a, 'cooked_meat')).toBe(1)
        server:advance(10600)
        expect(I('GetItemCount', a, 'cooked_meat')).toBe(3)
        expect(I('GetItemCount', a, 'raw_meat')).toBe(2)
        expect(last(a, 'wasteland:hunting:client:cooking').args[1].message).toBe('Cooked 3 x Cooked meat.')
    end)

    it('walking away stops the cooking', function()
        act(a, 'cook', fire.netId, 'raw_meat', 2)
        server.players[a].coords = { x = 20.0, y = 0.0, z = 30.0 }
        server:advance(1000)
        expect(last(a, 'wasteland:hunting:client:cooking').args[1].message).toBe('You walked away from the fire.')
        expect(I('GetItemCount', a, 'raw_meat')).toBe(2)
        server.players[a].coords = { x = 0.0, y = 0.0, z = 30.0 }
    end)

    it('only its owner picks it up; then it is a campfire item again', function()
        act(b, 'pickUp', fire.netId)
        expect(note(b)).toBe('Only the player who made this fire can pick it up.')
        act(a, 'pickUp', fire.netId)
        expect(I('GetItemCount', a, 'campfire')).toBe(1)
        expect(#server:entityList('wlCampfire')).toBe(0)
    end)

    it('a fire that burns out goes back to its owner', function()
        I('AddItem', a, 'firewood', 2); server:advance(100)
        act(a, 'placeFire', -1.0, 1.0, 30.0)
        expect(#server:entityList('wlCampfire')).toBe(1)
        server:advance(2 * 60000 + 11000)
        expect(#server:entityList('wlCampfire')).toBe(0)
        expect(I('GetItemCount', a, 'campfire')).toBe(1)
        expect(note(a)).toBe('Your campfire burnt out. It is back in your inventory.')
        expect(#server:lines('raised:')).toBe(0)
    end)
end)
