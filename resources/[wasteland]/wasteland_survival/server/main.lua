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
local loadedAt = {}     -- [source] = game time the character was loaded (armour reports wait a moment)
local runToken = nil

local commandRegistered = false
local adminCommand -- defined below

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

-- Which items help with what (for the inventory's health panel), from the
-- consumables in survival.lua and the item labels.
local function curesList()
    local out = { bleeding = {}, infection = {}, hunger = {}, thirst = {}, health = {}, cold = {} }
    local function label(name)
        if GetResourceState('wasteland_inventory') ~= 'started' then return name end
        local ok, d = pcall(function() return exports.wasteland_inventory:GetItemDefinition(name) end)
        return ok and d and d.label or name
    end
    local names = {}
    for name in pairs(M.config.consumables) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local e = M.config.consumables[name]
        if (e.stopBleeding or 0) > 0 then out.bleeding[#out.bleeding + 1] = label(name) end
        if (e.infection or 0) < 0 then out.infection[#out.infection + 1] = label(name) end
        if (e.hunger or 0) > 0 then out.hunger[#out.hunger + 1] = label(name) end
        if (e.thirst or 0) > 0 then out.thirst[#out.thirst + 1] = label(name) end
        if (e.health or 0) > 0 then out.health[#out.health + 1] = label(name) end
        if (e.temperature or 0) > 0 then out.cold[#out.cold + 1] = label(name) end
    end
    return out
end

local function sendStats(src, cid)
    local s = states[cid]
    if not s then return end
    local e = env[src] or {}
    local ok, character = pcall(function() return players():GetCharacter(src) end)
    local name = ok and character and (character.firstName .. ' ' .. character.lastName) or nil
    TriggerClientEvent('wasteland:survival:client:stats', src, {
        name = name,
        hunger = s.hunger, thirst = s.thirst, infection = s.infection, bleeding = s.bleeding,
        temperature = s.temperature, treatment = s.treatment > 0, dead = s.dead,
        bladder = (M.config.toilet and M.config.toilet.enabled) and s.bladder or nil,
        bowel = (M.config.toilet and M.config.toilet.enabled) and s.bowel or nil,
        ambient = e.ambient,
        cures = curesList(),
        limits = { hypothermia = M.config.temperature.hypothermia, hyperthermia = M.config.temperature.hyperthermia,
            infectionDamage = M.config.infection.damageThreshold },
    })
end

-- Other modules add warmth (a campfire) and respawn points (a sleeping bag):
-- name -> function. See RegisterWarmthSource / RegisterRespawnPoint.
local warmthSources, respawnPoints = {}, {}

local function warmthOf(src)
    local total = 0
    for name, fn in pairs(warmthSources) do
        local ok, w = pcall(fn, src)
        if ok and type(w) == 'number' and w > 0 then total = total + math.min(w, 50) end
        if not ok then warmthSources[name] = nil end
    end
    if GetResourceState('wasteland_inventory') ~= 'started' then return total end
    local ok, worn = pcall(function() return exports.wasteland_inventory:GetWornItems(src) end)
    if not ok or type(worn) ~= 'table' then return total end
    for _, w in ipairs(worn) do
        total = total + Model.clothingWarmth(w.warmth, w.metadata and w.metadata.durability, w.durability)
    end
    return total
end

-------------------------------------------------------------------------------
-- Loading
-------------------------------------------------------------------------------

local function load(src, cid)
    loadedAt[src] = GetGameTimer()
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
    TriggerEvent('wasteland:survival:consumed', src, stack.name, (effect.hunger or 0) > 0 or (effect.thirst or 0) > 0)
    -- medicine: treating wounds (healing, bleeding, infection) is a skill
    local medical = (effect.health or 0) > 0 or (effect.stopBleeding or 0) > 0 or (effect.infection or 0) < 0
        or (effect.treatmentMinutes or 0) > 0
    if medical then
        if heal > 0 and GetResourceState('wasteland_skills') == 'started' then
            local ok, b = pcall(function() return exports.wasteland_skills:GetBonus(src, 'medicine', 'heal') end)
            if ok and tonumber(b) then heal = math.floor(heal * (1 + b) + 0.5) end
        end
        TriggerEvent('wasteland:survival:treated', src, stack.name)
    end
    local t = M.config.toilet
    if t and t.enabled then
        s.bladder = Model.clamp((s.bladder or 0) + math.max(0, effect.thirst or 0) * t.drinkToBladder, 0, 100)
        s.bowel = Model.clamp((s.bowel or 0) + math.max(0, effect.hunger or 0) * t.foodToBowel, 0, 100)
    end
    if heal > 0 then TriggerClientEvent('wasteland:survival:client:heal', src, heal) end
    TriggerClientEvent('wasteland:survival:client:consumed', src, effect.animation or 'eat', effect.prop)
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

-------------------------------------------------------------------------------
-- Clothing: zombie hits wear it out; repair items (sewing kit) mend it.
-- A ruined piece (0) stays on but gives no warmth until it is mended.
-------------------------------------------------------------------------------

local function clothingRunning() return GetResourceState('wasteland_inventory') == 'started' end
local function notice(src, msg) TriggerClientEvent('wasteland:survival:client:notice', src, msg) end

local function currentOf(stack, max) return stack.metadata and stack.metadata.durability or max end

AddEventHandler('wasteland:zombies:hit', function(victim)
    if not (M and M.active) or not clothingRunning() then return end
    local wear = M.config.clothing.hitWear
    if wear[2] <= 0 then return end
    local ok, worn = pcall(function() return exports.wasteland_inventory:GetWornItems(victim) end)
    if not ok or type(worn) ~= 'table' then return end
    local pieces = {}
    for _, w in ipairs(worn) do
        if w.category == 'clothing' and (w.durability or 0) > 0 and currentOf(w, w.durability) > 0 then pieces[#pieces + 1] = w end
    end
    if #pieces == 0 then return end
    local w = pieces[math.random(#pieces)]
    local before = currentOf(w, w.durability)
    local after = math.max(0, before - math.random(wear[1], math.max(wear[1], wear[2])))
    exports.wasteland_inventory:SetItemMetadata(victim, w.uid, { durability = after })
    if after <= 0 then notice(victim, string.format('Your %s is ruined. Mend it with a sewing kit.', w.label:lower())) end
end)

-------------------------------------------------------------------------------
-- Armor plates (worn in the inventory's armor slot): while a plate holds,
-- incoming damage is stopped. Hits from the server (zombies, Damage) and
-- what the game takes from the GTA armour the client keeps full
-- (wasteland:survival:server:armorHit) wear the plate down slowly.
-------------------------------------------------------------------------------

local plateCarry = {}   -- [uid] = wear below 1 not yet taken off the plate

local function wornPlate(src)
    if not clothingRunning() then return nil end
    local ok, worn = pcall(function() return exports.wasteland_inventory:GetWornItems(src) end)
    if not ok or type(worn) ~= 'table' then return nil end
    for _, w in ipairs(worn) do
        if w.category == 'armor' and (w.durability or 0) > 0 and currentOf(w, w.durability) > 0 then return w end
    end
    return nil
end

--- The plate takes `damage`; true if a plate was there to take it.
local function wearPlate(src, damage)
    local w = wornPlate(src)
    if not w then return false end
    local loss = damage * M.config.armor.wearPerDamage + (plateCarry[w.uid] or 0)
    local whole = math.floor(loss)
    plateCarry[w.uid] = loss - whole
    if whole > 0 then
        local after = math.max(0, currentOf(w, w.durability) - whole)
        exports.wasteland_inventory:SetItemMetadata(src, w.uid, { durability = after })
        if after <= 0 then
            plateCarry[w.uid] = nil
            notice(src, string.format('Your %s broke. Repair it with an armor repair kit.', w.label:lower()))
        end
    end
    return true
end

-- What to repair: the piece the player chose, else the most worn piece of
-- that category they wear, else the most worn one they carry.
local function repairTarget(src, category, targetUid)
    local inv = exports.wasteland_inventory
    if targetUid then
        local s = inv:FindItem(src, targetUid)
        local d = s and inv:GetItemDefinition(s.name)
        if not d or d.category ~= category or (d.durability or 0) <= 0 then return nil, 'That cannot be repaired with this.' end
        return { uid = s.uid, label = d.label, current = currentOf(s, d.durability), max = d.durability }
    end
    local best
    local function consider(uid, label, current, max)
        if current < max and (not best or current / max < best.current / best.max) then
            best = { uid = uid, label = label, current = current, max = max }
        end
    end
    for _, w in ipairs(inv:GetWornItems(src)) do
        if w.category == category and (w.durability or 0) > 0 then consider(w.uid, w.label, currentOf(w, w.durability), w.durability) end
    end
    if best then return best end
    for _, it in ipairs(inv:GetItemList()) do
        if it.category == category then
            local d = inv:GetItemDefinition(it.name)
            if d and (d.durability or 0) > 0 then
                for _, s in ipairs(inv:FindItems(src, it.name)) do consider(s.uid, d.label, currentOf(s, d.durability), d.durability) end
            end
        end
    end
    return best
end

-- Repair items: clothing.repairItems mend clothing, armor.repairItems
-- repair armor plates (the category from the config section).
local function repairInfo(name)
    if M.config.clothing.repairItems[name] then return 'clothing', M.config.clothing.repairItems[name].percent end
    if M.config.armor.repairItems[name] then return 'armor', M.config.armor.repairItems[name].percent end
    return nil
end

local function useRepairItem(src, stack, _, targetUid)
    local cid = characterOf(src)
    local s = cid and states[cid]
    if not s or s.dead then return false, 'You cannot do that right now.' end
    local category, percent = repairInfo(stack.name)
    if not category then return false, 'Nothing happens.' end
    local cloth = category == 'clothing'
    local t, err = repairTarget(src, category, targetUid)
    if not t then return false, err or (cloth and 'Nothing you wear or carry needs mending.' or 'You have no damaged armor plate.') end
    if t.current >= t.max then return false, string.format('Your %s does not need %s.', t.label:lower(), cloth and 'mending' or 'repairs') end
    local after = math.min(t.max, t.current + math.ceil(t.max * percent / 100))
    local ok, e = exports.wasteland_inventory:SetItemMetadata(src, t.uid, { durability = after })
    if not ok then return false, e end
    plateCarry[t.uid] = nil
    TriggerClientEvent('wasteland:survival:client:consumed', src, 'treat', nil)
    return 1, string.format('You %s your %s (%d%% -> %d%%).', cloth and 'mend' or 'repair', t.label:lower(),
        math.floor(t.current / t.max * 100 + 0.5), math.floor(after / t.max * 100 + 0.5))
end

local function registerClothingRepairs()
    if not clothingRunning() then return end
    for _, list in ipairs({ M.config.clothing.repairItems, M.config.armor.repairItems }) do
        for name in pairs(list) do
            local ok, err = exports.wasteland_inventory:RegisterUsable(name, useRepairItem)
            if not ok then M.log:warn('repair item "%s": %s', name, tostring(err)) end
        end
    end
end

-- The inventory restarted: register again.
AddEventHandler('wasteland:core:moduleState', function(name, state)
    if name == 'inventory' and state == 'running' and M and M.active then registerConsumables(); registerClothingRepairs() end
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
    for name, fn in pairs(respawnPoints) do
        local ok, point = pcall(fn, src, cid)
        if not ok then respawnPoints[name] = nil
        elseif type(point) == 'table' and type(point.x) == 'number' and type(point.y) == 'number' and type(point.z) == 'number' then
            p = { x = point.x, y = point.y, z = point.z, heading = tonumber(point.heading) or 0.0 }
            break
        end
    end
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
-- Admin: /survival <server id> <stat> <value>   (testing and support)
-------------------------------------------------------------------------------

local SETTABLE = { hunger = { 0, 100 }, thirst = { 0, 100 }, infection = { 0, 100 }, bleeding = { 0, 3 }, temperature = { 30, 42 } }

adminCommand = function(src, args)
    local reply = function(msg)
        if src == 0 then print(msg) else TriggerClientEvent('wasteland:core:client:consoleOutput', src, { msg }) end
    end
    if src ~= 0 and not IsPlayerAceAllowed(tostring(src), M.config.adminAce) then
        M.log:warn('player %d tried "%s" without the %s ACE', src, M.config.adminCommand, M.config.adminAce)
        return
    end
    local target, stat, value = tonumber(args[1]), args[2], tonumber(args[3])
    local range = stat and SETTABLE[stat]
    if not target or not range or not value then
        reply(string.format('usage: %s <server id> <hunger|thirst|infection|bleeding|temperature> <value>', M.config.adminCommand))
        return
    end
    local cid = characterOf(target)
    local s = cid and states[cid]
    if not s then reply(string.format('player %d has no loaded character', target)); return end
    if s.dead then reply('that character is dead'); return end
    value = Model.clamp(value, range[1], range[2])
    if stat == 'bleeding' then value = math.floor(value) end
    s[stat] = value
    players():SetCharacterData(cid, DATA_KEY, s)
    sendStats(target, cid)
    M.log:info('%s set %s of player %d to %s', src == 0 and 'console' or ('player ' .. src), stat, target, tostring(value))
    reply(string.format('Set %s of player %d to %s.', stat, target, tostring(value)))
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
    prop = { type = 'string', pattern = '^[%w_]+$', maxLength = 64, description = 'Model held in the hand while using it' },
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
            adminCommand = { type = 'string', default = 'survival', pattern = '^[a-z][a-z0-9_]*$' },
            adminAce = { type = 'string', default = 'wasteland.admin', minLength = 1 },
            start = { type = 'table', fields = { hunger = num(100, 0, 100), thirst = num(100, 0, 100) } },
            hunger = { type = 'table', fields = { drainPerHour = num(50, 0, 1000), starvingDamagePerMinute = num(2, 0, 200) } },
            thirst = { type = 'table', fields = { drainPerHour = num(66.7, 0, 1000), dehydratedDamagePerMinute = num(3, 0, 200),
                hotMultiplier = num(1.5, 1, 10) } },
            toilet = { type = 'table', fields = {
                enabled = { type = 'boolean', default = true },
                bladderPerHour = num(50, 0, 1000), bowelPerHour = num(25, 0, 1000),
                drinkToBladder = num(0.4, 0, 5), foodToBowel = num(0.3, 0, 5), minToGo = num(20, 0, 100),
            } },
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
            clothing = { type = 'table', fields = {
                hitWear = { type = 'array', default = { 4, 10 }, minItems = 2, maxItems = 2, items = { type = 'integer', min = 0, max = 100000 },
                    description = 'Durability one worn piece loses when a zombie hits (min, max)' },
                repairItems = { type = 'map', default = { sewing_kit = { percent = 50 } }, keys = { type = 'string', pattern = '^[a-z][a-z0-9_]*$' },
                    values = { type = 'table', fields = { percent = { type = 'number', default = 50, min = 1, max = 100 } } } },
            } },
            armor = { type = 'table', fields = {
                wearPerDamage = num(0.25, 0, 10),
                repairItems = { type = 'map', default = { armor_repair_kit = { percent = 40 } }, keys = { type = 'string', pattern = '^[a-z][a-z0-9_]*$' },
                    values = { type = 'table', fields = { percent = { type = 'number', default = 40, min = 1, max = 100 } } } },
            } },
        } },
    },

    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        if M.config.temperature.comfortLow >= M.config.temperature.comfortHigh then
            return false, 'survival.lua: temperature.comfortLow must be below comfortHigh'
        end
        states, online, deathAt, damageCarry = {}, {}, {}, {}
        if not commandRegistered then
            RegisterCommand(M.config.adminCommand, function(source, args) adminCommand(tonumber(source) or 0, args) end, false)
            commandRegistered = true
        end
        registerConsumables()
        registerClothingRepairs()
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

-- The game took GTA armour (gunshots, melee): the plate wears down. The
-- client keeps the armour full while a plate holds.
M.netEvent('wasteland:survival:server:armorHit', { args = { { type = 'number', required = true, min = 0, max = 400 } },
    rateLimit = { burst = 4, perSecond = 2 } }, function(src, amount)
    local cid = characterOf(src)
    -- Right after loading, the game's armour is being set up: not a hit.
    if loadedAt[src] and GetGameTimer() - loadedAt[src] < 15000 then return end
    if cid and states[cid] and not states[cid].dead and amount > 0 then wearPlate(src, amount) end
end)

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

-- /pee and /poop: empty the meter, everyone nearby sees the animation.
M.netEvent('wasteland:survival:server:relieve', {
    args = { { type = 'string', required = true, pattern = '^%a+$', maxLength = 8 } },
    rateLimit = { burst = 2, perSecond = 0.2 },
}, function(src, kind)
    local t = M.config.toilet
    if not (t and t.enabled) or (kind ~= 'pee' and kind ~= 'poop') then return end
    local cid = characterOf(src)
    local s = cid and states[cid]
    if not s or s.dead then return end
    local field = kind == 'pee' and 'bladder' or 'bowel'
    if (s[field] or 0) < t.minToGo then
        notice(src, kind == 'pee' and 'You do not need to pee right now.' or 'You do not need to go right now.')
        return
    end
    s[field] = 0
    players():SetCharacterData(cid, DATA_KEY, s)
    sendStats(src, cid)
    TriggerClientEvent('wasteland:survival:client:relieve', -1, src, kind)
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

--- Heal(source) -> ok   (admin: full health, fed, no bleeding/infection, normal temperature)
exports('Heal', function(src)
    local s, cid = stateOf(src)
    if not s or s.dead then return false end
    s.hunger, s.thirst, s.bleeding, s.infection, s.treatment = 100, 100, 0, 0, 0
    s.temperature = M.config.temperature.normal
    damageCarry[cid] = 0
    players():SetCharacterData(cid, DATA_KEY, s)
    TriggerClientEvent('wasteland:survival:client:heal', tonumber(src), 400)
    sendStats(tonumber(src), cid)
    return true
end)

--- Revive(source) -> ok   (admin: a dead character gets up where it lies;
--- the body bag stays where it is)
exports('Revive', function(src)
    local s, cid = stateOf(src)
    if not s or not s.dead then return false end
    local fresh = Model.fresh(M.config)
    fresh.hunger, fresh.thirst = M.config.respawn.stats.hunger, M.config.respawn.stats.thirst
    states[cid], damageCarry[cid], deathAt[cid] = fresh, 0, nil
    save(cid, true)
    TriggerClientEvent('wasteland:survival:client:revive', tonumber(src))
    sendStats(tonumber(src), cid)
    return true
end)

--- RegisterWarmthSource(name, fn(source) -> degrees)   (e.g. near a campfire; added to clothing warmth)
exports('RegisterWarmthSource', function(name, fn)
    if type(name) ~= 'string' then return false end
    warmthSources[name] = fn
    return true
end)

--- RegisterRespawnPoint(name, fn(source, characterId) -> { x, y, z, heading } | nil)
--- (e.g. a sleeping bag). The first point given is used; otherwise a random respawn point.
exports('RegisterRespawnPoint', function(name, fn)
    if type(name) ~= 'string' then return false end
    respawnPoints[name] = fn
    return true
end)

--- Damage(source, amount) -> ok, absorbed (an armor plate took it) -> ok   (zombie hits; health points of 100)
exports('Damage', function(src, amount)
    local s = stateOf(src)
    amount = math.floor(tonumber(amount) or 0)
    if not s or s.dead or amount <= 0 then return false end
    local ps = Player(tonumber(src)) and Player(tonumber(src)).state
    if ps and ps.wlProtected then return false end -- making a character / choosing where to start
    if wearPlate(tonumber(src), amount) then return true, true end -- the armor plate took it
    TriggerClientEvent('wasteland:survival:client:damage', tonumber(src), math.min(amount, 400))
    return true, false
end)

--- IsDead(source) -> boolean
exports('IsDead', function(src)
    local s = stateOf(src)
    return s ~= nil and s.dead == true
end)
