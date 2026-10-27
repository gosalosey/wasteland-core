-- wasteland_quests (server): board at a camp trader, accept, progress from
-- kills / searches / crafts / visits, bring and hand in, rewards, cooldowns,
-- limits, persistence, abuse.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['camps.lua'] = [[return {
        shops = { shop = { label = 'Trader', items = { { name = 'bandage', buy = 10 } } } },
        camps = {
            { id = 'base', label = 'Base Camp', coords = { x = 0.0, y = 0.0, z = 30.0 }, radius = 40,
                traders = { { shop = 'shop', coords = { x = 1.0, y = 0.0, z = 30.0 } } } },
            { id = 'far', label = 'Far Camp', coords = { x = 3000.0, y = 0.0, z = 30.0 }, radius = 40,
                traders = { { shop = 'shop', coords = { x = 3001.0, y = 0.0, z = 30.0 } } } },
        },
    }]],
    ['quests.lua'] = [[return {
        maxActive = 2,
        quests = {
            scrap = { label = 'Scrap', cooldownMinutes = 60, objectives = { { type = 'bring', item = 'scrap_metal', count = 3 } },
                rewards = { cash = 50, items = { { name = 'duct_tape', count = 1 } } } },
            hunt = { label = 'Hunt', cooldownMinutes = 0, objectives = { { type = 'kill', count = 2 } }, rewards = { cash = 20 } },
            make = { label = 'Make', cooldownMinutes = 0, objectives = { { type = 'craft', recipe = 'bandage', count = 1 } }, rewards = { cash = 5 } },
            tower = { label = 'Tower', camps = { 'base' }, cooldownMinutes = 0,
                objectives = { { type = 'visit', coords = { x = 300.0, y = 0.0, z = 30.0 }, radius = 20, label = 'the tower' } },
                rewards = { cash = 30 } },
            elsewhere = { label = 'Elsewhere', camps = { 'far' }, objectives = { { type = 'kill', count = 1 } }, rewards = { cash = 1 } },
            big = { label = 'Big reward', cooldownMinutes = 0, objectives = { { type = 'kill', count = 1 } },
                rewards = { items = { { name = 'weapon_pumpshotgun', count = 30 } } } },
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
        'wasteland_zombies', 'wasteland_camps', 'wasteland_crafting', 'wasteland_quests' })
    return server
end

local function player(server, license)
    local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
    server:advance(200)
    server.players[id].coords = { x = 2.0, y = 0.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    -- Start from $0 (new characters get $50) so the reward sums stay simple.
    server:export('wasteland_inventory', 'RemoveCash', id, 50); server:advance(100)
    return id
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end
local function I(server, fn, ...) return server:export('wasteland_inventory', fn, ...) end
local function board(server, id) return last(events(server, id, 'wasteland:quests:client:board')).args[1] end
local function tracker(server, id) return last(events(server, id, 'wasteland:quests:client:tracker')).args[1] end
local function quest(d, qid) for _, q in ipairs(d.quests) do if q.id == qid then return q end end end
local function act(server, id, action, qid)
    server:clientEvent(id, 'wasteland:quests:server:' .. action, 'base', qid)
    server:advance(200)
    return board(server, id)
end
local function killZombie(server, killer)
    local netId = server:export('wasteland_zombies', 'SpawnZombie', { x = 100.0, y = 0.0, z = 30.0 })
    local z = server:entityList('wlZombie')
    z = z[#z]
    z.health = 0
    z.owner = killer
    server:clientEvent(killer, 'wasteland:zombies:server:died', netId, killer)
    server:advance(100)
end

describe('quests', function()
    local server = world()
    local id = player(server, 'hero')

    it('the board at a camp trader lists the jobs this camp gives', function()
        expect(states(server).quests).toBe('running')
        server:clientEvent(id, 'wasteland:quests:server:board', 'base')
        server:advance(200)
        local d = board(server, id)
        expect(d.place).toBe('Base Camp')
        expect(quest(d, 'scrap').status).toBe('available')
        expect(quest(d, 'scrap').rewards[1]).toBe('$50')
        expect(quest(d, 'tower') ~= nil).toBe(true)
        expect(quest(d, 'elsewhere')).toBe(nil)
    end)

    it('accepting puts it in the tracker; bring items count live', function()
        act(server, id, 'accept', 'scrap')
        local t = tracker(server, id)
        expect(t[1].label).toBe('Scrap'); expect(t[1].objectives[1].text).toBe('Bring Scrap metal 0/3')
        I(server, 'AddItem', id, 'scrap_metal', 3); server:advance(200)
        t = tracker(server, id)
        expect(t[1].objectives[1].text).toBe('Bring Scrap metal 3/3'); expect(t[1].ready).toBe(true)
    end)

    it('the tracker says how to do it, when it was taken, and where to hand it in', function()
        local t = tracker(server, id)
        expect(t[1].objectives[1].how).toContain('Carry Scrap metal back to camp')
        expect(type(t[1].startedAt)).toBe('number')
        expect(t[1].rewards[1]).toBe('$50')
        expect(t[1].handIn[1].label).toBe('Base Camp')
    end)

    it('/quest: the log has the jobs in full', function()
        server:clientEvent(id, 'wasteland:quests:server:log'); server:advance(200)
        local l = server:clientEventsFor(id, 'wasteland:quests:client:log')
        local d = l[#l].args[1]
        expect(d.quests[1].label).toBe('Scrap'); expect(d.active).toBe(1); expect(d.maxActive).toBe(2)
        expect(#d.again).toBe(0)
    end)

    it('only so many jobs at once', function()
        act(server, id, 'accept', 'hunt')
        expect(act(server, id, 'accept', 'make').message).toBe('You can only have 2 jobs at once.')
    end)

    it('handing in takes the items and gives the rewards; then a cooldown', function()
        local d = act(server, id, 'handIn', 'scrap')
        expect(d.message).toBe('Job done: Scrap. Thanks.')
        expect(I(server, 'GetItemCount', id, 'scrap_metal')).toBe(0)
        expect(I(server, 'GetCash', id)).toBe(50)
        expect(I(server, 'GetItemCount', id, 'duct_tape')).toBe(1)
        expect(quest(d, 'scrap').status).toBe('cooldown'); expect(quest(d, 'scrap').minutes).toBe(60)
        expect(act(server, id, 'accept', 'scrap').message).toBe('Come back in 60 min.')
        server:clientEvent(id, 'wasteland:quests:server:log'); server:advance(200)
        local l = server:clientEventsFor(id, 'wasteland:quests:client:log')
        local again = l[#l].args[1].again
        expect(again[1].label).toBe('Scrap'); expect(again[1].minutes).toBe(60)
    end)

    it('kills count only when this player killed the zombie', function()
        local other = player(server, 'other')
        killZombie(server, other)
        expect(tracker(server, id)[1].objectives[1].text).toBe('Kill zombies 0/2')
        killZombie(server, id)
        killZombie(server, id)
        local t = tracker(server, id)
        expect(t[1].objectives[1].text).toBe('Kill zombies 2/2'); expect(t[1].ready).toBe(true)
        act(server, id, 'handIn', 'hunt')
        expect(I(server, 'GetCash', id)).toBe(70)
    end)

    it('crafts count (event from crafting)', function()
        act(server, id, 'accept', 'make')
        I(server, 'AddItem', id, 'rag', 2); server:advance(100)
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'bandage'); server:advance(3100)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(tracker(server, id)[1].ready).toBe(true)
        act(server, id, 'handIn', 'make')
    end)

    it('visits are checked by the server from where the player is', function()
        act(server, id, 'accept', 'tower')
        expect(tracker(server, id)[1].objectives[1].text).toBe('Go to the tower')
        expect(tracker(server, id)[1].objectives[1].coords.x).toBe(300.0)
        server.players[id].coords = { x = 305.0, y = 0.0, z = 30.0 }
        server:advance(2100)
        expect(tracker(server, id)[1].objectives[1].text).toBe('Go to the tower (done)')
        server.players[id].coords = { x = 2.0, y = 0.0, z = 30.0 }
        act(server, id, 'handIn', 'tower')
        expect(I(server, 'GetCash', id)).toBe(105)
    end)

    it('a reward that does not fit: nothing happens, the job stays', function()
        act(server, id, 'accept', 'big')
        killZombie(server, id)
        local d = act(server, id, 'handIn', 'big')
        expect(d.message).toBe('Make room in your inventory for the reward first.')
        expect(I(server, 'GetItemCount', id, 'weapon_pumpshotgun')).toBe(0)
        expect(quest(d, 'big').status).toBe('ready')
        act(server, id, 'abandon', 'big')
        expect(#tracker(server, id)).toBe(0)
    end)

    it('only at a camp trader; jobs of another camp cannot be taken here', function()
        local before = #events(server, id, 'wasteland:quests:client:board')
        server:clientEvent(id, 'wasteland:quests:server:accept', 'far', 'elsewhere'); server:advance(200)
        server.players[id].coords = { x = 60.0, y = 0.0, z = 30.0 }
        server:clientEvent(id, 'wasteland:quests:server:board', 'base'); server:advance(200)
        expect(#events(server, id, 'wasteland:quests:client:board')).toBe(before)
        server.players[id].coords = { x = 2.0, y = 0.0, z = 30.0 }
        act(server, id, 'accept', 'elsewhere')
        expect(#server:export('wasteland_quests', 'GetActiveQuests', id)).toBe(0)
        expect(#server.scriptErrors).toBe(0)
    end)

    it('jobs and cooldowns stay with the character', function()
        act(server, id, 'accept', 'hunt')
        killZombie(server, id)
        server:dropPlayer(id); server:advance(1000)
        local id2 = server:connectAndJoin({ name = 'P-hero', license = 'hero' })
        server:advance(200)
        server.players[id2].coords = { x = 2.0, y = 0.0, z = 30.0 }
        server:command(id2, 'character select 1'); server:advance(800)
        expect(tracker(server, id2)[1].objectives[1].text).toBe('Kill zombies 1/2')
        server:clientEvent(id2, 'wasteland:quests:server:board', 'base'); server:advance(200)
        expect(quest(board(server, id2), 'scrap').status).toBe('cooldown')
    end)
end)
