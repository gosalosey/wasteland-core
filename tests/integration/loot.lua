-- wasteland_loot (server): searching world props (checks, timing, fill,
-- shared containers, refills, "found nothing"), zombie bodies, abuse.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['loot.lua'] = [[return {
        containers = {
            dumpster = { label = 'Dumpster', table = 'sure', searchSeconds = 2, refillMinutes = 1, grid = { 4, 4 }, models = { 'prop_dumpster_01a' } },
            bin = { label = 'Trash can', table = 'none', searchSeconds = 1, refillMinutes = 1, models = { 'prop_bin_01a' } },
            body = { label = 'Body', table = 'sure', searchSeconds = 1, refillMinutes = 9999 },
            wreck = { label = 'Wrecked vehicle', table = 'sure', searchSeconds = 1, refillMinutes = 1, reach = 7, models = { 'prop_rub_carwreck_3' } },
            tree = { label = 'Tree', action = 'Chop', verb = 'Chopping', table = 'sure', searchSeconds = 1, refillMinutes = 1,
                direct = true, tools = { 'weapon_hatchet' }, anim = 'chop', models = { 'prop_tree_pine_01' } },
        },
        tables = {
            sure = { emptyChance = 0, rolls = { 1, 1 }, items = { { name = 'bandage', min = 3, max = 3, weight = 1 } } },
            none = { emptyChance = 1, rolls = { 1, 1 }, items = { { name = 'rag', min = 1, max = 1, weight = 1 } } },
        },
    }]],
    ['zombies.lua'] = 'return { population = { perPlayer = 0, corpseSeconds = 30 } }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function world()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival',
        'wasteland_zombies', 'wasteland_loot' })
    return server
end

