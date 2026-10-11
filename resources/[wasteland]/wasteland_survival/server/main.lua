-- wasteland_survival :: server/main.lua
-- Module "survival": the server owns every character's hunger, thirst,
-- bleeding, infection and body temperature (character data "survival"),
-- runs the rules (shared/model.lua) on a tick, applies food and medicine,
-- and handles death (body bag via the inventory) and respawn.
--
-- Health itself lives on the client's ped (GTA); the server tells the
-- client to apply damage or healing. Damage the world deals is reported by
-- the client and only used to start bleeding (a client that lies about it
-- only hurts itself).

local Model = WLS.Model
local DATA_KEY = 'survival'

local M
local states = {}       -- [characterId] = state
local online = {}       -- [characterId] = source
local env = {}          -- [source] = { ambient, wet }
local deathAt = {}      -- [characterId] = game time of death
local damageCarry = {}  -- [characterId] = fractional damage not yet applied
local runToken = nil

local function players() return exports.wasteland_players end

local function characterOf(src)
    local ok, id = pcall(function() return players():GetCharacterId(src) end)
    return ok and id or nil
end

local function save(cid, now)
    if not states[cid] then return end
    players():SetCharacterData(cid, DATA_KEY, states[cid])
    if now then players():SaveCharacter(cid) end
end

local function sendStats(src, cid)
    local s = states[cid]
    if not s then return end
    local e = env[src] or {}
    TriggerClientEvent('wasteland:survival:client:stats', src, {
        hunger = s.hunger, thirst = s.thirst, infection = s.infection, bleeding = s.bleeding,
        temperature = s.temperature, treatment = s.treatment > 0, dead = s.dead,
        ambient = e.ambient,
    })
end

local function warmthOf(src)
    if GetResourceState('wasteland_inventory') ~= 'started' then return 0 end
    local ok, worn = pcall(function() return exports.wasteland_inventory:GetWornItems(src) end)
    if not ok or type(worn) ~= 'table' then return 0 end
    local total = 0
    for _, w in ipairs(worn) do total = total + (tonumber(w.warmth) or 0) end
    return total
end

-------------------------------------------------------------------------------
-- Loading
-------------------------------------------------------------------------------

local function load(src, cid)
    local stored = players():GetCharacterData(cid, DATA_KEY)
    local s = Model.fresh(M.config)
    if type(stored) == 'table' then
        for k in pairs(s) do if stored[k] ~= nil then s[k] = stored[k] end end
    end
    states[cid], online[cid], damageCarry[cid] = s, src, 0
    if s.dead then
        -- Died and left before respawning: the items are already in a body
        -- bag; let them respawn straight away.
        deathAt[cid] = GetGameTimer() - M.config.respawn.delaySeconds * 1000
        TriggerClientEvent('wasteland:survival:client:dead', src, { respawnSeconds = 0 })
    end
    sendStats(src, cid)
end

AddEventHandler('wasteland:players:characterLoaded', function(src, character)
    if not (M and M.active) or type(character) ~= 'table' then return end
    load(src, character.id)
end)

AddEventHandler('wasteland:players:characterUnloading', function(_, character)
    if type(character) ~= 'table' then return end
    local cid = character.id
    if states[cid] then players():SetCharacterData(cid, DATA_KEY, states[cid]) end
    states[cid], online[cid], deathAt[cid], damageCarry[cid] = nil, nil, nil, nil
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then env[src] = nil end
end)

-------------------------------------------------------------------------------
-- Tick
-------------------------------------------------------------------------------

local function tick(dt)
    local cfg = M.config
    for cid, src in pairs(online) do
        local s = states[cid]
        if s and not s.dead then
            local e = env[src] or {}
            local damage = Model.tick(s, dt, cfg, { ambient = e.ambient, wet = e.wet, warmth = warmthOf(src) })
            if cfg.bleeding.enabled and s.bleeding > 0 and math.random() < Model.clotChance(cfg, s, dt) then
                s.bleeding = s.bleeding - 1
            end
            damageCarry[cid] = (damageCarry[cid] or 0) + damage
            local whole = math.floor(damageCarry[cid])
            if whole >= 1 then
                damageCarry[cid] = damageCarry[cid] - whole
                TriggerClientEvent('wasteland:survival:client:damage', src, whole)
            end
            players():SetCharacterData(cid, DATA_KEY, s)
            sendStats(src, cid)
        end
    end
