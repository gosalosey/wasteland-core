-- wasteland_zombies :: shared/ai.lua
-- Pure rules for the zombie AI upgrade (no natives): personalities and
-- special infected (from the zombie's uid, so every game and the server
-- agree without sending anything), time-of-day phases, vision, pack slots,
-- search points, giving up, and the horde layer (who answers a noise, how
-- repeated gunfire grows). Unit-tested. The defaults below are used for any
-- setting zombies.lua `ai` leaves out; `ai.enabled = false` restores the
-- original zombie behaviour.

WLZ = WLZ or {}
local AI = {}
WLZ.AI = AI

AI.DEFAULTS = {
    enabled = true,

    -- How each zombie behaves. weight / nightWeight: share of zombies (day /
    -- dusk-and-night). A zombie keeps its personality while it is busy; when
    -- the time of day changes, calm zombies pick again (a few at a time).
    personalities = {
        wanderer = { weight = 45, nightWeight = 35, reactMs = 600 },
        stalker = { weight = 10, nightWeight = 20, reactMs = 300,
            keepDistance = { 12, 22 },  -- follows this far behind
            stalkSeconds = { 8, 20 },   -- before it charges
            chargeDistance = 8,         -- charges at once when this close (or from behind)
            disengageChance = 0.3 },    -- chance it backs off when a charge does not reach you
        ambusher = { weight = 10, nightWeight = 10, reactMs = 0,
            triggerRadius = 9 },        -- waits still; jumps anyone this close (no line of sight needed)
        sprinter = { weight = 10, nightWeight = 15, reactMs = 800,
            sprintSpeed = 3.0, sprintSeconds = 6, recoverSpeed = 1.4, cooldownSeconds = 5 },
        sleeper = { weight = 10, nightWeight = 5, reactMs = 1200,
            wakeRadius = 7 },           -- lies still; wakes for anyone this close (half when crouching) or a noise
        pack = { weight = 15, nightWeight = 15, reactMs = 400,
            ringRadius = 3.5,           -- surround the target this far out, then close in
            packRadius = 35 },          -- pack hunters this close to each other hunt together
    },

    -- Ambushers within `radius` of a point go there and wait.
    -- { x = 0.0, y = 0.0, z = 0.0, radius = 40 }
    ambushPoints = {},

    -- Buildings with a way in: a noise inside `radius` of `x, y, z` sends
    -- zombies to `entry` first. { x, y, z, radius = 15, entry = { x, y, z } }
    entryPoints = {},

    senses = {
        senseEveryMs = 500,      -- how often a zombie looks and listens (staggered)
        fov = 130,               -- degrees in front of it with full sight
        peripheral = 0.4,        -- sight outside that cone (share)
        stationary = 0.6,        -- sight on someone standing still (share)
        sprinting = 1.3,         -- sight on someone running
        vehicleEngine = 45,      -- hears a running engine this far (metres; moving: full, idling: 60%)
    },

    -- Barricades (base building walls, doors and gates): a zombie whose
    -- target hides behind them (or in a base's safe zone) attacks the nearest
    -- piece between them instead of giving up. Damage per hit is set in
    -- basebuilding.lua `raid.zombies`.
    barricades = {
        enabled = true,
        searchRadius = 15,       -- pieces this close to the zombie
        playerRadius = 35,       -- only while its target is this close
        giveUpSeconds = 60,      -- stops after this long (then searches / wanders)
    },

    memory = {
        searchSeconds = 20,      -- looks around the last place it saw you
        searchRadius = 12,
        loseDistance = 60,       -- gives up when its target is this far from it
        maxChaseSeconds = 120,   -- gives up a chase after this long ...
        maxChaseDistance = 160,  -- ... or this far from where it started
    },

    -- Noises. radius (metres; gunshots use the weapon's own noise times
    -- radiusScale), intensity (1 quiet - 3 loud: wakes sleepers at 2+),
    -- cooldownMs (the same noise in the same spot is ignored this long).
    sounds = {
        gunshot = { radiusScale = 1.0, intensity = 2, cooldownMs = 400 },
        explosion = { radius = 120, intensity = 3, cooldownMs = 2000 },
        crash = { radius = 45, intensity = 2, cooldownMs = 3000 },
        horn = { radius = 80, intensity = 2, cooldownMs = 1500 },
        scream = { radius = 60, intensity = 2, cooldownMs = 5000 },
        howl = { radius = 180, intensity = 3, cooldownMs = 20000 },
        other = { radiusScale = 1.0, intensity = 1, cooldownMs = 400 },
    },

    -- Horde: how many zombies answer one noise (the nearest), how repeated
    -- gunfire in one area reaches further, and how they spread around it.
    horde = {
        enabled = true,
        maxResponders = 15,
        repeatWindowSeconds = 20, repeatStep = 0.25, repeatMax = 2.5,
        spread = 6,              -- metres between zombies arriving at the same noise
    },

    -- Time of day (game hours). Multipliers on sight, chase speed and the
    -- horde (noise reach and responders).
    phases = {
        dawn = { from = 5, to = 7, sight = 0.9, speed = 1.0, horde = 1.0 },
        day = { from = 7, to = 19, sight = 1.0, speed = 1.0, horde = 1.0 },
        dusk = { from = 19, to = 21, sight = 0.85, speed = 1.05, horde = 1.15 },
        night = { from = 21, to = 5, sight = 1.0, speed = 1.15, horde = 1.3 },
    },

    -- Special infected: a small share of zombies (chance: percent each,
    -- rolled separately from personality). They use the zombie's existing model.
    --   health       hit points (GTA peds have 200)
    --   speedMult, damageMult, cooldownMult (attack), windupMult (slower, telegraphed swing)
    --   clipset      walking style (a GTA clipset name)
    -- Bosses (boss = true) are off (chance 0) until you raise their chance.
    specials = {
        enabled = true,
        screamer = { chance = 3, cooldownSeconds = 30 },   -- screams on spotting you: brings the others
        brute = { chance = 3, health = 600, speedMult = 0.8, damageMult = 1.8, windupMult = 2.0, cooldownMult = 1.5,
            clipset = 'move_m@gangster@generic' },
        howler = { chance = 1, cooldownSeconds = 60 },     -- a long call that brings a horde from far
        spitter = { chance = 2, range = 14, minRange = 4, cooldownSeconds = 8, damage = 8, infection = 4 },
        crawler = { chance = 0, speedMult = 0.7, damageMult = 0.7, cooldownMult = 0.6, health = 150,
            clipset = 'move_injured_generic' },                              -- off: GTA has no true crawl walk for these models
        hunter = { chance = 2, isolation = 25 },           -- advanced stalker: goes for players on their own
        juggernaut = { boss = true, chance = 0, health = 1500, armour = 100, speedMult = 0.75, damageMult = 2.2,
            windupMult = 1.6, cooldownMult = 1.4, clipset = 'move_m@gangster@generic' },
        alpha = { boss = true, chance = 0, health = 800, speedMult = 1.1, damageMult = 1.4, cooldownSeconds = 25 },
        butcher = { boss = true, chance = 0, health = 900, damageMult = 2.5, cooldownMult = 0.8 },
        nightterror = { boss = true, chance = 0, health = 700, nightSpeedMult = 1.4, nightSightMult = 1.5, damageMult = 1.6 },
    },
}

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------

local function isArray(t)
    return type(t) == 'table' and (next(t) == nil or t[1] ~= nil)
end

--- Defaults with the user's settings on top (lists are replaced, tables
--- merged). A value of the wrong type keeps the default (and is reported in
--- `warnings`, a list, when given).
function AI.merge(defaults, user, warnings, path)
    if type(user) ~= 'table' then return defaults end
    if isArray(defaults) then return user end
    local out = {}
    for k, v in pairs(defaults) do out[k] = v end
    for k, v in pairs(user) do
        local d = defaults[k]
        local where = (path and path .. '.' or '') .. tostring(k)
        if d ~= nil and type(v) ~= type(d) then
            if warnings then warnings[#warnings + 1] = string.format('%s should be a %s (the default is used)', where, type(d)) end
        elseif type(v) == 'table' and type(d) == 'table' then
            out[k] = AI.merge(d, v, warnings, where)
        else
            out[k] = v
        end
    end
    return out
end

local cache = { src = nil, merged = nil }
--- The AI settings in use for zombies.lua `ai` (cached per table).
function AI.settings(user, warnings)
    if not warnings and cache.merged and cache.src == user then return cache.merged end
    local merged = AI.merge(AI.DEFAULTS, user, warnings)
    cache.src, cache.merged = user, merged
    return merged
end

-------------------------------------------------------------------------------
-- Who a zombie is (from its uid)
-------------------------------------------------------------------------------

--- A number in [0, 1) from a uid and a salt (FNV-1a), the same everywhere.
function AI.roll(uid, salt)
    local h = 2166136261
    local s = tostring(salt or '') .. ':' .. tostring(uid or '')
    for i = 1, #s do
        h = h ~ s:byte(i)
        h = (h * 16777619) & 0xffffffff
    end
    return h / 4294967296
end

local function sortedNames(t)
    local names = {}
    for k in pairs(t) do if type(t[k]) == 'table' then names[#names + 1] = k end end
    table.sort(names)
    return names
end

--- Phase of the day for a game hour: name, settings.
function AI.phase(ai, hour)
    hour = tonumber(hour) or 12
    for _, name in ipairs({ 'dawn', 'day', 'dusk', 'night' }) do
        local p = ai.phases[name]
        if p then
            local inside
            if p.from <= p.to then inside = hour >= p.from and hour < p.to else inside = hour >= p.from or hour < p.to end
            if inside then return name, p end
        end
    end
    return 'day', ai.phases.day or { sight = 1, speed = 1, horde = 1 }
end

local function dark(phaseName) return phaseName == 'night' or phaseName == 'dusk' end

--- Personality name for a zombie. `epoch` changes the roll when the phase
--- changes (so calm zombies may pick again).
function AI.personality(ai, uid, phaseName, epoch)
    local names = sortedNames(ai.personalities)
    local total = 0
    for _, n in ipairs(names) do
        local p = ai.personalities[n]
        total = total + math.max(0, (dark(phaseName) and p.nightWeight or p.weight) or 0)
    end
    if total <= 0 then return 'wanderer' end
    local pick = AI.roll(uid, 'personality' .. tostring(epoch or '')) * total
    for _, n in ipairs(names) do
        local p = ai.personalities[n]
        pick = pick - math.max(0, (dark(phaseName) and p.nightWeight or p.weight) or 0)
        if pick < 0 then return n end
    end
    return names[#names]
end

--- Special infected name for a zombie, or nil (fixed for its life).
function AI.special(ai, uid)
    if not ai.specials or ai.specials.enabled == false then return nil end
    local roll = AI.roll(uid, 'special')
    local acc = 0
    for _, n in ipairs(sortedNames(ai.specials)) do
        local s = ai.specials[n]
        acc = acc + (s.chance or 0) / 100
        if roll < acc then return n, s end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Senses
-------------------------------------------------------------------------------

--- How far a zombie sees a target.
--- o = { base, phaseSight, specialSight, inFront, speed (m/s), sprinting }
function AI.sightRange(senses, o)
    local r = (o.base or 0) * (o.phaseSight or 1) * (o.specialSight or 1)
    if not o.inFront then r = r * senses.peripheral end
    if o.sprinting then r = r * senses.sprinting
    elseif (o.speed or 0) < 0.3 then r = r * senses.stationary end
    return r
end

--- Is `to` inside the zombie's view cone? fwd = { x, y } unit vector.
function AI.inFront(senses, fwd, from, to)
    local dx, dy = to.x - from.x, to.y - from.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return true end
    local cos = (fwd.x * dx + fwd.y * dy) / len
    return cos >= math.cos(math.rad(senses.fov / 2))
end

--- How far a zombie hears a target. o = { walk, crouch, sprint, crouching,
--- running, still, vehicle (engine on), vehicleMoving }
function AI.hearRange(senses, o)
    local r = o.walk
    if o.crouching then r = o.crouch
    elseif o.running then r = o.sprint
    elseif o.still then r = math.min(o.walk, o.crouch) end
    if o.vehicle then r = math.max(r, senses.vehicleEngine * (o.vehicleMoving and 1 or 0.6)) end
    return r
end

-------------------------------------------------------------------------------
-- Movement helpers
-------------------------------------------------------------------------------

--- The spot for pack member `index` (1..count) around `target`.
function AI.packSlot(index, count, target, radius, baseAngle)
    local a = (baseAngle or 0) + (index - 1) * (2 * math.pi / math.max(1, count))
    return { x = target.x + math.cos(a) * radius, y = target.y + math.sin(a) * radius, z = target.z }
end

--- A spot `dist` from target, on the zombie's side, turned `turn` radians
--- (stalkers circle round instead of walking straight in).
function AI.stalkPoint(zombie, target, dist, turn)
    local a = math.atan(zombie.y - target.y, zombie.x - target.x) + (turn or 0)
    return { x = target.x + math.cos(a) * dist, y = target.y + math.sin(a) * dist, z = target.z }
end

--- A place to look while searching around `center`. r1, r2 in [0, 1).
function AI.searchPoint(center, radius, r1, r2)
    local a, d = r1 * 2 * math.pi, radius * (0.3 + 0.7 * r2)
    return { x = center.x + math.cos(a) * d, y = center.y + math.sin(a) * d, z = center.z }
end

--- A value from a { lo, hi } pair and a roll in [0, 1).
function AI.between(pair, roll)
    if type(pair) ~= 'table' then return tonumber(pair) or 0 end
    return pair[1] + (pair[2] - pair[1]) * roll
end

--- Should a chase end? chase = { startedAt, from = {x,y,z} }; here = zombie position.
function AI.giveUp(memory, chase, t, here)
    if not chase or not chase.startedAt then return false end
    if t - chase.startedAt > memory.maxChaseSeconds * 1000 then return true, 'too long' end
    if chase.from and here then
        local dx, dy = here.x - chase.from.x, here.y - chase.from.y
        if math.sqrt(dx * dx + dy * dy) > memory.maxChaseDistance then return true, 'too far' end
    end
    return false
end

--- Is `who` on their own? others: list of {x,y,z} (other players).
function AI.isolated(who, others, radius)
    for _, o in ipairs(others) do
        local dx, dy = o.x - who.x, o.y - who.y
        if math.sqrt(dx * dx + dy * dy) <= radius then return false end
    end
    return true
end

-------------------------------------------------------------------------------
-- Horde (server)
-------------------------------------------------------------------------------

--- How much further repeated gunfire reaches: history is a list of
--- { t, x, y } (kept by the caller; old entries are dropped here).
function AI.repeatScale(horde, history, t, at)
    local window = horde.repeatWindowSeconds * 1000
    local n = 0
    for i = #history, 1, -1 do
        local h = history[i]
        if t - h.t > window then table.remove(history, i)
        else
            local dx, dy = h.x - at.x, h.y - at.y
            if math.sqrt(dx * dx + dy * dy) <= 60 then n = n + 1 end
        end
    end
    history[#history + 1] = { t = t, x = at.x, y = at.y }
    return math.min(horde.repeatMax, 1 + horde.repeatStep * n)
end

--- Zombies that answer a noise: the nearest `max` within `radius`.
--- zombies: list of { id, coords, dead }. -> list of ids, nearest first.
function AI.responders(zombies, at, radius, max)
    local list = {}
    for _, z in ipairs(zombies) do
        if not z.dead and z.coords then
            local dx, dy, dz = z.coords.x - at.x, z.coords.y - at.y, (z.coords.z or 0) - (at.z or 0)
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            if d <= radius then list[#list + 1] = { id = z.id, d = d } end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    local out = {}
    for i = 1, math.min(#list, max or #list) do out[i] = list[i].id end
    return out
end

--- Where responder `slot` (0 = first) goes: the first to the noise itself,
--- the others spread on rings around it so they do not stack.
function AI.spreadPoint(at, slot, spread)
    if slot == 0 then return { x = at.x, y = at.y, z = at.z } end
    local ring = math.floor((slot - 1) / 6) + 1
    local a = ((slot - 1) % 6) * (math.pi / 3) + ring * 0.5
    return { x = at.x + math.cos(a) * spread * ring, y = at.y + math.sin(a) * spread * ring, z = at.z }
end

--- A building entry point for a noise at `at`, or nil.
function AI.entryFor(points, at)
    for _, p in ipairs(points or {}) do
        local dx, dy = p.x - at.x, p.y - at.y
        if math.sqrt(dx * dx + dy * dy) <= (p.radius or 15) and type(p.entry) == 'table' then return p.entry end
    end
    return nil
end

--- The nearest ambush point within its radius of `at`, or nil.
function AI.ambushPointFor(points, at)
    local best, bestD
    for _, p in ipairs(points or {}) do
        local dx, dy = p.x - at.x, p.y - at.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d <= (p.radius or 40) and (not bestD or d < bestD) then best, bestD = p, d end
    end
    return best
end

--- Key for a sound's cooldown: kind and a 30 m cell.
function AI.cooldownKey(kind, at)
    return string.format('%s:%d:%d', kind, math.floor(at.x / 30), math.floor(at.y / 30))
end

return AI
