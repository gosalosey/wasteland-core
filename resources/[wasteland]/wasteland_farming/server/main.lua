-- wasteland_farming :: server/main.lua
-- Module "farming": farm plots (small, medium, large) are crafted and placed
-- anywhere. Seeds are planted in their spots; plants grow while the plot has
-- water (water bottles, or rain when the plot is outdoors: no roof built
-- over it); ripe plants are harvested for food (and sometimes seeds back).
-- Every change is checked here; clients show the plots and ask.

local Rules = WLF.Rules
local SQL = WLF.SQL
local M
local plots = {}     -- id -> { id, owner, size, coords, heading, water, slots = { [i] = { crop, growth } | false } }
local runToken = nil

local function inv() return exports.wasteland_inventory end
local function players() return exports.wasteland_players end
local function notice(src, msg) TriggerClientEvent('wasteland:farming:client:notice', src, msg) end

local function characterOf(src)
    local ok, cid = pcall(function() return players():GetCharacterId(src) end)
    return ok and cid or nil
end

local function playerCoords(src)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return c and { x = c.x, y = c.y, z = c.z } or nil
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + ((a.z or 0) - (b.z or 0)) ^ 2) end
local function near(src, coords, reach)
    local p = playerCoords(src)
    return p ~= nil and dist(p, coords) <= reach
end

local function label(item)
    local d = inv():GetItemDefinition(item)
    return d and d.label or item
end

-- Picture of an item for the screen (wasteland_images; nil if it has none)
local function imageUrl(name)
    local d = inv():GetItemDefinition(name)
    if not d or GetResourceState('wasteland_images') ~= 'started' then return nil end
    return ('https://cfx-nui-wasteland_images/html/images/%s.webp'):format(d.image or name)
end

local function give(src, name, count)
    if count <= 0 then return end
    if inv():AddItem(src, name, count) then return end
    local c = playerCoords(src)
    if c then inv():CreateLootDrop(c, { { name = name, count = count } }, { label = label(name) }) end
    notice(src, label(name) .. ' did not fit and was dropped at your feet.')
end

local function sameGroup(a, b)
    if GetResourceState('wasteland_groups') ~= 'started' then return false end
    local ok, same = pcall(function() return exports.wasteland_groups:SameGroup(a, b) end)
    return ok and same == true
end

local function isAdmin(src)
    if GetResourceState('wasteland_admin') == 'started' then
        local ok, yes = pcall(function() return exports.wasteland_admin:IsAdmin(src) end)
        if ok then return yes == true end
    end
    local allowed = IsPlayerAceAllowed(tostring(src), 'wasteland.admin')
    return allowed == true or allowed == 1
end

local function slotsJson(p)
    local out = {}
    for i = 1, p.size * p.size do out[i] = p.slots[i] or false end
    return json.encode(out)
end

local function save(p)
    Citizen.CreateThread(function()
        local ok, err = WDB.update(SQL.update, { p.water, slotsJson(p), p.id })
        if not ok then M.log:warn('saving plot %d: %s', p.id, tostring(err)) end
    end)
end

-- What every client needs to draw a plot (and its plants by stage).
local function info(p)
    local slots = {}
    for i = 1, p.size * p.size do
        local s = p.slots[i]
        local c = s and M.config.crops[s.crop]
        slots[i] = c and { crop = s.crop, stage = Rules.stage(s.growth, c.minutes), color = c.color } or false
    end
    return { id = p.id, kind = p.kind, size = p.size, coords = p.coords, heading = p.heading, slots = slots }
end

local function broadcast(p) TriggerClientEvent('wasteland:farming:client:plot', -1, info(p)) end

-------------------------------------------------------------------------------
-- Rain: outdoors (no roof built over it) and the server's weather is rainy
-------------------------------------------------------------------------------

local function raining()
    if GetResourceState('wasteland_world') ~= 'started' then return false end
    local ok, name = pcall(function() return exports.wasteland_world:GetWeather() end)
    if not ok or type(name) ~= 'string' then return false end
    for _, w in ipairs(M.config.rainWeathers) do if w == name then return true end end
    return false
