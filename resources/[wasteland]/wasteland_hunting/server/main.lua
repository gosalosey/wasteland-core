-- wasteland_hunting :: server/main.lua
-- Module "hunting":
--   * Animals (deer, boar, rabbits, coyotes) are spawned around players and
--     removed again when nobody is near.
--   * A dead animal (any animal) can be harvested with a blade: raw meat,
--     and a pelt from the bigger ones.
--   * A campfire (an item) is placed anywhere; lighting it takes matches and
--     firewood. Anyone can cook on it; it warms; its owner picks it up again.
--   * Cooking: raw meat becomes cooked meat, one piece after another, as
--     many as the player chose.

local Rules = WLH.Rules
local M
local animals = {}   -- handle -> { handle, kind, spawnedAt, deadAt }
local pending = {}   -- source -> true while a client looks for spawn spots
local harvesting = {} -- source -> { netId, at }
local fires = {}     -- id -> { id, handle, netId, owner (character id), ownerSrc, x, y, z, expiresAt }
local cooking = {}   -- source -> { fire, item, left, done, nextAt }
local nextFire = 0
local animalModels = {} -- model hash -> true
local runToken = nil

local function inv() return exports.wasteland_inventory end
local function players() return exports.wasteland_players end
local function now() return GetGameTimer() end
local function notice(src, msg) TriggerClientEvent('wasteland:hunting:client:notice', src, msg) end

local function characterOf(src)
    local ok, cid = pcall(function() return players():GetCharacterId(src) end)
    return ok and cid or nil
end