end

local function loop(token)
    local ms = M.config.tickSeconds * 1000
    while runToken == token do
        Citizen.Wait(ms)
        if runToken ~= token then return end
        tick(M.config.tickSeconds)
    end
end

-------------------------------------------------------------------------------
-- Consumables (usable items registered with the inventory)
-------------------------------------------------------------------------------

local function useConsumable(src, stack)
    local cid = characterOf(src)
    local s = cid and states[cid]
    if not s then return false, 'You cannot do that right now.' end
    if s.dead then return false, 'You are dead.' end
    local effect = M.config.consumables[stack.name]
    if not effect then return false, 'Nothing happens.' end
    if not Model.useful(s, effect) then return false, 'You do not need that right now.' end
    local heal = Model.consume(s, effect)
    if heal > 0 then TriggerClientEvent('wasteland:survival:client:heal', src, heal) end
    TriggerClientEvent('wasteland:survival:client:consumed', src, effect.animation or 'eat')
    players():SetCharacterData(cid, DATA_KEY, s)
    sendStats(src, cid)
    return 1, effect.message
end

local function registerConsumables()
    if GetResourceState('wasteland_inventory') ~= 'started' then return end
    for name in pairs(M.config.consumables) do
        local ok, err = exports.wasteland_inventory:RegisterUsable(name, useConsumable)
        if not ok then M.log:warn('consumable "%s": %s', name, tostring(err)) end
    end
end

-- The inventory restarted: register again.
AddEventHandler('wasteland:core:moduleState', function(name, state)
    if name == 'inventory' and state == 'running' and M and M.active then registerConsumables() end
end)

-------------------------------------------------------------------------------
-- Death and respawn
-------------------------------------------------------------------------------

local function die(src, cid, cause)
    local s = states[cid]
    if not s or s.dead then return end
    s.dead = true
    s.bleeding = 0
    deathAt[cid] = GetGameTimer()
    local character = players():GetCharacter(src)
    local label = character and string.format('Body of %s %s', character.firstName, character.lastName) or 'Body'
    if GetResourceState('wasteland_inventory') == 'started' then
        local result, err = exports.wasteland_inventory:DeathDrop(src, label)
        if not result then M.log:error('player %d died but the body bag failed: %s', src, tostring(err)) end
    end
    save(cid, true)
    M.log:info('player %d (character %d) died (%s)', src, cid, tostring(cause or 'unknown'))
    TriggerClientEvent('wasteland:survival:client:dead', src, { respawnSeconds = M.config.respawn.delaySeconds })
    TriggerEvent('wasteland:survival:died', src, cid, cause)
end

