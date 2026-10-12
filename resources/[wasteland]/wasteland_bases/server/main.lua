-- wasteland_bases :: server/main.lua
-- Module "bases": players claim a spot with a base flag and build walls,
-- doors, gates, storage, a workbench, campfires, sleeping bags and rain
-- collectors on it. A base belongs to a character; everyone in the owner's
-- group shares it. Upkeep is paid from the flag's box; an unpaid base
-- decays and is removed. Everything is stored in the database.
--
-- The server owns every rule: the client only shows the preview and the
-- props, and sends where the player wants a piece (the server snaps it).

local Rules = WLB.Rules
local SQL = WLB.SQL
local M
local bases = {}       -- id -> { id, owner, x, y, z, heading, paidUntil, pieces = { [id] = piece }, count }
local pieceBase = {}   -- piece id -> base id
local doorsOpen = {}   -- piece id -> true
local lastMade = {}    -- rain collector piece id -> clock() of the last water
local lastRespawn = {} -- character id -> clock()
local demolishArm = {} -- source -> { piece, at }
local runToken = nil
local clockStart, timerStart = os.time(), 0

local function inv() return exports.wasteland_inventory end
local function players() return exports.wasteland_players end
local function notice(src, msg) TriggerClientEvent('wasteland:bases:client:notice', src, msg) end
local function running(res) return GetResourceState(res) == 'started' end

-- Unix seconds that follow the game timer (so a server that was asleep, or a
-- test, moves on with it).
local function clock() return clockStart + math.floor((GetGameTimer() - timerStart) / 1000) end

local function write(sql, params, what)
    Citizen.CreateThread(function()
        local _, err = WDB.update(sql, params)
        if err then M.log:warn('%s failed: %s', what, tostring(err)) end
    end)
end

local function characterOf(src)
    local ok, cid = pcall(function() return players():GetCharacterId(src) end)
    return ok and cid or nil
end

local function sourceOf(cid)
    local ok, src = pcall(function() return players():GetSourceByCharacterId(cid) end)
    return ok and src or nil
end

local function coordsOf(src)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

local function dist2(a, b) return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + ((a.z or 0) - (b.z or 0)) ^ 2 end

local function label(item)
    local d = inv():GetItemDefinition(item)
    return d and d.label or item
end

-------------------------------------------------------------------------------
-- Who may use a base: its owner and the owner's group
-------------------------------------------------------------------------------

local function sameGroup(a, b)
    if not running('wasteland_groups') then return false end
    local ok, same = pcall(function() return exports.wasteland_groups:SameGroup(a, b) end)
    return ok and same == true
end

local function hasAccess(cid, b) return cid ~= nil and b ~= nil and (b.owner == cid or sameGroup(cid, b.owner)) end

local function baseOfCharacter(cid)
    if not cid then return nil end
    local best = nil
    for _, b in pairs(bases) do
        if b.owner == cid then return b end
        if not best and hasAccess(cid, b) then best = b end
    end
    return best
end

local function baseAt(x, y)
    for _, b in pairs(bases) do
        if Rules.inClaim(b, x, y, M.config.claimRadius) then return b end
    end
    return nil
end

-------------------------------------------------------------------------------
-- What clients get: the pieces config, every base, and which are theirs
-------------------------------------------------------------------------------

local function clientConfig()
    local c = M.config
    return { grid = c.grid, wallHeight = c.wallHeight, claimRadius = c.claimRadius, streamDistance = c.streamDistance,
        solidModel = c.solidModel, flag = c.flag, pieces = c.pieces, command = c.command }
end

local function pieceInfo(p) return { id = p.id, kind = p.kind, x = p.x, y = p.y, z = p.z, heading = p.heading, open = doorsOpen[p.id] == true } end