local function coordsOf(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    local c = GetEntityCoords(ent)
    return { x = c.x, y = c.y, z = c.z }
end

local function playerCoords(src) return coordsOf(GetPlayerPed(tostring(src))) end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + ((a.z or 0) - (b.z or 0)) ^ 2) end
local function dist2d(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function label(item)
    local d = inv():GetItemDefinition(item)
    return d and d.label or item
end

-- Give items; what does not fit is dropped at the player's feet.
local function give(src, name, count)
    if count <= 0 then return end
    if inv():AddItem(src, name, count) then return end
    local c = playerCoords(src)
    if c then inv():CreateLootDrop(c, { { name = name, count = count } }, { label = label(name) }) end
    notice(src, label(name) .. ' did not fit and was dropped at your feet.')
end

local function onlinePlayers()
    local ok, list = pcall(function() return players():GetOnlineCharacters() end)
    return ok and list or {}
end

-------------------------------------------------------------------------------
-- Animals
-------------------------------------------------------------------------------

local function animalEntry(handle)
    local model = GetEntityModel(handle)
    for _, a in ipairs(M.config.animals) do
        if GetHashKey(a.model) == model then return a end
    end
    return nil
end

local function spawnAnimal(point)
    local a = Rules.pick(M.config.animals, math.random())
    if not a then return end
    local handle = CreatePed(28, GetHashKey(a.model), point.x + 0.0, point.y + 0.0, point.z + 0.0, math.random() * 360.0, true, true)
    if not handle or handle == 0 or not DoesEntityExist(handle) then
        M.log:warn('could not create a %s at %.0f %.0f', a.model, point.x, point.y)
        return
    end
    Entity(handle).state:set('wlAnimal', { kind = a.label }, true)
    animals[handle] = { handle = handle, kind = a.label, spawnedAt = now() }
end

local function inSafeZone(p)
    if GetResourceState('wasteland_camps') ~= 'started' then return false end
    local ok, safe = pcall(function() return exports.wasteland_camps:IsInSafeZone(p) end)
    return ok and safe == true
end

-- Spots a client found (untrusted: each is checked).
local function spotsFound(src, points)
    if not pending[src] then return end
    pending[src] = nil
    local me = playerCoords(src)
    if not me or type(points) ~= 'table' then return end
    local s = M.config.spawn
    for i, p in ipairs(points) do
        if i > 5 then break end
        if type(p) == 'table' and type(p.x) == 'number' and type(p.y) == 'number' and type(p.z) == 'number' then
            local d = dist2d(me, p)
            if d >= s.minDistance - 5 and d <= s.maxDistance + 5 and math.abs(p.z - me.z) < 120 and not inSafeZone(p) then
                spawnAnimal(p)
            end
        end
    end
end

local function populate()
    local s = M.config.spawn
    local total = 0
    for h, a in pairs(animals) do
        if DoesEntityExist(h) then total = total + 1 else animals[h] = nil end
    end
    for _, c in ipairs(onlinePlayers()) do
        local me = playerCoords(c.source)
        if me and not pending[c.source] and total < s.max then
            local near = 0
            for h in pairs(animals) do
                local p = coordsOf(h)
                if p and dist2d(p, me) <= s.despawnDistance and GetEntityHealth(h) > 0 then near = near + 1 end
            end
            local want = math.min(s.perPlayer - near, s.max - total, 3)
            if want > 0 then
                pending[c.source] = true
                total = total + want
                TriggerClientEvent('wasteland:hunting:client:findSpots', c.source, want, s.minDistance, s.maxDistance)
                local src = c.source
                Citizen.SetTimeout(10000, function() pending[src] = nil end)
            end
        end
    end
end

-- Far from everyone, or dead for a while: gone.
local function cleanup()
    local s = M.config.spawn
    local where = {}
    for _, c in ipairs(onlinePlayers()) do where[#where + 1] = playerCoords(c.source) end
    for h, a in pairs(animals) do
        local p = coordsOf(h)
        if not p then
            animals[h] = nil
        else
            if GetEntityHealth(h) <= 0 and not a.deadAt then a.deadAt = now() end
            local near = false
            for _, w in ipairs(where) do if dist2d(w, p) <= s.despawnDistance then near = true end end
            if not near or (a.deadAt and now() - a.deadAt > s.deadMinutes * 60000) then
                DeleteEntity(h)
                animals[h] = nil
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Harvesting
-------------------------------------------------------------------------------

local function hasBlade(src)
    for _, t in ipairs(M.config.harvest.tools) do
        if (inv():GetItemCount(src, t) or 0) > 0 then return true end
    end
    return false
end

local function deadAnimal(netId)
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    if not animalModels[GetEntityModel(ent)] then return nil end
    if GetEntityHealth(ent) > 0 then return nil end
    return ent
end

local function harvestStart(src, netId)
    if harvesting[src] or cooking[src] then return end
    local ent = deadAnimal(netId)
    if not ent then notice(src, 'There is nothing to harvest.'); return end
    if Entity(ent).state.wlHarvested then notice(src, 'Someone already harvested this.'); return end
    local me, p = playerCoords(src), coordsOf(ent)
    if not me or dist(me, p) > 3.5 then notice(src, 'Get closer.'); return end
    if not hasBlade(src) then notice(src, 'You need a knife (or another blade) to harvest it.'); return end
    harvesting[src] = { netId = netId, at = now() }
    TriggerClientEvent('wasteland:hunting:client:harvesting', src, M.config.harvest.seconds)
end

local function harvestFinish(src)
    local h = harvesting[src]
    harvesting[src] = nil
    if not h or now() - h.at < (M.config.harvest.seconds - 0.5) * 1000 then return end
    local ent = deadAnimal(h.netId)
    if not ent or Entity(ent).state.wlHarvested then notice(src, 'There is nothing left to harvest.'); return end
    local me, p = playerCoords(src), coordsOf(ent)
    if not me or dist(me, p) > 4.0 or not hasBlade(src) then return end
    Entity(ent).state:set('wlHarvested', true, true)
    local entry = animalEntry(ent)
    local meat, pelt = Rules.yield(entry, M.config.otherAnimalMeat, math.random())
    give(src, M.config.harvest.meatItem, meat)
    if pelt > 0 then give(src, M.config.harvest.peltItem, pelt) end
    notice(src, string.format('You got %d x %s%s.', meat, label(M.config.harvest.meatItem),
        pelt > 0 and string.format(' and %d x %s', pelt, label(M.config.harvest.peltItem)) or ''))
    TriggerEvent('wasteland:hunting:harvested', src, entry and entry.label or 'animal', meat, pelt)
    -- the carcass goes a moment later
    Citizen.SetTimeout(3000, function()
        if DoesEntityExist(ent) then DeleteEntity(ent) end
        animals[ent] = nil
    end)
end

-------------------------------------------------------------------------------
-- Campfires
-------------------------------------------------------------------------------

local function fireByNet(netId)
    for _, f in pairs(fires) do if f.netId == netId then return f end end
    return nil
end

local function fireMissing(src)
    local cf = M.config.campfire
    for _, n in ipairs(cf.needs) do
        local have = inv():GetItemCount(src, n.name) or 0
        if have < n.count then return string.format('You need %d x %s to light a campfire (you have %d).', n.count, label(n.name), have) end
    end
    return nil
end

local function useCampfire(src)
    if not characterOf(src) then return false end
    local why = fireMissing(src)
    if why then return false, why end
    TriggerClientEvent('wasteland:hunting:client:placeFire', src)
    return 0 -- taken when it is placed
end

local function placeFire(src, x, y, z)
    local cid = characterOf(src)
    if not cid then return end
    local me = playerCoords(src)
    if not me or dist(me, { x = x, y = y, z = z }) > 4.0 then notice(src, 'Too far away.'); return end
    for _, f in pairs(fires) do
        if dist2d(f, { x = x, y = y }) < 2.0 then notice(src, 'There is already a fire here.'); return end
    end
    local cf = M.config.campfire
    if (inv():GetItemCount(src, cf.item) or 0) < 1 then notice(src, 'You need a ' .. label(cf.item) .. '.'); return end
    local why = fireMissing(src)
    if why then notice(src, why); return end
    if not inv():RemoveItem(src, cf.item, 1) then return end
    for _, n in ipairs(cf.needs) do inv():RemoveItem(src, n.name, n.count) end
    local handle = CreateObjectNoOffset(GetHashKey(cf.model), x + 0.0, y + 0.0, z + 0.0, true, true, false)
    if not handle or handle == 0 or not DoesEntityExist(handle) then
        give(src, cf.item, 1)
        notice(src, 'The campfire could not be placed here.')
        return
    end
    FreezeEntityPosition(handle, true)
    nextFire = nextFire + 1
    local f = { id = nextFire, handle = handle, netId = NetworkGetNetworkIdFromEntity(handle), owner = cid, ownerSrc = src,
        x = x, y = y, z = z, expiresAt = now() + cf.burnMinutes * 60000 }
    fires[f.id] = f
    Entity(handle).state:set('wlCampfire', { id = f.id, owner = cid }, true)
    TriggerClientEvent('wasteland:hunting:client:fires', -1, { [f.netId] = true })
    notice(src, string.format('The fire is burning (about %d minutes). Hold Left Alt on it to cook, or to pick it up.', cf.burnMinutes))
end

local function putOut(f, why)
    fires[f.id] = nil
    for src, c in pairs(cooking) do
        if c.fire == f.id then
            cooking[src] = nil
            TriggerClientEvent('wasteland:hunting:client:cooking', src, { done = true, message = 'The fire went out.' })
        end
    end
    if DoesEntityExist(f.handle) then DeleteEntity(f.handle) end
    M.log:info('campfire %d out (%s)', f.id, why)
end

local function pickUp(src, netId)
    local f = fireByNet(netId)
    if not f then return end
    local me = playerCoords(src)
    if not me or dist(me, f) > 3.5 then notice(src, 'Get closer.'); return end
    if f.owner ~= characterOf(src) then notice(src, 'Only the player who made this fire can pick it up.'); return end
    putOut(f, 'picked up')
    give(src, M.config.campfire.item, 1)
    notice(src, 'You put out the fire and packed it up.')
end

-- Burnt out: the fire pit stays usable (back to its owner, or on the ground).
local function burnOut(f)
    putOut(f, 'burnt out')
    local item = M.config.campfire.item
    local ok, src = pcall(function() return players():GetSourceByCharacterId(f.owner) end)
    if ok and src and inv():AddItem(src, item, 1) then
        notice(src, 'Your campfire burnt out. It is back in your inventory.')
    else
        inv():CreateLootDrop({ x = f.x, y = f.y, z = f.z }, { { name = item, count = 1 } }, { label = label(item) })
    end
end

local function warmthAt(src)
    local me = playerCoords(src)
    if not me then return 0 end
    for _, f in pairs(fires) do
        if dist(me, f) <= M.config.campfire.warmthRadius then return M.config.campfire.warmth end
    end
    return 0
end

-------------------------------------------------------------------------------
-- Cooking
-------------------------------------------------------------------------------

local function cookScreen(src, f, message)
    local list = {}
    local names = {}
    for raw in pairs(M.config.cooking.recipes) do names[#names + 1] = raw end
    table.sort(names)
    local images = {}
    for _, it in ipairs(inv():GetItemList()) do images[it.name] = it.image end
    for _, raw in ipairs(names) do
        local out = M.config.cooking.recipes[raw]
        list[#list + 1] = { item = raw, label = label(raw), result = label(out), have = inv():GetItemCount(src, raw) or 0, image = images[raw] }
    end
    local c = cooking[src]
    TriggerClientEvent('wasteland:hunting:client:cookScreen', src, { fire = f.netId, items = list, seconds = M.config.cooking.seconds,
        max = M.config.cooking.maxBatch, message = message,
        cooking = c and { label = label(c.item), done = c.done, total = c.done + c.left } or nil })
end

local function openCook(src, netId)
    local f = fireByNet(netId)
    if not f then return end
    local me = playerCoords(src)
    if not me or dist(me, f) > 3.5 then notice(src, 'Get closer to the fire.'); return end
    cookScreen(src, f)
end

local function startCook(src, netId, item, want)
    local f = fireByNet(netId)
    if not f or cooking[src] or harvesting[src] then return end
    if not M.config.cooking.recipes[item] then return end
    local me = playerCoords(src)
    if not me or dist(me, f) > 3.5 then notice(src, 'Get closer to the fire.'); return end
    local n = Rules.cookCount(want, inv():GetItemCount(src, item) or 0, M.config.cooking.maxBatch)
    if n == 0 then cookScreen(src, f, 'You have no ' .. label(item):lower() .. '.'); return end
    cooking[src] = { fire = f.id, item = item, left = n, done = 0, nextAt = now() + M.config.cooking.seconds * 1000 }
    cookScreen(src, f)
    TriggerClientEvent('wasteland:hunting:client:cooking', src, { label = label(item), done = 0, total = n, seconds = M.config.cooking.seconds })
end

local function stopCook(src, message)
    local c = cooking[src]
    if not c then return end
    cooking[src] = nil
    TriggerClientEvent('wasteland:hunting:client:cooking', src, { done = true, message = message })
    local f = fires[c.fire]
    if f then cookScreen(src, f, message) end
end

local function cookTick()
    local t = now()
    for src, c in pairs(cooking) do
        local f = fires[c.fire]
        local me = playerCoords(src)
        if not f then cooking[src] = nil
        elseif not me or dist(me, f) > 4.0 then stopCook(src, 'You walked away from the fire.')
        elseif t >= c.nextAt then
            local out = M.config.cooking.recipes[c.item]
            if not inv():RemoveItem(src, c.item, 1) then
                stopCook(src, 'You have no more ' .. label(c.item):lower() .. '.')
            elseif not inv():AddItem(src, out, 1) then
                inv():AddItem(src, c.item, 1)
                stopCook(src, 'No room for the ' .. label(out):lower() .. '.')
            else
                c.left, c.done = c.left - 1, c.done + 1
                if c.left <= 0 then
                    cooking[src] = nil
                    TriggerClientEvent('wasteland:hunting:client:cooking', src, { done = true, message = string.format('Cooked %d x %s.', c.done, label(out)) })
                    cookScreen(src, f, string.format('Cooked %d x %s.', c.done, label(out)))
                else
                    c.nextAt = t + M.config.cooking.seconds * 1000
                    TriggerClientEvent('wasteland:hunting:client:cooking', src, { label = label(c.item), done = c.done, total = c.done + c.left,
                        seconds = M.config.cooking.seconds })
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Loops
-------------------------------------------------------------------------------

local function loop(token)
    local sinceSpawn, sinceClean = 0, 0
    while runToken == token do
        Citizen.Wait(500)
        if runToken ~= token then return end
        sinceSpawn, sinceClean = sinceSpawn + 500, sinceClean + 500
        cookTick()
        if sinceClean >= 10000 then
            sinceClean = 0
            cleanup()
            local t = now()
            for _, f in pairs(fires) do
                if t >= f.expiresAt then burnOut(f) elseif not DoesEntityExist(f.handle) then putOut(f, 'gone') end
            end
        end
        if M.config.spawn.enabled and sinceSpawn >= M.config.spawn.everySeconds * 1000 then
            sinceSpawn = 0
            populate()
        end
    end
end

local function registerHooks()
    if GetResourceState('wasteland_survival') == 'started' then
        pcall(function() exports.wasteland_survival:RegisterWarmthSource('hunting', warmthAt) end)
    end
end

AddEventHandler('onResourceStart', function(res)
    if res == 'wasteland_survival' and M and M.active then Citizen.SetTimeout(1000, registerHooks) end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then harvesting[src], cooking[src], pending[src] = nil, nil, nil end
end)

AddEventHandler('wasteland:players:characterLoaded', function(src)
    if not (M and M.active) then return end
    local list = {}
    for _, f in pairs(fires) do list[f.netId] = true end
    TriggerClientEvent('wasteland:hunting:client:fires', src, list)
end)

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local PAIR = { type = 'array', minItems = 1, items = { type = 'integer', min = 0, max = 100 } }

M = Wasteland.DefineModule({
    name = 'hunting',
    version = '0.1.0',
    description = 'Animals, harvesting, campfires and cooking',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', inventory = '^0.1.0' },
    optionalDependencies = { survival = '^0.1.0', camps = '^0.1.0' },
    config = {
        file = 'hunting.lua',
        optional = true,
        schema = { type = 'table', fields = {
            animals = { type = 'array', default = {}, items = { type = 'table', fields = {
                model = { type = 'string', required = true, pattern = '^[%w_]+$' },
                label = { type = 'string', required = true, minLength = 1, maxLength = 32 },
                weight = { type = 'number', default = 1, min = 0, max = 1000 },
                meat = PAIR,
                pelt = { type = 'integer', default = 0, min = 0, max = 10 },
            } } },
            otherAnimalMeat = { type = 'array', default = { 1, 2 }, items = { type = 'integer', min = 0, max = 100 } },
            spawn = { type = 'table', fields = {
                enabled = { type = 'boolean', default = true },
                perPlayer = { type = 'integer', default = 3, min = 0, max = 20 },
                max = { type = 'integer', default = 40, min = 0, max = 300 },
                minDistance = { type = 'number', default = 90, min = 30, max = 500 },
                maxDistance = { type = 'number', default = 200, min = 40, max = 800 },
                everySeconds = { type = 'number', default = 20, min = 5, max = 600 },
                despawnDistance = { type = 'number', default = 350, min = 100, max = 2000 },
                deadMinutes = { type = 'number', default = 10, min = 1, max = 120 },
            } },
            harvest = { type = 'table', fields = {
                seconds = { type = 'number', default = 6, min = 1, max = 60 },
                tools = { type = 'array', default = { 'weapon_knife' }, items = { type = 'string', pattern = '^[%w_]+$' } },
                meatItem = { type = 'string', default = 'raw_meat', pattern = '^[%w_]+$' },
                peltItem = { type = 'string', default = 'animal_pelt', pattern = '^[%w_]+$' },
            } },
            campfire = { type = 'table', fields = {
                item = { type = 'string', default = 'campfire', pattern = '^[%w_]+$' },
                model = { type = 'string', default = 'prop_beach_fire' },
                needs = { type = 'array', default = { { name = 'matches', count = 1 }, { name = 'firewood', count = 2 } }, items = { type = 'table', fields = {
                    name = { type = 'string', required = true, pattern = '^[%w_]+$' },
                    count = { type = 'integer', required = true, min = 1, max = 100 },
                } } },
                burnMinutes = { type = 'number', default = 30, min = 1, max = 600 },
                warmth = { type = 'number', default = 8, min = 0, max = 50 },
                warmthRadius = { type = 'number', default = 5, min = 1, max = 30 },
            } },
            cooking = { type = 'table', fields = {
                seconds = { type = 'number', default = 5, min = 0.5, max = 120, description = 'Per piece' },
                maxBatch = { type = 'integer', default = 50, min = 1, max = 500 },
                recipes = { type = 'map', default = { raw_meat = 'cooked_meat' }, keys = { type = 'string', pattern = '^[%w_]+$' },
                    values = { type = 'string', pattern = '^[%w_]+$' } },
            } },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        local known = function(item) return inv():GetItemDefinition(item) ~= nil end
        local need = { M.config.harvest.meatItem, M.config.harvest.peltItem, M.config.campfire.item }
        for _, n in ipairs(M.config.campfire.needs) do need[#need + 1] = n.name end
        for _, t in ipairs(M.config.harvest.tools) do need[#need + 1] = t end
        for raw, out in pairs(M.config.cooking.recipes) do need[#need + 1] = raw; need[#need + 1] = out end
        for _, item in ipairs(need) do
            if not known(item) then return false, string.format('hunting.lua names item "%s", which is not in inventory.lua items', item) end
        end
        animalModels = {}
        for _, m in ipairs(Rules.ANIMAL_MODELS) do animalModels[GetHashKey(m)] = true end
        for _, a in ipairs(M.config.animals) do animalModels[GetHashKey(a.model)] = true end
        animals, pending, harvesting, fires, cooking = {}, {}, {}, {}, {}
        local ok, err = inv():RegisterUsable(M.config.campfire.item, useCampfire)
        if not ok then return false, 'could not register the campfire item: ' .. tostring(err) end
        registerHooks()
        local token = {}
        runToken = token
        Citizen.CreateThread(function() loop(token) end)
        return true
    end,
    onShutdown = function()
        runToken = nil
        for h in pairs(animals) do if DoesEntityExist(h) then DeleteEntity(h) end end
        for _, f in pairs(fires) do burnOut(f) end
        animals, fires, cooking, harvesting = {}, {}, {}, {}
    end,
})

local RATE = { burst = 6, perSecond = 2 }
local NET = { type = 'integer', required = true, min = 0, max = 1000000 }
local COORD = { type = 'number', required = true, min = -20000, max = 20000 }

M.netEvent('wasteland:hunting:server:config', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    local list = {}
    for _, f in pairs(fires) do list[f.netId] = true end
    TriggerClientEvent('wasteland:hunting:client:config', src, { fireModel = M.config.campfire.model, harvestSeconds = M.config.harvest.seconds })
    TriggerClientEvent('wasteland:hunting:client:fires', src, list)
end)
local POINT = { type = 'table', fields = { x = COORD, y = COORD, z = COORD } }
M.netEvent('wasteland:hunting:server:spots', { args = { { type = 'array', required = true, maxItems = 10, items = POINT } }, rateLimit = RATE },
    function(src, points) spotsFound(src, points) end)
M.netEvent('wasteland:hunting:server:harvest', { args = { NET }, rateLimit = RATE }, function(src, netId) harvestStart(src, netId) end)
M.netEvent('wasteland:hunting:server:harvestDone', { rateLimit = RATE }, function(src) harvestFinish(src) end)
M.netEvent('wasteland:hunting:server:harvestCancel', { rateLimit = RATE }, function(src) harvesting[src] = nil end)
M.netEvent('wasteland:hunting:server:placeFire', { args = { COORD, COORD, COORD }, rateLimit = { burst = 3, perSecond = 0.5 } },
    function(src, x, y, z) placeFire(src, x, y, z) end)
M.netEvent('wasteland:hunting:server:pickUp', { args = { NET }, rateLimit = RATE }, function(src, netId) pickUp(src, netId) end)
M.netEvent('wasteland:hunting:server:openCook', { args = { NET }, rateLimit = RATE }, function(src, netId) openCook(src, netId) end)
M.netEvent('wasteland:hunting:server:cook', {
    args = { NET, { type = 'string', required = true, pattern = '^[%w_]+$', maxLength = 48 }, { type = 'integer', required = true, min = 1, max = 500 } },
    rateLimit = RATE,
}, function(src, netId, item, n) startCook(src, netId, item, n) end)
M.netEvent('wasteland:hunting:server:stopCook', { rateLimit = RATE }, function(src) stopCook(src, 'You stopped cooking.') end)

--- GetAnimalCount() -> number of animals this module has out
exports('GetAnimalCount', function()
    local n = 0
    for _ in pairs(animals) do n = n + 1 end
    return n
end)
