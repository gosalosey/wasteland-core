-- wasteland_zombies :: server/hordes.lua
-- Wandering hordes (zombies.lua `hordes`). A horde is a group of zombies
-- that roams the map. Far from everyone it is only a point that moves
-- (no peds, no cost). When a player comes within activateDistance, its
-- zombies are created around that point (spawn points found by that
-- player's game) and walk on together to the horde's next waypoint.
-- Players within warnDistance are warned (feed message), at most once per
-- warnCooldownSeconds per horde. A horde is over when its zombies are dead
-- or its time is up while nobody is near it.

local Rules = WLZ.Rules
local S = WLZ.Server
local M = S.module()

local hordes = {}       -- id -> horde
local nextId = 0
local runToken = nil

local function cfg() return M.config.hordes end
local function now() return GetGameTimer() end

local function players()
    local list = {}
    for _, src in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            list[#list + 1] = { source = tonumber(src), coords = { x = c.x, y = c.y, z = c.z } }
        end
    end
    return list
end

local function nearestPlayer(point, list)
    local best, bestD
    for _, p in ipairs(list) do
        local d = Rules.dist2d(point, p.coords)
        if not bestD or d < bestD then best, bestD = p, d end
    end
    return best, bestD
end

-- Somewhere for the horde to head: usually through where players are (so
-- it is met), sometimes off somewhere else. Never into a camp.
local function waypoint(h, list)
    for _ = 1, 8 do
        local p
        if #list > 0 and math.random() < 0.7 then
            local who = list[math.random(1, #list)].coords
            local a, d = math.random() * math.pi * 2, math.random() * 150
            p = { x = who.x + math.cos(a) * d, y = who.y + math.sin(a) * d, z = who.z }
        else
            local a = math.random() * math.pi * 2
            p = { x = h.x + math.cos(a) * 400, y = h.y + math.sin(a) * 400, z = h.z }
        end
        if not S.inSafeZone(p) then return p end
    end
    return { x = h.x, y = h.y, z = h.z }
end

local function members(h)
    local alive = {}
    for handle in pairs(h.members) do
        local z = S.zombies()[handle]
        if z and not z.dead and DoesEntityExist(handle) then alive[#alive + 1] = z else h.members[handle] = nil end
    end
    return alive
end

local function create(list, near, night)
    local c = cfg()
    local size = night and c.nightSize or c.size
    local a = math.random() * math.pi * 2
    local d = c.startMin + math.random() * (c.startMax - c.startMin)
    nextId = nextId + 1
    local h = { id = nextId, x = near.x + math.cos(a) * d, y = near.y + math.sin(a) * d, z = near.z,
        size = math.random(math.floor(size[1]), math.floor(size[2])), members = {}, live = false,
        startedAt = now(), warned = {}, askedAt = now() - 10000, orderedAt = 0 }
    h.target = { x = near.x, y = near.y, z = near.z } -- first heads for the player it started near
    hordes[h.id] = h
    M.log:info('wandering horde #%d of %d zombies started %.0f m from a player', h.id, h.size, d)
    return h
end

local function remove(h, why)
    hordes[h.id] = nil
    M.log:info('wandering horde #%d over (%s)', h.id, why)
end

-- The zombies walk on together: all of them head for the waypoint.
local function order(h)
    local t = now()
    for handle in pairs(h.members) do
        if DoesEntityExist(handle) then
            Entity(handle).state:set('wlInvestigate', { x = h.target.x + math.random(-8, 8), y = h.target.y + math.random(-8, 8),
                z = h.target.z, untilMs = 30000, at = t }, true)
        end
    end
    h.orderedAt = t
end

local function warn(h, list)
    local c = cfg()
    local t = now()
    for _, p in ipairs(list) do
        local d = Rules.dist2d(p.coords, h)
        local last = h.warned[p.source]
        if d <= c.warnDistance and (not last or t - last >= c.warnCooldownSeconds * 1000) then
            h.warned[p.source] = t
            local alive = h.live and #members(h) or h.size
            TriggerClientEvent('wasteland:zombies:client:hordeWarning', p.source,
                string.format('~r~A wandering horde~s~ of about %d zombies is near: ~%d m to the %s.',
                    math.max(alive, 1), math.floor(d / 10 + 0.5) * 10, Rules.compass(p.coords, h)))
        end
    end
end

local function step(h, list, dt)
    local c = cfg()
    local t = now()
    if h.live then
        local alive = members(h)
        if #alive == 0 then
            h.live = false -- killed, or nobody stayed near it (the rest roam on unseen)
        else
            local sx, sy, sz = 0, 0, 0
            for _, z in ipairs(alive) do
                local p = S.coordsOf(z.handle)
                sx, sy, sz = sx + p.x, sy + p.y, sz + p.z
            end
            h.x, h.y, h.z = sx / #alive, sy / #alive, sz / #alive
            if Rules.dist2d(h, h.target) < 20 then h.target = waypoint(h, list); order(h)
            elseif t - h.orderedAt >= 25000 then order(h) end
        end
    end
    if not h.live then
        if h.size <= 0 then return remove(h, 'all dead') end
        local p, d = nearestPlayer(h, list)
        if (not p or d > c.activateDistance) and t - h.startedAt >= c.lifetimeMinutes * 60000 then
            return remove(h, 'time up')
        end
        local moved = Rules.moveToward(h, h.target, c.speed * dt)
        h.x, h.y = moved.x, moved.y
        if Rules.dist2d(h, h.target) < 5 then h.target = waypoint(h, list) end
        if p and d <= c.activateDistance and t - h.askedAt >= 10000 then
            h.askedAt = t
            h.asked = p.source
            TriggerClientEvent('wasteland:zombies:client:findHordeSpawns', p.source, h.id, { x = h.x, y = h.y, z = p.coords.z },
                math.min(h.size, 30), c.spread)
        end
    end
    warn(h, list)
end

-- Spawn points from the game of the player that was asked (checked: near
-- the horde, not in a camp).
local function spawnsFound(src, id, points)
    local h = hordes[id]
    if not h or h.live or h.asked ~= src then return end
    h.asked = nil
    local c = cfg()
    local made = 0
    local hasRunner = M.config.kinds.runner ~= nil
    for _, point in ipairs(points) do
        if made >= h.size then break end
        if Rules.dist2d(point, h) <= c.spread + 15 and not S.inSafeZone(point) then
            local kind = (hasRunner and math.random() < c.runnerShare) and 'runner' or 'walker'
            local z = S.spawnAt(point, kind)
            if z then
                z.horde = h.id
                h.members[z.handle] = true
                made = made + 1
            end
        end
    end
    if made > 0 then
        h.live = true
        order(h)
        M.log:info('wandering horde #%d: %d zombies appeared', h.id, made)
    end
end

M.netEvent('wasteland:zombies:server:hordeSpawns', {
    args = { { type = 'integer', required = true, min = 1 },
        { type = 'array', required = true, maxItems = 30, items = { type = 'table', fields = {
            x = { type = 'number', required = true }, y = { type = 'number', required = true }, z = { type = 'number', required = true } } } } },
    rateLimit = { burst = 3, perSecond = 1 },
}, function(src, id, points) spawnsFound(src, id, points) end)

-- A horde zombie died: one fewer in the horde.
AddEventHandler('wasteland:zombies:died', function(netId)
    local z = S.byNet(tonumber(netId))
    local h = z and z.horde and hordes[z.horde]
    if h then h.size = h.size - 1 end
end)

local function loop(token)
    local sinceCheck = 0
    while runToken == token do
        Citizen.Wait(2000)
        if runToken ~= token then return end
        local c = cfg()
        local list = players()
        for _, h in pairs(hordes) do step(h, list, 2) end
        sinceCheck = sinceCheck + 2
        if sinceCheck >= c.checkSeconds then
            sinceCheck = 0
            local n = 0
            for _ in pairs(hordes) do n = n + 1 end
            if #list > 0 and n < c.max and math.random() < c.chance then
                create(list, list[math.random(1, #list)].coords, S.isNight())
            end
        end
    end
end

WLZ.Hordes = {
    -- Called by the module (start / stop).
    start = function()
        hordes, nextId = {}, 0
        local token = {}
        runToken = token
        if cfg().enabled then Citizen.CreateThread(function() loop(token) end) end
    end,
    stop = function() runToken = nil; hordes = {} end,
    -- /zombies horde: one starts near an admin, heading for them.
    startNear = function(coords) return create(players(), coords, S.isNight()) end,
    list = function() return hordes end,
}

-- The module may already be running (this file loads after main.lua).
if M.active then WLZ.Hordes.start() end
