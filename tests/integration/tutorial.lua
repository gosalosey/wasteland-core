-- wasteland_quests (server): the new player tutorial. Offered once after
-- spawning (Start / No thanks); skipping is remembered; /tutorial asks again.
-- Steps: have a hatchet and a pickaxe, chop trees, mine rocks, sell wood /
-- stone at a trader. It finishes by itself and pays out; never on boards.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['camps.lua'] = [[return {
        shops = { shop = { label = 'Trader', items = { { name = 'wood_log', sell = 10 }, { name = 'bandage', buy = 10 } } } },
        camps = {
            { id = 'base', label = 'Base Camp', coords = { x = 0.0, y = 0.0, z = 30.0 }, radius = 40,
                traders = { { shop = 'shop', coords = { x = 1.0, y = 0.0, z = 30.0 } } } },
        },
    }]],
    ['quests.lua'] = [[return {
        maxActive = 1,
        tutorial = { quest = 'first_steps', askDelaySeconds = 1 },
        quests = {
            first_steps = { label = 'First steps', tutorial = true, description = 'Learn the ropes.',
                objectives = {
                    { type = 'have', items = { 'weapon_hatchet', 'scrap_axe' }, label = 'a hatchet',
                        materials = { { item = 'scrap_metal', count = 2 }, { item = 'rag', count = 1 } }, hint = 'Craft one (K).' },
                    { type = 'have', item = 'pickaxe', label = 'a pickaxe' },
                    { type = 'gather', kind = 'tree', count = 2 },
                    { type = 'gather', kind = 'rock', count = 2 },
                    { type = 'sell', items = { 'wood_log', 'stone' }, count = 3, label = 'wood or stone' },
                },
                rewards = { cash = 50, items = { { name = 'bandage', count = 1 } } } },
            hunt = { label = 'Hunt', cooldownMinutes = 0, objectives = { { type = 'kill', count = 2 } }, rewards = { cash = 20 } },
        },
    }]],
    ['zombies.lua'] = 'return { population = { perPlayer = 0 } }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('new player tutorial', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival',
        'wasteland_zombies', 'wasteland_camps', 'wasteland_crafting', 'wasteland_quests' })
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local function events(id, name) return server:clientEventsFor(id, name) end
    local function last(id, name) local l = events(id, name); return l[#l] and l[#l].args[1] end
    local function tutorial(id, choice) server:clientEvent(id, 'wasteland:quests:server:tutorial', choice); server:advance(300) end
    local function tracker(id) return last(id, 'wasteland:quests:client:tracker') end

    local function player(license)
        local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
        server:advance(200)
        server.players[id].coords = { x = 2.0, y = 0.0, z = 30.0 }
        server:command(id, 'character create Nu Player'); server:advance(300)
        server:command(id, 'character select 1'); server:advance(500)
        server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
        I('RemoveCash', id, 50); server:advance(100)
        return id
    end

    local id = player('newbie')

    it('is offered a moment after spawning, with its steps', function()
        server:triggerEvent(id, 'wasteland:camps:spawnChosen', id, 'base'); server:advance(1500)
        local o = last(id, 'wasteland:quests:client:tutorialOffer')
        expect(o ~= nil).toBe(true)
        expect(o.label).toBe('First steps')
        expect(o.steps[1]).toBe('Get a hatchet')
        expect(o.steps[3]).toBe('Chop trees')
        expect(o.steps[5]).toBe('Sell wood or stone')
        expect(o.rewards[1]).toBe('$50')
    end)

    it('No thanks: nothing starts, and it is not asked again', function()
        tutorial(id, 'skip')
        expect(#server:export('wasteland_quests', 'GetActiveQuests', id)).toBe(0)
        expect(last(id, 'wasteland:quests:client:notice')).toContain('/tutorial')
        local before = #events(id, 'wasteland:quests:client:tutorialOffer')
        server:triggerEvent(id, 'wasteland:camps:spawnChosen', id, 'base'); server:advance(1500)
        expect(#events(id, 'wasteland:quests:client:tutorialOffer')).toBe(before)
    end)

    it('/tutorial asks again; Start puts it in the tracker without using a job slot', function()
        server:clientEvent(id, 'wasteland:quests:server:tutorialCommand', ''); server:advance(300)
        expect(last(id, 'wasteland:quests:client:tutorialOffer').label).toBe('First steps')
        tutorial(id, 'start')
        local t = tracker(id)
        expect(t[1].label).toBe('First steps')
        expect(t[1].objectives[1].text).toBe('Get a hatchet')
        expect(t[1].objectives[1].how).toContain('Craft one (K).')
        expect(#t[1].handIn).toBe(0)
        -- maxActive is 1, and the tutorial does not count
        server:clientEvent(id, 'wasteland:quests:server:accept', 'base', 'hunt'); server:advance(200)
        expect(#server:export('wasteland_quests', 'GetActiveQuests', id)).toBe(2)
        server:clientEvent(id, 'wasteland:quests:server:board', 'base'); server:advance(200)
        local b = last(id, 'wasteland:quests:client:board')
        for _, q in ipairs(b.quests) do expect(q.id ~= 'first_steps').toBe(true) end
    end)

    it('picking up materials pops up how many more, then that everything is there', function()
        I('RemoveItem', id, 'scrap_metal', I('GetItemCount', id, 'scrap_metal')); I('RemoveItem', id, 'rag', I('GetItemCount', id, 'rag'))
        server:advance(300)
        I('AddItem', id, 'scrap_metal', 1); server:advance(300)
        expect(last(id, 'wasteland:quests:client:notice')).toBe('Scrap metal 1/2 for a hatchet: 1 more needed.')
        expect(tracker(id)[1].objectives[1].how).toContain('Scrap metal 1/2')
        I('AddItem', id, 'scrap_metal', 1); server:advance(300)
        expect(last(id, 'wasteland:quests:client:notice')).toContain('that is enough')
        I('AddItem', id, 'rag', 1); server:advance(300)
        expect(last(id, 'wasteland:quests:client:notice')).toBe('You have everything for a hatchet! Press K and craft it.')
        expect(#events(id, 'wasteland:quests:client:ready')).toBe(1)
        expect(tracker(id)[1].objectives[1].how).toContain('You have everything')
    end)

    it('tools count once carried, and stay done', function()
        I('AddItem', id, 'scrap_axe', 1); server:advance(300)
        expect(tracker(id)[1].objectives[1].done).toBe(true)
        I('RemoveItem', id, 'scrap_axe', 1); server:advance(300)
        expect(tracker(id)[1].objectives[1].done).toBe(true)
        I('AddItem', id, 'weapon_hatchet', 1); I('AddItem', id, 'pickaxe', 1); server:advance(300)
        expect(tracker(id)[1].objectives[2].done).toBe(true)
    end)

    it('chopping trees and mining rocks count by kind', function()
        server:triggerEvent(id, 'wasteland:loot:gathered', id, 'tree'); server:advance(100)
        server:triggerEvent(id, 'wasteland:loot:gathered', id, 'tree'); server:advance(100)
        server:triggerEvent(id, 'wasteland:loot:gathered', id, 'tree'); server:advance(100)
        server:triggerEvent(id, 'wasteland:loot:gathered', id, 'rock'); server:advance(200)
        local o = tracker(id)[1].objectives
        expect(o[3].text).toBe('Chop trees 2/2'); expect(o[4].text).toBe('Mine rocks 1/2')
        server:triggerEvent(id, 'wasteland:loot:gathered', id, 'rock'); server:advance(200)
        expect(tracker(id)[1].objectives[4].done).toBe(true)
    end)

    it('selling wood at a trader finishes it: cash and items paid, done for good', function()
        I('AddItem', id, 'wood_log', 3); server:advance(200)
        local cash, bandages = I('GetCash', id), I('GetItemCount', id, 'bandage')
        server:clientEvent(id, 'wasteland:quests:server:sell', 'base', 1, 'wood_log', 3) -- wrong event: ignored
        server:clientEvent(id, 'wasteland:camps:server:sell', 'base', 1, 'wood_log', 3); server:advance(400)
        local done = last(id, 'wasteland:quests:client:tutorialDone')
        expect(done ~= nil).toBe(true)
        expect(done.rewards[1]).toBe('$50')
        expect(I('GetCash', id)).toBe(cash + 30 + 50)
        expect(I('GetItemCount', id, 'bandage')).toBe(bandages + 1)
        local active = server:export('wasteland_quests', 'GetActiveQuests', id)
        expect(#active).toBe(1); expect(active[1]).toBe('hunt')
        server:clientEvent(id, 'wasteland:quests:server:log'); server:advance(200)
        expect(#last(id, 'wasteland:quests:client:log').again).toBe(0)
        expect(#server.scriptErrors).toBe(0)
    end)

    it('/tutorial stop drops it', function()
        local id2 = player('quitter')
        server:clientEvent(id2, 'wasteland:quests:server:tutorialCommand', ''); server:advance(300)
        tutorial(id2, 'start')
        expect(#server:export('wasteland_quests', 'GetActiveQuests', id2)).toBe(1)
        server:clientEvent(id2, 'wasteland:quests:server:tutorialCommand', 'stop'); server:advance(300)
        expect(#server:export('wasteland_quests', 'GetActiveQuests', id2)).toBe(0)
        expect(last(id2, 'wasteland:quests:client:notice')).toContain('Tutorial stopped')
    end)
end)
