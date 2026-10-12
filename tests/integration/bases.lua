-- wasteland_bases (server): claim with a flag, build on the grid, upgrade,
-- doors, storage, demolish with refund, group access, workbench crafting,
-- sleeping bag respawn, kept across a restart, upkeep and
-- decay.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['groups.lua'] = 'return { markerSeconds = 30 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end

describe('bases', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival', 'wasteland_crafting',
        'wasteland_groups', 'wasteland_bases' })
    local function player(license, first, x)
        local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
        server:advance(200)
        server.players[id].coords = { x = x, y = 0.0, z = 30.0 }
        server:command(id, 'character create ' .. first .. ' Test'); server:advance(300)
        server:command(id, 'character select 1'); server:advance(500)
        server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
        server:advance(500)
        server.players[id].coords = { x = x, y = 0.0, z = 30.0 } -- the character was placed at a spawn point
        return id
    end
    local a = player('ba', 'Anna', 0.0)
    local b = player('bb', 'Bert', 2.0)
    local c = player('bc', 'Cleo', 4.0)
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local function give(id, name, n) assert(I('AddItem', id, name, n)) end
    local function count(id, name) return I('GetItemCount', id, name) end
    local function note(id) return last(events(server, id, 'wasteland:bases:client:notice')).args[1] end
    local function act(id, what, ...) server:clientEvent(id, 'wasteland:bases:server:' .. what, ...); server:advance(200) end
    local function lastPiece(id) return last(events(server, id, 'wasteland:bases:client:piece')).args[2] end
    local cidA = server:export('wasteland_players', 'GetCharacterId', a)

    it('runs; the flag item is needed; a claim is made and shown to everyone', function()
        expect(states(server).bases).toBe('running')
        act(a, 'placeFlag', 1.0, 1.0, 30.0, 0.0)
        expect(note(a)).toBe('You need a base flag.')
        give(a, 'base_flag', 2)
        act(a, 'placeFlag', 40.0, 1.0, 30.0, 0.0)
        expect(note(a)).toBe('Stand where you place the flag.')
        act(a, 'placeFlag', 1.0, 1.0, 30.0, 0.0)
        expect(note(a)).toContain('Base claimed.')
        expect(count(a, 'base_flag')).toBe(1)
        expect(last(events(server, c, 'wasteland:bases:client:base')).args[1].x).toBe(1.0)
        expect(last(events(server, a, 'wasteland:bases:client:access')).args[1][1]).toBe(1)
        act(a, 'placeFlag', 2.0, 1.0, 30.0, 0.0)
        expect(note(a)).toBe('You (or your group) already have a base.')
        expect(server:export('wasteland_bases', 'GetBaseOf', cidA).id).toBe(1)
    end)

    it('walls snap to the grid, one per edge; materials are taken', function()
        act(a, 'build', 'wall_scrap', 2.0, 1.2, 30.0, 0.0)
        expect(note(a)).toBe('You need 4 x Wood planks (you have 0).')
        give(a, 'wood_planks', 8); give(a, 'nails', 40)
        act(a, 'build', 'wall_scrap', 2.0, 1.2, 30.0, 0.0)
        expect(note(a)).toBe('Scrap wall built.')
        local p = lastPiece(a)
        expect(p.x).toBe(2.5); expect(p.y).toBe(1.0); expect(p.heading).toBe(0.0)
        expect(count(a, 'wood_planks')).toBe(4); expect(count(a, 'nails')).toBe(30)
        act(a, 'build', 'wall_scrap', 2.4, 1.1, 30.0, 180.0)
        expect(note(a)).toBe('Something is already built there.')
        act(a, 'build', 'wall_scrap', 60.0, 1.0, 30.0, 0.0)
        expect(note(a)).toBe('You can only build inside your own base\'s claim.')
    end)

    it('a better wall upgrades the old one in place', function()
        give(a, 'metal_sheet', 2); give(a, 'scrap_metal', 2)
        local before = lastPiece(a).id
        act(a, 'build', 'wall_metal', 2.0, 1.2, 30.0, 0.0)
        expect(note(a)).toBe('Metal wall built.')
        local p = lastPiece(a)
        expect(p.id).toBe(before); expect(p.kind).toBe('wall_metal')
        expect(server:export('wasteland_bases', 'GetBaseOf', cidA).pieces).toBe(1)
    end)

    it('doors open for the owner and the group only', function()
        give(a, 'wood_planks', 5); give(a, 'scrap_metal', 1)
        act(a, 'build', 'door_scrap', 1.1, 2.0, 30.0, 90.0)
        local door = lastPiece(a)
        expect(door.kind).toBe('door_scrap'); expect(door.heading).toBe(90.0)
        act(a, 'door', door.id)
        local ev = last(events(server, c, 'wasteland:bases:client:door'))
        expect(ev.args[1]).toBe(door.id); expect(ev.args[2]).toBe(true)
        act(c, 'door', door.id)
        expect(note(c)).toBe('This is not your base.')
        -- Bert joins Anna's group: he may use it and build
        server:clientEvent(a, 'wasteland:groups:server:create', 'Fort'); server:advance(300)
        server:clientEvent(a, 'wasteland:groups:server:invite', b); server:advance(200)
        local inv = last(events(server, b, 'wasteland:groups:client:notice'))
        expect(inv.args[1]).toContain('invites you')
        server:clientEvent(b, 'wasteland:groups:server:view'); server:advance(100)
        local gid = last(events(server, b, 'wasteland:groups:client:view')).args[1].invite.group
        server:clientEvent(b, 'wasteland:groups:server:respond', gid, true); server:advance(500)
        expect(last(events(server, b, 'wasteland:bases:client:access')).args[1][1]).toBe(1)
        act(b, 'door', door.id)
        expect(last(events(server, b, 'wasteland:bases:client:door')).args[2]).toBe(false)
        give(b, 'base_flag', 1)
        act(b, 'placeFlag', 2.0, 1.0, 30.0, 0.0)
        expect(note(b)).toBe('You (or your group) already have a base.')
    end)

    it('storage must be empty to demolish; demolish needs a second ask and refunds half', function()
        give(b, 'wood_planks', 4); give(b, 'nails', 10)
        act(b, 'build', 'storage_small', 5.0, 4.0, 30.0, 45.0)
        local crate = lastPiece(b)
        expect(crate.heading).toBe(45.0)
        server:createThread('wasteland_bases', function()
            local id = I('EnsureStash', 'base_piece_' .. crate.id, { width = 6, height = 5 })
            I('AddItem', id, 'bandage', 1)
        end)
        server:advance(300)
        act(b, 'demolish', crate.id)
        expect(note(b)).toBe('Empty it first.')
        server:createThread('wasteland_bases', function()
            local id = I('EnsureStash', 'base_piece_' .. crate.id, { width = 6, height = 5 })
            I('RemoveItem', id, 'bandage', 1)
        end)
        server:advance(300)
        act(b, 'demolish', crate.id)
        expect(note(b)).toContain('Choose Demolish again to confirm')
        local planks = count(b, 'wood_planks')
        act(b, 'demolish', crate.id)
        expect(note(b)).toBe('Storage crate demolished.')
        expect(count(b, 'wood_planks')).toBe(planks + 2)
        expect(last(events(server, a, 'wasteland:bases:client:removed')).args[2]).toBe(crate.id)
    end)

    it('the workbench lets you make metal sheets', function()
        I('ClearInventory', a)
        give(a, 'scrap_metal', 8); give(a, 'duct_tape', 2)
        server:clientEvent(a, 'wasteland:crafting:server:craft', 'metal_sheet'); server:advance(200)
        expect(last(events(server, a, 'wasteland:crafting:client:screen')).args[1].message).toBe('You need to be at a Workbench.')
        give(a, 'wood_planks', 6); give(a, 'nails', 20)
        act(a, 'build', 'workbench', 0.5, -2.0, 30.0, 0.0)
        expect(note(a)).toBe('Workbench built.')
        server:clientEvent(a, 'wasteland:crafting:server:craft', 'metal_sheet'); server:advance(200)
        expect(last(events(server, a, 'wasteland:crafting:client:progress')).args[1].label).toContain('metal sheet')
    end)

    it('a sleeping bag is where the group respawns', function()
        I('ClearInventory', a)
        give(a, 'rag', 6); give(a, 'duct_tape', 1)
        act(a, 'build', 'sleeping_bag', -3.0, -3.0, 30.0, 10.0)
        expect(note(a)).toBe('Sleeping bag built.')
        server:clientEvent(b, 'wasteland:survival:server:died'); server:advance(500)
        server:advance(16000)
        server:clientEvent(b, 'wasteland:survival:server:respawn'); server:advance(300)
        local r = last(events(server, b, 'wasteland:survival:client:respawn')).args[1]
        expect(r.x).toBe(-3.0); expect(r.y).toBe(-3.0)
    end)

    it('is kept across a restart', function()
        server:restart('wasteland_bases'); server:advance(2000)
        expect(states(server).bases).toBe('running')
        expect(server:export('wasteland_bases', 'GetBaseOf', cidA).pieces).toBe(4)
        local all = last(events(server, c, 'wasteland:bases:client:all')).args[1]
        expect(#all.bases).toBe(1); expect(#all.bases[1].pieces).toBe(4)
    end)

    it('upkeep: paid from the box, unpaid it decays and is removed', function()
        -- (other modules would make days of game time slow to run)
        server:stop('wasteland_crafting'); server:stop('wasteland_survival'); server:stop('wasteland_groups')
        -- a new base is paid for 3 days; jump past that
        server:advance(3 * 86400 * 1000 + 61000)
        expect(note(a)).toContain('Your base needs upkeep')
        server:createThread('wasteland_bases', function()
            local id = I('EnsureStash', 'base_upkeep_1', { width = 4, height = 3 })
            I('AddItem', id, 'scrap_metal', 2)
        end)
        server:advance(61000)
        expect(server:export('wasteland_bases', 'GetBaseOf', cidA) ~= nil).toBe(true)
        -- a day later the box is empty: 72 hours after that the base is gone
        server:advance((86400 + 72 * 3600) * 1000 + 120000)
        expect(server:export('wasteland_bases', 'GetBaseOf', cidA) == nil).toBe(true)
        expect(last(events(server, c, 'wasteland:bases:client:baseRemoved')).args[1]).toBe(1)
        local n = 0
        for _ in pairs(server.db.backend.data.wl_base_pieces) do n = n + 1 end
        expect(n).toBe(0)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)
