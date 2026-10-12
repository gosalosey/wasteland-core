-- wasteland_camps (server): traders (buy, sell, stock, cash, distance,
-- full inventory), safe zones and zombies, guarded events.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['camps.lua'] = [[return {
        restockMinutes = 1,
        shops = {
            shop = { label = 'Test trader', items = {
                { name = 'bandage', buy = 25, sell = 8, stock = 3, restock = 2 },
                { name = 'scrap_metal', sell = 4 },
                { name = 'weapon_pumpshotgun', buy = 10, stock = 50 },
            } },
        },
        camps = {
            { id = 'base', label = 'Test Camp', coords = { x = 0.0, y = 0.0, z = 30.0 }, radius = 50,
                traders = { { shop = 'shop', coords = { x = 2.0, y = 0.0, z = 30.0 } } } },
        },
    }]],
    ['zombies.lua'] = 'return { population = { perPlayer = 0 } }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function world()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival',
        'wasteland_zombies', 'wasteland_camps' })
    return server
end

local function player(server, license, coords)
    local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
    server:advance(200)
    server.players[id].coords = coords or { x = 1.0, y = 0.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    return id
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end
local function I(server, fn, ...) return server:export('wasteland_inventory', fn, ...) end
local function screen(server, id) return last(events(server, id, 'wasteland:camps:client:trader')).args[1] end
local function trade(server, id, action, item, count)
    server:clientEvent(id, 'wasteland:camps:server:' .. action, 'base', 1, item, count)
    server:advance(200)
    return screen(server, id)
end

describe('traders', function()
    local server = world()
    local id = player(server, 'buyer')

    it('runs; clients get the camps and traders', function()
        expect(states(server).camps).toBe('running')
        local c = last(events(server, -1, 'wasteland:camps:client:config')).args[1]
        expect(c.camps[1].label).toBe('Test Camp')
        expect(c.camps[1].traders[1].label).toBe('Test trader')
    end)

    it('opening shows prices, stock, what you carry and your cash', function()
        I(server, 'RemoveCash', id, 50) -- the starting cash, so the numbers below are simple
        I(server, 'AddCash', id, 100)
        server:advance(100)
        server:clientEvent(id, 'wasteland:camps:server:open', 'base', 1)
        server:advance(200)
        local d = screen(server, id)
        expect(d.title).toBe('Test trader'); expect(d.cash).toBe(100)
        expect(d.items[1].name).toBe('bandage'); expect(d.items[1].stock).toBe(3); expect(d.items[1].have).toBe(2)
        expect(d.items[2].buy).toBe(nil); expect(d.items[2].sell).toBe(4)
    end)

    it('buying takes cash, gives the items and lowers the stock', function()
        local d = trade(server, id, 'buy', 'bandage', 2)
        expect(d.ok).toBe(true); expect(d.message).toBe('Bought 2 x Bandage for $50.')
        expect(I(server, 'GetCash', id)).toBe(50)
        expect(I(server, 'GetItemCount', id, 'bandage')).toBe(4)
        expect(d.items[1].stock).toBe(1)
    end)

    it('refuses more than the stock or the cash', function()
        expect(trade(server, id, 'buy', 'bandage', 2).message).toBe('Only 1 left.')
        I(server, 'RemoveCash', id, 40); server:advance(100)
        expect(trade(server, id, 'buy', 'bandage', 1).message).toBe('You need $25 (you have $10).')
        expect(I(server, 'GetItemCount', id, 'bandage')).toBe(4)
    end)

    it('selling takes the items, pays cash and refills the stock', function()
        local d = trade(server, id, 'sell', 'bandage', 3)
        expect(d.ok).toBe(true)
        expect(I(server, 'GetCash', id)).toBe(34)
        expect(I(server, 'GetItemCount', id, 'bandage')).toBe(1)
        expect(d.items[1].stock).toBe(3) -- 1 + 3, capped at 3
        expect(trade(server, id, 'sell', 'bandage', 5).message).toBe('You only have 1.')
        expect(trade(server, id, 'sell', 'water_bottle', 1).message).toBe('This trader does not buy that.')
    end)

    it('no room in the inventory: no sale, money back', function()
        I(server, 'AddCash', id, 1000); server:advance(100)
        for _ = 1, 6 do I(server, 'AddItem', id, 'scrap_metal', 1) end -- fill some space
        local before = I(server, 'GetCash', id)
        local d = trade(server, id, 'buy', 'weapon_pumpshotgun', 20) -- 20 shotguns never fit
        expect(d.ok).toBe(false)
        expect(I(server, 'GetCash', id)).toBe(before)
        expect(I(server, 'GetItemCount', id, 'weapon_pumpshotgun')).toBe(0)
    end)

    it('the stock refills over time', function()
        trade(server, id, 'buy', 'bandage', 3)
        server:advance(61000)
        server:clientEvent(id, 'wasteland:camps:server:open', 'base', 1)
        server:advance(200)
        expect(screen(server, id).items[1].stock).toBe(2)
    end)

    it('only at the trader', function()
        local count = #events(server, id, 'wasteland:camps:client:trader')
        server.players[id].coords = { x = 30.0, y = 0.0, z = 30.0 }
        server:clientEvent(id, 'wasteland:camps:server:buy', 'base', 1, 'bandage', 1)
        server:clientEvent(id, 'wasteland:camps:server:open', 'base', 1)
        server:advance(200)
        expect(#events(server, id, 'wasteland:camps:client:trader')).toBe(count)
        server:clientEvent(id, 'wasteland:camps:server:buy', 'base', 1, 'bandage', 0) -- rejected by the guard
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('safe zones and zombies', function()
    local server = world()
    local id = player(server, 'safe', { x = 100.0, y = 0.0, z = 30.0 })

    it('the camp is a safe zone', function()
        expect(server:export('wasteland_camps', 'IsInSafeZone', { x = 10.0, y = 10.0, z = 30.0 })).toBe(true)
        expect(server:export('wasteland_camps', 'IsInSafeZone', { x = 100.0, y = 0.0, z = 30.0 })).toBe(false)
        expect(server:export('wasteland_camps', 'GetCampAt', { x = 10.0, y = 10.0, z = 30.0 }).label).toBe('Test Camp')
    end)

    it('zombies are not spawned inside a camp, and ones that wander in are removed', function()
        server.aces[id .. '|wasteland.admin'] = true
        server:command(id, 'zombies spawn 2'); server:advance(100)
        server:clientEvent(id, 'wasteland:zombies:server:spawns', { { x = 30.0, y = 0.0, z = 30.0 }, { x = 120.0, y = 0.0, z = 30.0 } })
        server:advance(100)
        local zs = server:entityList('wlZombie')
        expect(#zs).toBe(1)
        expect(zs[1].coords.x).toBe(120.0)
        zs[1].coords = { x = 20.0, y = 0.0, z = 30.0 } -- walks into the camp
        server:advance(1100)
        expect(#server:entityList('wlZombie')).toBe(0)
    end)

    it('a zombie cannot hurt a player inside a camp', function()
        local netId = server:export('wasteland_zombies', 'SpawnZombie', { x = 51.0, y = 0.0, z = 30.0 })
        server.players[id].coords = { x = 49.5, y = 0.0, z = 30.0 }
        server:clientEvent(id, 'wasteland:zombies:server:hit', netId, id)
        server:advance(100)
        expect(#events(server, id, 'wasteland:survival:client:damage')).toBe(0)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('new characters: protected, then choose a camp to start at', function()
    local server = world()
    local id = player(server, 'newbie')
    local function state() return server.resources.wasteland_camps.env.Player(id).state end

    it('after the creator, the player is asked where to start and is protected', function()
        local ask = last(events(server, id, 'wasteland:camps:client:chooseSpawn')).args[1]
        expect(#ask >= 1).toBe(true)
        expect(ask[1].id).toBe('base')
        expect(state().wlProtected).toBe(true)
    end)

    it('protected players take no damage', function()
        local before = #events(server, id, 'wasteland:survival:client:damage')
        local ok = server:export('wasteland_survival', 'Damage', id, 30)
        expect(ok).toBe(false)
        expect(#events(server, id, 'wasteland:survival:client:damage')).toBe(before)
    end)

    it('picking a camp sends them there; protection ends a few seconds later', function()
        server:clientEvent(id, 'wasteland:camps:server:chooseSpawn', 'nope'); server:advance(100)
        expect(#events(server, id, 'wasteland:camps:client:spawnAt')).toBe(0)
        server:clientEvent(id, 'wasteland:camps:server:chooseSpawn', 'base'); server:advance(100)
        local at = last(events(server, id, 'wasteland:camps:client:spawnAt')).args
        expect(at[2]).toBe('Test Camp')
        expect(state().wlProtected).toBe(true)
        server:advance(8200)
        expect(state().wlProtected).toBe(false)
        -- only once
        server:clientEvent(id, 'wasteland:camps:server:chooseSpawn', 'base'); server:advance(1100)
        expect(#events(server, id, 'wasteland:camps:client:spawnAt')).toBe(1)
        expect(server:export('wasteland_survival', 'Damage', id, 5)).toBe(true)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)


describe('returning characters: last known position or a safe camp', function()
    local server = world()
    local id = player(server, 'regular')
    server:clientEvent(id, 'wasteland:camps:server:chooseSpawn', 'base'); server:advance(9000)
    -- they walk off and log out far from the camp
    server.players[id].coords = { x = 500.0, y = 600.0, z = 31.0 }
    server:clientEvent(id, 'wasteland:players:server:placed'); server:advance(12000)
    server:dropPlayer(id); server:advance(1500)
    local back = server:connectAndJoin({ name = 'P-regular', license = 'regular' })
    server:advance(200)
    server.players[back].coords = { x = -2000.0, y = -2000.0, z = 10.0 } -- spawnmanager put them somewhere
    server:command(back, 'character select 1'); server:advance(2500)

    it('is asked where to wake up: last known position first, then the camps', function()
        local ev = last(events(server, back, 'wasteland:camps:client:chooseSpawn'))
        expect(ev ~= nil).toBe(true)
        local list, returning = ev.args[1], ev.args[2]
        expect(returning).toBe(true)
        expect(list[1].id).toBe('last'); expect(list[2].id).toBe('base')
        expect(server.resources.wasteland_camps.env.Player(back).state.wlProtected).toBe(true)
    end)

    it('"last" puts them back where they logged out', function()
        server:clientEvent(back, 'wasteland:camps:server:chooseSpawn', 'last'); server:advance(100)
        local at = last(events(server, back, 'wasteland:camps:client:spawnAt')).args
        expect(at[1].x).toBe(500.0); expect(at[1].y).toBe(600.0)
        expect(at[2] == nil).toBe(true)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)