local function baseInfo(b)
    local list = {}
    for _, p in pairs(b.pieces) do list[#list + 1] = pieceInfo(p) end
    return { id = b.id, x = b.x, y = b.y, z = b.z, heading = b.heading, pieces = list }
end

local function accessList(cid)
    local out = {}
    for id, b in pairs(bases) do if hasAccess(cid, b) then out[#out + 1] = id end end
    table.sort(out)
    return out
end

local function sendAccess(src)
    local cid = characterOf(src)
    if cid then TriggerClientEvent('wasteland:bases:client:access', src, accessList(cid)) end
end

local function sendAccessAll()
    local ok, list = pcall(function() return players():GetOnlineCharacters() end)
    if not ok then return end
    for _, c in ipairs(list or {}) do sendAccess(c.source) end
end

local function sendAll(target)
    local list = {}
    for _, b in pairs(bases) do list[#list + 1] = baseInfo(b) end
    TriggerClientEvent('wasteland:bases:client:all', target, { config = clientConfig(), bases = list })
end

-------------------------------------------------------------------------------
-- Stashes (storage, rain collectors, the upkeep box)
-------------------------------------------------------------------------------

local function stashName(p) return 'base_piece_' .. p.id end
local function boxName(b) return 'base_upkeep_' .. b.id end

local function stashOpts(def, coords)
    return { label = def.label, width = def.stash.width, height = def.stash.height, maxWeight = def.stash.maxWeight, coords = coords, reach = 4.0 }
end

local function boxOpts(b)
    local box = M.config.upkeep.box
    return { label = 'Upkeep box', width = box.width, height = box.height, maxWeight = box.maxWeight, coords = { x = b.x, y = b.y, z = b.z }, reach = 4.0 }
end

local function stashEmpty(name, opts)
    local id = inv():EnsureStash(name, opts)
    if not id then return true end
    local snap = inv():GetInventory(id)
    return not snap or #(snap.items or {}) == 0
end

-------------------------------------------------------------------------------
-- The base screen
-------------------------------------------------------------------------------

local function upkeepInfo(b)
    local u = M.config.upkeep
    local stock = 0
    local id = inv():EnsureStash(boxName(b), boxOpts(b))
    if id then stock = inv():GetItemCount(id, u.item) or 0 end
    local perDay = Rules.upkeepPerDay(u, b.count)
    local left = b.paidUntil - clock()
    return { item = label(u.item), perDay = perDay, stock = stock, paidHours = math.max(0, math.floor(left / 3600)),
        decaying = left < 0, removeHours = left < 0 and math.max(0, math.floor((left + u.decayHours * 3600) / 3600)) or nil,
        coveredDays = perDay > 0 and math.floor(stock / perDay) or 0 }
end

-- Runs in a thread (stash loading may read the database).
local function view(src)
    local cid = characterOf(src)
    if not cid then return nil end
    local countOf = function(item) return inv():GetItemCount(src, item) or 0 end
    local out = { claimRadius = M.config.claimRadius, maxPieces = M.config.maxPieces, flags = countOf('base_flag') }
    local b = baseOfCharacter(cid)
    if b then
        local here = coordsOf(src)
        local kinds = {}
        for _, p in pairs(b.pieces) do kinds[p.kind] = (kinds[p.kind] or 0) + 1 end
        local ownerName = 'you'
        if b.owner ~= cid then
            local ok, c = pcall(function() return players():GetCharacter(sourceOf(b.owner)) end)
            ownerName = (ok and c) and (c.firstName .. ' ' .. c.lastName) or 'your group'
        end
        out.base = { id = b.id, owner = b.owner == cid, ownerName = ownerName, pieces = b.count,
            inClaim = here ~= nil and Rules.inClaim(b, here.x, here.y, M.config.claimRadius),
            distance = here and math.floor(math.sqrt((here.x - b.x) ^ 2 + (here.y - b.y) ^ 2)) or nil,
            upkeep = upkeepInfo(b) }
        local catalog = {}
        for kind, def in pairs(M.config.pieces) do
            local cost = {}
            for _, c in ipairs(def.cost) do cost[#cost + 1] = { name = c.name, label = label(c.name), count = c.count, have = countOf(c.name) } end
            catalog[#catalog + 1] = { kind = kind, label = def.label, slot = def.slot, family = def.family, tier = def.tier or 0,
                cost = cost, built = kinds[kind] or 0, max = def.max, canPay = #Rules.missing(def.cost, countOf) == 0 }
        end
        table.sort(catalog, function(x, y)
            if x.slot ~= y.slot then return x.slot == 'edge' end
            if (x.family or '') ~= (y.family or '') then return (x.family or '') > (y.family or '') end
            if x.tier ~= y.tier then return x.tier < y.tier end
            return x.label < y.label
        end)
        out.catalog = catalog
    end
    return out
end

local function sendView(src)
    Citizen.CreateThread(function()
        local v = view(src)
        if v then TriggerClientEvent('wasteland:bases:client:view', src, v) end
    end)
end

-------------------------------------------------------------------------------
-- Claiming
-------------------------------------------------------------------------------

local function campList()
    if not running('wasteland_camps') then return {} end
    local ok, camps = pcall(function() return exports.wasteland_camps:GetCamps() end)
    local out = {}
    for _, c in ipairs(ok and camps or {}) do
        out[#out + 1] = { x = c.coords.x, y = c.coords.y, radius = c.radius, label = c.label }
    end
    return out
end

local function claimCheck(x, y)
    local others = {}
    for _, b in pairs(bases) do others[#others + 1] = { x = b.x, y = b.y } end
    return Rules.claimAllowed(x, y, others, campList(), M.config)
end

local function placeFlag(src, x, y, z, heading)
    local cid = characterOf(src)
    if not cid then return end
    if baseOfCharacter(cid) then notice(src, 'You (or your group) already have a base.'); return end
    local here = coordsOf(src)
    if not here or dist2(here, { x = x, y = y, z = z }) > 8.0 ^ 2 then notice(src, 'Stand where you place the flag.'); return end
    local ok, why = claimCheck(x, y)
    if not ok then notice(src, why); return end
    if (inv():GetItemCount(src, 'base_flag') or 0) < 1 then notice(src, 'You need a base flag.'); return end
    local removed = inv():RemoveItem(src, 'base_flag', 1)
    if not removed then notice(src, 'You need a base flag.'); return end
    heading = Rules.heading(heading)
    local paidUntil = clock() + M.config.upkeep.firstDays * 86400
    local id, err = WDB.insert(SQL.insertBase, { cid, x, y, z, heading, paidUntil, os.time() })
    if not id then
        inv():AddItem(src, 'base_flag', 1)
        notice(src, 'The base could not be saved. Try again.')
        M.log:warn('claim: %s', tostring(err))
        return
    end
    local b = { id = id, owner = cid, x = x, y = y, z = z, heading = heading, paidUntil = paidUntil, pieces = {}, count = 0 }
    bases[id] = b
    M.log:info('player %d (character %d) claimed base %d at %.1f, %.1f, %.1f', src, cid, id, x, y, z)
    notice(src, string.format('Base claimed. Build within %d m of the flag: /%s (F7). Keep %s in the flag\'s upkeep box.',
        math.floor(M.config.claimRadius), M.config.command, label(M.config.upkeep.item)))
    TriggerClientEvent('wasteland:bases:client:base', -1, baseInfo(b))
    sendAccessAll()
    TriggerEvent('wasteland:bases:claimed', id, cid)
    sendView(src)
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function pay(src, cost)
    local taken = {}
    for _, c in ipairs(cost) do
        local ok = inv():RemoveItem(src, c.name, c.count)
        if not ok then
            for _, t in ipairs(taken) do inv():AddItem(src, t.name, t.count) end
            return false
        end
        taken[#taken + 1] = c
    end
    return true
end

-- Give items to a player; what does not fit is dropped next to them.
local function give(src, items)
    local rest = {}
    for _, it in ipairs(items) do
        if not inv():AddItem(src, it.name, it.count) then rest[#rest + 1] = it end
    end
    if #rest > 0 then
        local c = coordsOf(src)
        if c then inv():CreateLootDrop(c, rest, { label = 'Materials' }) end
        notice(src, 'Some materials did not fit and were dropped at your feet.')
    end
end

local function countKind(b, kind)
    local n = 0
    for _, p in pairs(b.pieces) do if p.kind == kind then n = n + 1 end end
    return n
end

local function build(src, kind, x, y, z, turn)
    local cid = characterOf(src)
    local def = M.config.pieces[kind]
    if not cid or not def then return end
    local b = baseAt(x, y)
    if not b or not hasAccess(cid, b) then notice(src, 'You can only build inside your own base\'s claim.'); return end
    local here = coordsOf(src)
    if not here or dist2(here, { x = x, y = y, z = z }) > 12.0 ^ 2 then notice(src, 'Too far away.'); return end
    if math.abs(z - b.z) > 25.0 then notice(src, 'Too far above or below the flag.'); return end

    local heading, key, replace = Rules.heading(turn), nil, nil
    if def.slot == 'edge' then
        local s = Rules.snapEdge(b, x, y, M.config.grid, turn)
        if not Rules.inClaim(b, s.x, s.y, M.config.claimRadius) then notice(src, 'That is outside the claim.'); return end
        x, y, heading, key = s.x, s.y, s.heading, s.key
        for _, p in pairs(b.pieces) do
            if p.key == key then
                local old = M.config.pieces[p.kind]
                if old and old.family == def.family and (def.tier or 0) > (old.tier or 0) then
                    replace = p
                else
                    notice(src, 'Something is already built there.'); return
                end
            end
        end
    else
        if not Rules.inClaim(b, x, y, M.config.claimRadius) then notice(src, 'That is outside the claim.'); return end
        for _, p in pairs(b.pieces) do
            if not p.key and (p.x - x) ^ 2 + (p.y - y) ^ 2 < 0.8 ^ 2 then notice(src, 'Too close to another piece.'); return end
        end
        if (b.x - x) ^ 2 + (b.y - y) ^ 2 < 1.2 ^ 2 then notice(src, 'Too close to the flag.'); return end
    end

    if not replace then
        if b.count >= M.config.maxPieces then notice(src, string.format('The base has the most pieces it can (%d).', M.config.maxPieces)); return end
        if def.max and countKind(b, kind) >= def.max then notice(src, string.format('You can have %d %s in a base.', def.max, def.label:lower())); return end
    end
    local missing = Rules.missing(def.cost, function(item) return inv():GetItemCount(src, item) or 0 end)
    if #missing > 0 then
        notice(src, string.format('You need %d x %s (you have %d).', missing[1].need, label(missing[1].name), missing[1].have))
        return
    end
    if not pay(src, def.cost) then notice(src, 'You do not have the materials.'); return end

    if replace then
        replace.kind, replace.heading = kind, heading
        write(SQL.upgradePiece, { kind, heading, replace.id }, 'upgrading piece ' .. replace.id)
        doorsOpen[replace.id] = nil
        TriggerClientEvent('wasteland:bases:client:piece', -1, b.id, pieceInfo(replace))
        notice(src, def.label .. ' built.')
        return
    end
    local id, err = WDB.insert(SQL.insertPiece, { b.id, kind, x, y, z, heading, key, cid, os.time() })
    if not id then
        give(src, def.cost)
        notice(src, 'The piece could not be saved. Try again.')
        M.log:warn('build: %s', tostring(err))
        return
    end
    local p = { id = id, base = b.id, kind = kind, x = x, y = y, z = z, heading = heading, key = key, builder = cid }
    b.pieces[id], b.count, pieceBase[id] = p, b.count + 1, b.id
    TriggerClientEvent('wasteland:bases:client:piece', -1, b.id, pieceInfo(p))
    TriggerEvent('wasteland:bases:built', b.id, id, kind, cid)
    notice(src, def.label .. ' built.')
end

local function pieceFor(src, pieceId, reach)
    local cid = characterOf(src)
    local b = bases[pieceBase[pieceId]]
    local p = b and b.pieces[pieceId]
    if not p then return nil end
    if not hasAccess(cid, b) then notice(src, 'This is not your base.'); return nil end
    local here = coordsOf(src)
    if not here or dist2(here, p) > reach * reach then notice(src, 'Too far away.'); return nil end
    return p, b, cid
end

local function removePiece(b, p)
    b.pieces[p.id], b.count, pieceBase[p.id] = nil, b.count - 1, nil
    doorsOpen[p.id], lastMade[p.id] = nil, nil
    if M.config.pieces[p.kind] and M.config.pieces[p.kind].stash then pcall(function() inv():DeleteStash(stashName(p)) end) end
    write(SQL.deletePiece, { p.id }, 'removing piece ' .. p.id)
    TriggerClientEvent('wasteland:bases:client:removed', -1, b.id, p.id)
end

-- Demolish needs a second request within 5 s (the first one warns).
local function demolish(src, pieceId)
    local p, b = pieceFor(src, pieceId, 6.0)
    if not p then return end
    local def = M.config.pieces[p.kind]
    if def and def.stash and not stashEmpty(stashName(p), stashOpts(def, p)) then notice(src, 'Empty it first.'); return end
    local arm = demolishArm[src]
    if not arm or arm.piece ~= pieceId or GetGameTimer() - arm.at > 5000 then
        demolishArm[src] = { piece = pieceId, at = GetGameTimer() }
        notice(src, 'Demolish ' .. (def and def.label or 'this') .. '? Choose Demolish again to confirm.')
        return
    end
    demolishArm[src] = nil
    removePiece(b, p)
    if def then give(src, Rules.refund(def.cost, M.config.refund)) end
    notice(src, (def and def.label or 'Piece') .. ' demolished.')
end

local function removeBase(b, why)
    for _, p in pairs(b.pieces) do
        local def = M.config.pieces[p.kind]
        if def and def.stash then pcall(function() inv():DeleteStash(stashName(p)) end) end
        pieceBase[p.id], doorsOpen[p.id], lastMade[p.id] = nil, nil, nil
    end
    pcall(function() inv():DeleteStash(boxName(b)) end)
    bases[b.id] = nil
    write(SQL.deletePieces, { b.id }, 'removing base ' .. b.id)
    write(SQL.deleteBase, { b.id }, 'removing base ' .. b.id)
    TriggerClientEvent('wasteland:bases:client:baseRemoved', -1, b.id)
    M.log:info('base %d removed (%s)', b.id, why)
    TriggerEvent('wasteland:bases:removed', b.id, why)
    sendAccessAll()
end

local function abandon(src)
    local cid = characterOf(src)
    local b = baseOfCharacter(cid)
    if not b then return end
    if b.owner ~= cid then notice(src, 'Only the player who placed the flag can remove the base.'); return end
    removeBase(b, 'removed by its owner')
    notice(src, 'Your base was removed.')
    sendView(src)
end

local function toggleDoor(src, pieceId)
    local p = pieceFor(src, pieceId, 4.0)
    if not p then return end
    local def = M.config.pieces[p.kind]
    if not def or not def.door then return end
    doorsOpen[p.id] = not doorsOpen[p.id] or nil
    TriggerClientEvent('wasteland:bases:client:door', -1, p.id, doorsOpen[p.id] == true)
end

local function openStorage(src, pieceId)
    local p = pieceFor(src, pieceId, 4.0)
    if not p then return end
    local def = M.config.pieces[p.kind]
    if not def or not def.stash then return end
    local opts = stashOpts(def, { x = p.x, y = p.y, z = p.z })
    opts.open = true
    inv():OpenStash(src, stashName(p), opts)
end

local function openBox(src, baseId)
    local cid = characterOf(src)
    local b = bases[baseId]
    if not b or not hasAccess(cid, b) then notice(src, 'This is not your base.'); return end
    local opts = boxOpts(b)
    opts.open = true
    inv():OpenStash(src, boxName(b), opts)
end

-------------------------------------------------------------------------------
-- Using the flag item
-------------------------------------------------------------------------------

local function useFlag(src)
    local cid = characterOf(src)
    if not cid then return false end
    if baseOfCharacter(cid) then return false, 'You (or your group) already have a base.' end
    local here = coordsOf(src)
    if here then
        local ok, why = claimCheck(here.x, here.y)
        if not ok then return false, why end
    end
    TriggerClientEvent('wasteland:bases:client:placeFlag', src)
    return 0
end

-------------------------------------------------------------------------------
-- Upkeep, decay and rain collectors (once a minute)
-------------------------------------------------------------------------------

local function upkeepTick()
    local now = clock()
    local u = M.config.upkeep
    for _, b in pairs(bases) do
        local state = Rules.upkeepState(b.paidUntil, now, u.decayHours)
        if state == 'gone' then
            removeBase(b, 'upkeep unpaid')
            local s = sourceOf(b.owner)
            if s then notice(s, 'Your base was not kept up and has fallen apart.') end
        elseif state == 'due' then
            local need = Rules.upkeepPerDay(u, b.count)
            local id = inv():EnsureStash(boxName(b), boxOpts(b))
            if id and (inv():GetItemCount(id, u.item) or 0) >= need and inv():RemoveItem(id, u.item, need) then
                b.paidUntil = b.paidUntil + 86400
                write(SQL.paidUntil, { b.paidUntil, b.id }, 'upkeep of base ' .. b.id)
            elseif not b.warned then
                b.warned = true
                local s = sourceOf(b.owner)
                if s then notice(s, string.format('Your base needs upkeep: put %d x %s in the flag\'s box or it falls apart.', need, label(u.item))) end
            end
            if b.paidUntil > now then b.warned = nil end
        end
    end
    -- rain collectors
    for _, b in pairs(bases) do
        for _, p in pairs(b.pieces) do
            local def = M.config.pieces[p.kind]
            local prod = def and def.produces
            if prod then
                lastMade[p.id] = lastMade[p.id] or now
                if now - lastMade[p.id] >= prod.everyMinutes * 60 then
                    lastMade[p.id] = now
                    local id = inv():EnsureStash(stashName(p), stashOpts(def, p))
                    if id and (inv():GetItemCount(id, prod.item) or 0) < prod.max then inv():AddItem(id, prod.item, 1) end
                end
            end
        end
    end
end

local function loop(token)
    while runToken == token do
        Citizen.Wait(60000)
        if runToken ~= token then return end
        local ok, err = pcall(upkeepTick)
        if not ok then M.log:warn('upkeep: %s', tostring(err)) end
    end
end

-------------------------------------------------------------------------------
-- What other modules ask: campfire warmth, sleeping bag respawns, workbench
-------------------------------------------------------------------------------

local function warmthAt(src)
    local here = coordsOf(src)
    if not here then return 0 end
    local best = 0
    for _, b in pairs(bases) do
        if (b.x - here.x) ^ 2 + (b.y - here.y) ^ 2 < (M.config.claimRadius + 20) ^ 2 then
            for _, p in pairs(b.pieces) do
                local def = M.config.pieces[p.kind]
                if def and def.warmth and dist2(here, p) <= (def.warmthRadius or 5) ^ 2 then best = math.max(best, def.warmth) end
            end
        end
    end
    return best
end

local function respawnPoint(src, cid)
    cid = cid or characterOf(src)
    local b = baseOfCharacter(cid)
    if not b then return nil end
    if lastRespawn[cid] and clock() - lastRespawn[cid] < M.config.respawnCooldownMinutes * 60 then return nil end
    local pick = nil
    for _, p in pairs(b.pieces) do
        local def = M.config.pieces[p.kind]
        if def and def.respawn and (not pick or p.builder == cid and pick.builder ~= cid) then pick = p end
    end
    if not pick then return nil end
    lastRespawn[cid] = clock()
    return { x = pick.x, y = pick.y, z = pick.z + 0.5, heading = pick.heading, label = 'your sleeping bag' }
end

local function atStation(src, station)
    local cid = characterOf(src)
    local here = coordsOf(src)
    if not cid or not here then return false end
    for _, b in pairs(bases) do
        if hasAccess(cid, b) then
            for _, p in pairs(b.pieces) do
                local def = M.config.pieces[p.kind]
                if def and def.station == station and dist2(here, p) <= 3.5 ^ 2 then return true end
            end
        end
    end
    return false
end

local function registerHooks()
    if running('wasteland_survival') then
        pcall(function() exports.wasteland_survival:RegisterWarmthSource('bases', warmthAt) end)
        pcall(function() exports.wasteland_survival:RegisterRespawnPoint('bases', respawnPoint) end)
    end
    if running('wasteland_crafting') then
        pcall(function() exports.wasteland_crafting:RegisterStation('workbench', 'Workbench', function(src) return atStation(src, 'workbench') end) end)
    end
end

AddEventHandler('onResourceStart', function(res)
    if not (M and M.active) then return end
    if res == 'wasteland_survival' or res == 'wasteland_crafting' then Citizen.SetTimeout(1000, registerHooks) end
end)

AddEventHandler('wasteland:players:characterLoaded', function(src)
    if not (M and M.active) then return end
    sendAll(src)
    sendAccess(src)
end)
AddEventHandler('wasteland:players:characterUnloaded', function(src) demolishArm[src] = nil end)
for _, ev in ipairs({ 'wasteland:groups:joined', 'wasteland:groups:left', 'wasteland:groups:disbanded', 'wasteland:groups:created' }) do
    AddEventHandler(ev, function() if M and M.active then Citizen.SetTimeout(200, sendAccessAll) end end)
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local NUM = { type = 'number', default = 0.0 }
local STACK = { type = 'table', fields = {
    name = { type = 'string', required = true, pattern = '^[%w_]+$' },
    count = { type = 'integer', required = true, min = 1, max = 1000 },
} }
local PART = { type = 'table', fields = {
    model = { type = 'string', required = true, minLength = 1, maxLength = 64 },
    x = NUM, y = NUM, z = NUM, rx = NUM, ry = NUM, rz = NUM,
    door = { type = 'boolean', default = false },
} }
local GRID = { type = 'table', nullable = true, fields = {
    width = { type = 'integer', required = true, min = 1, max = 20 },
    height = { type = 'integer', required = true, min = 1, max = 20 },
    maxWeight = { type = 'number', default = 100, min = 1, max = 10000 },
} }

M = Wasteland.DefineModule({
    name = 'bases',
    version = '0.1.0',
    description = 'Base building: claim with a flag, walls, doors, storage, upkeep',
    core = '^1.1.0',
    dependencies = { database = '^0.1.0', players = '^0.1.0', inventory = '^0.1.0' },
    optionalDependencies = { groups = '^0.1.0', survival = '^0.1.0', crafting = '^0.1.0', camps = '^0.1.0' },
    async = true,
    config = {
        file = 'bases.lua',
        optional = true,
        schema = { type = 'table', fields = {
            command = { type = 'string', default = 'base', pattern = '^[a-z][a-z0-9_]*$' },
            claimRadius = { type = 'number', default = 30.0, min = 5, max = 200 },
            grid = { type = 'number', default = 3.0, min = 1, max = 10 },
            wallHeight = { type = 'number', default = 3.0, min = 1, max = 10 },
            campDistance = { type = 'number', default = 150.0, min = 0, max = 5000 },
            baseDistance = { type = 'number', default = 150.0, min = 0, max = 5000 },
            maxPieces = { type = 'integer', default = 60, min = 1, max = 1000 },
            refund = { type = 'number', default = 0.5, min = 0, max = 1 },
            streamDistance = { type = 'number', default = 150.0, min = 30, max = 1000 },
            respawnCooldownMinutes = { type = 'number', default = 5, min = 0, max = 1440 },
            solidModel = { type = 'string', default = 'prop_cons_plyboard_01' },
            upkeep = { type = 'table', fields = {
                item = { type = 'string', default = 'scrap_metal', pattern = '^[%w_]+$' },
                base = { type = 'integer', default = 1, min = 0, max = 1000 },
                perPieces = { type = 'integer', default = 10, min = 1, max = 1000 },
                perBlock = { type = 'integer', default = 1, min = 0, max = 1000 },
                decayHours = { type = 'number', default = 72, min = 0, max = 10000 },
                firstDays = { type = 'number', default = 3, min = 0, max = 365 },
                box = { type = 'table', fields = {
                    width = { type = 'integer', default = 4, min = 1, max = 20 },
                    height = { type = 'integer', default = 3, min = 1, max = 20 },
                    maxWeight = { type = 'number', default = 60, min = 1, max = 10000 },
                } },
            } },
            flag = { type = 'table', fields = {
                label = { type = 'string', default = 'Base flag' },
                parts = { type = 'array', default = { { model = 'prop_flagpole_1a' } }, items = PART },
            } },
            pieces = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%a][%w_]*$' }, values = { type = 'table', fields = {
                label = { type = 'string', required = true, minLength = 1, maxLength = 48 },
                slot = { type = 'enum', values = { 'edge', 'free' }, default = 'free' },
                family = { type = 'string', pattern = '^[%w_]+$' },
                tier = { type = 'integer', default = 1, min = 0, max = 100 },
                max = { type = 'integer', min = 1, max = 1000 },
                cost = { type = 'array', required = true, minItems = 1, items = STACK },
                parts = { type = 'array', required = true, minItems = 1, items = PART },
                door = { type = 'table', nullable = true, fields = {
                    hinge = { type = 'number', default = -0.6 },
                    width = { type = 'number', default = 1.2, min = 0.3, max = 10 },
                    height = { type = 'number', default = 2.2, min = 0.5, max = 10 },
                } },
                stash = GRID,
                station = { type = 'string', pattern = '^[%w_]+$' },
                warmth = { type = 'number', min = 0, max = 50 },
                warmthRadius = { type = 'number', default = 5.0, min = 0.5, max = 50 },
                respawn = { type = 'boolean', default = false },
                produces = { type = 'table', nullable = true, fields = {
                    item = { type = 'string', required = true, pattern = '^[%w_]+$' },
                    everyMinutes = { type = 'number', default = 30, min = 1, max = 10000 },
                    max = { type = 'integer', default = 4, min = 1, max = 1000 },
                } },
            } } },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        local function known(item) return inv():GetItemDefinition(item) ~= nil end
        if not known('base_flag') then return false, 'inventory.lua has no "base_flag" item' end
        if not known(M.config.upkeep.item) then return false, string.format('bases.lua: upkeep item "%s" is not in inventory.lua items', M.config.upkeep.item) end
        for kind, def in pairs(M.config.pieces) do
            for _, c in ipairs(def.cost) do
                if not known(c.name) then return false, string.format('bases.lua: piece "%s" costs "%s", which is not in inventory.lua items', kind, c.name) end
            end
            if def.produces and not known(def.produces.item) then
                return false, string.format('bases.lua: piece "%s" produces "%s", which is not in inventory.lua items', kind, def.produces.item)
            end
            if def.slot == 'edge' and not def.family then return false, string.format('bases.lua: wall piece "%s" needs a family', kind) end
            if def.produces and not def.stash then return false, string.format('bases.lua: piece "%s" produces items but has no stash', kind) end
        end
        bases, pieceBase, doorsOpen, lastMade, lastRespawn, demolishArm = {}, {}, {}, {}, {}, {}
        clockStart, timerStart = os.time(), GetGameTimer()
        local token = {}
        runToken = token
        Citizen.CreateThread(function()
            local ok, err = WDB.migrate('bases', WLB.MIGRATIONS)
            if runToken ~= token then return end
            if not ok then return M.fail('database migrations failed: ' .. tostring(err)) end
            local rows, qerr = WDB.query(SQL.selectBases, {})
            local pieces, perr = WDB.query(SQL.selectPieces, {})
            if runToken ~= token then return end
            if not rows or not pieces then return M.fail('could not load bases: ' .. tostring(qerr or perr)) end
            for _, r in ipairs(rows) do
                bases[r.id] = { id = r.id, owner = r.owner_id, x = r.x, y = r.y, z = r.z, heading = r.heading, paidUntil = r.paid_until, pieces = {}, count = 0 }
            end
            local dropped = 0
            for _, r in ipairs(pieces) do
                local b = bases[r.base_id]
                if b and M.config.pieces[r.kind] then
                    b.pieces[r.id] = { id = r.id, base = b.id, kind = r.kind, x = r.x, y = r.y, z = r.z, heading = r.heading,
                        key = r.slot_key, builder = r.builder_id }
                    b.count, pieceBase[r.id] = b.count + 1, b.id
                else
                    dropped = dropped + 1
                end
            end
            if dropped > 0 then M.log:warn('%d stored pieces were skipped (their base or kind is gone from bases.lua)', dropped) end
            local n = 0
            for _ in pairs(bases) do n = n + 1 end
            M.log:info('%d bases loaded', n)
            local ok2, okFlag = pcall(function() return inv():RegisterUsable('base_flag', useFlag) end)
            if not ok2 or not okFlag then M.log:warn('could not register the base flag item') end
            registerHooks()
            sendAll(-1)
            sendAccessAll()
            Citizen.CreateThread(function() loop(token) end)
            M.ready()
        end)
        RegisterCommand('baseadmin', function(source, args)
            local src = tonumber(source)
            if src ~= 0 and not IsPlayerAceAllowed(tostring(src), 'wasteland.admin') then return end
            if args[1] == 'remove' and src ~= 0 then
                local here = coordsOf(src)
                local nearest, best = nil, 50.0 ^ 2
                for _, b in pairs(bases) do
                    local d = (b.x - here.x) ^ 2 + (b.y - here.y) ^ 2
                    if d < best then nearest, best = b, d end
                end
                if not nearest then notice(src, 'No base within 50 m.'); return end
                removeBase(nearest, 'removed by admin ' .. src)
                notice(src, 'Base ' .. nearest.id .. ' removed.')
            elseif args[1] == 'preview' and src ~= 0 then
                TriggerClientEvent('wasteland:bases:client:preview', src)
            else
                local n = 0
                for _ in pairs(bases) do n = n + 1 end
                local msg = string.format('%d bases. /baseadmin remove (nearest within 50 m) | /baseadmin preview (show every piece)', n)
                if src == 0 then print(msg) else notice(src, msg) end
            end
        end, false)
        return true
    end,
    onShutdown = function()
        runToken = nil
        TriggerClientEvent('wasteland:bases:client:all', -1, { bases = {} })
    end,
})

local RATE = { burst = 6, perSecond = 2 }
local COORD = { type = 'number', required = true, min = -20000, max = 20000 }
local HEADING = { type = 'number', required = true, min = -720, max = 720 }
local ID = { type = 'integer', required = true, min = 1 }

M.netEvent('wasteland:bases:server:sync', { rateLimit = { burst = 2, perSecond = 0.2 } }, function(src) sendAll(src); sendAccess(src) end)
M.netEvent('wasteland:bases:server:view', { rateLimit = RATE }, function(src) sendView(src) end)
M.netEvent('wasteland:bases:server:placeFlag', { args = { COORD, COORD, COORD, HEADING }, rateLimit = { burst = 4, perSecond = 1 } },
    function(src, x, y, z, h) Citizen.CreateThread(function() placeFlag(src, x, y, z, h) end) end)
M.netEvent('wasteland:bases:server:build', {
    args = { { type = 'string', required = true, pattern = '^[%a][%w_]*$', maxLength = 32 }, COORD, COORD, COORD, HEADING },
    rateLimit = { burst = 8, perSecond = 2 },
}, function(src, kind, x, y, z, h) Citizen.CreateThread(function() build(src, kind, x, y, z, h) end) end)
M.netEvent('wasteland:bases:server:demolish', { args = { ID }, rateLimit = RATE }, function(src, id) Citizen.CreateThread(function() demolish(src, id) end) end)
M.netEvent('wasteland:bases:server:door', { args = { ID }, rateLimit = { burst = 6, perSecond = 3 } }, function(src, id) toggleDoor(src, id) end)
M.netEvent('wasteland:bases:server:open', { args = { ID }, rateLimit = RATE }, function(src, id) openStorage(src, id) end)
M.netEvent('wasteland:bases:server:box', { args = { ID }, rateLimit = RATE }, function(src, id) openBox(src, id) end)
M.netEvent('wasteland:bases:server:abandon', { rateLimit = { burst = 2, perSecond = 0.2 } }, function(src) abandon(src) end)

-------------------------------------------------------------------------------
-- Exports (bases api 0.1)
-------------------------------------------------------------------------------

--- GetBaseAt(coords) -> { id, owner } | nil   (the claim the point is in)
exports('GetBaseAt', function(coords)
    if not (M and M.active) or type(coords) ~= 'table' then return nil end
    local b = baseAt(coords.x, coords.y)
    return b and { id = b.id, owner = b.owner } or nil
end)

--- GetBaseOf(characterId) -> { id, owner, x, y, z, pieces } | nil   (own or the group's)
exports('GetBaseOf', function(cid)
    if not (M and M.active) then return nil end
    local b = baseOfCharacter(tonumber(cid))
    return b and { id = b.id, owner = b.owner, x = b.x, y = b.y, z = b.z, pieces = b.count } or nil
end)
