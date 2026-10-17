-- Inventory "Take all" (wasteland_inventory Inv.takeAll): everything from an
-- open stash into pockets then the worn bag; stackables top up stacks,
-- one-of-a-kind items keep their condition; what does not fit stays;
-- only from something you have open and can reach; never from your own.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('inventory take all', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory' })
    local id = server:connectAndJoin({ name = 'P-take', license = 'take' })
    server:advance(200)
    server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
    server:command(id, 'character create Tia Take'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local stash
    server:createThread('wasteland_inventory', function()
        stash = I('EnsureStash', 'take_test', { width = 6, height = 6, maxWeight = 200, coords = { x = 1.0, y = 0.0, z = 30.0 } })
    end)
    server:advance(300)
    I('ClearInventory', id); server:advance(100)
    I('AddItem', id, 'bandage', 3); server:advance(100)
    I('AddItem', stash, 'bandage', 5)
    I('AddItem', stash, 'water_bottle', 2)
    I('AddItem', stash, 'weapon_knife', 1, { durability = 123 })
    server:advance(100)
    local function count(name) return I('GetItemCount', id, name) end
    local function take(invId) server:clientEvent(id, 'wasteland:inventory:server:takeAll', invId); server:advance(200) end
    local function stashItems() return #I('GetInventory', stash).items end

    it('not from a stash you have not opened', function()
        take(stash)
        expect(stashItems()).toBe(3)
    end)

    it('takes everything; bandages join the stack you had; the knife keeps its condition', function()
        server:createThread('wasteland_inventory', function() I('OpenStash', id, 'take_test', { coords = { x = 1.0, y = 0.0, z = 30.0 } }) end)
        server:advance(300)
        take(stash)
        expect(stashItems()).toBe(0)
        expect(count('bandage')).toBe(8)
        expect(count('water_bottle')).toBe(2)
        local knife
        for _, s in ipairs(I('GetInventory', 'player:1').items) do if s.name == 'weapon_knife' then knife = s end end
        expect(knife ~= nil).toBe(true)
        expect(knife.metadata.durability).toBe(123)
        local bandageStacks = 0
        for _, s in ipairs(I('GetTradeable', id)) do if s.name == 'bandage' then bandageStacks = bandageStacks + 1 end end
        expect(bandageStacks).toBe(1)
    end)

    it('what does not fit stays in the stash (and the player is told)', function()
        I('AddItem', stash, 'weapon_pumpshotgun', 1) -- 5 x 2: too big for the test pockets once full
        I('AddItem', stash, 'scrap_metal', 1)
        for _ = 1, 30 do I('AddItem', id, 'rag', 100) end
        server:advance(100)
        take(stash)
        local left = I('GetInventory', stash).items
        expect(#left >= 1).toBe(true)
        local errs = server:clientEventsFor(id, 'wasteland:inventory:client:error')
        expect(#errs > 0).toBe(true)
    end)

    it('never from your own pockets', function()
        local before = count('bandage')
        take('player:1')
        expect(count('bandage')).toBe(before)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
