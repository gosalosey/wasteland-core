-- Pockets that grow with what is worn (the shipped inventory.lua): 3 x 3
-- bare, +2 x 2 each for a top, pants and armor, at most 10 x 10. Taking
-- something off is refused while the smaller pockets could not hold what is
-- in them. Backpack sizes and weights.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('pockets grow with clothing', function()
    local server = newServer({ config = CFG, shippedPockets = true })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival' })
    local function snap(id)
        local list = server:clientEventsFor(id, 'wasteland:inventory:client:sync')
        return list[#list].args[1]
    end
    local function inv(id, invId)
        for _, i in ipairs(snap(id).inventories) do if i.id == invId then return i end end
    end
    local function find(id, name)
        for _, i in ipairs(snap(id).inventories) do
            for _, s in ipairs(i.items) do if s.name == name then return s, i.id end end
        end
    end
    local function lastError(id)
        local list = server:clientEventsFor(id, 'wasteland:inventory:client:error')
        return list[#list] and list[#list].args[1]
    end
    local function op(id, name, ...) server:clientEvent(id, 'wasteland:inventory:server:' .. name, ...); server:advance(150) end
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local function size(id) local p = inv(id, 'player:1'); return p.width .. 'x' .. p.height end

    local id = server:connectAndJoin({ name = 'Pocket', license = 'pockets' })
    server:advance(200)
    server.players[id].coords = { x = 100.0, y = 100.0, z = 30.0 }
    server:command(id, 'character create Pat Pocket'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)

    it('bare: 3 x 3 pockets holding 55 kg', function()
        local p = inv(id, 'player:1')
        expect(size(id)).toBe('3x3'); expect(p.maxWeight).toBe(55.0)
    end)

    it('the starting outfit (a top and pants) makes them 7 x 7', function()
        server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
        expect(find(id, 'clothing_top') ~= nil).toBe(true)
        expect(size(id)).toBe('7x7')
    end)

    it('an armor plate adds 2 x 2 more; the most is 10 x 10', function()
        I('ClearInventory', id); server:advance(200)
        expect(size(id)).toBe('3x3')
        I('AddItem', id, 'clothing_top', 1); server:advance(100)
        op(id, 'equip', find(id, 'clothing_top').uid, 'player:1', 'torso')
        expect(size(id)).toBe('5x5')
        I('AddItem', id, 'clothing_pants', 1); server:advance(100)
        op(id, 'equip', find(id, 'clothing_pants').uid, 'player:1', 'legs')
        expect(size(id)).toBe('7x7')
        I('AddItem', id, 'armor_plate', 1); server:advance(100)
        op(id, 'equip', find(id, 'armor_plate').uid, 'player:1', 'armor')
        expect(size(id)).toBe('9x9')
    end)

    it('taking something off is refused while the smaller pockets could not hold it all', function()
        -- fill the 9 x 9 pockets with 1 x 1 items that do not stack: more than 7 x 7 holds
        I('AddItem', id, 'bandage', 1); server:advance(50)
        for n = 1, 60 do I('AddItem', id, 'weapon_knuckle', 1) end
        server:advance(200)
        op(id, 'unequip', 'armor', 'player:1')
        expect(lastError(id)).toContain('make room in them first')
        expect(size(id)).toBe('9x9')
    end)

    it('with room, it comes off: stacks outside move inside and the pockets shrink', function()
        I('RemoveItem', id, 'weapon_knuckle', 60); server:advance(100)
        -- a stack in the far corner, outside 7 x 7
        local b = find(id, 'bandage')
        op(id, 'move', b.uid, 'player:1', 'player:1', 8, 8, false)
        expect(find(id, 'bandage').x).toBe(8)
        op(id, 'unequip', 'armor', 'player:1')
        expect(size(id)).toBe('7x7')
        local moved = find(id, 'bandage')
        expect(moved.x < 7 and moved.y < 7).toBe(true)
        local plate, where = find(id, 'armor_plate')
        expect(where).toBe('player:1'); expect(plate.x < 7 and plate.y < 7).toBe(true)
    end)

    it('the size comes back after a restart', function()
        server:restart('wasteland_inventory'); server:advance(2000)
        server:clientEvent(id, 'wasteland:inventory:server:request'); server:advance(300)
        expect(size(id)).toBe('7x7')
    end)

    it('dying: the clothes go in the body bag, kept hotbar items fit the 3 x 3 pockets', function()
        local plate = find(id, 'armor_plate')
        op(id, 'move', plate.uid, 'player:1', 'player:1', 5, 5, false)
        op(id, 'setHotbar', 1, plate.uid)
        server:clientEvent(id, 'wasteland:survival:server:died'); server:advance(500)
        expect(size(id)).toBe('3x3')
        local kept, where = find(id, 'armor_plate')
        expect(where).toBe('player:1'); expect(kept.x < 3 and kept.y < 3).toBe(true)
        expect(find(id, 'clothing_top') == nil).toBe(true)
    end)

    it('backpacks: small 10 x 10 / 100 kg, hiking 15 x 15 / 175 kg', function()
        local small = server:export('wasteland_inventory', 'GetItemDefinition', 'backpack_small').container
        local large = server:export('wasteland_inventory', 'GetItemDefinition', 'backpack_large').container
        expect(small.width .. 'x' .. small.height .. ' ' .. small.maxWeight).toBe('10x10 100')
        expect(large.width .. 'x' .. large.height .. ' ' .. large.maxWeight).toBe('15x15 175')
        expect(#server:lines('raised:')).toBe(0)
    end)
end)
