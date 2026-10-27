-- wasteland_crafting (server): screen data, blueprints, crafting (known,
-- materials, timing, full inventory), persistence of known recipes.

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
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_crafting' })
    return server
end

local function player(server, license)
    local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
    server:advance(200)
    server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    return id
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end
local function I(server, fn, ...) return server:export('wasteland_inventory', fn, ...) end
local function snapOf(server, id) return last(events(server, id, 'wasteland:inventory:client:sync')).args[1] end
local function screen(server, id) return last(events(server, id, 'wasteland:crafting:client:screen')).args[1] end
local function find(server, id, name)
    for _, i in ipairs(snapOf(server, id).inventories) do
        for _, s in ipairs(i.items) do if s.name == name then return s, i.id end end
    end
end
local function craft(server, id, recipe, waitMs)
    server:clientEvent(id, 'wasteland:crafting:server:craft', recipe)
    server:advance(waitMs or 100)
end

describe('crafting', function()
    local server = world()
    local id = player(server, 'maker')

    it('runs; the screen lists the starter recipes and how many are left to learn', function()
        expect(states(server).crafting).toBe('running')
        server:clientEvent(id, 'wasteland:crafting:server:open')
        server:advance(100)
        local d = screen(server, id)
        local names = {}
        for _, r in ipairs(d.recipes) do names[#names + 1] = r.name end
        table.sort(names)
        expect(table.concat(names, ',')).toBe('armor_repair_kit,bandage,building_plan,campfire,farm_plot_large,farm_plot_medium,farm_plot_small,lockpick,metal_sheet,moonshine_still,pickaxe,rag,rag_hat,rag_pants,rag_shoes,rain_catcher,saw_planks,saw_planks_5,sewing_kit,weapon_hatchet,weapon_molotov')
        expect(d.unknown).toBe(29)
    end)

    it('needs the materials', function()
        craft(server, id, 'bandage')
        expect(screen(server, id).message).toBe('You need 2 x Clean rag (you have 0).')
        expect(#events(server, id, 'wasteland:crafting:client:progress')).toBe(0)
    end)

    it('crafts after the time: materials taken, result given', function()
        I(server, 'AddItem', id, 'rag', 4); server:advance(100)
        craft(server, id, 'bandage')
        local p = last(events(server, id, 'wasteland:crafting:client:progress')).args[1]
        expect(p.seconds).toBe(3)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(100) -- too early
        expect(#server:lines('finished crafting "bandage" too early')).toBe(1)
        expect(I(server, 'GetItemCount', id, 'rag')).toBe(4)
        craft(server, id, 'bandage', 3100)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(screen(server, id).message).toBe('Made 1 x Bandage.')
        expect(I(server, 'GetItemCount', id, 'rag')).toBe(2)
        expect(I(server, 'GetItemCount', id, 'bandage')).toBe(3) -- 2 starting + 1
    end)

    it('makes several one after another, and stops when the materials run out', function()
        I(server, 'AddItem', id, 'rag', 3); server:advance(100) -- 2 left + 3 = 5 rags: two bandages
        server:clientEvent(id, 'wasteland:crafting:server:craft', 'bandage', 3); server:advance(100)
        expect(last(events(server, id, 'wasteland:crafting:client:progress')).args[1].label).toBe('Making bandage (1 of 3)')
        server:advance(3100)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(last(events(server, id, 'wasteland:crafting:client:progress')).args[1].label).toBe('Making bandage (2 of 3)')
        expect(last(events(server, id, 'wasteland:crafting:client:notice')).args[1]).toBe('Made 1 of 3.')
        server:advance(3100)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(screen(server, id).message).toBe('Made 2 of 3 x Bandage: out of materials.')
        expect(I(server, 'GetItemCount', id, 'bandage')).toBe(5)
        expect(I(server, 'GetItemCount', id, 'rag')).toBe(1)
        I(server, 'AddItem', id, 'rag', 1); server:advance(100) -- back to 2 for the tests below
    end)

    it('recipes with a blueprint are refused until learned', function()
        I(server, 'AddItem', id, 'scrap_metal', 4); I(server, 'AddItem', id, 'duct_tape', 2); server:advance(100)
        craft(server, id, 'weapon_machete')
        expect(#server:lines('tried to craft "weapon_machete" without the blueprint')).toBe(1)
    end)

    it('using a blueprint teaches the recipe (once) and uses up the blueprint', function()
        I(server, 'AddItem', id, 'blueprint_machete', 2); server:advance(100)
        local bp, invId = find(server, id, 'blueprint_machete')
        server:clientEvent(id, 'wasteland:inventory:server:use', bp.uid, invId); server:advance(200)
        expect(last(events(server, id, 'wasteland:inventory:client:notice')).args[1]).toContain('You learned how to make: Machete')
        expect(I(server, 'GetItemCount', id, 'blueprint_machete')).toBe(1)
        expect(server:export('wasteland_crafting', 'KnowsRecipe', id, 'weapon_machete')).toBe(true)
        bp, invId = find(server, id, 'blueprint_machete')
        server:clientEvent(id, 'wasteland:inventory:server:use', bp.uid, invId); server:advance(200)
        expect(last(events(server, id, 'wasteland:inventory:client:error')).args[1]).toBe('You already know this.')
        expect(I(server, 'GetItemCount', id, 'blueprint_machete')).toBe(1)
    end)

    it('crafts the learned weapon (with full durability)', function()
        craft(server, id, 'weapon_machete', 8100)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        local m = find(server, id, 'weapon_machete')
        expect(m ~= nil).toBe(true); expect(m.metadata.durability).toBe(300)
        expect(I(server, 'GetItemCount', id, 'scrap_metal')).toBe(0)
        expect(I(server, 'GetItemCount', id, 'rag')).toBe(1)
    end)

    it('known recipes stay with the character', function()
        server:dropPlayer(id); server:advance(1000)
        local id2 = server:connectAndJoin({ name = 'P-maker', license = 'maker' })
        server:advance(200)
        server.players[id2].coords = { x = 0.0, y = 0.0, z = 30.0 }
        server:command(id2, 'character select 1'); server:advance(800)
        expect(server:export('wasteland_crafting', 'KnowsRecipe', id2, 'weapon_machete')).toBe(true)
        expect(server:export('wasteland_crafting', 'KnowsRecipe', id2, 'weapon_knife')).toBe(false)
    end)
end)

describe('crafting with no room for the result', function()
    local cfg = {}
    for k, v in pairs(CFG) do cfg[k] = v end
    cfg['crafting.lua'] = [[return { recipes = {
        big = { label = 'Big thing', result = { name = 'weapon_pumpshotgun', count = 1 },
            ingredients = { { name = 'duct_tape', count = 1 } }, seconds = 1 },
    } }]]
    local server = newServer({ config = cfg })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_crafting' })
    local id = player(server, 'full')

    it('gives the materials back and says why', function()
        I(server, 'AddItem', id, 'duct_tape', 1); server:advance(100)
        for _ = 1, 30 do I(server, 'AddItem', id, 'weapon_knife', 1) end -- fill the pockets
        server:advance(100)
        craft(server, id, 'big', 1100)
        server:clientEvent(id, 'wasteland:crafting:server:finish'); server:advance(200)
        expect(screen(server, id).message).toContain('No room for the pump shotgun')
        expect(I(server, 'GetItemCount', id, 'duct_tape')).toBe(1)
        expect(I(server, 'GetItemCount', id, 'weapon_pumpshotgun')).toBe(0)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('crafting: tracking recipes', function()
    local server = world()
    local id = player(server, 'tracker')
    local function tracker() return last(events(server, id, 'wasteland:crafting:client:tracker')).args[1] end
    local function track(name) server:clientEvent(id, 'wasteland:crafting:server:track', name); server:advance(100) end

    it('tracking shows what a recipe needs and what you have, and follows the inventory', function()
        track('bandage')
        local t = tracker()
        expect(#t).toBe(1); expect(t[1].name).toBe('bandage')
        expect(t[1].ingredients[1].need > 0).toBe(true)
        local ing = t[1].ingredients[1]
        local before = ing.have
        local item
        server:clientEvent(id, 'wasteland:crafting:server:open'); server:advance(100)
        for _, r in ipairs(screen(server, id).recipes) do
            if r.name == 'bandage' then expect(r.tracked).toBe(true); item = r.ingredients[1].name end
        end
        I(server, 'AddItem', id, item, 2); server:advance(200)
        expect(tracker()[1].ingredients[1].have).toBe(before + 2)
    end)

    it('at most three; the oldest drops off; tracking again untracks; unknown recipes are refused', function()
        track('rag'); track('lockpick'); track('campfire')
        local names = {}
        for _, r in ipairs(tracker()) do names[#names + 1] = r.name end
        expect(table.concat(names, ',')).toBe('rag,lockpick,campfire')
        track('rag')
        expect(#tracker()).toBe(2)
        local n = #events(server, id, 'wasteland:crafting:client:tracker')
        track('weapon_pumpshotgun')
        expect(#events(server, id, 'wasteland:crafting:client:tracker')).toBe(n)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
