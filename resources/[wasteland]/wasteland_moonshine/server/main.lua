-- wasteland_moonshine :: server/main.lua
-- Module "moonshine": a still (crafted, placed anywhere) turns crops, sugar,
-- water and firewood into moonshine jars. Drinking one heals a little, eases
-- the infection, makes you drunk and fills the Zombie Blind meter; with the
-- meter full, zombies ignore you (state bag wlMasked) until it drains below
-- the line. Every change is checked here; clients show and ask.

local Rules = WLM.Rules
local M
local stills = {}    -- id -> { id, owner, coords, heading, brew = { flavour, left (seconds), runs } | nil, ready = { item, count } | nil }
local states = {}    -- source -> { drunk, blind, masked }
local runToken = nil
local ticks = 0

local SQL, MIGRATIONS = WLM.SQL, WLM.MIGRATIONS

local function inv() return exports.wasteland_inventory end
local function notice(src, msg) TriggerClientEvent('wasteland:moonshine:client:notice', src, msg) end

local function characterOf(src)
    local ok, cid = pcall(function() return exports.wasteland_players:GetCharacterId(src) end)
    return ok and cid or nil
end

local function playerCoords(src)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return c and { x = c.x, y = c.y, z = c.z } or nil
end
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + ((a.z or 0) - (b.z or 0)) ^ 2) end
local function near(src, coords, reach) local p = playerCoords(src); return p ~= nil and dist(p, coords) <= reach end

local function label(item) local d = inv():GetItemDefinition(item); return d and d.label or item end
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

local function brewJson(s) return json.encode({ brew = s.brew or false, ready = s.ready or false }) end
local function save(s) Citizen.CreateThread(function() WDB.update(SQL.update, { brewJson(s), s.id }) end) end
local function info(s) return { id = s.id, coords = s.coords, heading = s.heading, brewing = s.brew ~= nil } end
local function broadcast(s) TriggerClientEvent('wasteland:moonshine:client:still', -1, info(s)) end

-------------------------------------------------------------------------------
-- Brewing
-------------------------------------------------------------------------------

