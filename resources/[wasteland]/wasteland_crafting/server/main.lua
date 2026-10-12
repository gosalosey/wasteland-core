-- wasteland_crafting :: server/main.lua
-- Module "crafting": recipes from crafting.lua, learned from blueprint
-- items (use one) unless they need none. Crafting happens anywhere: the
-- server checks the recipe is known and the ingredients are there, times
-- the craft (the client shows a progress bar; moving cancels), then takes
-- the ingredients and gives the result in one go (everything goes back if
-- the result does not fit). Known recipes are stored with the character.

local Recipes = WLCR.Recipes
local M
local crafting = {}    -- source -> { recipe, startedAt }
local DATA_KEY = 'crafting'

local function inv() return exports.wasteland_inventory end
local function players() return exports.wasteland_players end
local function now() return GetGameTimer() end
local function notice(src, msg) TriggerClientEvent('wasteland:crafting:client:notice', src, msg) end

local function characterOf(src)
    local ok, cid = pcall(function() return players():GetCharacterId(src) end)
    return ok and cid or nil
end

local function knownOf(cid)
    local data = cid and players():GetCharacterData(cid, DATA_KEY)
    return type(data) == 'table' and type(data.known) == 'table' and data.known or {}
end

local function label(item)
    local d = inv():GetItemDefinition(item)
    return d and d.label or item
end

