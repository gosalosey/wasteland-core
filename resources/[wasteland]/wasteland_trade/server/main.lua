-- wasteland_trade :: server/main.lua
-- Module "trade": two players trade items face to face. One asks (target
-- on the other player: "Trade"), the other accepts; both see one window:
-- what they carry, what they offer and what the other offers. Each side
-- presses Accept; any change to an offer takes both accepts back. When both
-- have accepted, the inventory swaps everything at once (all or nothing).

local M
local trades = {}    -- id -> { id, a, b, offers = { [src] = { [uid] = count } }, ready = { [src] = bool } }
local tradeOf = {}   -- source -> trade id
local invites = {}   -- target source -> { from, at }
local nextId = 0
local runToken = nil

local function inv() return exports.wasteland_inventory end
local function players() return exports.wasteland_players end
local function notice(src, msg) TriggerClientEvent('wasteland:trade:client:notice', src, msg) end

local function nameOf(src)
    local ok, c = pcall(function() return players():GetCharacter(src) end)
    if ok and c then return c.firstName .. ' ' .. c.lastName end
    return GetPlayerName(tostring(src)) or ('Player ' .. tostring(src))
end

local function loaded(src)
    local ok, cid = pcall(function() return players():GetCharacterId(src) end)
    return ok and cid ~= nil
end

local function dead(src)
    if GetResourceState('wasteland_survival') ~= 'started' then return false end
    local ok, d = pcall(function() return exports.wasteland_survival:IsDead(src) end)
    return ok and d == true
end

local function coords(src)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

local function near(a, b, dist)
    local pa, pb = coords(a), coords(b)
    if not pa or not pb then return false end
    return (pa.x - pb.x) ^ 2 + (pa.y - pb.y) ^ 2 + (pa.z - pb.z) ^ 2 <= dist * dist
end

local function other(t, src) return t.a == src and t.b or t.a end

-------------------------------------------------------------------------------
-- What each side sees
-------------------------------------------------------------------------------

local function itemInfo()
    local labels, images = {}, {}
    for _, it in ipairs(inv():GetItemList()) do labels[it.name], images[it.name] = it.label, it.image end
    return labels, images
end

-- Offers only name stacks the player still has, never more than they have.
local function clampOffer(t, src)
    local have = {}
    for _, s in ipairs(inv():GetTradeable(src)) do have[s.uid] = s.count end
    local changed = false
    for uid, n in pairs(t.offers[src]) do
        local max = have[uid] or 0
        if n > max then
            t.offers[src][uid] = max > 0 and max or nil
            changed = true
        end
    end
    return changed
end

