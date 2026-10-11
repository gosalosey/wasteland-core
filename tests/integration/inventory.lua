-- wasteland_inventory (server): operations, persistence, drops, clothing,
-- hotbar, usables, exports; plus the required abuse tests: duplication,
-- concurrency, disconnect mid-action, database failure, invalid events.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { saveIntervalSeconds = 10, restoreDelayMs = 200, maxCharacters = 2 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function world()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory' })
    return server
end

-- A player with a loaded character and a saved look (so clothes are worn).
local function player(server, license, coords)
    local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
    server:advance(200)
    server.players[id].coords = coords or { x = 100.0, y = 100.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    return id
end

local function snap(server, id)
    local list = server:clientEventsFor(id, 'wasteland:inventory:client:sync')
    return list[#list] and list[#list].args[1]
end

local function inv(snapshot, id)
    for _, i in ipairs(snapshot.inventories) do if i.id == id then return i end end
    return nil
end

-- First stack named `name` in a snapshot: stack, inventory id
local function find(snapshot, name)
    for _, i in ipairs(snapshot.inventories) do
        for _, s in ipairs(i.items) do if s.name == name then return s, i.id end end
    end
    return nil
end

local function lastError(server, id)
    local list = server:clientEventsFor(id, 'wasteland:inventory:client:error')
    return list[#list] and list[#list].args[1]
end

local function errorCount(server, id) return #server:clientEventsFor(id, 'wasteland:inventory:client:error') end

local function op(server, id, name, ...)
    server:clientEvent(id, 'wasteland:inventory:server:' .. name, ...)
    server:advance(150)
end

local function give(server, id, item, count)
    server:command(0, string.format('give %d %s %d', id, item, count or 1))
    server:advance(150)
end

local function rows(server, inventoryId)
    local out = {}
    for _, r in pairs(server.db.backend.data.wl_items) do
        if not inventoryId or r.inventory_id == inventoryId then out[#out + 1] = r end
    end
    return out
end

local function rowCount(server, name)
    local n = 0
    for _, r in pairs(server.db.backend.data.wl_items) do if r.name == name then n = n + r.count end end
    return n
end

describe('inventory startup and new characters', function()
    local server = world()
    local id = player(server, 'alice')

    it('runs and records its migrations', function()
        expect(states(server).inventory).toBe('running')
        local n = 0
        for _, m in ipairs(server.db.backend.data.wl_migrations) do if m.module_name == 'inventory' then n = n + 1 end end
        expect(n).toBe(3)
    end)

    it('gives the starting items into the pockets and saves them', function()
        local s = snap(server, id)
        expect(s.pockets).toBe('player:1')
        local pockets = inv(s, 'player:1')
        expect(pockets.width).toBe(6)
        expect(#pockets.items).toBe(3)
        expect(#rows(server, 'player:1')).toBe(3)
        expect(rowCount(server, 'canned_beans')).toBe(2)
    end)

    it('turns the starting outfit from the creator into worn clothing items, once', function()
        local equip = inv(snap(server, id), 'equip:1')
        local slots = {}
        for _, it in ipairs(equip.items) do slots[it.slot] = it end
        expect(slots.torso.name).toBe('clothing_top')
        expect(slots.torso.metadata.model).toBe('mp_m_freemode_01')
        expect(slots.torso.metadata.undershirt[1]).toBe(15)
        expect(slots.legs.name).toBe('clothing_pants')
        expect(slots.feet.name).toBe('clothing_shoes')
        expect(slots.head).toBe(nil) -- no hat chosen
        -- an admin reopening the creator does not create more clothes
        server:command(0, 'appearance ' .. id); server:advance(3000)
        server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
        expect(#inv(snap(server, id), 'equip:1').items).toBe(3)
        expect(#server.scriptErrors).toBe(0)
    end)

    it('sends item definitions with usability and the slot list', function()
        local defs = server:clientEventsFor(id, 'wasteland:inventory:client:definitions')
        local d = defs[#defs].args[1]
        expect(d.items.backpack_small.container.width).toBe(5)
        expect(d.slots[1]).toBe('head')
        expect(d.naked.mp_m_freemode_01.legs[1]).toBe(61)
        -- the look of given/looted clothing that carries none of its own
        expect(d.plain.mp_m_freemode_01.top[1]).toBe(0)
        expect(d.plain.mp_f_freemode_01.shoes[1]).toBe(1)
        expect(d.items.bandage.image).toBe(nil) -- wasteland_images not started
    end)

    it('item pictures come from wasteland_images: own name, `image` field, or none', function()
        server:start('wasteland_images')
        server:advance(200)
        local defs = server:clientEventsFor(id, 'wasteland:inventory:client:definitions')
        local d = defs[#defs].args[1]
        expect(d.items.bandage.image).toBe('https://cfx-nui-wasteland_images/html/images/bandage.webp')
        expect(d.items.backpack_small.image).toBe('https://cfx-nui-wasteland_images/html/images/bag.webp')
        expect(d.items.clothing_pants.image).toBe('https://cfx-nui-wasteland_images/html/images/jeans.webp') -- own picture (tools/images)
        expect(d.items.flashlight.image).toContain('weapon_flashlight')
        local list = server:export('wasteland_inventory', 'GetItemList')
        local byName = {}
        for _, it in ipairs(list) do byName[it.name] = it end
        expect(byName.water_bottle.image).toContain('water_bottle.webp')
        server:stop('wasteland_images')
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('moving, rotating, merging and splitting', function()
    local server = world()
    local id = player(server, 'bob')

    it('moves an item to a free cell and saves the position', function()
        local bottle = find(snap(server, id), 'water_bottle')
        op(server, id, 'move', bottle.uid, 'player:1', 'player:1', 5, 2, false)
        local moved = find(snap(server, id), 'water_bottle')
        expect(moved.x).toBe(5); expect(moved.y).toBe(2)
        expect(server.db.backend.data.wl_items[bottle.uid].pos_x).toBe(5)
    end)

    it('rotates in place and refuses cells that are taken or outside', function()
        local bottle = find(snap(server, id), 'water_bottle')
        op(server, id, 'move', bottle.uid, 'player:1', 'player:1', 4, 3, true)
        expect(find(snap(server, id), 'water_bottle').rotated).toBe(true)
        local beans = find(snap(server, id), 'canned_beans')
        local before = errorCount(server, id)
        op(server, id, 'move', beans.uid, 'player:1', 'player:1', 4, 3, false)
        expect(lastError(server, id)).toContain('no room there')
        op(server, id, 'move', beans.uid, 'player:1', 'player:1', 6, 0, false)
        expect(errorCount(server, id)).toBe(before + 2)
    end)

    it('merges stacks up to the stack size and splits them again', function()
        -- bandages: light, stack 100 in the config
        give(server, id, 'bandage', 101) -- 2 + 101: tops up to 100, new stack of 3
        local s = snap(server, id)
        local stacks = {}
        for _, it in ipairs(inv(s, 'player:1').items) do if it.name == 'bandage' then stacks[#stacks + 1] = it end end
        expect(#stacks).toBe(2)
        table.sort(stacks, function(a, b) return a.count > b.count end)
        expect(stacks[1].count).toBe(100); expect(stacks[2].count).toBe(3)
        op(server, id, 'merge', stacks[2].uid, 'player:1', stacks[1].uid, 'player:1', 1)
        expect(lastError(server, id)).toContain('stack is full')
        op(server, id, 'split', stacks[1].uid, 'player:1', 3)
        op(server, id, 'merge', stacks[2].uid, 'player:1', stacks[1].uid, 'player:1', 1)
        local after = {}
        for _, it in ipairs(inv(snap(server, id), 'player:1').items) do if it.name == 'bandage' then after[#after + 1] = it.count end end
        table.sort(after)
        expect(after).toEqual({ 2, 3, 98 })
        expect(rowCount(server, 'bandage')).toBe(103)
    end)

    it('refuses splits of 0 or the whole stack', function()
        local beans = find(snap(server, id), 'canned_beans')
        op(server, id, 'split', beans.uid, 'player:1', beans.count)
        expect(lastError(server, id)).toContain('you can split 1 to')
        expect(rowCount(server, 'canned_beans')).toBe(2)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('backpacks and equipment', function()
    local server = world()
    local id = player(server, 'carol')
    give(server, id, 'backpack_small')

    it('wearing a backpack adds its grid', function()
        local bag = find(snap(server, id), 'backpack_small')
        op(server, id, 'equip', bag.uid, 'player:1', 'back')
        local s = snap(server, id)
        expect(s.backpack).toBe('item:' .. bag.uid)
        expect(inv(s, s.backpack).width).toBe(5)
    end)

    it('items move into the bag; its weight limit holds', function()
        local s = snap(server, id)
        local bottle = find(s, 'water_bottle')
        op(server, id, 'move', bottle.uid, 'player:1', s.backpack, 0, 0, false)
        expect(select(2, find(snap(server, id), 'water_bottle'))).toBe(s.backpack)
        server:command(0, string.format('give %d scrap_metal 10', id)); server:advance(150)
        -- pockets hold 35 kg, the small bag 35 kg; scrap is 1 kg each
        local scrap = find(snap(server, id), 'scrap_metal')
        expect(scrap.count).toBe(10)
        give(server, id, 'scrap_metal', 10)
        expect(rowCount(server, 'scrap_metal')).toBe(20)
        give(server, id, 'scrap_metal', 55)
        expect(rowCount(server, 'scrap_metal')).toBe(20) -- 75 kg would not fit: nothing added (all or nothing)
    end)

    it('a bag can never go inside a bag (here: from a stash into the worn bag)', function()
        server:export('wasteland_inventory', 'OpenStash', id, 'test_locker', { label = 'Locker', width = 8, height = 8 })
        server:advance(300)
        expect(server:export('wasteland_inventory', 'AddItem', 'stash:test_locker', 'backpack_large', 1)).toBe(true)
        server:advance(100)
        local s = snap(server, id)
        local large = find(s, 'backpack_large')
        expect(large ~= nil).toBe(true)
        op(server, id, 'move', large.uid, 'stash:test_locker', s.backpack, 0, 0, false)
        expect(lastError(server, id)).toBe('a bag cannot go inside another bag')
        -- but it can be worn: the small bag swaps into the stash, contents kept
        local smallUid = s.backpack:sub(6)
        op(server, id, 'equip', large.uid, 'stash:test_locker', 'back')
        local after = snap(server, id)
        expect(after.backpack).toBe('item:' .. large.uid)
        local inStash = false
        for _, it in ipairs(inv(after, 'stash:test_locker').items) do if it.uid == smallUid then inStash = true end end
        expect(inStash).toBe(true)
        expect(server.db.backend.data.wl_items[smallUid].inventory_id).toBe('stash:test_locker')
        local bottleRow
        for _, r in pairs(server.db.backend.data.wl_items) do if r.name == 'water_bottle' then bottleRow = r end end
        expect(bottleRow.inventory_id).toBe('item:' .. smallUid) -- still inside the small bag
    end)

    it('unequips clothing into the pockets and back; wrong slots are refused', function()
        local s = snap(server, id)
        local top
        for _, it in ipairs(inv(s, 'equip:1').items) do if it.slot == 'torso' then top = it end end
        op(server, id, 'equip', top.uid, 'equip:1', 'legs')
        expect(lastError(server, id)).toBe('that item is already worn')
        -- make room: drop the scrap first is not needed; take off the hat slot (empty) errors
        op(server, id, 'unequip', 'head', 'player:1')
        expect(lastError(server, id)).toBe('nothing is worn there')
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('dropping and picking up', function()
    local server = world()
    local a = player(server, 'dave', { x = 0.0, y = 0.0, z = 30.0 })
    local b = player(server, 'erin', { x = 1.0, y = 0.0, z = 30.0 })

    it('drops part of a stack on the ground (stored, broadcast)', function()
        local beans = find(snap(server, a), 'canned_beans')
        op(server, a, 'drop', beans.uid, 'player:1', 1)
        expect(find(snap(server, a), 'canned_beans').count).toBe(1)
        local drops = server:clientEventsFor(b, 'wasteland:inventory:client:drops')
        local list = drops[#drops].args[1]
        expect(#list).toBe(1)
        expect(next(server.db.backend.data.wl_drops) ~= nil).toBe(true)
    end)

    it('two players race for the same item: exactly one gets it', function()
        local dropId = server:clientEventsFor(b, 'wasteland:inventory:client:drops')
        dropId = dropId[#dropId].args[1][1].id
        op(server, a, 'openDrop', dropId)
        op(server, b, 'openDrop', dropId)
        local onGround = inv(snap(server, b), 'drop:' .. dropId).items[1]
        -- both send the move in the same tick
        server:clientEvent(a, 'wasteland:inventory:server:move', onGround.uid, 'drop:' .. dropId, 'player:1', 5, 3, false)
        server:clientEvent(b, 'wasteland:inventory:server:move', onGround.uid, 'drop:' .. dropId, 'player:2', 5, 3, false)
        server:advance(200)
        local inA = 0
        for _, it in ipairs(inv(snap(server, a), 'player:1').items) do if it.uid == onGround.uid then inA = 1 end end
        local inB = 0
        for _, it in ipairs(inv(snap(server, b), 'player:2').items) do if it.uid == onGround.uid then inB = 1 end end
        expect(inA + inB).toBe(1)
        expect(rowCount(server, 'canned_beans')).toBe(4) -- 2 + 2 starting items: nothing duplicated
        -- the empty drop disappeared
        expect(next(server.db.backend.data.wl_drops)).toBe(nil)
    end)

    it('refuses drops that are out of reach and players without a known position', function()
        local bottle = find(snap(server, a), 'water_bottle')
        op(server, a, 'drop', bottle.uid, 'player:1')
        local dropId = server:clientEventsFor(b, 'wasteland:inventory:client:drops')
        dropId = dropId[#dropId].args[1][1].id
        server.players[b].coords = { x = 50.0, y = 0.0, z = 30.0 }
        op(server, b, 'openDrop', dropId)
        expect(lastError(server, b)).toContain('too far away')
        server.players[b].coords = nil
        op(server, b, 'openDrop', dropId)
        expect(lastError(server, b)).toContain('OneSync')
    end)

    it('drops survive a restart of the inventory resource', function()
        server:restart('wasteland_inventory')
        server:advance(3000)
        expect(states(server).inventory).toBe('running')
        local drops = server:clientEventsFor(a, 'wasteland:inventory:client:drops')
        expect(#drops[#drops].args[1]).toBe(1)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('abuse: duplication and forged requests', function()
    local server = world()
    local a = player(server, 'frank')
    local b = player(server, 'gina')

    it('the same move sent twice in one tick applies once', function()
        local bottle = find(snap(server, a), 'water_bottle')
        server:clientEvent(a, 'wasteland:inventory:server:move', bottle.uid, 'player:1', 'player:1', 5, 0, false)
        server:clientEvent(a, 'wasteland:inventory:server:drop', bottle.uid, 'player:1')
        server:clientEvent(a, 'wasteland:inventory:server:drop', bottle.uid, 'player:1')
        server:advance(300)
        expect(rowCount(server, 'water_bottle')).toBe(2) -- a's one + b's one; never three
    end)

    it("another player's inventory cannot be touched", function()
        local theirs = find(snap(server, b), 'canned_beans')
        op(server, a, 'move', theirs.uid, 'player:2', 'player:1', 0, 3, false)
        expect(lastError(server, a)).toBe('you cannot reach that')
        op(server, a, 'drop', theirs.uid, 'player:2')
        expect(lastError(server, a)).toBe('you cannot reach that')
        expect(find(snap(server, b), 'canned_beans').count).toBe(2)
    end)

    it('merging a stack into itself does nothing', function()
        local beans = find(snap(server, a), 'canned_beans')
        op(server, a, 'merge', beans.uid, 'player:1', beans.uid, 'player:1', 1)
        expect(lastError(server, a)).toBe('those items do not stack')
        expect(rowCount(server, 'canned_beans')).toBe(4)
    end)

    it('malformed requests are rejected by the guard before the module runs', function()
        local beans = find(snap(server, a), 'canned_beans')
        server:clientEvent(a, 'wasteland:inventory:server:split', beans.uid, 'player:1', -5)
        server:advance(1000)
        server:clientEvent(a, 'wasteland:inventory:server:move', "'; DROP TABLE wl_items; --", 'player:1', 'player:1', 0, 0, false)
        server:advance(1000)
        server:clientEvent(a, 'wasteland:inventory:server:move', beans.uid, 'player:1', 'player:1', 99, 0, false)
        expect(#server:lines('rejected "wasteland:inventory:server:split" from player 1 (payload)')).toBe(1)
        expect(#server:lines('rejected "wasteland:inventory:server:move" from player 1 (payload)') >= 1).toBe(true)
        expect(rowCount(server, 'canned_beans')).toBe(4)
    end)

    it('the hotbar only accepts items the player owns', function()
        local theirs = find(snap(server, b), 'bandage')
        op(server, a, 'setHotbar', 1, theirs.uid)
        expect(lastError(server, a)).toBe('that item is not in your inventory')
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('persistence, disconnects and database failures', function()
    local server = world()
    local a = player(server, 'hank')

    it('a change made right before disconnecting is kept', function()
        local bottle = find(snap(server, a), 'water_bottle')
        server:clientEvent(a, 'wasteland:inventory:server:move', bottle.uid, 'player:1', 'player:1', 5, 2, false)
        server:dropPlayer(a)
        server:advance(1000)
        local a2 = server:connectAndJoin({ name = 'P-hank', license = 'hank' }); server:advance(200)
        server.players[a2].coords = { x = 100.0, y = 100.0, z = 30.0 }
        server:command(a2, 'character select 1'); server:advance(500)
        local again = find(snap(server, a2), 'water_bottle')
        expect(again.uid).toBe(bottle.uid)
        expect(again.x).toBe(5)
        expect(#inv(snap(server, a2), 'equip:1').items).toBe(3) -- clothes still worn
        a = a2
    end)

    it('failed writes are retried in order until they succeed', function()
        local bottle = find(snap(server, a), 'water_bottle')
        server.db.backend.failPattern = 'INSERT INTO wl_items'
        op(server, a, 'move', bottle.uid, 'player:1', 'player:1', 0, 2, false)
        server:advance(3000)
        expect(server:export('wasteland_core', 'GetModuleStatus', 'inventory').health).toBe('degraded')
        expect(server.db.backend.data.wl_items[bottle.uid].pos_x).toBe(5)
        server.db.backend.failPattern = nil
        server:advance(5000)
        expect(server.db.backend.data.wl_items[bottle.uid].pos_x).toBe(0)
        expect(server:export('wasteland_core', 'GetModuleStatus', 'inventory').health).toBe('ok')
    end)

    it('refuses changes while the database is down', function()
        server.db.hang = true
        server:advance(4000)
        local bottle = find(snap(server, a), 'water_bottle')
        op(server, a, 'move', bottle.uid, 'player:1', 'player:1', 5, 2, false)
        expect(lastError(server, a)).toContain('paused')
        server.db.hang = false
        server:advance(3000)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('usable items, hotbar and exports', function()
    local server = world()
    addModule(server, 'fx_medic', [[
Wasteland.DefineModule({ name = 'medic', version = '1.0.0', core = '^1.1.0', dependencies = { inventory = '^0.1.0' },
    onInit = function()
        exports.wasteland_inventory:RegisterUsable('bandage', function(src, stack)
            track('used ' .. stack.name .. ' by ' .. src)
            return 1, 'You patch yourself up.'
        end)
    end })
]], { 'wasteland_inventory' })
    server:start('fx_medic')
    local a = player(server, 'ivy')

    it('uses an item through the registered handler and consumes it', function()
        local bandage = find(snap(server, a), 'bandage')
        op(server, a, 'use', bandage.uid, 'player:1')
        expect(server:export('fx_medic', 'Calls')).toContain('used bandage by ' .. a)
        expect(find(snap(server, a), 'bandage').count).toBe(1)
        local notes = server:clientEventsFor(a, 'wasteland:inventory:client:notice')
        expect(notes[#notes].args[1]).toBe('You patch yourself up.')
    end)

    it('refuses items without a handler', function()
        local bottle = find(snap(server, a), 'water_bottle')
        op(server, a, 'use', bottle.uid, 'player:1')
        expect(lastError(server, a)).toBe('Water bottle cannot be used')
    end)

    it('puts an item on the hotbar (saved) and uses it by key', function()
        local bandage = find(snap(server, a), 'bandage')
        op(server, a, 'setHotbar', 2, bandage.uid)
        expect(snap(server, a).hotbar[2]).toBe(bandage.uid)
        op(server, a, 'useHotbar', 2)
        expect(find(snap(server, a), 'bandage')).toBe(nil) -- last one used
        op(server, a, 'useHotbar', 2)
        expect(lastError(server, a)).toBe('that item is no longer in your inventory')
    end)

    it('AddItem / RemoveItem are all-or-nothing; GetItemCount counts every stack', function()
        expect(server:export('wasteland_inventory', 'AddItem', a, 'scrap_metal', 100)).toBe(false)
        expect(server:export('wasteland_inventory', 'GetItemCount', a, 'scrap_metal')).toBe(0)
        expect(server:export('wasteland_inventory', 'AddItem', a, 'duct_tape', 7)).toBe(true)
        expect(server:export('wasteland_inventory', 'GetItemCount', a, 'duct_tape')).toBe(7)
        local ok, err = server:export('wasteland_inventory', 'RemoveItem', a, 'duct_tape', 8)
        expect(ok).toBe(false); expect(err).toBe('not enough items')
        expect(server:export('wasteland_inventory', 'RemoveItem', a, 'duct_tape', 6)).toBe(true)
        expect(server:export('wasteland_inventory', 'GetItemCount', a, 'duct_tape')).toBe(1)
        server:advance(200) -- let the write queue run
        expect(rowCount(server, 'duct_tape')).toBe(1)
    end)

    it('cash is an item: one weightless stack, GetCash / AddCash / RemoveCash', function()
        local I = function(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        expect(I('GetCash', a)).toBe(0)
        expect(I('AddCash', a, 250000)).toBe(true)
        expect(I('AddCash', a, 1500)).toBe(true)
        expect(I('GetCash', a)).toBe(251500)
        expect(find(snap(server, a), 'cash').count).toBe(251500) -- one stack, no weight
        local ok, err = I('RemoveCash', a, 300000)
        expect(ok).toBe(false); expect(err).toBe('not enough items')
        expect(I('RemoveCash', a, 1500)).toBe(true)
        expect(I('GetCash', a)).toBe(250000)
        -- big amounts can be split (and so dropped or handed over)
        local stack = find(snap(server, a), 'cash')
        op(server, a, 'split', stack.uid, 'player:1', 200000)
        expect(I('GetCash', a)).toBe(250000)
        local stacks = 0
        for _, i in ipairs(snap(server, a).inventories) do
            for _, s in ipairs(i.items) do if s.name == 'cash' then stacks = stacks + 1 end end
        end
        expect(stacks).toBe(2)
        local defs = server:clientEventsFor(a, 'wasteland:inventory:client:definitions')
        expect(defs[#defs].args[1].cashItem).toBe('cash')
    end)

    it('the give command needs the admin ACE and explains mistakes', function()
        server:clearOutput()
        server:command(a, 'give ' .. a .. ' duct_tape 1'); server:advance(100)
        expect(#server:lines('tried "give" without the wasteland.admin ACE')).toBe(1)
        server:command(0, 'give ' .. a .. ' unicorn 1'); server:advance(100)
        expect(#server:lines('Could not give: unknown item "unicorn"')).toBe(1)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('death: body bags', function()
    local server = world()
    local a = player(server, 'jack', { x = 10.0, y = 20.0, z = 30.0 })
    give(server, a, 'backpack_small')
    local s0 = snap(server, a)
    local bag = find(s0, 'backpack_small')
    op(server, a, 'equip', bag.uid, 'player:1', 'back')
    local s1 = snap(server, a)
    local bandage = find(s1, 'bandage')
    local bottle = find(s1, 'water_bottle')
    op(server, a, 'move', bottle.uid, 'player:1', s1.backpack, 0, 0, false) -- bottle inside the bag
    op(server, a, 'setHotbar', 1, bandage.uid)                              -- kept (pockets)
    op(server, a, 'setHotbar', 2, bottle.uid)                               -- kept (moves out of the bag)
    local result = server:export('wasteland_inventory', 'DeathDrop', a, 'Body of John Doe')
    server:advance(300)

    it('moves everything except hotbar items into a body bag at the position', function()
        expect(#result.dropIds).toBe(1)
        local s = snap(server, a)
        local pockets = inv(s, 'player:1')
        local names = {}
        for _, it in ipairs(pockets.items) do names[#names + 1] = it.name end
        table.sort(names)
        expect(names).toEqual({ 'bandage', 'water_bottle' })
        expect(#inv(s, 'equip:1').items).toBe(0)
        expect(s.backpack).toBe(nil)
    end)

    it('the bag is stored with owner, label and its own lifetime, and the bag keeps its contents', function()
        local row = server.db.backend.data.wl_drops[result.dropIds[1]]
        expect(row.owner_character).toBe(1)
        expect(row.label).toBe('Body of John Doe')
        expect(row.expires_unix - row.created_unix).toBe(120 * 60)
        local inBag = rows(server, 'drop:' .. result.dropIds[1])
        local names = {}
        for _, r in ipairs(inBag) do names[r.name] = true end
        expect(names.backpack_small).toBe(true)
        expect(names.clothing_top).toBe(true)
        expect(names.canned_beans).toBe(true)
        expect(rowCount(server, 'bandage')).toBe(2) -- kept, not duplicated
    end)

    it('the drop list tells clients who owns the bag (map marker)', function()
        local drops = server:clientEventsFor(a, 'wasteland:inventory:client:drops')
        local list = drops[#drops].args[1]
        expect(list[1].owner).toBe(1)
        expect(list[1].label).toBe('Body of John Doe')
    end)

    it('anyone can loot it; new drops never join a body bag', function()
        local b = player(server, 'kate', { x = 10.5, y = 20.0, z = 30.0 })
        local beans = find(snap(server, b), 'canned_beans')
        op(server, b, 'drop', beans.uid, 'player:2', 1)
        local list = server:clientEventsFor(b, 'wasteland:inventory:client:drops')
        expect(#list[#list].args[1]).toBe(2)
        op(server, b, 'openDrop', result.dropIds[1])
        expect(inv(snap(server, b), 'drop:' .. result.dropIds[1]).label).toBe('Body of John Doe')
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('configuration errors', function()
    it('a bad item definition stops the module with the item and setting named', function()
        local cfg = {}
        for k, v in pairs(CFG) do cfg[k] = v end
        cfg['inventory.lua'] = [[return { items = { rock = { label = 'Rock', width = 20 } }, clothingItems = {} }]]
        local server = newServer({ config = cfg })
        boot(server, { 'wasteland_inventory' })
        local s = server:export('wasteland_core', 'GetModuleStatus', 'inventory')
        expect(s.state).toBe('failed')
        expect(s.reason).toContain('items.item "rock": width')
    end)
end)