end

local function outdoors(p)
    if GetResourceState('wasteland_basebuilding') ~= 'started' then return true end
    local ok, roofed = pcall(function() return exports.wasteland_basebuilding:IsRoofed(p.coords) end)
    return not (ok and roofed == true)
end

-------------------------------------------------------------------------------
-- The plot screen
-------------------------------------------------------------------------------

local function view(src, p)
    local slots = {}
    for i = 1, p.size * p.size do
        local s = p.slots[i]
        local c = s and M.config.crops[s.crop]
        if c then
            slots[i] = { crop = s.crop, label = c.label, stage = Rules.stage(s.growth, c.minutes),
                minutesLeft = Rules.minutesLeft(s.growth, c.minutes), progress = math.floor((s.growth or 0) / c.minutes * 100 + 0.5),
                image = imageUrl(c.produce) }
        else
            slots[i] = false
        end
    end
    local seeds = {}
    for key, c in pairs(M.config.crops) do
        local n = inv():GetItemCount(src, c.seed) or 0
        if n > 0 then
            seeds[#seeds + 1] = { crop = key, label = c.label, count = n, minutes = c.minutes,
                image = imageUrl(c.seed) }
        end
    end
    table.sort(seeds, function(a, b) return a.label < b.label end)
    local cid = characterOf(src)
    local kind = M.config.plots[p.kind]
    local out = outdoors(p)
    return {
        id = p.id, label = kind and kind.label or 'Farm plot', size = p.size, slots = slots, seeds = seeds,
        water = math.floor(p.water + 0.5), maxWater = M.config.maxWaterMinutes, waterPerBottle = kind and kind.waterPerBottle or 30,
        bottles = inv():GetItemCount(src, M.config.waterItem) or 0, waterLabel = label(M.config.waterItem),
        outdoors = out, raining = out and raining(),
        canPickUp = cid ~= nil and (p.owner == cid or sameGroup(cid, p.owner) or isAdmin(src)),
    }
end

local function sendView(src, p) TriggerClientEvent('wasteland:farming:client:view', src, view(src, p)) end

local function plotFor(src, id)
    local p = plots[id]
    if not p or not characterOf(src) then return nil end
    if not near(src, p.coords, 4.0) then notice(src, 'Get closer to the farm plot.'); return nil end
    return p
end

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------

local function usePlotItem(kindKey)
    return function(src)
        if not characterOf(src) then return false end
        TriggerClientEvent('wasteland:farming:client:place', src, kindKey)
        return 0 -- taken when it is placed
    end
end

local function placePlot(src, kindKey, x, y, z, heading)
    local cid = characterOf(src)
    local kind = M.config.plots[kindKey]
    if not cid or not kind then return end
    local coords = { x = x, y = y, z = z }
    if not near(src, coords, 8.0) then notice(src, 'Too far away to place that.'); return end
    local mine = 0
    for _, p in pairs(plots) do
        if p.owner == cid then mine = mine + 1 end
        local gap = (p.size + kind.size) / 2 - 0.05
        if math.abs(p.coords.x - x) < gap and math.abs(p.coords.y - y) < gap and math.abs(p.coords.z - z) < 1.0 then
            notice(src, 'There is already a farm plot there.'); return
        end
    end
    if mine >= M.config.maxPlotsPerPlayer then notice(src, ('You have %d farm plots already (the most allowed).'):format(mine)); return end
    if (inv():GetItemCount(src, kind.item) or 0) < 1 then notice(src, 'You need a ' .. label(kind.item) .. '.'); return end
    if not inv():RemoveItem(src, kind.item, 1) then return end
    heading = (tonumber(heading) or 0.0) % 360.0
    local p = { owner = cid, kind = kindKey, size = kind.size, coords = coords, heading = heading, water = 0, slots = {} }
    Citizen.CreateThread(function()
        local id, err = WDB.insert(SQL.insert, { cid, kindKey, x, y, z, heading, slotsJson(p), os.time() })
        if not id then give(src, kind.item, 1); notice(src, 'The farm plot could not be saved. Try again.'); M.log:warn('plot: %s', tostring(err)); return end
        p.id = id
        plots[id] = p
        broadcast(p)
        notice(src, kind.label .. ' placed. Plant seeds and keep it watered.')
    end)