local function offerList(t, src, labels, images, stacks)
    local out = {}
    for _, s in ipairs(stacks) do
        local n = t.offers[src][s.uid]
        if n then
            out[#out + 1] = { uid = s.uid, name = s.name, label = labels[s.name] or s.name, image = images[s.name], count = n, max = s.count }
        end
    end
    table.sort(out, function(x, y) return x.label < y.label end)
    return out
end

local function view(t, src)
    local labels, images = itemInfo()
    local mine, theirs = inv():GetTradeable(src), inv():GetTradeable(other(t, src))
    local carried = {}
    for _, s in ipairs(mine) do
        carried[#carried + 1] = { uid = s.uid, name = s.name, label = labels[s.name] or s.name, image = images[s.name], count = s.count,
            offered = t.offers[src][s.uid] or 0 }
    end
    table.sort(carried, function(x, y)
        if x.label ~= y.label then return x.label < y.label end
        return x.uid < y.uid
    end)
    local o = other(t, src)
    return {
        id = t.id,
        me = { name = nameOf(src), items = carried, offer = offerList(t, src, labels, images, mine), ready = t.ready[src] == true },
        them = { name = nameOf(o), offer = offerList(t, o, labels, images, theirs), ready = t.ready[o] == true },
        maxItems = M.config.maxItems,
    }
end

local function refresh(t, message)
    for _, src in ipairs({ t.a, t.b }) do
        local v = view(t, src)
        v.message = message
        TriggerClientEvent('wasteland:trade:client:view', src, v)
    end
end

local function close(t, message)
    if not trades[t.id] then return end
    trades[t.id] = nil
    for _, src in ipairs({ t.a, t.b }) do
        if tradeOf[src] == t.id then tradeOf[src] = nil end
        TriggerClientEvent('wasteland:trade:client:closed', src, message)
    end
end

-------------------------------------------------------------------------------
-- Asking, answering
-------------------------------------------------------------------------------

local function canTrade(src)
    if not loaded(src) then return false, 'You have no character loaded.' end
    if dead(src) then return false, 'You cannot trade while dead.' end
    if tradeOf[src] then return false, 'You are already trading.' end
    return true
end

local function request(src, target)
    if target == src then return end
    local ok, why = canTrade(src)
    if not ok then notice(src, why); return end
    if not GetPlayerName(tostring(target)) or not loaded(target) or dead(target) then notice(src, 'That player cannot trade right now.'); return end
    if tradeOf[target] then notice(src, nameOf(target) .. ' is already trading.'); return end
    if not near(src, target, M.config.distance) then notice(src, 'Get closer to trade.'); return end
    invites[target] = { from = src, at = GetGameTimer() }
    notice(src, 'You asked ' .. nameOf(target) .. ' to trade.')
    TriggerClientEvent('wasteland:trade:client:invite', target, { from = src, name = nameOf(src), seconds = M.config.inviteSeconds })
end

local function respond(src, from, accept)
    local inviteFrom = invites[src]
    if not inviteFrom or inviteFrom.from ~= from then return end
    invites[src] = nil
    if not accept then notice(from, nameOf(src) .. ' does not want to trade.'); return end
    if GetGameTimer() - inviteFrom.at > M.config.inviteSeconds * 1000 then notice(src, 'The trade request has expired.'); return end
    local ok1, why1 = canTrade(src)
    local ok2 = canTrade(from)
    if not ok1 then notice(src, why1); return end
    if not ok2 then notice(src, nameOf(from) .. ' cannot trade right now.'); return end
    if not near(src, from, M.config.distance + 1.0) then notice(src, 'Get closer to trade.'); notice(from, 'Get closer to trade.'); return end
    nextId = nextId + 1
    local t = { id = nextId, a = from, b = src, offers = { [from] = {}, [src] = {} }, ready = {} }
    trades[t.id], tradeOf[from], tradeOf[src] = t, t.id, t.id
    M.log:info('trade %d started: player %d and player %d', t.id, from, src)
    refresh(t)
end

-------------------------------------------------------------------------------
-- Offers and accepting
-------------------------------------------------------------------------------

local function count(map) local n = 0 for _ in pairs(map) do n = n + 1 end return n end

local function setOffer(src, uid, n)
    local t = trades[tradeOf[src]]
    if not t then return end
    local have = 0
    for _, s in ipairs(inv():GetTradeable(src)) do if s.uid == uid then have = s.count end end
    if have == 0 and n > 0 then refresh(t, 'You no longer have that.'); return end
    n = math.max(0, math.min(n, have))
    if n > 0 and not t.offers[src][uid] and count(t.offers[src]) >= M.config.maxItems then
        refresh(t, string.format('At most %d different items in one trade.', M.config.maxItems)); return
    end
    t.offers[src][uid] = n > 0 and n or nil
    t.ready = {} -- any change: both have to accept again
    refresh(t)
end

local function setReady(src, ready)
    local t = trades[tradeOf[src]]
    if not t then return end
    if clampOffer(t, t.a) or clampOffer(t, t.b) then
        t.ready = {}
        refresh(t, 'An offer changed: check it and accept again.')
        return
    end
    t.ready[src] = ready == true
    if not (t.ready[t.a] and t.ready[t.b]) then refresh(t); return end
    if not near(t.a, t.b, M.config.distance + 2.0) then t.ready = {}; refresh(t, 'Stand closer together to trade.'); return end
    local function list(src2)
        local out = {}
        for uid, n in pairs(t.offers[src2]) do out[#out + 1] = { uid = uid, count = n } end
        return out
    end
    local oa, ob = list(t.a), list(t.b)
    if #oa == 0 and #ob == 0 then t.ready = {}; refresh(t, 'Nothing is offered.'); return end
    local ok, err = inv():Trade(t.a, oa, t.b, ob)
    if not ok then
        t.ready = {}
        refresh(t, 'The trade did not go through: ' .. tostring(err) .. '.')
        return
    end
    M.log:info('trade %d done: player %d gave %d stacks, player %d gave %d stacks', t.id, t.a, #oa, t.b, #ob)
    TriggerEvent('wasteland:trade:done', t.a, oa, t.b, ob)
    close(t, 'Trade done.')
end

local function cancel(src, message)
    local t = trades[tradeOf[src]]
    if t then close(t, message or (nameOf(src) .. ' cancelled the trade.')) end
end

-- Moving apart, dying or leaving ends a trade.
local function watch(token)
    while runToken == token do
        Citizen.Wait(1000)
        if runToken ~= token then return end
        for _, t in pairs(trades) do
            if not GetPlayerName(tostring(t.a)) or not GetPlayerName(tostring(t.b)) then close(t, 'The other player left.')
            elseif dead(t.a) or dead(t.b) then close(t, 'The trade was cancelled.')
            elseif not near(t.a, t.b, M.config.cancelDistance) then close(t, 'You moved too far apart: the trade was cancelled.') end
        end
    end
end

AddEventHandler('wasteland:players:characterUnloaded', function(src) if M and M.active then cancel(src, 'The trade was cancelled.'); invites[src] = nil end end)
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src and M and M.active then cancel(src, 'The other player left.'); invites[src] = nil end
end)
-- Something changed in an inventory (moved, used, dropped): keep the window right.
AddEventHandler('wasteland:inventory:playerUpdated', function(src)
    if not (M and M.active) then return end
    local t = trades[tradeOf[src]]
    if not t then return end
    if clampOffer(t, src) then t.ready = {} end
    refresh(t)
end)

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

M = Wasteland.DefineModule({
    name = 'trade',
    version = '0.1.0',
    description = 'Player to player trading',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', inventory = '^0.1.0' },
    config = {
        file = 'trade.lua',
        optional = true,
        schema = { type = 'table', fields = {
            distance = { type = 'number', default = 3.0, min = 1, max = 20, description = 'How close to ask to trade' },
            cancelDistance = { type = 'number', default = 8.0, min = 2, max = 50, description = 'Further apart than this ends the trade' },
            inviteSeconds = { type = 'integer', default = 30, min = 5, max = 300 },
            maxItems = { type = 'integer', default = 40, min = 1, max = 200, description = 'Different stacks one side can offer' },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        trades, tradeOf, invites = {}, {}, {}
        local token = {}
        runToken = token
        Citizen.CreateThread(function() watch(token) end)
        return true
    end,
    onShutdown = function()
        runToken = nil
        for _, t in pairs(trades) do close(t, 'Trading was stopped.') end
    end,
})

local RATE = { burst = 10, perSecond = 5 }
local SRC = { type = 'integer', required = true, min = 1, max = 65535 }
local UID = { type = 'string', required = true, maxLength = 64, pattern = '^[%w%-_:]+$' }

M.netEvent('wasteland:trade:server:request', { args = { SRC }, rateLimit = { burst = 3, perSecond = 0.5 } }, function(src, target) request(src, target) end)
M.netEvent('wasteland:trade:server:respond', { args = { SRC, { type = 'boolean', required = true } }, rateLimit = RATE },
    function(src, from, accept) respond(src, from, accept) end)
M.netEvent('wasteland:trade:server:offer', { args = { UID, { type = 'integer', required = true, min = 0, max = 10000000 } }, rateLimit = RATE },
    function(src, uid, n) setOffer(src, uid, n) end)
M.netEvent('wasteland:trade:server:ready', { args = { { type = 'boolean', required = true } }, rateLimit = RATE },
    function(src, ready) setReady(src, ready) end)
M.netEvent('wasteland:trade:server:cancel', { rateLimit = RATE }, function(src) cancel(src) end)

--- IsTrading(source) -> boolean
exports('IsTrading', function(src) return tradeOf[tonumber(src)] ~= nil end)
