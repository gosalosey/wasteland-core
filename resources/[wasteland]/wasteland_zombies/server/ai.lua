-- wasteland_zombies :: server/ai.lua
-- The server half of the zombie AI upgrade (zombies.lua `ai`):
--   * noise -> horde: who answers (the nearest, capped), where each one goes
--     (spread out, through a building's entry point), repeated gunfire
--     reaching further, night hordes, a cooldown per sound and spot;
--   * explosions, vehicle crashes, screamer / howler calls, spitter hits.
-- Zombies are only ever the existing ones: nothing here spawns.

local AI = WLZ.AI
local SAI = {}
WLZ.ServerAI = SAI

local cooldowns, gunHistory = {}, {}
local lastPrune = 0
local shouts, spits, pieceHits, touches = {}, {}, {}, {}   -- zombie handle -> next allowed / last time

local function Srv() return WLZ.Server end
local function M() return Srv() and Srv().module() end
local function settings()
    local m = M()
    return AI.settings(m and m.config and m.config.ai)
end

function SAI.enabled()
    local m = M()
    return m ~= nil and m.active and settings().enabled == true
end

function SAI.init()
    cooldowns, gunHistory, shouts, spits, pieceHits, touches = {}, {}, {}, {}, {}, {}
    local m = M()
    if not m then return end
    local warnings = {}
    AI.settings(m.config.ai, warnings)
    for _, w in ipairs(warnings) do m.log:warn('zombies.lua ai: %s', w) end
end

--- The special infected settings of a zombie record, or nil.
function SAI.specialOf(z)
    if not SAI.enabled() then return nil end
    if not z.specialChecked then
        z.specialChecked = true
        z.specialName, z.special = AI.special(settings(), z.uid)
    end
    return z.special, z.specialName
end

local function hour()
    if GetResourceState('wasteland_world') ~= 'started' then return 12 end
    local ok, h = pcall(function() return exports.wasteland_world:GetTime() end)
    return ok and tonumber(h) or 12
end

--- A noise at `coords`. radius: the noise's own reach (gunshots, other) or
--- nil (the sound's configured radius). -> number of zombies sent.
function SAI.alert(coords, radius, kind)
    local m = M()
    if not m or not m.active or type(coords) ~= 'table' or type(coords.x) ~= 'number' then return 0 end
    local ai = settings()
    local snd = ai.sounds[kind] or ai.sounds.other
    local t = GetGameTimer()
    if t - lastPrune > 60000 then
        lastPrune = t
        for key, untilT in pairs(cooldowns) do if untilT <= t then cooldowns[key] = nil end end
        local live = Srv().zombies()
        for h in pairs(shouts) do if not live[h] then shouts[h] = nil end end
        for h in pairs(spits) do if not live[h] then spits[h] = nil end end
        for h in pairs(pieceHits) do if not live[h] then pieceHits[h] = nil end end
        for h in pairs(touches) do if not live[h] then touches[h] = nil end end
    end
    local key = AI.cooldownKey(kind, coords)
    if cooldowns[key] and t < cooldowns[key] then return 0 end
    cooldowns[key] = t + (snd.cooldownMs or 0)

    local r = radius and radius * (snd.radiusScale or 1) or snd.radius or 0
    local max
    if ai.horde.enabled then
        if kind == 'gunshot' then r = r * AI.repeatScale(ai.horde, gunHistory, t, coords) end
        local _, phase = AI.phase(ai, hour())
        r = r * (phase.horde or 1)
        max = math.max(1, math.floor(ai.horde.maxResponders * (phase.horde or 1) + 0.5))
    end
    if r <= 0 then return 0 end

    -- Zombies already on their way to this spot are left to it, so more
    -- noise there (repeated gunfire) brings new ones from further out.
    local busyFor = (m.config.noise.investigateSeconds or 40) * 1000
    local near = (ai.horde.spread or 6) * 4
    local list = {}
    for _, z in pairs(Srv().zombies()) do
        if not z.dead and DoesEntityExist(z.handle) then
            local cur = Entity(z.handle).state.wlInvestigate
            local busy = type(cur) == 'table' and type(cur.at) == 'number' and t - cur.at < busyFor
                and WLZ.Rules.dist2d(cur, coords) <= near
            if not busy then list[#list + 1] = { id = z.handle, coords = Srv().coordsOf(z.handle) } end
        end
    end
    local ids = AI.responders(list, coords, r, max)
    local via = AI.entryFor(ai.entryPoints, coords)
    for slot, handle in ipairs(ids) do
        local p = AI.spreadPoint(coords, slot - 1, ai.horde.spread)
        Entity(handle).state:set('wlInvestigate', { x = p.x, y = p.y, z = p.z,
            untilMs = m.config.noise.investigateSeconds * 1000, at = t,
            kind = kind, intensity = snd.intensity or 1, via = via }, true)
    end
    return #ids, r
end

-------------------------------------------------------------------------------
-- Sounds the game reports
-------------------------------------------------------------------------------

AddEventHandler('explosionEvent', function(_, ev)
    if not SAI.enabled() or type(ev) ~= 'table' or type(ev.posX) ~= 'number' then return end
    SAI.alert({ x = ev.posX, y = ev.posY, z = ev.posZ }, nil, 'explosion')
end)

local function playerCoords(src)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil, nil end
    return ped, Srv().coordsOf(ped)
end

-- A vehicle crash: the noise is where the player really is.
local function crash(src)
    if not SAI.enabled() then return end
    local ped, at = playerCoords(src)
    if not ped or GetVehiclePedIsIn(ped, false) == 0 then return end
    SAI.alert(at, nil, 'crash')
end

-- A screamer / howler / alpha calls: checked (it is that special, the
-- caller runs it, its own cooldown), then a horde alert from where it is.
local SHOUTS = { screamer = 'scream', howler = 'howl', alpha = 'howl' }
local function shout(src, netId, kind)
    if not SAI.enabled() then return end
    local z = Srv().byNet(netId)
    if not z or z.dead or NetworkGetEntityOwner(z.handle) ~= src then return end
    local sp, name = SAI.specialOf(z)
    if not sp or SHOUTS[name] ~= kind then return end
    local t = GetGameTimer()
    if shouts[z.handle] and t < shouts[z.handle] then return end
    shouts[z.handle] = t + math.max(1, (sp.cooldownSeconds or 30) * 0.8) * 1000
    local at = Srv().coordsOf(z.handle)
    -- a call is always heard: not held back by the spot cooldown of other calls
    cooldowns[AI.cooldownKey(kind, at)] = nil
    SAI.alert(at, nil, kind)
end

-- A spitter's spit landed (its game says so; checked here like a hit).
local function spit(src, netId, victim)
    if not SAI.enabled() then return end
    local m = M()
    local z = Srv().byNet(netId)
    if not z or z.dead or NetworkGetEntityOwner(z.handle) ~= src then return end
    local sp, name = SAI.specialOf(z)
    if name ~= 'spitter' then return end
    local t = GetGameTimer()
    if spits[z.handle] and t < spits[z.handle] then return end
    local ps = Player(victim) and Player(victim).state
    if ps and (ps.wlProtected or ps.wlMasked) then return end
    local ped, at = playerCoords(victim)
    if not ped or Srv().survival('IsDead', victim) then return end
    if WLZ.Rules.dist3d(at, Srv().coordsOf(z.handle)) > sp.range + 3.0 then return end -- too far
    if Srv().inSafeZone(at) then return end
    spits[z.handle] = t + sp.cooldownSeconds * 800
    Srv().survival('Damage', victim, sp.damage or 8)
    if (sp.infection or 0) > 0 then Srv().survival('AddInfection', victim, sp.infection) end
    TriggerEvent('wasteland:zombies:hit', victim, z.netId, { damage = sp.damage or 8, infection = sp.infection or 0, bleeding = 0, spit = true })
    m.log:debug('spitter %d hit player %d', z.netId, victim)
end

-- A zombie hit a wall / door / gate (its game says so): it runs the zombie,
-- not too often; base building checks the piece and the distance.
local function hitPiece(src, netId, pieceId)
    if not SAI.enabled() or not settings().barricades.enabled then return end
    if GetResourceState('wasteland_basebuilding') ~= 'started' then return end
    local m = M()
    local z = Srv().byNet(netId)
    if not z or z.dead or NetworkGetEntityOwner(z.handle) ~= src then return end
    local sp = SAI.specialOf(z)
    local t = GetGameTimer()
    local cooldown = m.config.attack.cooldownMs * 1.2 * ((sp and sp.cooldownMult) or 1)
    if pieceHits[z.handle] and t - pieceHits[z.handle] < cooldown then return end
    pieceHits[z.handle] = t
    local at = Srv().coordsOf(z.handle)
    local ok, left = pcall(function() return exports.wasteland_basebuilding:ZombieHit(pieceId, at) end)
    if ok and left then m.log:debug('zombie %d hit base piece %d (%s left)', z.netId, pieceId, tostring(left)) end
end

-- A zombie walked into barbed wire or spikes (its game says so): it runs
-- the zombie, not more than once a second; base building checks the piece
-- and the distance and wears it. (With or without the upgraded AI.)
local function touchPiece(src, netId, pieceId)
    if GetResourceState('wasteland_basebuilding') ~= 'started' then return end
    local z = Srv().byNet(netId)
    if not z or z.dead or NetworkGetEntityOwner(z.handle) ~= src then return end
    local t = GetGameTimer()
    if touches[z.handle] and t - touches[z.handle] < 900 then return end
    touches[z.handle] = t
    local at = Srv().coordsOf(z.handle)
    pcall(function() return exports.wasteland_basebuilding:ZombieTouch(pieceId, at) end)
end

local function register()
    local m = M()
    if not m then return end
    m.netEvent('wasteland:zombies:server:crash', { rateLimit = { burst = 2, perSecond = 0.3 } }, function(src) crash(src) end)
    m.netEvent('wasteland:zombies:server:shout', {
        args = { { type = 'integer', required = true, min = 1 }, { type = 'string', required = true, pattern = '^%a+$', maxLength = 8 } },
        rateLimit = { burst = 3, perSecond = 0.5 },
    }, function(src, netId, kind) shout(src, netId, kind) end)
    m.netEvent('wasteland:zombies:server:touchPiece', {
        args = { { type = 'integer', required = true, min = 1 }, { type = 'integer', required = true, min = 1 } },
        rateLimit = { burst = 6, perSecond = 4 },
    }, function(src, netId, pieceId) touchPiece(src, netId, pieceId) end)
    m.netEvent('wasteland:zombies:server:hitPiece', {
        args = { { type = 'integer', required = true, min = 1 }, { type = 'integer', required = true, min = 1 } },
        rateLimit = { burst = 3, perSecond = 1 },
    }, function(src, netId, pieceId) hitPiece(src, netId, pieceId) end)
    m.netEvent('wasteland:zombies:server:spit', {
        args = { { type = 'integer', required = true, min = 1 }, { type = 'integer', required = true, min = 1, max = 65535 } },
        rateLimit = { burst = 3, perSecond = 1 },
    }, function(src, netId, victim) spit(src, netId, victim) end)
end
register()