end

local function plant(src, id, slot, crop)
    local p = plotFor(src, id)
    local c = M.config.crops[crop]
    if not p or not c or slot < 1 or slot > p.size * p.size then return end
    if p.slots[slot] then notice(src, 'Something already grows there.'); sendView(src, p); return end
    if not inv():RemoveItem(src, c.seed, 1) then notice(src, 'You have no ' .. label(c.seed) .. '.'); return end
    p.slots[slot] = { crop = crop, growth = 0 }
    save(p); broadcast(p); sendView(src, p)
end

local function water(src, id)
    local p = plotFor(src, id)
    if not p then return end
    local kind = M.config.plots[p.kind]
    if p.water >= M.config.maxWaterMinutes - 1 then notice(src, 'The soil is soaked already.'); return end
    if not inv():RemoveItem(src, M.config.waterItem, 1) then notice(src, 'You need a ' .. label(M.config.waterItem) .. '.'); return end
    p.water = math.min(M.config.maxWaterMinutes, p.water + (kind and kind.waterPerBottle or 30))
    save(p); sendView(src, p)
end

local function harvest(src, id, slot)
    local p = plotFor(src, id)
    if not p then return end
    local s = p.slots[slot]
    local c = s and M.config.crops[s.crop]
    if not c then return end
    if (s.growth or 0) < c.minutes then notice(src, c.label .. ' is not ripe yet.'); return end
    local n = math.random(c.yield[1], c.yield[2])
    p.slots[slot] = false
    give(src, c.produce, n)
    local msg = ('You harvest %d %s.'):format(n, label(c.produce))
    if math.random() < M.config.seedBackChance then
        local back = math.random(1, 2)
        give(src, c.seed, back)
        msg = msg .. (' And %d %s.'):format(back, label(c.seed))
    end
    notice(src, msg)
    save(p); broadcast(p); sendView(src, p)
end

local function pull(src, id, slot)
    local p = plotFor(src, id)
    if not p or not p.slots[slot] then return end
    p.slots[slot] = false
    save(p); broadcast(p); sendView(src, p)
end

local function pickUp(src, id)
    local p = plotFor(src, id)
    if not p then return end
    local cid = characterOf(src)
    if not (p.owner == cid or sameGroup(cid, p.owner) or isAdmin(src)) then notice(src, 'This is not your farm plot.'); return end
    for i = 1, p.size * p.size do
        if p.slots[i] then notice(src, 'Harvest or pull up the plants first.'); return end
    end
    local kind = M.config.plots[p.kind]
    plots[id] = nil
    Citizen.CreateThread(function() WDB.update(SQL.delete, { id }) end)
    TriggerClientEvent('wasteland:farming:client:remove', -1, id)
    TriggerClientEvent('wasteland:farming:client:closeView', src)
    if kind then give(src, kind.item, 1) end
    notice(src, 'Farm plot picked up.')
end

-------------------------------------------------------------------------------
-- Growing
-------------------------------------------------------------------------------

local function tick()
    local wet = raining()
    local dt = M.config.tickSeconds / 60
    for _, p in pairs(plots) do
        local rained = wet and outdoors(p)
        local before = p.water
        local changed = Rules.tick(p, M.config.crops, dt, rained, M.config.maxWaterMinutes)
        local growing = false
        for _, s in pairs(p.slots) do if s then growing = true end end
        if growing or p.water ~= before then save(p) end
        if changed then broadcast(p) end
    end
end

