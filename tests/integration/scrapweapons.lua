-- wasteland_scrapweapons and the registration exports it relies on:
-- RegisterItem (inventory), RegisterWeapon (weapons), RegisterRecipe
-- (crafting). A test catalog stands in for the real weapons.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local TEST_CATALOG = {
    scrap_test_club = {
        item = { label = 'Test club', category = 'weapon', width = 1, height = 3, weight = 0.6, durability = 50 },
        weapon = { hash = 'WEAPON_WL_TESTCLUB', noise = 9 },
        recipe = { label = 'Test club', result = { name = 'scrap_test_club', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 2 } }, seconds = 1 },
        status = 'testing',
    },
}

describe('scrap weapons: registration', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_weapons', 'wasteland_crafting', 'wasteland_scrapweapons' })
    local id = server:connectAndJoin({ name = 'P-scrap', license = 'scrap' })
    server:advance(200)
    server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
    server:command(id, 'character create Scrap Test'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
    local env = server.resources.wasteland_scrapweapons.env

    it('the shipped catalog registers and breaks nothing', function()
        local cat = server:export('wasteland_scrapweapons', 'GetCatalog')
        expect(cat.scrap_spiked_bat.hash).toBe('WEAPON_WL_SPIKEDBAT')
        expect(server:export('wasteland_weapons', 'GetWeaponConfig', 'scrap_spiked_bat').hash).toBe('WEAPON_WL_SPIKEDBAT')
        expect(server:export('wasteland_inventory', 'GetItemDefinition', 'scrap_spiked_bat').label).toBe('Spiked bat')
        expect(states(server).weapons).toBe('running')
        expect(states(server).crafting).toBe('running')
        expect(#server.scriptErrors).toBe(0)
    end)

    it('the spiked bat is crafted from a bat, nails, scrap and tape', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        I('AddItem', id, 'weapon_bat', 1); I('AddItem', id, 'nails', 10); I('AddItem', id, 'scrap_metal', 1); I('AddItem', id, 'duct_tape', 1)
        server:advance(100)
        local tape = I('GetItemCount', id, 'duct_tape')
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'scrap_spiked_bat'); server:advance(8200)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(I('GetItemCount', id, 'scrap_spiked_bat')).toBe(1)
        expect(I('GetItemCount', id, 'weapon_bat')).toBe(0)
        expect(I('GetItemCount', id, 'nails')).toBe(0)
        expect(I('GetItemCount', id, 'duct_tape')).toBe(tape - 1)
    end)

    it('a catalog weapon becomes an item, a weapon you can hold and a recipe', function()
        env.WLSW.catalog = TEST_CATALOG
        env.TriggerEvent('wasteland:core:moduleState', 'inventory', 'running')
        server:advance(100)
        expect(server:export('wasteland_inventory', 'GetItemDefinition', 'scrap_test_club').label).toBe('Test club')
        expect(server:export('wasteland_weapons', 'GetWeaponConfig', 'scrap_test_club').hash).toBe('WEAPON_WL_TESTCLUB')
        expect(server:export('wasteland_weapons', 'GetWeaponConfig', 'scrap_test_club').wear).toBe(1) -- default applied
        server:export('wasteland_inventory', 'AddItem', id, 'scrap_metal', 2); server:advance(100)
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'scrap_test_club'); server:advance(1200)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(server:export('wasteland_inventory', 'GetItemCount', id, 'scrap_test_club')).toBe(1)
        expect(server:export('wasteland_inventory', 'GetItemCount', id, 'scrap_metal')).toBe(0)
        local snap = server:clientEventsFor(id, 'wasteland:inventory:client:sync')
        local uid, invId
        for _, i in ipairs(snap[#snap].args[1].inventories) do
            for _, st in ipairs(i.items) do if st.name == 'scrap_test_club' then uid, invId = st.uid, i.id end end
        end
        server:clientEvent(id, 'wasteland:inventory:server:use', uid, invId); server:advance(200)
        local held = server:export('wasteland_weapons', 'GetHeldWeapon', id)
        expect(held and held.item).toBe('scrap_test_club')
    end)

    it('registering again (a restart) is allowed; bad definitions are refused with a reason', function()
        env.TriggerEvent('wasteland:core:moduleState', 'inventory', 'running'); server:advance(100)
        local ok, err = server:export('wasteland_weapons', 'RegisterWeapon', 'scrap_nothing', { hash = 'WEAPON_X' })
        expect(ok).toBe(false); expect(err:find('unknown item', 1, true) ~= nil).toBe(true)
        ok, err = server:export('wasteland_weapons', 'RegisterWeapon', 'scrap_test_club', { hash = 'not a hash' })
        expect(ok).toBe(false)
        ok, err = server:export('wasteland_crafting', 'RegisterRecipe', 'scrap_x', { label = 'X', result = { name = 'nope', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 1 } } })
        expect(ok).toBe(false); expect(err:find('nope', 1, true) ~= nil).toBe(true)
        -- a config weapon is not replaced
        ok = server:export('wasteland_weapons', 'RegisterWeapon', 'weapon_bat', { hash = 'WEAPON_WL_OTHER' })
        expect(server:export('wasteland_weapons', 'GetWeaponConfig', 'weapon_bat').hash).toBe('WEAPON_BAT')
        expect(#server.scriptErrors).toBe(0)
    end)
end)