local function needs(f)
    local list = { { name = f.crop, count = f.count } }
    for _, b in ipairs(M.config.base) do list[#list + 1] = b end
    return list
end

local function batchSeconds(runs) return math.floor(M.config.brewSeconds * (1 + (runs - 1) * M.config.batchSecondsFactor) + 0.5) end

local function view(src, s)
    local fl = {}
    for key, f in pairs(M.config.flavours) do
        local parts, most = {}, M.config.maxBatch
        for _, n in ipairs(needs(f)) do
            local have = inv():GetItemCount(src, n.name) or 0
            most = math.min(most, math.floor(have / n.count))
            parts[#parts + 1] = { label = label(n.name), count = n.count, have = have }
        end
        fl[#fl + 1] = { key = key, label = f.label, image = imageUrl(f.item), needs = parts, canBrew = most >= 1, most = most }
    end
    table.sort(fl, function(a, b) return a.label < b.label end)
    local times = {}
    for r = 1, M.config.maxBatch do times[r] = batchSeconds(r) end
    local v = { id = s.id, flavours = fl, jars = M.config.jarsPerRun, seconds = M.config.brewSeconds, times = times }
    if s.brew then
        local f = M.config.flavours[s.brew.flavour]
        v.brewing = { runs = s.brew.runs or 1, label = f and f.label or s.brew.flavour, left = math.max(0, math.ceil(s.brew.left or 0)) }
    end
    if s.ready then v.ready = { label = label(s.ready.item), count = s.ready.count, image = imageUrl(s.ready.item) } end
    local cid = characterOf(src)
    v.canPickUp = cid ~= nil and (s.owner == cid or sameGroup(cid, s.owner) or isAdmin(src))
    return v
end
local function sendView(src, s) TriggerClientEvent('wasteland:moonshine:client:view', src, view(src, s)) end

local function stillFor(src, id)
    local s = stills[id]
    if not s or not characterOf(src) then return nil end
    if not near(src, s.coords, 4.0) then notice(src, 'Get closer to the still.'); return nil end
    return s
end

local function brew(src, id, key, runs)
    local s = stillFor(src, id)
    local f = M.config.flavours[key]
    if not s or not f then return end
    runs = math.max(1, math.min(M.config.maxBatch, math.floor(tonumber(runs) or 1)))
    if s.brew then notice(src, 'The still is already running.'); return end
    if s.ready then notice(src, 'Collect the jars first.'); return end
    for _, n in ipairs(needs(f)) do
        if (inv():GetItemCount(src, n.name) or 0) < n.count * runs then notice(src, ('You need %d %s.'):format(n.count * runs, label(n.name))); return end
    end
    local taken = {}
    for _, n in ipairs(needs(f)) do
        if not inv():RemoveItem(src, n.name, n.count * runs) then
            for _, t in ipairs(taken) do give(src, t.name, t.count) end
            return
        end
        taken[#taken + 1] = { name = n.name, count = n.count * runs }
    end
    local secs = batchSeconds(runs)
    s.brew = { flavour = key, left = secs, runs = runs }
    save(s); broadcast(s); sendView(src, s)
    notice(src, ('The still is running: %d jars of %s, ready in %d seconds.'):format(runs * M.config.jarsPerRun, f.label, secs))
end

local function collect(src, id)
    local s = stillFor(src, id)
    if not s then return end
    if not s.ready then notice(src, s.brew and 'It is not done yet.' or 'There is nothing to collect.'); return end
    give(src, s.ready.item, s.ready.count)
    notice(src, ('You collect %d %s.'):format(s.ready.count, label(s.ready.item)))
    s.ready = nil
    save(s); broadcast(s); sendView(src, s)
end

local function pickUp(src, id)
    local s = stillFor(src, id)
    if not s then return end
    local cid = characterOf(src)
    if not (s.owner == cid or sameGroup(cid, s.owner) or isAdmin(src)) then notice(src, 'This is not your still.'); return end
    if s.brew or s.ready then notice(src, 'Let it finish and collect the jars first.'); return end
    stills[id] = nil
    Citizen.CreateThread(function() WDB.update(SQL.delete, { id }) end)
    TriggerClientEvent('wasteland:moonshine:client:remove', -1, id)
    TriggerClientEvent('wasteland:moonshine:client:closeView', src)
    give(src, M.config.stillItem, 1)
    notice(src, 'Still picked up.')
end

local function useStillItem(src)
    if not characterOf(src) then return false end
    TriggerClientEvent('wasteland:moonshine:client:place', src)
    return 0
end

local function placeStill(src, x, y, z, heading)
    local cid = characterOf(src)
    if not cid then return end
    local coords = { x = x, y = y, z = z }
    if not near(src, coords, 8.0) then notice(src, 'Too far away to place that.'); return end
    local mine = 0
    for _, s in pairs(stills) do
        if s.owner == cid then mine = mine + 1 end
        if dist(s.coords, coords) < 2.5 then notice(src, 'There is already a still there.'); return end
    end
    if mine >= M.config.maxStillsPerPlayer then notice(src, ('You have %d stills already (the most allowed).'):format(mine)); return end
    if not inv():RemoveItem(src, M.config.stillItem, 1) then notice(src, 'You need a ' .. label(M.config.stillItem) .. '.'); return end
    heading = (tonumber(heading) or 0.0) % 360.0
    Citizen.CreateThread(function()
        local s = { owner = cid, coords = coords, heading = heading }
        local id, err = WDB.insert(SQL.insert, { cid, x, y, z, heading, brewJson(s), os.time() })
        if not id then give(src, M.config.stillItem, 1); notice(src, 'The still could not be saved. Try again.'); M.log:warn('still: %s', tostring(err)); return end
        s.id = id
        stills[id] = s
        broadcast(s)
        notice(src, 'Moonshine still placed. Left Alt on it to brew.')
    end)
end

-------------------------------------------------------------------------------
-- Drinking: drunk and the Zombie Blind meter
-------------------------------------------------------------------------------

local function publish(src, st)
    TriggerClientEvent('wasteland:moonshine:client:state', src, { drunk = st.drunk, blind = st.blind, masked = st.masked == true })
    local pst = Player(src) and Player(src).state
    if pst and (pst.wlMasked == true) ~= (st.masked == true) then pst:set('wlMasked', st.masked == true, true) end
end

local function drinkFlavour(item)
    return function(src)
        if not characterOf(src) then return false end
        local d = M.config.drink
        local st = states[src] or { drunk = 0, blind = 0, masked = false }
        states[src] = Rules.drink(st, d)
        if GetResourceState('wasteland_survival') == 'started' then
            pcall(function() exports.wasteland_survival:ModifyStats(src, { infection = -d.infection, thirst = d.thirst }) end)
        end
        if d.health > 0 then TriggerClientEvent('wasteland:survival:client:heal', src, d.health) end
        TriggerClientEvent('wasteland:moonshine:client:drank', src)
        publish(src, st)
        if st.masked then notice(src, 'The zombies cannot smell you now.') end
        return 1
    end
end

local function tick()
    local dt = 2 / 60
    for src, st in pairs(states) do
        if not GetPlayerName(tostring(src)) then
            states[src] = nil
        else
            Rules.decay(st, dt, M.config)
            publish(src, st)
            if Rules.idle(st) then states[src] = nil end
        end
    end
    ticks = ticks + 1
    for _, s in pairs(stills) do
        if s.brew then s.brew.left = (tonumber(s.brew.left) or 0) - 2 end
        if s.brew and ticks % 15 == 0 and s.brew.left > 0 then save(s) end -- keep the time left if the server stops
        if s.brew and s.brew.left <= 0 then
            local f = M.config.flavours[s.brew.flavour]
            s.ready = f and { item = f.item, count = M.config.jarsPerRun * math.max(1, tonumber(s.brew.runs) or 1) } or nil
            s.brew = nil
            save(s); broadcast(s)
        end
    end
end

local function loop(token)
    while runToken == token do
        Citizen.Wait(2000)
        if runToken ~= token then return end
        local ok, err = pcall(tick)
        if not ok then M.log:warn('moonshine: %s', tostring(err)) end
    end
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local ITEMS = { type = 'array', default = {}, items = { type = 'table', fields = {
    name = { type = 'string', required = true, pattern = '^[%w_]+$' }, count = { type = 'integer', default = 1, min = 1, max = 1000 } } } }

M = Wasteland.DefineModule({
    name = 'moonshine',
    version = '1.0.0',
    description = 'Moonshine stills, flavours, drunk, and the Zombie Blind meter',
    core = '^1.1.0',
    dependencies = { database = '^0.1.0', players = '^0.1.0', inventory = '^0.1.0' },
    async = true,
    config = {
        file = 'moonshine.lua',
        optional = true,
        schema = { type = 'table', fields = {
            stillItem = { type = 'string', default = 'moonshine_still', pattern = '^[%w_]+$' },
            stillModel = { type = 'string', default = 'wl_moonshine_still', pattern = '^[%w_]+$' },
            maxStillsPerPlayer = { type = 'integer', default = 3, min = 1, max = 100 },
            streamDistance = { type = 'number', default = 150, min = 20, max = 1000 },
            brewSeconds = { type = 'number', default = 120, min = 1, max = 86400 },
            jarsPerRun = { type = 'integer', default = 2, min = 1, max = 100 },
            maxBatch = { type = 'integer', default = 10, min = 1, max = 100 },
            batchSecondsFactor = { type = 'number', default = 0.5, min = 0, max = 10 },
            base = ITEMS,
            flavours = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%w_]+$' }, values = { type = 'table', fields = {
                label = { type = 'string', required = true, maxLength = 48 },
                item = { type = 'string', required = true, pattern = '^[%w_]+$' },
                crop = { type = 'string', required = true, pattern = '^[%w_]+$' },
                count = { type = 'integer', default = 4, min = 1, max = 1000 },
            } } },
            drink = { type = 'table', default = {}, fields = {
                health = { type = 'number', default = 3, min = 0, max = 200 },
                infection = { type = 'number', default = 3, min = 0, max = 100 },
                thirst = { type = 'number', default = 4, min = -100, max = 100 },
                drunk = { type = 'number', default = 18, min = 0, max = 100 },
                blind = { type = 'number', default = 34, min = 0, max = 100 },
            } },
            soberPerMinute = { type = 'number', default = 6, min = 0, max = 1000 },
            blindPerMinute = { type = 'number', default = 10, min = 0, max = 1000 },
            unmaskBelow = { type = 'number', default = 40, min = 0, max = 100 },
        } },
    },

    onInit = function(mod)
        M = mod
        local known = function(item) return inv():GetItemDefinition(item) ~= nil end
        if not known(M.config.stillItem) then return false, 'moonshine.lua: stillItem is not in inventory.lua items' end
        for _, b in ipairs(M.config.base) do
            if not known(b.name) then return false, ('moonshine.lua base: "%s" is not in inventory.lua items'):format(b.name) end
        end
        for key, f in pairs(M.config.flavours) do
            if not known(f.item) then return false, ('moonshine.lua flavour %s: item "%s" is not in inventory.lua items'):format(key, f.item) end
            if not known(f.crop) then return false, ('moonshine.lua flavour %s: crop "%s" is not in inventory.lua items'):format(key, f.crop) end
        end
        stills, states = {}, {}
        local token = {}
        runToken = token
        Citizen.CreateThread(function()
            local ok, err = WDB.migrate('moonshine', MIGRATIONS)
            if runToken ~= token then return end
            if not ok then return M.fail('database migrations failed: ' .. tostring(err)) end
            local rows, e = WDB.query(SQL.select, {})
            if runToken ~= token then return end
            if not rows then return M.fail('could not load stills: ' .. tostring(e)) end
            for _, r in ipairs(rows) do
                local okJ, b = pcall(json.decode, r.brew or '{}')
                b = okJ and type(b) == 'table' and b or {}
                stills[r.id] = { id = r.id, owner = r.owner_id, heading = r.heading + 0.0, coords = { x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0 },
                    brew = type(b.brew) == 'table' and b.brew or nil, ready = type(b.ready) == 'table' and b.ready or nil }
            end
            local okU, errU = inv():RegisterUsable(M.config.stillItem, useStillItem)
            if not okU then M.log:warn('could not register the still: %s', tostring(errU)) end
            for _, f in pairs(M.config.flavours) do
                local okD, errD = inv():RegisterUsable(f.item, drinkFlavour(f.item))
                if not okD then M.log:warn('could not register %s: %s', f.item, tostring(errD)) end
            end
            local list = {}
            for _, s in pairs(stills) do list[#list + 1] = info(s) end
            TriggerClientEvent('wasteland:moonshine:client:sync', -1, { model = M.config.stillModel, streamDistance = M.config.streamDistance,
                unmaskBelow = M.config.unmaskBelow }, list)
            Citizen.CreateThread(function() loop(token) end)
            M.ready()
        end)
        return true
    end,

    onShutdown = function()
        runToken = nil
        for src in pairs(states) do
            local pst = Player(src) and Player(src).state
            if pst and pst.wlMasked then pst:set('wlMasked', false, true) end
        end
        TriggerClientEvent('wasteland:moonshine:client:sync', -1, nil, {})
    end,
})

local function syncTo(src)
    if not (M and M.active) then return end
    local list = {}
    for _, s in pairs(stills) do list[#list + 1] = info(s) end
    TriggerClientEvent('wasteland:moonshine:client:sync', src, { model = M.config.stillModel, streamDistance = M.config.streamDistance,
        unmaskBelow = M.config.unmaskBelow }, list)
end

local ID = { type = 'integer', required = true, min = 1 }
local COORD = { type = 'number', required = true, min = -20000, max = 20000 }
local RATE = { burst = 8, perSecond = 3 }

M.netEvent('wasteland:moonshine:server:sync', { rateLimit = { burst = 2, perSecond = 0.2 } }, function(src) syncTo(src) end)
M.netEvent('wasteland:moonshine:server:place', { args = { COORD, COORD, COORD, { type = 'number', required = true, min = -720, max = 720 } },
    rateLimit = { burst = 3, perSecond = 1 } }, function(src, x, y, z, h) placeStill(src, x, y, z, h) end)
M.netEvent('wasteland:moonshine:server:open', { args = { ID }, rateLimit = RATE }, function(src, id)
    local s = stillFor(src, id)
    if s then sendView(src, s) end
end)
M.netEvent('wasteland:moonshine:server:brew', { args = { ID, { type = 'string', required = true, pattern = '^[%w_]+$', maxLength = 32 },
    { type = 'integer', min = 1, max = 100 } }, rateLimit = RATE },
    function(src, id, key, runs) brew(src, id, key, runs) end)
M.netEvent('wasteland:moonshine:server:collect', { args = { ID }, rateLimit = RATE }, function(src, id) collect(src, id) end)
M.netEvent('wasteland:moonshine:server:pickup', { args = { ID }, rateLimit = RATE }, function(src, id) pickUp(src, id) end)

AddEventHandler('wasteland:players:characterLoaded', function(src) syncTo(src) end)
AddEventHandler('playerDropped', function() states[tonumber(source)] = nil end)

--- IsMasked(source) -> boolean: zombies cannot smell this player (moonshine)
exports('IsMasked', function(src) local st = states[tonumber(src)]; return st ~= nil and st.masked == true end)
