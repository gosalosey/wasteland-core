-- wasteland_weapons (server): holding and holstering, ammo taken from the
-- inventory per reported shot, durability and breaking, repairs, the held
-- weapon leaving the inventory, death, guarded events.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function world()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival', 'wasteland_weapons' })
    return server
end

local function player(server, license)
    local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
    server:advance(200)
    server.players[id].coords = { x = 100.0, y = 100.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    return id
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end
local function I(server, fn, ...) return server:export('wasteland_inventory', fn, ...) end
local function snap(server, id) return last(events(server, id, 'wasteland:inventory:client:sync')).args[1] end
local function find(server, id, name)
    for _, i in ipairs(snap(server, id).inventories) do
        for _, s in ipairs(i.items) do if s.name == name then return s, i.id end end
    end
end
local function use(server, id, name)
    local s, invId = find(server, id, name)
    server:clientEvent(id, 'wasteland:inventory:server:use', s.uid, invId)
    server:advance(200)
    return s
end
local function fire(server, id, n)
    server:clientEvent(id, 'wasteland:weapons:server:used', n, { x = 100.0, y = 100.0, z = 30.0 })
    server:advance(300)
end

describe('holding guns and ammo', function()
    local server = world()
    local id = player(server, 'gun')
    I(server, 'AddItem', id, 'weapon_pistol', 1)
    I(server, 'AddItem', id, 'ammo_9mm', 30)
    server:advance(200)
    local noise = {}
    server:on('wasteland:weapons:used', function(src, item, n, radius) noise[#noise + 1] = { src, item, n, radius } end)

    it('runs; weapon items are usable', function()
        expect(states(server).weapons).toBe('running')
        local defs = last(events(server, id, 'wasteland:inventory:client:definitions')).args[1]
        expect(defs.items.weapon_pistol.usable).toBe(true)
        expect(defs.items.weapon_repair_kit.usable).toBe(true)
    end)

    it('using a gun holds it with the inventory ammo; it is not used up', function()
        local pistol = use(server, id, 'weapon_pistol')
        local h = last(events(server, id, 'wasteland:weapons:client:hold')).args[1]
        expect(h.hash).toBe('WEAPON_PISTOL')
        expect(h.ammo).toBe(30)
        expect(h.melee).toBe(false)
        expect(h.durability).toBe(600)
        expect(server:export('wasteland_weapons', 'GetHeldWeapon', id).uid).toBe(pistol.uid)
        expect(find(server, id, 'weapon_pistol') ~= nil).toBe(true)
    end)

    it('reported shots take ammo, wear the weapon and make noise', function()
        fire(server, id, 5)
        expect(I(server, 'GetItemCount', id, 'ammo_9mm')).toBe(25)
        expect(find(server, id, 'weapon_pistol').metadata.durability).toBe(595)
        local st = last(events(server, id, 'wasteland:weapons:client:state')).args[1]
        expect(st.ammo).toBe(25)
        expect(noise[1][2]).toBe('weapon_pistol'); expect(noise[1][3]).toBe(5); expect(noise[1][4]).toBe(120)
    end)

    it('cannot take more ammo than the player has (and logs it)', function()
        fire(server, id, 40)
        expect(I(server, 'GetItemCount', id, 'ammo_9mm')).toBe(0)
        expect(find(server, id, 'weapon_pistol').metadata.durability).toBe(570)
        expect(#server:lines('reported 40 shots with weapon_pistol but had 25')).toBe(1)
        fire(server, id, 3)
        expect(find(server, id, 'weapon_pistol').metadata.durability).toBe(570)
    end)

    it('picking up ammo updates the held weapon', function()
        I(server, 'AddItem', id, 'ammo_9mm', 12)
        server:advance(200)
        expect(last(events(server, id, 'wasteland:weapons:client:state')).args[1].ammo).toBe(12)
    end)

    it('using it again holsters', function()
        use(server, id, 'weapon_pistol')
        expect(#events(server, id, 'wasteland:weapons:client:holster')).toBe(1)
        expect(server:export('wasteland_weapons', 'GetHeldWeapon', id)).toBe(nil)
        fire(server, id, 2) -- ignored: nothing held
        expect(I(server, 'GetItemCount', id, 'ammo_9mm')).toBe(12)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('melee, breaking and repairs', function()
    local server = world()
    local id = player(server, 'axe')
    I(server, 'AddItem', id, 'weapon_knife', 1, { durability = 3 })
    I(server, 'AddItem', id, 'weapon_repair_kit', 2)
    server:advance(200)

    it('a repair kit needs a weapon in hand', function()
        use(server, id, 'weapon_repair_kit')
        expect(I(server, 'GetItemCount', id, 'weapon_repair_kit')).toBe(2)
        expect(last(events(server, id, 'wasteland:inventory:client:error')).args[1]).toContain('Hold the weapon')
    end)

    it('melee hits wear the weapon until it breaks; broken weapons do nothing', function()
        use(server, id, 'weapon_knife')
        local h = last(events(server, id, 'wasteland:weapons:client:hold')).args[1]
        expect(h.melee).toBe(true)
        fire(server, id, 5)
        expect(find(server, id, 'weapon_knife').metadata.durability).toBe(0)
        expect(last(events(server, id, 'wasteland:weapons:client:notice')).args[1]).toContain('broke')
        expect(last(events(server, id, 'wasteland:weapons:client:state')).args[1].broken).toBe(true)
        fire(server, id, 1)
        expect(#server:lines('reported 1 uses of a broken weapon_knife')).toBe(1)
    end)

    it('a repair kit restores 40% of full durability and is used up', function()
        use(server, id, 'weapon_repair_kit')
        expect(find(server, id, 'weapon_knife').metadata.durability).toBe(120)
        expect(I(server, 'GetItemCount', id, 'weapon_repair_kit')).toBe(1)
        expect(last(events(server, id, 'wasteland:weapons:client:state')).args[1].broken).toBe(false)
    end)
end)

describe('the held weapon leaving the inventory', function()
    local server = world()
    local id = player(server, 'drop')
    I(server, 'AddItem', id, 'weapon_bat', 1)
    I(server, 'AddItem', id, 'weapon_pistol', 1)
    server:advance(200)

    it('dropping the held weapon holsters it', function()
        local bat = use(server, id, 'weapon_bat')
        server:clientEvent(id, 'wasteland:inventory:server:drop', bat.uid, 'player:1', 1)
        server:advance(300)
        expect(#events(server, id, 'wasteland:weapons:client:holster')).toBe(1)
        expect(server:export('wasteland_weapons', 'GetHeldWeapon', id)).toBe(nil)
    end)

    it('dying holsters the weapon', function()
        use(server, id, 'weapon_pistol')
        server:clientEvent(id, 'wasteland:survival:server:died')
        server:advance(300)
        expect(server:export('wasteland_weapons', 'GetHeldWeapon', id)).toBe(nil)
    end)

    it('rejects bad reports before the module sees them', function()
        local violations = 0
        server:on('wasteland:core:netViolation', function(_, _, name) if name == 'wasteland:weapons:server:used' then violations = violations + 1 end end)
        server:clientEvent(id, 'wasteland:weapons:server:used', 0, {})
        server:clientEvent(id, 'wasteland:weapons:server:used', 'lots', {})
        expect(violations).toBe(2)
        expect(#server.scriptErrors).toBe(0)
    end)

end)
