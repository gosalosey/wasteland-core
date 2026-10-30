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

    it('the spiked bat is crafted from a plank, nails, scrap and tape', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        I('AddItem', id, 'wood_planks', 1); I('AddItem', id, 'nails', 10); I('AddItem', id, 'scrap_metal', 1); I('AddItem', id, 'duct_tape', 1)
        server:advance(100)
        local tape = I('GetItemCount', id, 'duct_tape')
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'scrap_spiked_bat'); server:advance(8200)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(I('GetItemCount', id, 'scrap_spiked_bat')).toBe(1)
        expect(I('GetItemCount', id, 'wood_planks')).toBe(0)
        expect(I('GetItemCount', id, 'nails')).toBe(0)
        expect(I('GetItemCount', id, 'duct_tape')).toBe(tape - 1)
    end)

    it('the pipe shotgun: crafted from scrap, holds with 12 gauge, every shot uses a shell', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        local w = server:export('wasteland_weapons', 'GetWeaponConfig', 'scrap_pipe_shotgun')
        expect(w.hash).toBe('WEAPON_WL_PIPESHOTGUN'); expect(w.ammo).toBe('ammo_12g')
        I('AddItem', id, 'scrap_metal', 6); I('AddItem', id, 'wood_planks', 1); I('AddItem', id, 'nails', 4); I('AddItem', id, 'duct_tape', 2)
        server:advance(100)
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'scrap_pipe_shotgun'); server:advance(12200)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(I('GetItemCount', id, 'scrap_pipe_shotgun')).toBe(1)
        expect(I('GetItemCount', id, 'wood_planks')).toBe(0)
        I('AddItem', id, 'ammo_12g', 3); server:advance(100)
        local snap = server:clientEventsFor(id, 'wasteland:inventory:client:sync')
        local uid, invId
        for _, i in ipairs(snap[#snap].args[1].inventories) do
            for _, st in ipairs(i.items) do if st.name == 'scrap_pipe_shotgun' then uid, invId = st.uid, i.id end end
        end
        server:clientEvent(id, 'wasteland:inventory:server:use', uid, invId); server:advance(200)
        expect(server:export('wasteland_weapons', 'GetHeldWeapon', id).item).toBe('scrap_pipe_shotgun')
        local before = I('GetItemCount', id, 'ammo_12g')
        server:clientEvent(id, 'wasteland:weapons:server:used', 1, { x = 0.0, y = 0.0, z = 30.0 }); server:advance(200)
        expect(I('GetItemCount', id, 'ammo_12g')).toBe(before - 1)
        server:clientEvent(id, 'wasteland:inventory:server:use', uid, invId); server:advance(200)   -- put it away again
    end)

    it('the scrap axe: crafted from scrap, a log, nails, a rag and tape', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        expect(server:export('wasteland_weapons', 'GetWeaponConfig', 'scrap_axe').hash).toBe('WEAPON_WL_SCRAPAXE')
        I('ClearInventory', id); server:advance(100)   -- room in the pockets (earlier tests leave a shotgun and shells)
        I('AddItem', id, 'scrap_metal', 4); I('AddItem', id, 'wood_log', 1); I('AddItem', id, 'nails', 2); I('AddItem', id, 'rag', 1); I('AddItem', id, 'duct_tape', 1)
        server:advance(100)
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'scrap_axe'); server:advance(10200)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(I('GetItemCount', id, 'scrap_axe')).toBe(1)
        expect(I('GetItemCount', id, 'wood_log')).toBe(0)
    end)

    it('the scrap pump shotgun: crafted from scrap, sheet, planks, nails and tape; uses 12 gauge', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        local w = server:export('wasteland_weapons', 'GetWeaponConfig', 'scrap_pump_shotgun')
        expect(w.hash).toBe('WEAPON_WL_SCRAPPUMP'); expect(w.ammo).toBe('ammo_12g')
        I('ClearInventory', id); server:advance(100)
        I('AddItem', id, 'scrap_metal', 10); I('AddItem', id, 'metal_sheet', 2); I('AddItem', id, 'wood_planks', 2); I('AddItem', id, 'nails', 4); I('AddItem', id, 'duct_tape', 2)
        server:advance(100)
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'scrap_pump_shotgun'); server:advance(15200)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(I('GetItemCount', id, 'scrap_pump_shotgun')).toBe(1)
        expect(I('GetItemCount', id, 'metal_sheet')).toBe(0)
        I('ClearInventory', id); server:advance(100)
    end)

    it('the scrap bolt rifle: crafted from scrap, sheet, planks, nails and tape; uses .308', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        local w = server:export('wasteland_weapons', 'GetWeaponConfig', 'scrap_bolt_rifle')
        expect(w.hash).toBe('WEAPON_WL_SCRAPBOLT'); expect(w.ammo).toBe('ammo_308')
        I('ClearInventory', id); server:advance(100)
        I('AddItem', id, 'scrap_metal', 12); I('AddItem', id, 'metal_sheet', 1); I('AddItem', id, 'wood_planks', 3); I('AddItem', id, 'nails', 4); I('AddItem', id, 'duct_tape', 2)
        server:advance(100)
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'scrap_bolt_rifle'); server:advance(18200)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(I('GetItemCount', id, 'scrap_bolt_rifle')).toBe(1)
        I('ClearInventory', id); server:advance(100)
    end)

    it('the pipe club: crafted from scrap, tape and a rag', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        expect(server:export('wasteland_weapons', 'GetWeaponConfig', 'scrap_pipe_club').hash).toBe('WEAPON_WL_PIPECLUB')
        I('ClearInventory', id); server:advance(100)
        I('AddItem', id, 'scrap_metal', 5); I('AddItem', id, 'duct_tape', 1); I('AddItem', id, 'rag', 1)
        server:advance(100)
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'scrap_pipe_club'); server:advance(8200)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(I('GetItemCount', id, 'scrap_pipe_club')).toBe(1)
        I('ClearInventory', id); server:advance(100)
    end)

    it('the scrap machete: crafted from sheet, scrap, planks, a rag and tape', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        expect(server:export('wasteland_weapons', 'GetWeaponConfig', 'scrap_machete').hash).toBe('WEAPON_WL_SCRAPMACHETE')
        I('ClearInventory', id); server:advance(100)
        I('AddItem', id, 'metal_sheet', 1); I('AddItem', id, 'scrap_metal', 3); I('AddItem', id, 'wood_planks', 1); I('AddItem', id, 'rag', 1); I('AddItem', id, 'duct_tape', 1)
        server:advance(100)
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'scrap_machete'); server:advance(10200)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(I('GetItemCount', id, 'scrap_machete')).toBe(1)
        I('ClearInventory', id); server:advance(100)
    end)

    it('the scrap lever rifle: crafted from scrap, sheet, planks, nails and tape; uses .44', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        local w = server:export('wasteland_weapons', 'GetWeaponConfig', 'scrap_lever_rifle')
        expect(w.hash).toBe('WEAPON_WL_SCRAPLEVER'); expect(w.ammo).toBe('ammo_44')
        I('ClearInventory', id); server:advance(100)
        I('AddItem', id, 'scrap_metal', 12); I('AddItem', id, 'metal_sheet', 2); I('AddItem', id, 'wood_planks', 3); I('AddItem', id, 'nails', 6); I('AddItem', id, 'duct_tape', 1)
        server:advance(100)
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'scrap_lever_rifle'); server:advance(18200)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(I('GetItemCount', id, 'scrap_lever_rifle')).toBe(1)
        I('ClearInventory', id); server:advance(100)
    end)

    it('the heavy scrap maul: crafted from scrap, sheet, tape and a rag', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        expect(server:export('wasteland_weapons', 'GetWeaponConfig', 'scrap_maul').hash).toBe('WEAPON_WL_SCRAPMAUL')
        I('ClearInventory', id); server:advance(100)
        I('AddItem', id, 'scrap_metal', 10); I('AddItem', id, 'metal_sheet', 2); I('AddItem', id, 'duct_tape', 2); I('AddItem', id, 'rag', 1)
        server:advance(100)
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'scrap_maul'); server:advance(15200)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(I('GetItemCount', id, 'scrap_maul')).toBe(1)
        I('ClearInventory', id); server:advance(100)
    end)

    it('the improvised double-barrel: crafted from scrap, sheet, planks, nails and tape; uses 12 gauge', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        local w = server:export('wasteland_weapons', 'GetWeaponConfig', 'scrap_double_barrel')
        expect(w.hash).toBe('WEAPON_WL_SCRAPDOUBLE'); expect(w.ammo).toBe('ammo_12g')
        I('ClearInventory', id); server:advance(100)
        I('AddItem', id, 'scrap_metal', 10); I('AddItem', id, 'metal_sheet', 1); I('AddItem', id, 'wood_planks', 2); I('AddItem', id, 'nails', 4); I('AddItem', id, 'duct_tape', 2)
        server:advance(100)
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'scrap_double_barrel'); server:advance(15200)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(I('GetItemCount', id, 'scrap_double_barrel')).toBe(1)
        I('ClearInventory', id); server:advance(100)
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

    it('before the inventory module is running, RegisterItem says so instead of crashing', function()
        local inv = server.resources.wasteland_inventory.env.WLI
        local errors = #server.scriptErrors
        inv.M.active = false
        local ok, err = server:export('wasteland_inventory', 'RegisterItem', 'scrap_early', { label = 'Early', category = 'weapon' })
        inv.M.active = true
        expect(ok).toBe(false); expect(err:find('not running', 1, true) ~= nil).toBe(true)
        expect(#server.scriptErrors).toBe(errors)
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

describe('scrap weapons replace the standard ones', function()
    local CONFIG = RESOURCES .. '/wasteland_config/config/'
    local function config(name)
        local f = assert(io.open(CONFIG .. name, 'rb')); local src = f:read('a'); f:close()
        return assert(load(src, '@' .. name, 't', { vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
            vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end }))()
    end
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_scrapweapons/shared/catalog.lua', 't', env))()
    local catalog = env.WLSW.catalog
    local RETIRED = {}
    for _, n in ipairs({ 'crowbar', 'weapon_bat', 'weapon_machete', 'weapon_hammer', 'weapon_wrench', 'weapon_battleaxe', 'weapon_knuckle',
        'weapon_switchblade', 'weapon_pistol', 'weapon_revolver', 'weapon_dbshotgun', 'weapon_pumpshotgun', 'weapon_microsmg', 'weapon_smg',
        'weapon_carbine', 'weapon_assaultrifle', 'weapon_huntingrifle', 'ammo_9mm', 'ammo_556', 'ammo_762' }) do RETIRED[n] = true end

    it('inventory.lua defines every scrap weapon exactly as the catalog does', function()
        local items = config('inventory.lua').items
        for name, w in pairs(catalog) do
            local d = items[name]
            expect(name .. ':' .. tostring(d ~= nil)).toBe(name .. ':true')
            local function str(x)
                if type(x) ~= 'table' then return tostring(x) end
                local keys = {}
                for kk in pairs(x) do keys[#keys + 1] = tostring(kk) end
                table.sort(keys)
                for i, kk in ipairs(keys) do keys[i] = kk .. '=' .. tostring(x[kk]) end
                return '{' .. table.concat(keys, ',') .. '}'
            end
            for k, v in pairs(w.item) do expect(name .. '.' .. k .. '=' .. str(d[k])).toBe(name .. '.' .. k .. '=' .. str(v)) end
        end
    end)

    it('nothing hands out a retired standard weapon or its ammo any more', function()
        local found = {}
        local function check(where, name) if RETIRED[name] then found[#found + 1] = where .. ': ' .. name end end
        for tname, t in pairs(config('loot.lua').tables) do for _, it in ipairs(t.items) do check('loot ' .. tname, it.name) end end
        for _, it in ipairs(config('loot.lua').survivorCache.items or {}) do check('survivor cache', it.name) end
        for _, it in ipairs(config('supplydrops.lua').items) do check('supply drops', it.name) end
        for rname, r in pairs(config('crafting.lua').recipes) do check('recipe ' .. rname, r.result.name) end
        for sname, shop in pairs(config('camps.lua').shops) do
            for _, e in ipairs(shop.items) do if e.buy then check('shop ' .. sname, e.name) end end   -- selling old ones to traders is fine
        end
        for _, act in ipairs(config('story.lua').acts) do
            for _, step in ipairs(act.steps) do
                for _, c in ipairs(step.dialogue and step.dialogue.choices or {}) do
                    for _, g in ipairs(c.give or {}) do check('story ' .. step.id, g.name) end
                end
            end
        end
        expect(table.concat(found, ', ')).toBe('')
    end)

    it('no other config file hands them out either (events, quests, zombie bodies, ...)', function()
        local found = {}
        local skip = { ['inventory.lua'] = true, ['weapons.lua'] = true }   -- definitions: owned ones keep working
        local BS = string.char(92)
        local p = io.popen(package.config:sub(1, 1) == BS and ('dir /b "' .. (CONFIG:gsub('/', BS)) .. '*.lua"') or ('ls "' .. CONFIG .. '"'))
        for f in p:lines() do
            if f:match('%.lua$') and not skip[f] then
                local h = assert(io.open(CONFIG .. f, 'rb')); local src = h:read('a'); h:close()
                for line in src:gmatch('[^\n]+') do
                    local name = line:match("name = '([%w_]+)'")
                    -- trader lines that only buy from players are fine; so are tool lists
                    if name and RETIRED[name] and not line:match('sell = %d+ }%s*,?%s*$') then found[#found + 1] = f .. ': ' .. name end
                end
            end
        end
        p:close()
        expect(table.concat(found, ', ')).toBe('')
    end)
end)