local function player(server, license, coords)
    local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
    server:advance(200)
    server.players[id].coords = coords or { x = 10.0, y = 10.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    return id
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end

local DUMPSTER = { x = 11.0, y = 10.0, z = 30.0 }

describe('searching world props', function()
    local server = world()
    local a = player(server, 'ann')
    local b = player(server, 'ben', { x = 10.5, y = 10.5, z = 30.0 })
    local env = server.resources.wasteland_loot.env
    local DUMP, BIN = env.GetHashKey('prop_dumpster_01a'), env.GetHashKey('prop_bin_01a')

    it('runs; clients get the container models', function()
        expect(states(server).loot).toBe('running')
        local c = last(events(server, -1, 'wasteland:loot:client:config')).args[1]
        expect(c.containers.dumpster.models[1]).toBe('prop_dumpster_01a')
    end)

    it('refuses models that are not containers and searches from too far', function()
        server:clientEvent(a, 'wasteland:loot:server:start', 12345, DUMPSTER)
        server:advance(100)
        expect(#server:lines('which is not a container')).toBe(1)
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, { x = 50.0, y = 10.0, z = 30.0 })
        server:advance(100)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]).toBe('You are too far away.')
        expect(#events(server, a, 'wasteland:loot:client:search')).toBe(0)
    end)

    it('starts a timed search; finishing early does nothing', function()
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, DUMPSTER)
        server:advance(200)
        local s = last(events(server, a, 'wasteland:loot:client:search')).args[1]
        expect(s.seconds).toBe(2); expect(s.label).toBe('Searching dumpster')
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(100)
        expect(#server:lines('finished searching loot_dumpster_11_10_30 too early')).toBe(1)
        expect(#events(server, a, 'wasteland:inventory:client:open')).toBe(0)
    end)

    it('after the search the container is filled and opens next to the inventory', function()
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, DUMPSTER)
        server:advance(2100)
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(300)
        expect(#events(server, a, 'wasteland:inventory:client:open')).toBe(1)
        local snap = server:export('wasteland_inventory', 'GetInventory', 'stash:loot_dumpster_11_10_30')
        expect(#snap.items).toBe(1); expect(snap.items[1].name).toBe('bandage'); expect(snap.items[1].count).toBe(3)
        expect(snap.label).toBe('Dumpster')
    end)

    it('is shared: the next player finds what is left, and nothing more is added', function()
        server:clientEvent(b, 'wasteland:loot:server:start', DUMP, DUMPSTER)
        server:advance(2100)
        server:clientEvent(b, 'wasteland:loot:server:finish')
        server:advance(300)
        local snap = server:export('wasteland_inventory', 'GetInventory', 'stash:loot_dumpster_11_10_30')
        expect(#snap.items).toBe(1); expect(snap.items[1].count).toBe(3)
    end)

    it('once emptied it stays empty until the refill time', function()
        local uid = server:export('wasteland_inventory', 'GetInventory', 'stash:loot_dumpster_11_10_30').items[1].uid
        server:export('wasteland_inventory', 'RemoveItem', 'stash:loot_dumpster_11_10_30', 'bandage', 3)
        server:advance(100)
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, DUMPSTER)
        server:advance(300)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]).toContain('Already searched')
        server:advance(60000)
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, DUMPSTER)
        server:advance(2100)
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(300)
        local snap = server:export('wasteland_inventory', 'GetInventory', 'stash:loot_dumpster_11_10_30')
        expect(#snap.items).toBe(1); expect(snap.items[1].uid ~= uid).toBe(true)
    end)

    it('an empty roll means "you found nothing" (and it stays empty)', function()
        server:clientEvent(a, 'wasteland:loot:server:start', BIN, { x = 9.0, y = 10.0, z = 30.0 })
        server:advance(1100)
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(300)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]).toBe('You found nothing.')
        server:clientEvent(a, 'wasteland:loot:server:start', BIN, { x = 9.0, y = 10.0, z = 30.0 })
        server:advance(300)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]).toContain('Already searched')
    end)

    it('moving away during the search fails it; a cancelled search cannot be finished', function()
        server.players[a].coords = { x = 30.0, y = 30.0, z = 30.0 }
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, { x = 31.0, y = 30.0, z = 30.0 })
        server:advance(1000)
        server.players[a].coords = { x = 60.0, y = 30.0, z = 30.0 }
        server:advance(1100)
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(300)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]).toBe('You moved away.')
        server.players[a].coords = { x = 30.0, y = 30.0, z = 30.0 }
        server:clientEvent(a, 'wasteland:loot:server:start', DUMP, { x = 31.0, y = 30.0, z = 30.0 })
        server:advance(300)
        server:clientEvent(a, 'wasteland:loot:server:cancel')
        server:advance(2100)
        local opens = #events(server, a, 'wasteland:inventory:client:open')
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(300)
        expect(#events(server, a, 'wasteland:inventory:client:open')).toBe(opens)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('searching zombie bodies', function()
    local server = world()
    local a = player(server, 'cat')
    local netId = server:export('wasteland_zombies', 'SpawnZombie', { x = 11.0, y = 10.0, z = 30.0 })
    local z = server:entityList('wlZombie')[1]

    it('a living zombie cannot be searched', function()
        server:clientEvent(a, 'wasteland:loot:server:body', netId)
        server:advance(300)
        expect(#events(server, a, 'wasteland:loot:client:search')).toBe(0)
    end)

    it('a dead one can: its loot opens, and no loot bag is dropped', function()
        z.health = 0
        server:clientEvent(a, 'wasteland:zombies:server:died', netId)
        server:advance(300)
        local drops = last(events(server, -1, 'wasteland:inventory:client:drops'))
        expect(drops == nil or #drops.args[1] == 0).toBe(true)
        server:clientEvent(a, 'wasteland:loot:server:body', netId)
        server:advance(1100)
        server:clientEvent(a, 'wasteland:loot:server:finish')
        server:advance(300)
        local name = 'stash:loot_body_' .. z.state.wlZombie.uid
        expect(server:export('wasteland_inventory', 'GetInventory', name).items[1].name).toBe('bandage')
    end)

    it('the body and its loot are gone when the corpse is removed', function()
        local name = 'stash:loot_body_' .. z.state.wlZombie.uid
        server:advance(31000)
        expect(server:entity(z.handle)).toBe(nil)
        expect(server:export('wasteland_inventory', 'GetInventory', name)).toBe(nil)
        local rows = 0
        for _, r in pairs(server.db.backend.data.wl_items) do if r.inventory_id == name then rows = rows + 1 end end
        expect(rows).toBe(0)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('big props: wrecked vehicles', function()
    local server = world()
    local id = player(server, 'scav', { x = 100.0, y = 100.0, z = 30.0 })
    local WRECK = server.resources.wasteland_loot.env.GetHashKey('prop_rub_carwreck_3')

    it('can be searched from the side (reach 7 m from the middle), not from further', function()
        server:clientEvent(id, 'wasteland:loot:server:start', WRECK, { x = 108.0, y = 100.0, z = 30.0 })
        server:advance(200)
        expect(last(events(server, id, 'wasteland:loot:client:notice')).args[1]).toBe('You are too far away.')
        server:clientEvent(id, 'wasteland:loot:server:start', WRECK, { x = 105.5, y = 100.0, z = 30.0 })
        server:advance(200)
        expect(last(events(server, id, 'wasteland:loot:client:search')).args[1].label).toBe('Searching wrecked vehicle')
        server:advance(1100)
        server:clientEvent(id, 'wasteland:loot:server:finish')
        server:advance(300)
        expect(#events(server, id, 'wasteland:inventory:client:open')).toBe(1)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)

describe('props made lootable in the admin panel', function()
    local server = world()
    local id = player(server, 'admin', { x = 200.0, y = 200.0, z = 30.0 })
    local function L(fn, ...) return server:export('wasteland_loot', fn, ...) end
    local CONE = -1234567890            -- some prop model (signed, as the game reports it)
    local CONE_U = CONE + 4294967296    -- the same hash read unsigned

    it('lists what a prop can become and which models are containers already', function()
        local d = L('GetLootAdminData')
        local names = {}
        for _, c in ipairs(d.containers) do names[#names + 1] = c.name end
        expect(table.concat(names, ',')).toBe('dumpster,bin,tree,wreck')
        local u = server.resources.wasteland_loot.env.GetHashKey('prop_dumpster_01a') & 0xffffffff
        local dump = u >= 0x80000000 and u - 0x100000000 or u
        expect(d.known[tostring(dump)].type).toBe('dumpster')
        expect(d.known[tostring(dump)].added).toBe(false)
    end)

    it('adds a model to a container type; clients get it; it can be searched', function()
        local ok, err = L('AddContainerModel', CONE_U, 'dumpster')
        expect(ok).toBe(true)
        local c = last(events(server, -1, 'wasteland:loot:client:config')).args[1]
        local found = false
        for _, m in ipairs(c.containers.dumpster.models) do if m == CONE then found = true end end
        expect(found).toBe(true)
        expect(L('GetLootAdminData').known[tostring(CONE)].added).toBe(true)
        server:clientEvent(id, 'wasteland:loot:server:start', CONE, { x = 201.0, y = 200.0, z = 30.0 })
        server:advance(200)
        expect(last(events(server, id, 'wasteland:loot:client:search')).args[1].label).toBe('Searching dumpster')
    end)

    it('refuses unknown types, bodies and models loot.lua already uses', function()
        expect(select(2, L('AddContainerModel', 5, 'nope'))).toBe('unknown loot container type')
        expect(select(2, L('AddContainerModel', 5, 'body'))).toBe('unknown loot container type')
        local bin = server.resources.wasteland_loot.env.GetHashKey('prop_bin_01a')
        expect(select(2, L('AddContainerModel', bin, 'wreck'))).toContain('already a trash can')
    end)

    it('is kept after a restart, can be changed and removed', function()
        server:restart('wasteland_loot'); server:advance(500)
        expect(L('GetLootAdminData').known[tostring(CONE)].type).toBe('dumpster')
        expect(L('AddContainerModel', CONE, 'wreck')).toBe(true)
        expect(L('GetLootAdminData').known[tostring(CONE)].type).toBe('wreck')
        expect(L('RemoveContainerModel', CONE)).toBe(true)
        expect(L('GetLootAdminData').known[tostring(CONE)] == nil).toBe(true)
        expect(select(2, L('RemoveContainerModel', CONE))).toBe('that prop was not added in the admin panel')
        server:restart('wasteland_loot'); server:advance(500)
        expect(L('GetLootAdminData').known[tostring(CONE)] == nil).toBe(true)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)


describe('loot categories made in the admin panel', function()
    local server = world()
    local id = player(server, 'boss', { x = 300.0, y = 300.0, z = 30.0 })
    local function L(fn, ...) return server:export('wasteland_loot', fn, ...) end
    local SAFE = -55555
    local def = { label = 'Gun safe', searchSeconds = 1, refillMinutes = 5, gridW = 3, gridH = 3, emptyChance = 0, rollsMin = 1, rollsMax = 1,
        items = { { name = 'ammo_9mm', min = 7, max = 7, weight = 1 } } }

    it('checks the definition', function()
        expect(select(2, L('SaveLootCategory', 'Bad Id', def))).toContain('lower case')
        expect(select(2, L('SaveLootCategory', 'dumpster', def))).toBe('"dumpster" is already a loot type in loot.lua')
        expect(select(2, L('SaveLootCategory', 'safe', { label = '', items = def.items }))).toContain('give it a name')
        expect(select(2, L('SaveLootCategory', 'safe', { label = 'X', items = {} }))).toBe('add at least one item')
        expect(select(2, L('SaveLootCategory', 'safe', { label = 'X', items = { { name = 'no_such_item' } } }))).toBe('unknown item "no_such_item"')
        expect(select(2, L('SaveLootCategory', 'safe', { label = 'X', rollsMin = 3, rollsMax = 1, items = def.items }))).toContain('least items')
    end)

    it('is created, props can use it, and it gives its own loot', function()
        expect(L('SaveLootCategory', 'gun_safe', def)).toBe(true)
        expect(L('GetLootAdminData').custom.gun_safe.label).toBe('Gun safe')
        expect(L('AddContainerModel', SAFE, 'gun_safe', 'prop_ld_int_safe_01')).toBe(true)
        expect(L('GetLootAdminData').known[tostring(SAFE)].name).toBe('prop_ld_int_safe_01')
        server:clientEvent(id, 'wasteland:loot:server:start', SAFE, { x = 301.0, y = 300.0, z = 30.0 })
        server:advance(1200)
        server:clientEvent(id, 'wasteland:loot:server:finish')
        server:advance(300)
        local snap = server:export('wasteland_inventory', 'GetInventory', 'stash:loot_gun_safe_301_300_30')
        expect(snap.items[1].name).toBe('ammo_9mm'); expect(snap.items[1].count).toBe(7)
    end)

    it('is kept after a restart and can be changed', function()
        server:restart('wasteland_loot'); server:advance(500)
        expect(L('GetLootAdminData').custom.gun_safe.items[1].name).toBe('ammo_9mm')
        expect(L('GetLootAdminData').known[tostring(SAFE)].type).toBe('gun_safe')
        def.label = 'Big gun safe'
        expect(L('SaveLootCategory', 'gun_safe', def)).toBe(true)
        expect(L('GetLootAdminData').custom.gun_safe.label).toBe('Big gun safe')
    end)

    it('deleting it stops its props being searchable', function()
        expect(L('DeleteLootCategory', 'gun_safe')).toBe(true)
        expect(L('GetLootAdminData').custom.gun_safe == nil).toBe(true)
        expect(L('GetLootAdminData').known[tostring(SAFE)] == nil).toBe(true)
        expect(select(2, L('DeleteLootCategory', 'dumpster'))).toBe('that is not a loot category made in the admin panel')
        server:restart('wasteland_loot'); server:advance(500)
        expect(L('GetLootAdminData').custom.gun_safe == nil).toBe(true)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)

describe('named loot props', function()
    local server = world()
    local id = player(server, 'namer', { x = 400.0, y = 400.0, z = 30.0 })
    local function L(fn, ...) return server:export('wasteland_loot', fn, ...) end
    local BARREL = -777777

    it('players see the name: target option list, search bar and container', function()
        expect(L('AddContainerModel', BARREL, 'dumpster', '  Old  barrel ')).toBe(true)
        local c = last(events(server, -1, 'wasteland:loot:client:config')).args[1]
        expect(c.names[tostring(BARREL)]).toBe('Old  barrel')
        server:clientEvent(id, 'wasteland:loot:server:start', BARREL, { x = 401.0, y = 400.0, z = 30.0 })
        server:advance(200)
        expect(last(events(server, id, 'wasteland:loot:client:search')).args[1].label).toBe('Searching Old  barrel')
        server:advance(2100)
        server:clientEvent(id, 'wasteland:loot:server:finish'); server:advance(300)
        expect(#events(server, id, 'wasteland:inventory:client:open')).toBe(1)
    end)

    it('odd characters are not kept as a name', function()
        expect(L('AddContainerModel', BARREL, 'dumpster', '<b>bad</b>')).toBe(true)
        expect(last(events(server, -1, 'wasteland:loot:client:config')).args[1].names[tostring(BARREL)] == nil).toBe(true)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)

describe('trees: a tool, and the wood goes straight into the inventory', function()
    local server = world()
    local a = player(server, 'logger')
    local env = server.resources.wasteland_loot.env
    local TREE = env.GetHashKey('prop_tree_pine_01')
    local AT = { x = 11.0, y = 10.0, z = 30.0 }
    local function count(name) return server:export('wasteland_inventory', 'GetItemCount', a, name) end

    it('the option says Chop', function()
        local c = last(events(server, -1, 'wasteland:loot:client:config')).args[1]
        expect(c.containers.tree.action).toBe('Chop')
    end)

    it('without a hatchet: refused', function()
        server:clientEvent(a, 'wasteland:loot:server:start', TREE, AT); server:advance(200)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]).toBe('You need a hatchet for that.')
        expect(#events(server, a, 'wasteland:loot:client:search')).toBe(0)
    end)

    it('with a hatchet: chopping, then the items are in the inventory (no container opens)', function()
        server:export('wasteland_inventory', 'AddItem', a, 'weapon_hatchet', 1)
        local before = count('bandage')
        server:clientEvent(a, 'wasteland:loot:server:start', TREE, AT); server:advance(200)
        expect(last(events(server, a, 'wasteland:loot:client:search')).args[1].label).toBe('Chopping tree')
        server:advance(1100)
        server:clientEvent(a, 'wasteland:loot:server:finish'); server:advance(200)
        expect(count('bandage')).toBe(before + 3)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]).toBe('You got 3 x Bandage.')
    end)

    it('the same tree again right away: nothing left for now', function()
        server:clientEvent(a, 'wasteland:loot:server:start', TREE, AT); server:advance(200)
        expect(last(events(server, a, 'wasteland:loot:client:notice')).args[1]:find('Nothing left here right now', 1, true) ~= nil).toBe(true)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)
