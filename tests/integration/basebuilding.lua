-- wasteland_basebuilding (server): the build item, tool cupboards (claim,
-- access, group, authorize/revoke), placing pieces (materials, not on
-- someone else's land), doors, storage, lockpicking (and the raid notice),
-- upgrades, melee damage and repairs, upkeep (paid from supplies, decay
-- when short), kept across a restart, removing with a refund.

local function shipped(name, from, to)
    local f = assert(io.open(RESOURCES .. '/wasteland_config/config/' .. name, 'r'))
    local text = f:read('a')
    f:close()
    for i = 1, #from do
        local a, b = text:find(from[i], 1, true)
        assert(a, 'not in ' .. name .. ': ' .. from[i])
        text = text:sub(1, a - 1) .. to[i] .. text:sub(b + 1)
    end
    return text
end

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    -- upkeep every minute, 1 unit a minute per piece (so a test minute shows it)
    ['basebuilding.lua'] = shipped('basebuilding.lua', { 'tickMinutes = 5,', 'perPieceCostPerDay = { wood = 0.25, stone = 0.25, metal = 0.25 },' },
        { 'tickMinutes = 1,', 'perPieceCostPerDay = { wood = 1440, stone = 1440, metal = 1440 },' }),
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('base building', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_groups', 'wasteland_basebuilding' })
    local function player(license, first, x)
        local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
        server:advance(200)
        server:command(id, 'character create ' .. first .. ' Test'); server:advance(300)
        server:command(id, 'character select 1'); server:advance(500)
        server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
        server.players[id].coords = { x = x, y = 0.0, z = 30.0 }
        return id
    end
    local a = player('bba', 'Owen', 0.0)
    local b = player('bbb', 'Gwen', 1.0)   -- joins Owen's group
    local c = player('bbc', 'Rick', 2.0)   -- a stranger, later given access, then a raider
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local function last(id, ev) local l = server:clientEventsFor(id, ev); return l[#l] end
    local function note(id) local e = last(id, 'wasteland:basebuilding:client:notice'); return e and e.args[1] end
    local function act(id, what, ...) server:clientEvent(id, 'wasteland:basebuilding:server:' .. what, ...); server:advance(200) end
    local function place(id, key, x, y) act(id, 'place', key, x, y, 30.0, 0.0) end
    local function lastProp(id) return last(id, 'wasteland:basebuilding:client:propAdded').args[1] end
    for _, p in ipairs({ a, b, c }) do I('ClearInventory', p) end
    server:advance(200)

    local cupboardId
    it('runs; the building plan opens the build menu', function()
        expect(states(server).basebuilding).toBe('running')
        I('AddItem', a, 'building_plan', 1); server:advance(100)
        local plan
        for _, s in ipairs(I('GetTradeable', a)) do if s.name == 'building_plan' then plan = s end end
        server:clientEvent(a, 'wasteland:inventory:server:use', plan.uid, plan.inventoryId); server:advance(200)
        local view = last(a, 'wasteland:basebuilding:client:build').args[1]
        expect(view.categories[1].key).toBe('structure')
        expect(I('GetItemCount', a, 'building_plan')).toBe(1) -- not used up
    end)

    it('storage cannot be built before a tool cupboard claims the land', function()
        I('AddItem', a, 'wood_planks', 40); I('AddItem', a, 'scrap_metal', 6); server:advance(100)
        place(a, 'stash_small', 4.0, 0.0)
        expect(note(a)).toContain('Place a Tool Cupboard first')
    end)

    it('a tool cupboard claims the land for its owner', function()
        place(a, 'toolcupboard', 1.0, 1.0)
        local added = last(a, 'wasteland:basebuilding:client:cupboardAdded').args[1]
        cupboardId = added.id
        expect(added.radius).toBe(40.0)
        expect(I('GetItemCount', a, 'wood_planks')).toBe(30)
        expect(last(a, 'wasteland:basebuilding:client:mine').args[1][1]).toBe(cupboardId)
        expect(#last(c, 'wasteland:basebuilding:client:mine').args[1]).toBe(0)
    end)

    it('a tool cupboard keeps zombies out of 20 m around it (a safe zone for building)', function()
        local BB = function(...) return server:export('wasteland_basebuilding', 'IsInBaseZone', ...) end
        expect(BB({ x = 1.0, y = 1.0, z = 30.0 })).toBe(true)
        expect(BB({ x = 19.0, y = 1.0, z = 30.0 })).toBe(true)
        expect(BB({ x = 24.0, y = 1.0, z = 30.0 })).toBe(false)
    end)

    local foundation, door, box
    it('the owner builds; a stranger cannot build on the claim', function()
        place(a, 'foundation', 4.0, 0.0)
        foundation = lastProp(a)
        expect(foundation.piece).toBe('foundation'); expect(foundation.health).toBe(500)
        I('AddItem', c, 'wood_planks', 20); server:advance(100)
        place(c, 'wall', 5.0, 0.0)
        expect(note(c)).toBe('You are not allowed to build here.')
        place(a, 'door', 3.0, 1.0)
        door = lastProp(a)
        I('AddItem', a, 'wood_planks', 10); I('AddItem', a, 'scrap_metal', 2); server:advance(100)
        place(a, 'stash_small', 2.0, -1.0)
        box = lastProp(a)
        expect(box.category).toBe('stash')
    end)

    it('moving a placed piece: storage keeps what is in it; a stranger may not move it', function()
        act(a, 'stash', box.id) -- opening it loads the storage
        local inv = 'stash:bb_stash_' .. box.id
        I('AddItem', inv, 'bandage', 2); server:advance(200)
        expect(I('GetItemCount', inv, 'bandage')).toBe(2)
        act(a, 'move', box.id, 3.0, -2.0, 30.0, 90.0)
        expect(note(a)).toBe('Moved.')
        local moved = last(c, 'wasteland:basebuilding:client:propMoved').args
        expect(moved[1]).toBe(box.id); expect(moved[2].coords.x).toBe(3.0); expect(moved[2].heading).toBe(90.0)
        expect(server.db.backend.data.wl_bb_props[box.id].x).toBe(3.0)
        expect(I('GetItemCount', inv, 'bandage')).toBe(2)
        act(c, 'move', box.id, 2.0, -1.0, 30.0, 0.0)
        expect(note(c)).toBe('You are not allowed to move this.')
    end)

    it('the owner moves the tool cupboard; nobody else can', function()
        act(a, 'moveCupboard', cupboardId, 2.0, 2.0, 30.0, 45.0)
        expect(note(a)).toBe('Tool cupboard moved.')
        expect(last(c, 'wasteland:basebuilding:client:cupboardMoved').args[2].coords.x).toBe(2.0)
        act(c, 'moveCupboard', cupboardId, 1.0, 1.0, 30.0, 0.0)
        expect(note(c)).toBe('Only the owner can move this tool cupboard.')
    end)

    it('doors: the owner opens them, a stranger finds them locked', function()
        act(a, 'door', door.id)
        expect(last(c, 'wasteland:basebuilding:client:door').args[2]).toBe(true)
        act(c, 'door', door.id)
        expect(note(c)).toContain('This door is locked')
    end)

    it('the owner\'s group gets access; an authorized player too, until it is taken away', function()
        server:clientEvent(a, 'wasteland:groups:server:create', 'Builders'); server:advance(300)
        server:clientEvent(a, 'wasteland:groups:server:invite', b); server:advance(200)
        server:clientEvent(b, 'wasteland:groups:server:view'); server:advance(100)
        local gid = last(b, 'wasteland:groups:client:view').args[1].invite.group
        server:clientEvent(b, 'wasteland:groups:server:respond', gid, true); server:advance(600)
        act(b, 'door', door.id)
        expect(last(b, 'wasteland:basebuilding:client:door').args[2]).toBe(false)
        -- authorize the stranger by player id
        act(a, 'authorize', cupboardId, c)
        local view = last(a, 'wasteland:basebuilding:client:cupboard').args[1]
        expect(view.auth[1].name).toBe('Rick Test')
        act(c, 'stash', box.id)
        expect(#server:clientEventsFor(c, 'wasteland:inventory:client:open')).toBe(1)
        act(a, 'revoke', cupboardId, view.auth[1].id)
        act(c, 'stash', box.id)
        expect(note(c)).toContain('This storage is locked')
    end)

    it('lockpicking: the minigame result decides; a fail breaks the pick; the owner hears about it', function()
        act(c, 'lockpick', door.id)
        expect(note(c)).toBe('You need a lockpick.')
        I('AddItem', c, 'lockpick', 2); server:advance(100)
        act(c, 'lockpick', door.id)
        expect(last(c, 'wasteland:basebuilding:client:lockpick') ~= nil).toBe(true)
        server:advance(1500)
        act(c, 'lockpickResult', false)
        expect(note(c)).toBe('The lockpick snaps.')
        expect(I('GetItemCount', c, 'lockpick')).toBe(1)
        server:advance(5100) -- cooldown
        act(c, 'lockpick', door.id)
        server:advance(1500)
        act(c, 'lockpickResult', true)
        expect(note(c)).toBe('Lock picked!')
        expect(last(c, 'wasteland:basebuilding:client:door').args[2]).toBe(true)
        expect(note(a)).toBe('Your base is being raided! A door was lockpicked.')
    end)

    it('upgrade wood to stone; melee hurts wood; repairs need materials', function()
        I('AddItem', a, 'stone', 10); server:advance(100)
        act(a, 'upgrade', foundation.id)
        local up = last(a, 'wasteland:basebuilding:client:propUpgraded')
        expect(up.args[2].piece).toBe('foundation_stone'); expect(up.args[2].health).toBe(1000)
        -- melee only damages wood: the door is wood
        act(c, 'melee', door.id)
        expect(last(a, 'wasteland:basebuilding:client:propHealth').args[2]).toBe(595)
        local planks = I('GetItemCount', a, 'wood_planks')
        act(a, 'repair', door.id)
        expect(last(a, 'wasteland:basebuilding:client:propHealth').args[2]).toBe(600)
        expect(I('GetItemCount', a, 'wood_planks')).toBe(planks - 3)
    end)

    it('upkeep is paid from the supplies; without them the pieces decay', function()
        server:createThread('wasteland_basebuilding', function()
            local s = I('EnsureStash', 'bb_supply_' .. cupboardId, { width = 8, height = 6, maxWeight = 300 })
            I('AddItem', s, 'wood_planks', 10)
            I('AddItem', s, 'stone', 5)
        end)
        server:advance(300)
        local before = server.db.backend.data.wl_bb_props[door.id].health
        server:advance(61000) -- one tick: the supplies pay
        local snap = I('GetInventory', 'stash:bb_supply_' .. cupboardId)
        local planks = 0
        for _, s in ipairs(snap.items) do if s.name == 'wood_planks' then planks = planks + s.count end end
        expect(planks < 10).toBe(true)
        expect(server.db.backend.data.wl_bb_props[door.id].health).toBe(before)
        -- run the supplies dry: the wood pieces decay
        server:advance(9 * 61000)
        expect(server.db.backend.data.wl_bb_props[door.id].health < before).toBe(true)
    end)

    it('is kept across a restart', function()
        server:restart('wasteland_basebuilding'); server:advance(2500)
        expect(states(server).basebuilding).toBe('running')
        local sync = last(c, 'wasteland:basebuilding:client:sync').args[1]
        expect(#sync.cupboards).toBe(1); expect(#sync.props).toBe(3)
    end)

    it('removing a piece gives half back; only the owner removes the cupboard', function()
        local planks = I('GetItemCount', a, 'wood_planks')
        act(a, 'remove', door.id)
        expect(I('GetItemCount', a, 'wood_planks')).toBe(planks + 5)
        act(b, 'removeCupboard', cupboardId)
        expect(note(b)).toBe('Only the owner can remove this tool cupboard.')
        expect(#server:lines('raised:')).toBe(0)
    end)

    it('window bars and defenses (barbed wire, sandbags) can be built', function()
        I('ClearInventory', a); server:advance(100)
        I('AddItem', a, 'wood_planks', 6); I('AddItem', a, 'scrap_metal', 4); I('AddItem', a, 'stone', 10)
        I('AddItem', a, 'rag', 4); server:advance(100)
        place(a, 'windowbar', 3.0, 2.0)
        expect(lastProp(a).piece).toBe('windowbar')
        place(a, 'barbedwire', 6.0, 0.0)
        local wire = lastProp(a)
        expect(wire.piece).toBe('barbedwire'); expect(wire.category).toBe('defense')
        place(a, 'sandbags', 7.0, 3.0)
        expect(lastProp(a).piece).toBe('sandbags')
        -- a zombie walking into the wire wears it; one far away does not
        local BB = function(...) return server:export('wasteland_basebuilding', ...) end
        expect(BB('ZombieTouch', wire.id, { x = 6.5, y = 0.0, z = 30.0 })).toBe(296)
        expect(BB('ZombieTouch', wire.id, { x = 20.0, y = 0.0, z = 30.0 })).toBe(nil)
        expect(#server:lines('raised:')).toBe(0)
    end)

    it('without a cupboard (unclaimed land): a temporary barricade only its builder can use; gone after 12 hours', function()
        server.players[c].coords = { x = 300.0, y = 0.0, z = 30.0 }
        I('ClearInventory', c); server:advance(100)
        I('AddItem', c, 'wood_planks', 12); server:advance(100)
        place(c, 'door', 302.0, 0.0)
        expect(note(c)).toContain('placed without a tool cupboard')
        local barricade = lastProp(c)
        expect(barricade.cupboard_id).toBe(nil)
        -- its builder opens it; someone else finds it locked and cannot take it down
        act(c, 'door', barricade.id)
        expect(last(c, 'wasteland:basebuilding:client:door').args[2]).toBe(true)
        server.players[a].coords = { x = 301.0, y = 0.0, z = 30.0 }
        act(a, 'door', barricade.id)
        expect(note(a)).toContain('This door is locked')
        act(a, 'remove', barricade.id)
        expect(note(a)).toBe('You are not allowed to remove this.')
        server.players[a].coords = { x = 0.0, y = 0.0, z = 30.0 }
        -- 12 hours later it is gone
        local realTime = os.time
        os.time = function(t) if t then return realTime(t) end return realTime() + 13 * 3600 end
        local ok, err = pcall(function()
            server:advance(61000)
            expect(server.db.backend.data.wl_bb_props[barricade.id]).toBe(nil)
        end)
        os.time = realTime
        if not ok then error(err, 0) end
    end)

    it('the zombie-free zone lasts an hour after the cupboard is placed, then drops (the owner is told)', function()
        local BB = function(...) return server:export('wasteland_basebuilding', ...) end
        expect(BB('IsInBaseZone', { x = 1.0, y = 1.0, z = 30.0 })).toBe(true)
        local realTime = os.time
        os.time = function(t) if t then return realTime(t) end return realTime() + 3601 end
        local ok, err = pcall(function()
            expect(BB('IsInBaseZone', { x = 1.0, y = 1.0, z = 30.0 })).toBe(false)
            server:advance(16000)
            expect(note(a)).toContain('zombie-free zone round your base has dropped')
        end)
        os.time = realTime
        if not ok then error(err, 0) end
    end)

    it('/adminbuild: admins build for free (no materials, no refunds); others may not', function()
        server:command(c, 'adminbuild')
        expect(note(c)).toBe('Only admins can use admin build.')
        server.aces[a .. '|wasteland.admin'] = true
        I('ClearInventory', a); server:advance(100)
        server:command(a, 'adminbuild')
        expect(note(a)).toContain('Admin build ON')
        place(a, 'wall', 3.0, 2.0)
        local wall = lastProp(a)
        expect(wall.piece).toBe('wall')
        act(a, 'remove', wall.id)
        expect(I('GetItemCount', a, 'wood_planks')).toBe(0) -- no refund while on
        server:command(a, 'adminbuild')
        expect(note(a)).toBe('Admin build OFF.')
        place(a, 'wall', 3.0, 2.0)
        expect(note(a)).toContain('You need')
        server.aces[a .. '|wasteland.admin'] = nil
    end)


    it('external wall: its barbed wire hurts only someone up at the top of it', function()
        I('AddItem', a, 'metal_sheet', 8); I('AddItem', a, 'scrap_metal', 6); server:advance(100)
        place(a, 'extwall', 6.0, 4.0)
        local wall = lastProp(a)
        expect(wall.piece).toBe('extwall')
        local before = #server:clientEventsFor(a, 'wasteland:basebuilding:client:wireHurt')
        server.players[a].coords = { x = 6.0, y = 3.6, z = 31.0 }       -- standing next to it
        act(a, 'wire', wall.id); server:advance(1000)
        expect(#server:clientEventsFor(a, 'wasteland:basebuilding:client:wireHurt')).toBe(before)
        server.players[a].coords = { x = 6.5, y = 3.8, z = 34.0 }       -- climbing over the top
        act(a, 'wire', wall.id)
        expect(note(a)).toBe('Barbed wire!')
        expect(#server:clientEventsFor(a, 'wasteland:basebuilding:client:wireHurt')).toBe(before + 1)
        server.players[a].coords = { x = 0.0, y = 0.0, z = 30.0 }
    end)

    it('generator: fuel from a jerry can, on/off, burns fuel, powers lights nearby, stops when empty', function()
        I('AddItem', a, 'metal_sheet', 6); I('AddItem', a, 'scrap_metal', 10); I('AddItem', a, 'jerry_can', 1, { fuel = 0.05 }); server:advance(200)
        place(a, 'generator', 2.0, 3.0)
        local gen = lastProp(a)
        act(a, 'generator', gen.id)
        expect(note(a)).toContain('no fuel')
        act(a, 'generatorFuel', gen.id)
        expect(note(a)).toContain('Added 0.1 L')
        act(a, 'generator', gen.id)
        expect(note(a)).toBe('Generator on.')
        local BB = function(...) return server:export('wasteland_basebuilding', 'IsPowered', ...) end
        expect(BB({ x = 10.0, y = 3.0, z = 30.0 })).toBe(true)
        expect(BB({ x = 90.0, y = 3.0, z = 30.0 })).toBe(false)
        server:advance(61000) -- 2 L an hour: 0.05 L lasts under two minutes
        server:advance(61000)
        local last = server:clientEventsFor(c, 'wasteland:basebuilding:client:power')
        expect(last[#last].args[2].is_open).toBe(false)
        expect(BB({ x = 10.0, y = 3.0, z = 30.0 })).toBe(false)
    end)
end)