-- Stations (e.g. a base's workbench): name -> { label, check(source) -> bool },
-- added by other modules with RegisterStation.
local stations = {}

local function stationInfo(src, name)
    if not name then return nil end
    local st = stations[name]
    if not st then return { label = name, here = false } end
    local ok, here = pcall(st.check, src)
    return { label = st.label, here = ok and here == true }
end

--- What the crafting screen shows: every known recipe with what you have,
--- and how many recipes are still to be found.
local function screenData(src)
    local known = knownOf(characterOf(src))
    local images = {}
    for _, it in ipairs(inv():GetItemList()) do images[it.name] = it.image end
    local list, hidden = {}, 0
    local names = {}
    for name in pairs(M.config.recipes) do names[#names + 1] = name end
    table.sort(names, function(a, b) return M.config.recipes[a].label < M.config.recipes[b].label end)
    for _, name in ipairs(names) do
        local r = M.config.recipes[name]
        if Recipes.knows(known, name, r) then
            local ingredients = {}
            for _, ing in ipairs(r.ingredients) do
                ingredients[#ingredients + 1] = { name = ing.name, label = label(ing.name), image = images[ing.name], need = ing.count,
                    have = inv():GetItemCount(src, ing.name) or 0 }
            end
            list[#list + 1] = { name = name, label = r.label, seconds = r.seconds, image = images[r.result.name],
                result = { name = r.result.name, label = label(r.result.name), count = r.result.count }, ingredients = ingredients,
                station = stationInfo(src, r.station) }
        else
            hidden = hidden + 1
        end
    end
    return { recipes = list, unknown = hidden, busy = crafting[src] ~= nil }
end

local function send(src, message, ok)
    local d = screenData(src)
    d.message, d.ok = message, ok
    TriggerClientEvent('wasteland:crafting:client:screen', src, d)
end

local function countFor(src) return function(item) return inv():GetItemCount(src, item) or 0 end end

-------------------------------------------------------------------------------
-- Blueprints
-------------------------------------------------------------------------------

local function useBlueprint(src, stack)
    local cid = characterOf(src)
    if not cid then return false, 'You have no character loaded.' end
    local teaches = Recipes.taughtBy(M.config.recipes, stack.name)
    if #teaches == 0 then return false, 'This blueprint teaches nothing.' end
    local known = knownOf(cid)
    local new = {}
    for _, name in ipairs(teaches) do
        if not known[name] then known[name] = true; new[#new + 1] = M.config.recipes[name].label end
    end
    if #new == 0 then return false, 'You already know this.' end
    players():SetCharacterData(cid, DATA_KEY, { known = known })
    M.log:info('player %d (character %d) learned %s', src, cid, table.concat(teaches, ', '))
    TriggerEvent('wasteland:crafting:learned', src, teaches)
    return 1, 'You learned how to make: ' .. table.concat(new, ', ') .. '. Press K to craft.'
end

local function registerBlueprints()
    if GetResourceState('wasteland_inventory') ~= 'started' then return end
    local done = {}
    for _, r in pairs(M.config.recipes) do
        if r.blueprint and not done[r.blueprint] then
            done[r.blueprint] = true
            local ok, err = inv():RegisterUsable(r.blueprint, useBlueprint)
            if not ok then M.log:warn('blueprint "%s": %s', r.blueprint, tostring(err)) end
        end
    end
end

AddEventHandler('wasteland:core:moduleState', function(name, state)
    if name == 'inventory' and state == 'running' and M and M.active then registerBlueprints() end
end)

-------------------------------------------------------------------------------
-- Crafting
-------------------------------------------------------------------------------

local MAX_BATCH = 50

-- count: how many to make one after another (each one timed).
local function start(src, name, count)
    local r = M.config.recipes[name]
    local busy = crafting[src]
    if busy and now() - busy.startedAt < (M.config.recipes[busy.recipe].seconds + 10) * 1000 then return end
    crafting[src] = nil
    if not r then return end
    if not Recipes.knows(knownOf(characterOf(src)), name, r) then
        M.log:warn('player %d tried to craft "%s" without the blueprint', src, name)
        return
    end
    local station = stationInfo(src, r.station)
    if station and not station.here then send(src, 'You need to be at a ' .. station.label .. '.', false); return end
    local missing = Recipes.missing(r, countFor(src))
    if #missing > 0 then
        send(src, string.format('You need %d x %s (you have %d).', missing[1].need, label(missing[1].name), missing[1].have), false)
        return
    end
    count = math.max(1, math.min(MAX_BATCH, math.floor(tonumber(count) or 1)))
    crafting[src] = { recipe = name, startedAt = now(), total = count, made = 0 }
    TriggerClientEvent('wasteland:crafting:client:progress', src, { seconds = r.seconds,
        label = 'Making ' .. r.label:lower() .. (count > 1 and string.format(' (1 of %d)', count) or '') })
end

local function finish(src)
    local c = crafting[src]
    crafting[src] = nil
    if not c then return end
    local r = M.config.recipes[c.recipe]
    if now() - c.startedAt < r.seconds * 1000 - 300 then
        M.log:warn('player %d finished crafting "%s" too early', src, c.recipe)
        return
    end
    local total, made = c.total or 1, c.made or 0
    local function stopped(why)
        send(src, made > 0 and string.format('Made %d of %d. %s', made, total, why) or why, made > 0)
    end
    local missing = Recipes.missing(r, countFor(src))
    if #missing > 0 then stopped('Some of the materials are gone.'); return end
    -- Take every ingredient; on any failure put back what was taken.
    local taken = {}
    for _, ing in ipairs(r.ingredients) do
        local ok = inv():RemoveItem(src, ing.name, ing.count)
        if not ok then
            for _, t in ipairs(taken) do inv():AddItem(src, t.name, t.count) end
            stopped('Some of the materials are gone.')
            return
        end
        taken[#taken + 1] = ing
    end
    local ok, err = inv():AddItem(src, r.result.name, r.result.count)
    if not ok then
        for _, t in ipairs(taken) do inv():AddItem(src, t.name, t.count) end
        stopped('No room for the ' .. label(r.result.name):lower() .. ' (' .. tostring(err) .. ').')
        return
    end
    made = made + 1
    M.log:info('player %d crafted %d x %s', src, r.result.count, r.result.name)
    TriggerEvent('wasteland:crafting:crafted', src, c.recipe)
    if made < total then
        -- Next one, if the materials are still there.
        if #Recipes.missing(r, countFor(src)) > 0 then
            send(src, string.format('Made %d of %d x %s: out of materials.', made, total, label(r.result.name)), true)
            return
        end
        crafting[src] = { recipe = c.recipe, startedAt = now(), total = total, made = made }
        TriggerClientEvent('wasteland:crafting:client:notice', src, string.format('Made %d of %d.', made, total))
        TriggerClientEvent('wasteland:crafting:client:progress', src, { seconds = r.seconds,
            label = string.format('Making %s (%d of %d)', r.label:lower(), made + 1, total) })
        return
    end
    send(src, string.format('Made %d x %s.', r.result.count * total, label(r.result.name)), true)
end

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then crafting[src] = nil end
end)

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local STACK = { type = 'table', required = true, fields = {
    name = { type = 'string', required = true, pattern = '^[%w_]+$' },
    count = { type = 'integer', default = 1, min = 1, max = 100000 },
} }

M = Wasteland.DefineModule({
    name = 'crafting',
    version = '0.1.0',
    description = 'Crafting anywhere: recipes, blueprints, timed crafts',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', inventory = '^0.1.0' },
    config = {
        file = 'crafting.lua',
        optional = true,
        schema = { type = 'table', fields = {
            recipes = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%a][%w_]*$' }, values = { type = 'table', fields = {
                label = { type = 'string', required = true, minLength = 1, maxLength = 48 },
                result = STACK,
                ingredients = { type = 'array', required = true, minItems = 1, items = STACK },
                seconds = { type = 'number', default = 4, min = 0.5, max = 120 },
                blueprint = { type = 'string', pattern = '^[%w_]+$' },
                station = { type = 'string', pattern = '^[%w_]+$', description = 'Made only at this station (bases: workbench)' },
            } } },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        for name, r in pairs(M.config.recipes) do
            local items = { r.result.name, r.blueprint }
            for _, ing in ipairs(r.ingredients) do items[#items + 1] = ing.name end
            for _, item in pairs(items) do
                if item and not inv():GetItemDefinition(item) then
                    return false, string.format('crafting.lua: recipe "%s" names item "%s", which is not in inventory.lua items', name, item)
                end
            end
        end
        crafting = {}
        registerBlueprints()
        return true
    end,
    onShutdown = function()
        for src in pairs(crafting) do TriggerClientEvent('wasteland:crafting:client:cancel', src) end
        crafting = {}
    end,
})

local RATE = { burst = 6, perSecond = 2 }

M.netEvent('wasteland:crafting:server:open', { rateLimit = RATE }, function(src)
    if characterOf(src) then send(src) end
end)

M.netEvent('wasteland:crafting:server:craft', { args = { { type = 'string', required = true, pattern = '^[%a][%w_]*$', maxLength = 48 },
    { type = 'integer', min = 1, max = MAX_BATCH } }, rateLimit = RATE }, function(src, name, count) start(src, name, count) end)

M.netEvent('wasteland:crafting:server:finish', { rateLimit = RATE }, function(src) finish(src) end)
M.netEvent('wasteland:crafting:server:cancel', { rateLimit = RATE }, function(src) crafting[src] = nil end)

-------------------------------------------------------------------------------
-- Exports (crafting api 0.1)
-------------------------------------------------------------------------------

--- KnowsRecipe(source, recipe) -> boolean
exports('KnowsRecipe', function(src, name)
    local r = M and M.config.recipes[name]
    return r ~= nil and Recipes.knows(knownOf(characterOf(tonumber(src))), name, r)
end)

--- TeachRecipe(source, recipe) -> ok   (quests, rewards)
exports('TeachRecipe', function(src, name)
    local cid = characterOf(tonumber(src))
    if not cid or not (M and M.config.recipes[name]) then return false end
    local known = knownOf(cid)
    known[name] = true
    players():SetCharacterData(cid, DATA_KEY, { known = known })
    return true
end)

--- RegisterStation(name, label, check(source) -> boolean)   (recipes with station = name need it)
exports('RegisterStation', function(name, lbl, check)
    if type(name) ~= 'string' then return false end
    stations[name] = { label = tostring(lbl or name), check = check }
    return true
end)

--- GetRecipeSummary(source) -> list of { name, label, known, blueprint }   (admin panel)
exports('GetRecipeSummary', function(src)
    local known = knownOf(characterOf(tonumber(src)))
    local out = {}
    for name, r in pairs(M and M.config.recipes or {}) do
        out[#out + 1] = { name = name, label = r.label, known = Recipes.knows(known, name, r), blueprint = r.blueprint ~= nil }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

--- ForgetRecipe(source, recipe) -> ok   (admin; recipes without a blueprint cannot be forgotten)
exports('ForgetRecipe', function(src, name)
    local cid = characterOf(tonumber(src))
    if not cid or not (M and M.config.recipes[name]) then return false end
    local known = knownOf(cid)
    known[name] = nil
    players():SetCharacterData(cid, DATA_KEY, { known = known })
    return true
end)