local function loop(token)
    while runToken == token do
        Citizen.Wait(M.config.tickSeconds * 1000)
        if runToken ~= token then return end
        local ok, err = pcall(tick)
        if not ok then M.log:warn('farming: %s', tostring(err)) end
    end
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local CROP = { type = 'table', fields = {
    label = { type = 'string', required = true, maxLength = 48 },
    seed = { type = 'string', required = true, pattern = '^[%w_]+$' },
    produce = { type = 'string', required = true, pattern = '^[%w_]+$' },
    minutes = { type = 'number', required = true, min = 0.1, max = 100000 },
    yield = { type = 'array', required = true, minItems = 2, maxItems = 2, items = { type = 'integer', min = 0, max = 1000 } },
    color = { type = 'enum', values = { 'red', 'orange', 'yellow', 'green', 'purple', 'blue', 'brown', 'white' }, default = 'green' },
} }

M = Wasteland.DefineModule({
    name = 'farming',
    version = '1.0.0',
    description = 'Farm plots: plant, water (or rain), harvest food',
    core = '^1.1.0',
    dependencies = { database = '^0.1.0', players = '^0.1.0', inventory = '^0.1.0' },
    async = true,
    config = {
        file = 'farming.lua',
        optional = true,
        schema = { type = 'table', fields = {
            tickSeconds = { type = 'number', default = 60, min = 5, max = 3600 },
            streamDistance = { type = 'number', default = 150, min = 20, max = 1000 },
            maxPlotsPerPlayer = { type = 'integer', default = 12, min = 1, max = 1000 },
            waterItem = { type = 'string', default = 'water_bottle', pattern = '^[%w_]+$' },
            maxWaterMinutes = { type = 'number', default = 180, min = 1, max = 100000 },
            seedBackChance = { type = 'number', default = 0.6, min = 0, max = 1 },
            rainWeathers = { type = 'array', default = { 'RAIN', 'THUNDER' }, items = { type = 'string' } },
            plots = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%w_]+$' }, values = { type = 'table', fields = {
                label = { type = 'string', required = true, maxLength = 48 },
                item = { type = 'string', required = true, pattern = '^[%w_]+$' },
                model = { type = 'string', required = true, pattern = '^[%w_]+$' },
                size = { type = 'integer', required = true, min = 1, max = 6 },
                waterPerBottle = { type = 'number', default = 30, min = 1, max = 100000 },
            } } },
            stages = { type = 'map', default = {}, keys = { type = 'string' }, values = { type = 'string' } },
            crops = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%w_]+$' }, values = CROP },
        } },
    },

    onInit = function(mod)
        M = mod
        local known = function(item) return inv():GetItemDefinition(item) ~= nil end
        for key, k in pairs(M.config.plots) do
            if not known(k.item) then return false, ('farming.lua plot %s: item "%s" is not in inventory.lua items'):format(key, k.item) end
        end
        for key, c in pairs(M.config.crops) do
            if not known(c.seed) then return false, ('farming.lua crop %s: seed "%s" is not in inventory.lua items'):format(key, c.seed) end
            if not known(c.produce) then return false, ('farming.lua crop %s: produce "%s" is not in inventory.lua items'):format(key, c.produce) end
            if c.yield[1] > c.yield[2] then return false, ('farming.lua crop %s: yield min is above max'):format(key) end
        end
        if not known(M.config.waterItem) then return false, 'farming.lua: waterItem is not in inventory.lua items' end
        plots = {}
        local token = {}
        runToken = token
        Citizen.CreateThread(function()
            local ok, err = WDB.migrate('farming', WLF.MIGRATIONS)
            if runToken ~= token then return end
            if not ok then return M.fail('database migrations failed: ' .. tostring(err)) end
            local rows, e = WDB.query(SQL.select, {})
            if runToken ~= token then return end
            if not rows then return M.fail('could not load farm plots: ' .. tostring(e)) end
            for _, r in ipairs(rows) do
                local kind = M.config.plots[r.size]
                if kind then
                    local okJ, slots = pcall(json.decode, r.slots or '[]')
                    local p = { id = r.id, owner = r.owner_id, kind = r.size, size = kind.size, heading = r.heading + 0.0,
                        coords = { x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0 }, water = tonumber(r.water) or 0, slots = {} }
                    for i = 1, kind.size * kind.size do
                        local s = okJ and type(slots) == 'table' and slots[i] or false
                        p.slots[i] = (type(s) == 'table' and M.config.crops[s.crop]) and { crop = s.crop, growth = tonumber(s.growth) or 0 } or false
                    end
                    plots[p.id] = p
                end
            end
            for key, k in pairs(M.config.plots) do
                local okU, errU = inv():RegisterUsable(k.item, usePlotItem(key))
                if not okU then M.log:warn('could not register %s: %s', k.item, tostring(errU)) end
            end
            local n = 0
            for _ in pairs(plots) do n = n + 1 end
            M.log:info('%d farm plots loaded', n)
            TriggerClientEvent('wasteland:farming:client:sync', -1, M.clientConfig(), (function()
                local list = {}
                for _, p in pairs(plots) do list[#list + 1] = info(p) end
                return list
            end)())
            Citizen.CreateThread(function() loop(token) end)
            M.ready()
        end)
        return true
    end,

    onShutdown = function()
        runToken = nil
        TriggerClientEvent('wasteland:farming:client:sync', -1, nil, {})
    end,
})