local function respawn(src, cid)
    local s = states[cid]
    if not s or not s.dead then return false, 'You are not dead.' end
    local waited = GetGameTimer() - (deathAt[cid] or 0)
    if waited < M.config.respawn.delaySeconds * 1000 then
        return false, string.format('Wait %d more seconds.', math.ceil((M.config.respawn.delaySeconds * 1000 - waited) / 1000))
    end
    local points = M.config.respawn.points
    local p = points[math.random(1, #points)]
    local fresh = Model.fresh(M.config)
    fresh.hunger, fresh.thirst = M.config.respawn.stats.hunger, M.config.respawn.stats.thirst
    states[cid], damageCarry[cid], deathAt[cid] = fresh, 0, nil
    save(cid, true)
    M.log:info('player %d (character %d) respawned', src, cid)
    TriggerClientEvent('wasteland:survival:client:respawn', src, { x = p.x, y = p.y, z = p.z, heading = p.heading })
    TriggerEvent('wasteland:survival:respawned', src, cid)
    sendStats(src, cid)
    return true
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local num = function(def, lo, hi) return { type = 'number', default = def, min = lo, max = hi } end
local list3 = function(def) return { type = 'array', default = def, minItems = 3, maxItems = 3, items = { type = 'number', min = 0, max = 1000 } } end
local EFFECT = { type = 'table', fields = {
    hunger = { type = 'number', min = -100, max = 100 }, thirst = { type = 'number', min = -100, max = 100 },
    health = { type = 'number', min = 0, max = 200 }, stopBleeding = { type = 'integer', min = 1, max = 3 },
    infection = { type = 'number', min = -100, max = 100 }, treatmentMinutes = { type = 'number', min = 0, max = 600 },
    temperature = { type = 'number', min = -5, max = 5 },
    animation = { type = 'enum', values = { 'eat', 'drink', 'treat' }, default = 'eat' },
    message = { type = 'string', maxLength = 120 },
} }

M = Wasteland.DefineModule({
    name = 'survival',
    version = '0.1.0',
    description = 'Hunger, thirst, bleeding, infection, temperature, death and respawn',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', ui = '^0.1.0' },
    optionalDependencies = { inventory = '^0.1.0' },
    config = {
        file = 'survival.lua',
        optional = true,
        schema = { type = 'table', fields = {
            tickSeconds = { type = 'integer', default = 10, min = 1, max = 120 },
            start = { type = 'table', fields = { hunger = num(100, 0, 100), thirst = num(100, 0, 100) } },
            hunger = { type = 'table', fields = { drainPerHour = num(50, 0, 1000), starvingDamagePerMinute = num(2, 0, 200) } },
            thirst = { type = 'table', fields = { drainPerHour = num(66.7, 0, 1000), dehydratedDamagePerMinute = num(3, 0, 200),
                hotMultiplier = num(1.5, 1, 10) } },
            bleeding = { type = 'table', fields = {
                enabled = { type = 'boolean', default = true }, minDamage = num(10, 0, 200),
                chancePer10Damage = num(0.25, 0, 1), heavyDamage = num(40, 1, 400),
                damagePerMinute = list3({ 2, 6, 12 }),
                clotChancePerMinute = { type = 'array', default = { 0.2, 0.02, 0 }, minItems = 3, maxItems = 3, items = { type = 'number', min = 0, max = 1 } },
            } },
            infection = { type = 'table', fields = {
                enabled = { type = 'boolean', default = true }, growthPerMinute = num(0.8, 0, 100),
                recoveryPerMinute = num(3, 0, 100), damageThreshold = num(60, 1, 100),
                damagePerMinute = num(2, 0, 200), lethalDamagePerMinute = num(20, 0, 1000),
            } },
            temperature = { type = 'table', fields = {
                enabled = { type = 'boolean', default = true }, normal = num(37, 30, 42),
                comfortLow = num(12, -50, 50), comfortHigh = num(30, -50, 60), wetPenalty = num(10, 0, 50),
                coldFactor = num(0.2, 0, 5), heatFactor = num(0.15, 0, 5), changePerMinute = num(0.3, 0.01, 10),
                hypothermia = num(35, 25, 40), hyperthermia = num(39.5, 35, 45),
                coldDamagePerMinute = num(2, 0, 200), heatDamagePerMinute = num(1, 0, 200),
                min = num(30, 20, 40), max = num(42, 35, 50),
            } },
            respawn = { type = 'table', fields = {
                delaySeconds = { type = 'integer', default = 15, min = 0, max = 600 },
                stats = { type = 'table', fields = { hunger = num(70, 0, 100), thirst = num(70, 0, 100) } },
                points = { type = 'array', minItems = 1, default = { { x = 1734.0, y = 3297.0, z = 41.2, heading = 195.0 } },
                    items = { type = 'table', fields = {
                        x = { type = 'number', required = true }, y = { type = 'number', required = true },
                        z = { type = 'number', required = true }, heading = num(0, 0, 360),
                    } } },
            } },
            consumables = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[a-z][a-z0-9_]*$' }, values = EFFECT },
        } },
    },

    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        if M.config.temperature.comfortLow >= M.config.temperature.comfortHigh then
            return false, 'survival.lua: temperature.comfortLow must be below comfortHigh'
        end
        states, online, deathAt, damageCarry = {}, {}, {}, {}
        registerConsumables()
        for _, c in ipairs(players():GetOnlineCharacters()) do
            if c.source then load(c.source, c.id) end
        end
        local token = {}
        runToken = token
        Citizen.CreateThread(function() loop(token) end)
        return true
    end,

    onShutdown = function()
        runToken = nil
        for cid, s in pairs(states) do players():SetCharacterData(cid, DATA_KEY, s) end
        states, online = {}, {}
    end,
})

-------------------------------------------------------------------------------
-- Net events
-------------------------------------------------------------------------------

M.netEvent('wasteland:survival:server:died', { rateLimit = { burst = 2, perSecond = 0.2 } }, function(src)
    local cid = characterOf(src)
    if cid then die(src, cid, 'reported by client') end
end)

M.netEvent('wasteland:survival:server:respawn', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    local cid = characterOf(src)
    if not cid then return end
    local ok, err = respawn(src, cid)
    if not ok then TriggerClientEvent('wasteland:survival:client:notice', src, err) end
end)

M.netEvent('wasteland:survival:server:damaged', {
    args = { { type = 'integer', required = true, min = 1, max = 400 } },
    rateLimit = { burst = 10, perSecond = 4 },
}, function(src, amount)
    local cid = characterOf(src)
    local s = cid and states[cid]
    if s and Model.onDamage(s, M.config, amount, math.random()) then sendStats(src, cid) end
end)

M.netEvent('wasteland:survival:server:environment', {
    args = { { type = 'number', required = true, min = -40, max = 60 }, { type = 'boolean', default = false } },
    rateLimit = { burst = 3, perSecond = 0.5 },
}, function(src, ambient, wet)
    env[src] = { ambient = ambient, wet = wet }
end)

M.netEvent('wasteland:survival:server:request', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    local cid = characterOf(src)
    if cid then
        sendStats(src, cid)
        if states[cid] and states[cid].dead then
            local left = math.max(0, M.config.respawn.delaySeconds * 1000 - (GetGameTimer() - (deathAt[cid] or 0)))
            TriggerClientEvent('wasteland:survival:client:dead', src, { respawnSeconds = math.ceil(left / 1000) })
        end
    end
end)

-------------------------------------------------------------------------------
-- Exports (survival api 0.1)
-------------------------------------------------------------------------------

local function stateOf(src)
    local cid = characterOf(tonumber(src))
    return cid and states[cid], cid
end

--- GetStats(source) -> { hunger, thirst, infection, bleeding, temperature, dead } | nil
exports('GetStats', function(src)
    local s = stateOf(src)
    if not s then return nil end
    return { hunger = s.hunger, thirst = s.thirst, infection = s.infection, bleeding = s.bleeding,
        temperature = s.temperature, dead = s.dead }
end)

--- AddInfection(source, amount) -> ok   (zombie hits, Milestone 5)
exports('AddInfection', function(src, amount)
    local s, cid = stateOf(src)
    if not s or s.dead or not M.config.infection.enabled then return false end
    s.infection = Model.clamp(s.infection + (tonumber(amount) or 0), 0, 100)
    sendStats(tonumber(src), cid)
    return true
end)

--- AddBleeding(source, levels) -> ok
exports('AddBleeding', function(src, levels)
    local s, cid = stateOf(src)
    if not s or s.dead or not M.config.bleeding.enabled then return false end
    s.bleeding = Model.clamp(s.bleeding + (math.tointeger(tonumber(levels)) or 1), 0, 3)
    sendStats(tonumber(src), cid)
    return true
end)

--- ModifyStats(source, { hunger, thirst, infection, temperature }) -> ok  (deltas)
exports('ModifyStats', function(src, deltas)
    local s, cid = stateOf(src)
    if not s or s.dead or type(deltas) ~= 'table' then return false end
    Model.consume(s, { hunger = deltas.hunger, thirst = deltas.thirst, infection = deltas.infection, temperature = deltas.temperature })
    sendStats(tonumber(src), cid)
    return true
end)

--- IsDead(source) -> boolean
exports('IsDead', function(src)
    local s = stateOf(src)
    return s ~= nil and s.dead == true
end)
