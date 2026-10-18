-- Weapon attachments (wasteland_weapons + inventory): fitted to a gun they fit
-- (one per slot), shown to the client as GTA components, taken off again;
-- a suppressor halves the noise zombies hear.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('weapon attachments', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival', 'wasteland_weapons' })
    local id = server:connectAndJoin({ name = 'P-att', license = 'att' })
    server:advance(200)
    server.players[id].coords = { x = 100.0, y = 100.0, z = 30.0 }
    server:command(id, 'character create Ada Attach'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local function stackOf(name)
        for _, inv in ipairs({ 'player:1' }) do
            for _, s in ipairs(I('GetInventory', inv).items) do if s.name == name then return s end end
        end
    end
    local noise = {}
    server:on('wasteland:weapons:used', function(_, item, _, range) noise[#noise + 1] = range end)
    I('ClearInventory', id); server:advance(100)
    I('AddItem', id, 'weapon_pistol', 1); I('AddItem', id, 'ammo_9mm', 20)
    I('AddItem', id, 'att_suppressor', 1); I('AddItem', id, 'att_grip', 1); I('AddItem', id, 'att_suppressor', 1)
    server:advance(100)
    local function use(item, target)
        local s = stackOf(item)
        server:clientEvent(id, 'wasteland:inventory:server:use', s.uid, 'player:1', target); server:advance(200)
    end
    local function lastState() local l = server:clientEventsFor(id, 'wasteland:weapons:client:state'); return l[#l] and l[#l].args[1] end

    it('a gun fires at its full noise before a suppressor is fitted', function()
        use('weapon_pistol') -- hold it
        server:clientEvent(id, 'wasteland:weapons:server:used', 1, { x = 100.0, y = 100.0, z = 30.0 }); server:advance(200)
        expect(noise[#noise]).toBe(120)
    end)

    it('a suppressor fits the pistol (by picking the gun); the held gun gets the GTA component', function()
        use('att_suppressor', stackOf('weapon_pistol').uid)
        expect(stackOf('weapon_pistol').metadata.attachments.suppressor).toBe('att_suppressor')
        local s = lastState()
        expect(s.components[1]).toBe('COMPONENT_AT_PI_SUPP_02')
        expect(I('GetItemCount', id, 'att_suppressor')).toBe(1) -- one used, one left
    end)

    it('suppressed shots carry half as far (zombies hear them at half the distance)', function()
        server:clientEvent(id, 'wasteland:weapons:server:used', 1, { x = 100.0, y = 100.0, z = 30.0 }); server:advance(200)
        expect(noise[#noise]).toBe(60)
    end)

    it('one per slot, and only what fits: no second suppressor, no grip on a pistol', function()
        use('att_suppressor', stackOf('weapon_pistol').uid)
        expect(I('GetItemCount', id, 'att_suppressor')).toBe(1)
        use('att_grip', stackOf('weapon_pistol').uid)
        expect(I('GetItemCount', id, 'att_grip')).toBe(1)
    end)

    it('Remove attachments gives them back; the gun is loud again', function()
        server:clientEvent(id, 'wasteland:weapons:server:detach', stackOf('weapon_pistol').uid); server:advance(200)
        expect(I('GetItemCount', id, 'att_suppressor')).toBe(2)
        expect(next(stackOf('weapon_pistol').metadata.attachments or {})).toBe(nil)
        expect(#lastState().components).toBe(0)
        server:clientEvent(id, 'wasteland:weapons:server:used', 1, { x = 100.0, y = 100.0, z = 30.0 }); server:advance(200)
        expect(noise[#noise]).toBe(120)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