function M.clientConfig()
    local kinds = {}
    for key, k in pairs(M.config.plots) do kinds[key] = { label = k.label, model = k.model, size = k.size } end
    return { plots = kinds, stages = M.config.stages, streamDistance = M.config.streamDistance }
end

local function syncTo(src)
    if not (M and M.active) then return end
    local list = {}
    for _, p in pairs(plots) do list[#list + 1] = info(p) end
    TriggerClientEvent('wasteland:farming:client:sync', src, M.clientConfig(), list)
end

local ID = { type = 'integer', required = true, min = 1 }
local SLOT = { type = 'integer', required = true, min = 1, max = 64 }
local COORD = { type = 'number', required = true, min = -20000, max = 20000 }
local RATE = { burst = 8, perSecond = 3 }

M.netEvent('wasteland:farming:server:sync', { rateLimit = { burst = 2, perSecond = 0.2 } }, function(src) syncTo(src) end)
M.netEvent('wasteland:farming:server:place', {
    args = { { type = 'string', required = true, pattern = '^[%w_]+$', maxLength = 24 }, COORD, COORD, COORD, { type = 'number', required = true, min = -720, max = 720 } },
    rateLimit = { burst = 3, perSecond = 1 },
}, function(src, kind, x, y, z, h) placePlot(src, kind, x, y, z, h) end)
M.netEvent('wasteland:farming:server:open', { args = { ID }, rateLimit = RATE }, function(src, id)
    local p = plotFor(src, id)
    if p then sendView(src, p) end
end)
M.netEvent('wasteland:farming:server:plant', { args = { ID, SLOT, { type = 'string', required = true, pattern = '^[%w_]+$', maxLength = 32 } }, rateLimit = RATE },
    function(src, id, slot, crop) plant(src, id, slot, crop) end)
M.netEvent('wasteland:farming:server:water', { args = { ID }, rateLimit = RATE }, function(src, id) water(src, id) end)
M.netEvent('wasteland:farming:server:harvest', { args = { ID, SLOT }, rateLimit = RATE }, function(src, id, slot) harvest(src, id, slot) end)
M.netEvent('wasteland:farming:server:pull', { args = { ID, SLOT }, rateLimit = RATE }, function(src, id, slot) pull(src, id, slot) end)
M.netEvent('wasteland:farming:server:pickup', { args = { ID }, rateLimit = RATE }, function(src, id) pickUp(src, id) end)

AddEventHandler('wasteland:players:characterLoaded', function(src) syncTo(src) end)

--- GetPlots() -> list of plots (for other modules and admin tools)
exports('GetPlots', function()
    local list = {}
    for _, p in pairs(plots) do list[#list + 1] = info(p) end
    return list
end)
