-- wasteland_basebuilding :: server/main.lua
-- Module "basebuilding" (ported from sbb-basebuilding to Wasteland Core):
-- tool cupboards claim land; pieces snap together; doors, storage, upgrades,
-- repairs, upkeep with decay, raiding (explosions, melee on wood, lockpicks).
-- Access: the cupboard's owner, players they authorize, and the owner's
-- group. Every rule is checked here; clients only show and ask.
-- The props come from wasteland_buildprops (free, included) by default, or
-- any props pack (basebuilding.lua propsResource and each piece's model).

local Rules = WLBB.Rules
local SQL = WLBB.SQL
local M
local cupboards = {}   -- id -> { id, owner, coords, heading, radius, health, max_health, auth = { [characterId] = name } }
local props = {}       -- id -> { id, cupboard_id, category, piece, model, coords, heading, is_open, health, max_health, material }
local carry = {}       -- cupboard id -> { material = owed fraction }
local meleeCooldown, lockCooldown, picking = {}, {}, {}
local adminBuild = {} -- source -> true: /adminbuild (admins build, upgrade and repair for free)
local PoweredAt       -- (coords) -> boolean, set with the power code below
local snapRules = Rules.snapRules()
local runToken = nil

local function inv() return exports.wasteland_inventory end
local function players() return exports.wasteland_players end
local function now() return GetGameTimer() end
local zombieBarricades   -- function, below (damage section)
local zombieNotice = {}   -- cupboard id -> last "zombies at your base" notice
local function notice(src, msg) if src then TriggerClientEvent('wasteland:basebuilding:client:notice', src, msg) end end

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

local function nameOf(src)
    local ok, c = pcall(function() return players():GetCharacter(src) end)
    if ok and c then return c.firstName .. ' ' .. c.lastName end
    return GetPlayerName(tostring(src)) or ('Player ' .. tostring(src))
end

local function playerCoords(src)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

local function near(src, coords, reach)
    local p = playerCoords(src)
    return p ~= nil and Rules.dist(p, coords) <= reach
end

local function label(item)
    local d = inv():GetItemDefinition(item)
    return d and d.label or item
end

-- Admins: the same as the F10 admin panel (wasteland_admin), else its ACE.
local function isAdmin(src)
    if GetResourceState('wasteland_admin') == 'started' then
        local ok, yes = pcall(function() return exports.wasteland_admin:IsAdmin(src) end)
        if ok then return yes == true end
    end
    local allowed = IsPlayerAceAllowed(tostring(src), 'wasteland.admin')
    return allowed == true or allowed == 1
end

local function countOf(src) return function(item) return inv():GetItemCount(src, item) or 0 end end

local function pay(src, cost)
    if adminBuild[src] then return true end
    local taken = {}
    for item, n in pairs(cost or {}) do
        if not inv():RemoveItem(src, item, n) then
            for i, m in pairs(taken) do inv():AddItem(src, i, m) end
            return false
        end
        taken[item] = n
    end
    return true
end

-- Give items; what does not fit is dropped at the player's feet.
local function give(src, items)
    local rest = {}
    for item, n in pairs(items) do
        if n > 0 and not inv():AddItem(src, item, n) then rest[#rest + 1] = { name = item, count = n } end
    end
    if #rest > 0 then
        local p = playerCoords(src)
        if p then inv():CreateLootDrop(p, rest, { label = 'Materials' }) end
        notice(src, 'Some materials did not fit and were dropped at your feet.')
    end
end

local function missingText(cost, src)
    if adminBuild[src] then return nil end
    local miss = Rules.missing(cost, countOf(src))
    if #miss == 0 then return nil end
    local parts = {}
    for _, m in ipairs(miss) do parts[#parts + 1] = string.format('%d x %s (you have %d)', m.need, label(m.item), m.have) end
    return 'You need ' .. table.concat(parts, ', ') .. '.'
end

-------------------------------------------------------------------------------
-- Access
-------------------------------------------------------------------------------

local function sameGroup(a, b)
    if GetResourceState('wasteland_groups') ~= 'started' then return false end
    local ok, same = pcall(function() return exports.wasteland_groups:SameGroup(a, b) end)
    return ok and same == true
end

local function hasAccess(cid, c)
    if not cid or not c then return false end
    return c.owner == cid or c.auth[cid] ~= nil or sameGroup(cid, c.owner)
end

-- The cupboard that covers `coords` now (not the one a piece was built under:
-- a rebuilt cupboard keeps working for what is already there).
local function accessAt(cid, coords)
    local c = Rules.covering(cupboards, coords)
    if not c then return false, nil end
    return hasAccess(cid, c), c
end

-- May this character use (open, remove, repair, upgrade) piece `p`? Under a
-- cupboard: that cupboard's access. Without one: whoever built it, and their
-- group.
local function pieceAccess(cid, p)
    if not cid then return false end
    local c = Rules.covering(cupboards, p.coords)
    if c then return hasAccess(cid, c) end
    return p.owner ~= nil and (p.owner == cid or sameGroup(cid, p.owner))
end

-------------------------------------------------------------------------------
-- What clients get
-------------------------------------------------------------------------------

local function clientConfig()
    local c = M.config
    local pieces = {}
    for key, p in pairs(c.pieces) do
        pieces[key] = { label = p.label, model = p.model, category = p.category, family = p.family, hidden = p.hidden,
            openAngleOffset = p.openAngleOffset, openLift = p.openLift, cost = p.cost, material = p.material,
            interactDistance = p.interactDistance, passThrough = p.passThrough, altModels = p.altModels,
            contactDamage = p.contactDamage, slow = p.slow, wearPerTouch = p.wearPerTouch, touchRadius = p.touchRadius, scale = p.scale,
            ladder = p.ladder, wireDamage = p.wireDamage, wireFrom = p.wireFrom, wireTo = p.wireTo, wireReach = p.wireReach,
            generator = p.generator, light = p.light, needsPower = p.needsPower, shock = p.shock, bed = p.bed, adminOnly = p.adminOnly }
    end
    local upgrades = {}
    for key, u in pairs(c.upgrades) do upgrades[key] = { next = u.next, cost = u.cost } end
    return {
        pieces = pieces, upgrades = upgrades, snapRules = snapRules, placement = c.placement,
        categoryOrder = c.categoryOrder, categoryLabels = c.categoryLabels,
        interact = c.interact, targetDistance = c.targetDistance, streamRadius = c.streamRadius,
        cupboardPiece = c.cupboard.piece, lockpick = c.lockpick.enabled, safeRadius = c.cupboard.safeRadius,
        raid = { enabled = c.raid.enabled, explosionDamage = c.raid.explosionDamage, explosionRadius = c.raid.explosionRadius,
            melee = c.raid.melee.enabled, repairCost = c.raid.repair.cost },
        zombieBarricades = zombieBarricades(c),
    }
end

-- The zombie-free zone round a cupboard: seconds left (-1 = never ends,
-- 0 = over).
local function safeLeft(c)
    local cfgc = M.config.cupboard
    if not cfgc.safeRadius or cfgc.safeRadius <= 0 then return 0 end
    if not cfgc.safeMinutes or cfgc.safeMinutes <= 0 then return -1 end
    return math.max(0, (c.created or 0) + cfgc.safeMinutes * 60 - os.time())
end

local function cupboardInfo(c)
    return { id = c.id, coords = c.coords, heading = c.heading, radius = c.radius, health = c.health, max_health = c.max_health,
        safeLeft = safeLeft(c), owner = c.owner }
end

local function propInfo(p)
    return { id = p.id, cupboard_id = p.cupboard_id, category = p.category, piece = p.piece, model = p.model, coords = p.coords,
        heading = p.heading, is_open = p.is_open, health = p.health, max_health = p.max_health, material = p.material, fuel = p.fuel or 0 }
end

local function mineFor(cid)
    local out = {}
    for id, c in pairs(cupboards) do if hasAccess(cid, c) then out[#out + 1] = id end end
    return out
end

local function sync(target)
    local cl, pl = {}, {}
    for _, c in pairs(cupboards) do cl[#cl + 1] = cupboardInfo(c) end
    for _, p in pairs(props) do pl[#pl + 1] = propInfo(p) end
    local cid = target ~= -1 and characterOf(target) or nil
    TriggerClientEvent('wasteland:basebuilding:client:sync', target, { config = clientConfig(), cupboards = cl, props = pl,
        mine = cid and mineFor(cid) or nil })
end

local function sendMine(src)
    local cid = characterOf(src)
    if cid then TriggerClientEvent('wasteland:basebuilding:client:mine', src, mineFor(cid)) end
end

local function sendMineAll()
    local ok, list = pcall(function() return players():GetOnlineCharacters() end)
    for _, c in ipairs(ok and list or {}) do sendMine(c.source) end
end

-------------------------------------------------------------------------------
-- Stashes
-------------------------------------------------------------------------------

local function stashName(propId) return 'bb_stash_' .. propId end
local function supplyName(cupboardId) return 'bb_supply_' .. cupboardId end

local function stashOpts(p)
    local g = M.config.pieces[p.piece] and M.config.pieces[p.piece].grid or { width = 8, height = 6, maxWeight = 100 }
    return { label = M.config.pieces[p.piece] and M.config.pieces[p.piece].label or 'Storage', width = g.width, height = g.height,
        maxWeight = g.maxWeight, coords = p.coords, reach = M.config.targetDistance + 1.0 }
end

local function supplyOpts(c)
    local g = M.config.upkeep.supplyGrid
    return { label = 'Base supplies', width = g.width, height = g.height, maxWeight = g.maxWeight, coords = c.coords,
        reach = M.config.targetDistance + 1.0 }
end

-------------------------------------------------------------------------------
-- The build menu and the cupboard screen
-------------------------------------------------------------------------------

local function buildView(src)
    local have = countOf(src)
    local images = {}
    for _, it in ipairs(inv():GetItemList()) do images[it.name] = it.image end
    local cats = {}
    for _, cat in ipairs(M.config.categoryOrder) do
        local list = {}
        for key, p in pairs(M.config.pieces) do
            if p.category == cat and not p.hidden and (not p.adminOnly or isAdmin(src)) then
                local cost = {}
                local names = {}
                for item in pairs(p.cost or {}) do names[#names + 1] = item end
                table.sort(names)
                for _, item in ipairs(names) do cost[#cost + 1] = { label = label(item), count = p.cost[item], have = have(item), image = images[item] } end
                list[#list + 1] = { key = key, label = p.label, cost = cost, canPay = adminBuild[src] or #Rules.missing(p.cost, have) == 0 }
            end
        end
        table.sort(list, function(a, b) return a.label < b.label end)
        if #list > 0 then cats[#cats + 1] = { key = cat, label = M.config.categoryLabels[cat] or cat, pieces = list } end
    end
    return { categories = cats }
end

local function pieceCounts(cupboardId)
    local counts = { wood = 0, stone = 0, metal = 0 }
    for _, p in pairs(props) do
        if p.cupboard_id == cupboardId and counts[p.material] ~= nil then counts[p.material] = counts[p.material] + 1 end
    end
    return counts
end

-- Runs in a thread (the supplies stash may load from the database).
local function cupboardView(src, c)
    local cid = characterOf(src)
    local stash = inv():EnsureStash(supplyName(c.id), supplyOpts(c))
    local counts = pieceCounts(c.id)
    local upkeep = {}
    for _, material in ipairs({ 'wood', 'stone', 'metal' }) do
        local item = M.config.upkeep.items[material]
        local daily = counts[material] * (M.config.upkeep.perPieceCostPerDay[material] or 0)
        local have = stash and inv():GetItemCount(stash, item) or 0
        upkeep[#upkeep + 1] = { material = material, item = label(item), pieces = counts[material], daily = daily, have = have,
            hours = Rules.hoursLeft(have, daily), infinite = c.infinite == true }
    end
    local auth = {}
    for acid, name in pairs(c.auth) do auth[#auth + 1] = { id = acid, name = name, online = sourceOf(acid) ~= nil } end
    table.sort(auth, function(a, b) return a.name < b.name end)
    local damaged = 0
    for _, p in pairs(props) do if p.cupboard_id == c.id and p.health < p.max_health then damaged = damaged + 1 end end
    return { id = c.id, owner = c.owner == cid, health = c.health, maxHealth = c.max_health, radius = c.radius,
        auth = auth, upkeep = upkeep, damaged = damaged, upkeepEnabled = M.config.upkeep.enabled }
end

local function sendCupboard(src, c, message)
    Citizen.CreateThread(function()
        local v = cupboardView(src, c)
        v.message = message
        TriggerClientEvent('wasteland:basebuilding:client:cupboard', src, v)
    end)
end

-------------------------------------------------------------------------------
-- Placing and removing
-------------------------------------------------------------------------------

-- Camps and tree / rock zones (wasteland_camps, wasteland_loot): no building.
local function inSafeZone(coords)
    if GetResourceState('wasteland_camps') == 'started' then
        local ok, yes = pcall(function() return exports.wasteland_camps:IsInSafeZone(coords) end)
        if ok and yes == true then return true end
    end
    if GetResourceState('wasteland_loot') == 'started' then
        local ok, yes = pcall(function() return exports.wasteland_loot:IsInGatherZone(coords) end)
        if ok and yes == true then return true end
    end
    return false
end

local function placeProp(src, key, x, y, z, heading)
    local piece = M.config.pieces[key]
    local cid = characterOf(src)
    if not piece or piece.hidden or not cid then return end
    if piece.adminOnly and not isAdmin(src) then notice(src, 'Only admins can build that.'); return end
    local coords = { x = x, y = y, z = z }
    if not near(src, coords, M.config.placement.maxPlaceDistance + 2.0) then notice(src, 'Too far away to place that.'); return end
    if M.config.placement.noBuildInSafeZones and not adminBuild[src] and inSafeZone(coords) then
        notice(src, 'You cannot build inside a safe zone (camps, tree and rock zones).'); return
    end

    local cupboard = nil
    if piece.category == 'cupboard' then
        for _, c in pairs(cupboards) do
            if Rules.dist(coords, c.coords) < M.config.cupboard.minGap then notice(src, 'Too close to another tool cupboard.'); return end
        end
        local covering = Rules.covering(cupboards, coords)
        if covering and not hasAccess(cid, covering) then notice(src, 'This land is claimed by someone else.'); return end
    else
        local ok, c = accessAt(cid, coords)
        if not c then
            local fb = M.config.freeBuild
            local allowed = fb and fb.enabled
            if allowed then
                allowed = false
                for _, cat in ipairs(fb.categories or {}) do if cat == piece.category then allowed = true end end
            end
            if not allowed then notice(src, 'Place a Tool Cupboard first: you can only build within reach of one you may use.'); return end
        elseif not ok then notice(src, 'You are not allowed to build here.'); return end
        cupboard = c
    end

    local why = missingText(piece.cost, src)
    if why then notice(src, why); return end
    if not pay(src, piece.cost) then notice(src, 'You do not have the materials.'); return end

    heading = (tonumber(heading) or 0.0) % 360.0
    if piece.category == 'cupboard' then
        local infinite = piece.infiniteUpkeep == true
        local id, err = WDB.insert(SQL.insertCupboard, { cid, x, y, z, heading, M.config.cupboard.radius, piece.health, piece.health,
            infinite and 1 or 0, os.time() })
        if not id then give(src, piece.cost); notice(src, 'The cupboard could not be saved. Try again.'); M.log:warn('cupboard: %s', tostring(err)); return end
        local c = { id = id, owner = cid, coords = coords, heading = heading, radius = M.config.cupboard.radius,
            health = piece.health, max_health = piece.health, auth = {}, created = os.time(), infinite = infinite }
        cupboards[id] = c
        -- pieces left from an earlier cupboard here belong to this one now
        for _, p in pairs(props) do
            if not p.cupboard_id and Rules.dist(p.coords, coords) <= c.radius then
                p.cupboard_id = id
                write(SQL.attachProp, { id, p.id }, 'attach piece')
            end
        end
        TriggerClientEvent('wasteland:basebuilding:client:cupboardAdded', -1, cupboardInfo(c))
        sendMineAll()
        M.log:info('player %d (character %d) placed tool cupboard %d', src, cid, id)
        TriggerEvent('wasteland:basebuilding:cupboardPlaced', src, id)
        notice(src, 'Tool cupboard placed. You control building and access within ' .. math.floor(c.radius) .. ' m.')
        local left = safeLeft(c)
        if left ~= 0 then
            TriggerClientEvent('wasteland:basebuilding:client:safeZoneStarted', src, left > 0 and math.floor(left / 60) or -1,
                M.config.cupboard.safeRadius)
        end
        return
    end

    local cupboardId = cupboard and cupboard.id or nil
    local id, err = WDB.insert(SQL.insertProp, { cupboardId, cid, piece.category, key, piece.model, x, y, z, heading, piece.health, piece.health,
        piece.material, os.time() })
    if not id then give(src, piece.cost); notice(src, 'The piece could not be saved. Try again.'); M.log:warn('prop: %s', tostring(err)); return end
    local p = { id = id, cupboard_id = cupboardId, owner = cid, created = os.time(), category = piece.category, piece = key, model = piece.model,
        coords = coords, heading = heading, is_open = false, health = piece.health, max_health = piece.health, material = piece.material }
    props[id] = p
    TriggerClientEvent('wasteland:basebuilding:client:propAdded', -1, propInfo(p))
    if cupboard then notice(src, piece.label .. ' placed.')
    else notice(src, string.format('%s placed without a tool cupboard: it stays for %d hours (a cupboard placed here later keeps it for good). No zombie-free zone.',
        piece.label, M.config.freeBuild.hours)) end
end

local function removeProp(src, id)
    local cid = characterOf(src)
    local p = props[id]
    if not p or not cid or not near(src, p.coords, M.config.targetDistance + 1.0) then return end
    if not pieceAccess(cid, p) then notice(src, 'You are not allowed to remove this.'); return end
    if p.category == 'stash' then
        local stash = inv():EnsureStash(stashName(id), stashOpts(p))
        local snap = stash and inv():GetInventory(stash)
        if snap and #(snap.items or {}) > 0 then notice(src, 'Empty it first.'); return end
        pcall(function() inv():DeleteStash(stashName(id)) end)
    end
    local piece = M.config.pieces[p.piece]
    if piece and piece.cost and not adminBuild[src] then give(src, Rules.refund(piece.cost, M.config.refund)) end
    props[id] = nil
    write(SQL.deleteProp, { id }, 'removing piece ' .. id)
    TriggerClientEvent('wasteland:basebuilding:client:propRemoved', -1, id)
    notice(src, 'Removed.')
end

-- Move a placed piece somewhere else (it keeps its id, so storage keeps what
-- is in it). The same rules as building there apply at the new spot.
local function moveProp(src, id, x, y, z, heading)
    local cid = characterOf(src)
    local p = props[id]
    if not p or not cid then return end
    local coords = { x = x, y = y, z = z }
    if not near(src, p.coords, M.config.placement.maxPlaceDistance + 10.0) then notice(src, 'Too far from that piece.'); return end
    if not near(src, coords, M.config.placement.maxPlaceDistance + 2.0) then notice(src, 'Too far away to put it there.'); return end
    if not pieceAccess(cid, p) then notice(src, 'You are not allowed to move this.'); return end
    local ok, c = accessAt(cid, coords)
    if c and not ok then notice(src, 'You are not allowed to build there.'); return end
    if not c then
        local fb = M.config.freeBuild
        local allowed = false
        if fb and fb.enabled then
            for _, cat in ipairs(fb.categories or {}) do if cat == p.category then allowed = true end end
        end
        if not allowed then notice(src, 'Place a Tool Cupboard first: you can only build within reach of one you may use.'); return end
    end
    p.coords, p.heading, p.is_open = coords, (tonumber(heading) or 0.0) % 360.0, false
    p.cupboard_id = c and c.id or nil
    write(SQL.propMove, { x, y, z, p.heading, p.cupboard_id, id }, 'moving piece ' .. id)
    TriggerClientEvent('wasteland:basebuilding:client:propMoved', -1, id, { coords = coords, heading = p.heading, cupboard_id = p.cupboard_id })
    notice(src, 'Moved.')
end

-- Move the tool cupboard (owner only). It claims the land, so: every piece it
-- covers must stay within its reach, it may not go onto someone else's land,
-- and not too close to another cupboard.
local function moveCupboard(src, id, x, y, z, heading)
    local cid = characterOf(src)
    local c = cupboards[id]
    if not c or not cid then return end
    local coords = { x = x, y = y, z = z }
    if c.owner ~= cid then notice(src, 'Only the owner can move this tool cupboard.'); return end
    if not near(src, c.coords, M.config.placement.maxPlaceDistance + 10.0) then notice(src, 'Too far from the tool cupboard.'); return end
    if not near(src, coords, M.config.placement.maxPlaceDistance + 2.0) then notice(src, 'Too far away to put it there.'); return end
    for oid, o in pairs(cupboards) do
        if oid ~= id then
            if Rules.dist(coords, o.coords) < M.config.cupboard.minGap then notice(src, 'Too close to another tool cupboard.'); return end
            if Rules.dist(coords, o.coords) <= o.radius and not hasAccess(cid, o) then notice(src, 'This land is claimed by someone else.'); return end
        end
    end
    for _, p in pairs(props) do
        if p.cupboard_id == id and Rules.dist(p.coords, coords) > c.radius then
            notice(src, 'Part of your base would be outside the tool cupboard\'s reach. Move it closer to the middle.')
            return
        end
    end
    c.coords, c.heading = coords, (tonumber(heading) or 0.0) % 360.0
    write(SQL.cupboardMove, { x, y, z, c.heading, id }, 'moving cupboard ' .. id)
    TriggerClientEvent('wasteland:basebuilding:client:cupboardMoved', -1, id, { coords = coords, heading = c.heading })
    sendMineAll()
    notice(src, 'Tool cupboard moved.')
end

-- Barbed wire on top of a wall: is `at` touching it? (in the piece's own space:
-- along its width, close to its line, within the wire's height band)
local function onWire(p, piece, at)
    local dims = { x = at.x - p.coords.x, y = at.y - p.coords.y }
    local h = math.rad(p.heading or 0.0)
    local lx = dims.x * math.cos(h) + dims.y * math.sin(h)
    local ly = -dims.x * math.sin(h) + dims.y * math.cos(h)
    local lz = at.z - p.coords.z
    return math.abs(lx) <= 2.1 and math.abs(ly) <= (piece.wireReach or 0.75) + 0.3
        and lz >= (piece.wireFrom or 3.5) - 1.2 and lz <= (piece.wireTo or 4.7) + 0.5
end

local wireHurt = {} -- source -> last hurt (game timer)
local function touchWire(src, id)
    local p = props[id]
    local piece = p and M.config.pieces[p.piece]
    if not piece or not piece.wireDamage then return end
    local at = playerCoords(src)
    if not at or not onWire(p, piece, at) then return end
    if piece.needsPower and not (PoweredAt and PoweredAt(p.coords)) then return end
    local t = GetGameTimer()
    if t - (wireHurt[src] or 0) < 900 then return end
    wireHurt[src] = t
    local ok = pcall(function() exports.wasteland_survival:Damage(src, piece.wireDamage) end)
    if not ok then TriggerClientEvent('wasteland:basebuilding:client:wireHurt', src, piece.wireDamage) end
    if (piece.wireBleed or 0) > 0 and math.random() < piece.wireBleed then
        pcall(function() exports.wasteland_survival:AddBleeding(src, 1) end)
    end
    TriggerClientEvent('wasteland:basebuilding:client:notice', src, piece.shock and 'Zapped!' or 'Barbed wire!')
    if piece.shock then TriggerClientEvent('wasteland:basebuilding:client:shocked', src, id) end
end

-------------------------------------------------------------------------------
-- Power: generators (fuel from jerry cans, on/off) and the lights they power
-------------------------------------------------------------------------------

local function powerChanged(p)
    write(SQL.propPower, { p.fuel or 0, p.is_open and 1 or 0, p.id }, 'generator ' .. p.id)
    TriggerClientEvent('wasteland:basebuilding:client:power', -1, p.id, { is_open = p.is_open, fuel = p.fuel or 0 })
end

local function generatorOf(src, id)
    local cid = characterOf(src)
    local p = props[id]
    local piece = p and M.config.pieces[p.piece]
    if not piece or not piece.generator or not cid then return nil end
    if not near(src, p.coords, M.config.targetDistance + 1.0) then return nil end
    if not pieceAccess(cid, p) then notice(src, 'You are not allowed to use this generator.'); return nil end
    return p, piece.generator
end

local function generatorToggle(src, id)
    local p = generatorOf(src, id)
    if not p then return end
    local _, gcfg = generatorOf(src, id)
    if not p.is_open and (p.fuel or 0) <= 0 and not (gcfg and gcfg.unlimited) then notice(src, 'The generator has no fuel. Add fuel from a jerry can.'); return end
    p.is_open = not p.is_open
    powerChanged(p)
    notice(src, p.is_open and 'Generator on.' or 'Generator off.')
end

local function generatorFuel(src, id)
    local p, g = generatorOf(src, id)
    if not p then return end
    if g.unlimited then notice(src, 'This generator needs no fuel.'); return end
    local space = g.tankLitres - (p.fuel or 0)
    if space <= 0.05 then notice(src, 'The tank is full.'); return end
    local best
    for _, c in ipairs(inv():FindItems(src, 'jerry_can')) do
        if (c.metadata.fuel or 0) > 0 and (not best or c.metadata.fuel > best.metadata.fuel) then best = c end
    end
    if not best then notice(src, 'You need a jerry can with fuel in it.'); return end
    local amount = math.min(best.metadata.fuel, space)
    inv():SetItemMetadata(src, best.uid, { fuel = best.metadata.fuel - amount })
    p.fuel = (p.fuel or 0) + amount
    powerChanged(p)
    notice(src, ('Added %.1f L. Tank: %.1f / %d L (about %.1f hours).'):format(amount, p.fuel, g.tankLitres,
        g.litresPerHour > 0 and p.fuel / g.litresPerHour or 0))
end

-- Every minute: running generators burn fuel (and stop when empty); they are
-- loud, so zombies nearby come to look.
local function powerTick()
    for _, p in pairs(props) do
        local piece = M.config.pieces[p.piece]
        local g = piece and piece.generator
        if g and p.is_open and not g.unlimited then
            p.fuel = math.max(0, (p.fuel or 0) - g.litresPerHour / 60)
            if p.fuel <= 0 then p.is_open = false end
            powerChanged(p)
            if p.is_open and g.noise > 0 then TriggerEvent('wasteland:noise', p.coords, g.noise) end
        end
    end
end

--- IsPowered(coords) -> boolean: a running generator powers this spot (lights; electric fences later)
local function isPowered(at)
    for _, p in pairs(props) do
        local piece = M.config.pieces[p.piece]
        if piece and piece.generator and p.is_open and ((p.fuel or 0) > 0 or piece.generator.unlimited)
            and Rules.dist(p.coords, at) <= piece.generator.powerRadius then return true end
    end
    return false
end
PoweredAt = isPowered

--- IsRoofed(coords) -> boolean: a roof built with base building (a ceiling,
--- a ladder hatch, a floor or stairs above) is over this spot (farming: no rain)
local ROOF = { ceiling = true, hatch = true, foundation = true, stairs = true }
exports('IsRoofed', function(coords)
    if not (M and M.active) or type(coords) ~= 'table' then return false end
    for _, p in pairs(props) do
        local piece = M.config.pieces[p.piece]
        local family = piece and (piece.family or p.piece)
        if piece and (ROOF[family] or ROOF[p.piece]) then
            local dz = p.coords.z - coords.z
            if dz > 0.8 and dz < 9.0 then
                local dx, dy = coords.x - p.coords.x, coords.y - p.coords.y
                local h = math.rad(p.heading or 0.0)
                local lx = dx * math.cos(h) + dy * math.sin(h)
                local ly = -dx * math.sin(h) + dy * math.cos(h)
                if math.abs(lx) <= 2.1 and math.abs(ly) <= 2.1 then return true end
            end
        end
    end
    return false
end)
exports('IsPowered', function(coords)
    if not (M and M.active) or type(coords) ~= 'table' then return false end
    return isPowered({ x = coords.x, y = coords.y, z = coords.z or 0 })
end)

-------------------------------------------------------------------------------
-- Beds: lying on one slowly heals and fights the infection
-------------------------------------------------------------------------------

local resting = {} -- source -> { id, next (game timer) }

local function setResting(src, id, on)
    if not on then resting[src] = nil; return end
    local cid = characterOf(src)
    local p = props[id]
    local piece = p and M.config.pieces[p.piece]
    if not cid or not piece or not piece.bed then return end
    if not near(src, p.coords, 3.0) then notice(src, 'Get closer to the bed.'); return end
    if not pieceAccess(cid, p) then notice(src, 'This is not your bed.'); return end
    for other, r in pairs(resting) do
        if other ~= src and r.id == id then notice(src, 'Someone is lying in this bed.'); return end
    end
    resting[src] = { id = id, next = GetGameTimer() + piece.bed.tickSeconds * 1000 }
    TriggerClientEvent('wasteland:basebuilding:client:rest', src, id)
end

local function restTick()
    local t = GetGameTimer()
    for src, r in pairs(resting) do
        local p = props[r.id]
        local piece = p and M.config.pieces[p.piece]
        if not piece or not piece.bed or not near(src, p.coords, 3.0) then
            resting[src] = nil
        elseif t >= r.next then
            r.next = t + piece.bed.tickSeconds * 1000
            local b = piece.bed
            if b.infection > 0 then
                pcall(function() exports.wasteland_survival:ModifyStats(src, { infection = -b.infection }) end)
            end
            if b.health > 0 then TriggerClientEvent('wasteland:survival:client:heal', src, b.health) end
        end
    end
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        if M and M.active and next(resting) then
            local ok, err = pcall(restTick)
            if not ok then M.log:warn('rest: %s', tostring(err)) end
        end
    end
end)

local function dropCupboard(c, why)
    cupboards[c.id] = nil
    carry[c.id] = nil
    for _, p in pairs(props) do if p.cupboard_id == c.id then p.cupboard_id = nil end end
    write(SQL.detachProps, { c.id }, 'detaching pieces')
    write(SQL.deleteAuthAll, { c.id }, 'removing access list')
    write(SQL.deleteCupboard, { c.id }, 'removing cupboard')
    TriggerClientEvent('wasteland:basebuilding:client:cupboardRemoved', -1, c.id)
    sendMineAll()
    M.log:info('tool cupboard %d gone (%s)', c.id, why)
end

local function removeCupboard(src, id)
    local cid = characterOf(src)
    local c = cupboards[id]
    if not c or not near(src, c.coords, M.config.targetDistance + 1.0) then return end
    if c.owner ~= cid then notice(src, 'Only the owner can remove this tool cupboard.'); return end
    Citizen.CreateThread(function()
        local stash = inv():EnsureStash(supplyName(id), supplyOpts(c))
        local snap = stash and inv():GetInventory(stash)
        if snap and #(snap.items or {}) > 0 then notice(src, 'Take the supplies out of the cupboard first.'); return end
        pcall(function() inv():DeleteStash(supplyName(id)) end)
        local piece = M.config.pieces[M.config.cupboard.piece]
        if piece and piece.cost and not adminBuild[src] and not c.infinite then give(src, Rules.refund(piece.cost, M.config.refund)) end
        dropCupboard(c, 'removed by its owner')
        notice(src, 'Tool cupboard removed. The land is no longer claimed.')
    end)
end

-------------------------------------------------------------------------------
-- Doors, storage, supplies
-------------------------------------------------------------------------------

local function setDoor(p, open)
    p.is_open = open
    write(SQL.propOpen, { open and 1 or 0, p.id }, 'door ' .. p.id)
    TriggerClientEvent('wasteland:basebuilding:client:door', -1, p.id, open)
end

local function toggleDoor(src, id)
    local cid = characterOf(src)
    local p = props[id]
    if not p or (p.category ~= 'door' and p.category ~= 'garage') then return end
    local piece = M.config.pieces[p.piece]
    local reach = (piece and piece.interactDistance) or M.config.interact.distance
    if not near(src, p.coords, reach + 1.5) then return end
    if not pieceAccess(cid, p) then notice(src, 'This door is locked. (A lockpick might open it.)'); return end
    setDoor(p, not p.is_open)
end

local function openStash(src, id, forced)
    local cid = characterOf(src)
    local p = props[id]
    if not p or p.category ~= 'stash' or not near(src, p.coords, M.config.targetDistance + 1.0) then return end
    -- broken storage is wreckage anyone can loot
    if p.health > 0 and not forced then
        if not pieceAccess(cid, p) then notice(src, 'This storage is locked. (A lockpick might open it.)'); return end
    end
    local opts = stashOpts(p)
    opts.open = true
    inv():OpenStash(src, stashName(id), opts)
end

local function openSupplies(src, id)
    local c = cupboards[id]
    if not c or not near(src, c.coords, M.config.targetDistance + 1.0) then return end
    if not hasAccess(characterOf(src), c) then notice(src, 'You are not allowed to manage this cupboard.'); return end
    local opts = supplyOpts(c)
    opts.open = true
    inv():OpenStash(src, supplyName(id), opts)
end

local function openCupboard(src, id)
    local c = cupboards[id]
    if not c or not near(src, c.coords, M.config.targetDistance + 1.0) then return end
    if not hasAccess(characterOf(src), c) then notice(src, 'You are not allowed to manage this cupboard.'); return end
    sendCupboard(src, c)
end

local function authorize(src, id, targetSrc)
    local cid = characterOf(src)
    local c = cupboards[id]
    if not c or c.owner ~= cid then notice(src, 'Only the owner can manage access.'); return end
    local tcid = characterOf(targetSrc)
    if not tcid then sendCupboard(src, c, 'No player with id ' .. targetSrc .. ' is playing right now.'); return end
    if tcid == cid or c.auth[tcid] then sendCupboard(src, c, nameOf(targetSrc) .. ' already has access.'); return end
    local name = nameOf(targetSrc)
    c.auth[tcid] = name
    write(SQL.insertAuth, { id, tcid, name }, 'authorizing')
    notice(targetSrc, 'You were given access to a base (building, doors, storage).')
    sendMine(targetSrc)
    sendCupboard(src, c, name .. ' now has access.')
end

local function revoke(src, id, targetCid)
    local cid = characterOf(src)
    local c = cupboards[id]
    if not c or c.owner ~= cid then notice(src, 'Only the owner can manage access.'); return end
    if not c.auth[targetCid] then return end
    local name = c.auth[targetCid]
    c.auth[targetCid] = nil
    write(SQL.deleteAuth, { id, targetCid }, 'revoking')
    local s = sourceOf(targetCid)
    if s then notice(s, 'Your access to a base was taken away.'); sendMine(s) end
    sendCupboard(src, c, name .. ' no longer has access.')
end

-------------------------------------------------------------------------------
-- Damage, repairs, upgrades
-------------------------------------------------------------------------------

-- Raids and decay. Storage is never deleted at 0 (its contents would be lost):
-- it stays as wreckage that anyone can loot until it is removed.
-- Pieces zombies attack (by family: a stone wall is still a wall), and how
-- much each material takes per hit. nil = zombies leave bases alone.
local function familyOf(c, p)
    local piece = c.pieces[p.piece]
    return piece and piece.family or p.piece
end

zombieBarricades = function(c)
    local z = c.raid and c.raid.zombies
    if not (c.raid.enabled and z and z.enabled) then return nil end
    local families = {}
    for _, f in ipairs(z.pieces or {}) do families[f] = true end
    return { families = families, damage = z.damage }
end

local function damage(id, amount)
    local p = props[id]
    if not p then return end
    p.health = math.max(0, p.health - amount)
    if p.health <= 0 and p.category ~= 'stash' then
        props[id] = nil
        write(SQL.deleteProp, { id }, 'destroyed piece')
        TriggerClientEvent('wasteland:basebuilding:client:propRemoved', -1, id)
    else
        write(SQL.propHealth, { p.health, id }, 'piece health')
        TriggerClientEvent('wasteland:basebuilding:client:propHealth', -1, id, p.health)
    end
end

-- Explosives somebody really threw (wasteland_weapons): a blast only counts
-- if one of that kind was thrown near it lately (sticky bombs can wait).
local recentThrows = {}   -- { kind, at, t }
local blastSeen = {}      -- piece key -> time of the last blast counted
AddEventHandler('wasteland:weapons:used', function(src, item, n, _, coords)
    local thrown = M and M.config.raid.thrown
    local kind = thrown and thrown[item]
    if kind == nil or type(coords) ~= 'table' then return end
    recentThrows[#recentThrows + 1] = { kind = kind, at = { x = tonumber(coords.x) or 0, y = tonumber(coords.y) or 0, z = tonumber(coords.z) or 0 }, t = os.time() }
    if #recentThrows > 200 then table.remove(recentThrows, 1) end
end)

local function wasThrown(kind, where)
    local r = M.config.raid
    if not r.requireThrow then return true end
    local t = os.time()
    for i = #recentThrows, 1, -1 do
        local e = recentThrows[i]
        local keep = e.kind == 2 and r.stickySeconds or r.throwSeconds
        if t - e.t <= keep and e.kind == kind and Rules.dist(e.at, where) <= r.throwRange then return true end
    end
    return false
end

-- A cupboard at 0 health is destroyed: its supplies go, the land is free.
local cupboardAttackNotice = {} -- cupboard id -> last "under attack" notice
local function damageCupboard(c, dmg)
    c.health = math.max(0, c.health - dmg)
    local t = now()
    if not cupboardAttackNotice[c.id] or t - cupboardAttackNotice[c.id] > 180000 then
        cupboardAttackNotice[c.id] = t
        local message = c.health <= 0 and 'Your tool cupboard was destroyed! The land is no longer claimed.'
            or 'Your tool cupboard is under attack!'
        local s = sourceOf and sourceOf(c.owner)
        if s then notice(s, message) else write(SQL.insertNotice, { c.owner, message, os.time() }, 'cupboard notice') end
    end
    if c.health <= 0 then
        pcall(function() inv():DeleteStash(supplyName(c.id)) end)
        dropCupboard(c, 'destroyed')
        cupboardAttackNotice[c.id] = nil
    else
        write(SQL.cupboardHealth, { c.health, c.id }, 'cupboard health')
        TriggerClientEvent('wasteland:basebuilding:client:cupboardHealth', -1, c.id, c.health)
    end
end

local function explosion(src, id, kind, at, isCupboard)
    if not M.config.raid.enabled or type(at) ~= 'table' then return end
    local target = isCupboard and cupboards[id] or props[id]
    if not target then return end
    -- every player nearby sees (and reports) the same blast: count it once
    local key = (isCupboard and 'c' or 'p') .. id
    local t = now()
    if blastSeen[key] and t - blastSeen[key] < 1500 then return end
    if not wasThrown(kind, target.coords) then return end
    blastSeen[key] = t
    local where = { x = tonumber(at.x) or 0, y = tonumber(at.y) or 0, z = tonumber(at.z) or 0 }
    if Rules.dist(where, target.coords) > M.config.raid.explosionRadius then return end
    local rules = M.config.raid.explosionDamage[isCupboard and 'wood' or target.material]
    local dmg = rules and (rules[kind] or rules[tostring(kind)])
    if not dmg then return end
    if isCupboard then
        damageCupboard(target, dmg)
    else
        damage(id, dmg)
    end
end

local function melee(src, id, isCupboard)
    if not (M.config.raid.enabled and M.config.raid.melee.enabled) then return end
    local t = now()
    if meleeCooldown[src] and t - meleeCooldown[src] < M.config.raid.melee.cooldownMs then return end
    meleeCooldown[src] = t
    if isCupboard then
        -- Other players can break a cupboard with melee; its own people cannot
        -- (so nobody wrecks their own by accident).
        local c = cupboards[id]
        local dmg = M.config.raid.melee.cupboardDamage or 0
        if not c or dmg <= 0 or not near(src, c.coords, 3.0) then return end
        if hasAccess(characterOf(src), c) then return end
        damageCupboard(c, dmg)
        return
    end
    local p = props[id]
    if not p or p.material ~= 'wood' or not near(src, p.coords, 3.0) then return end
    damage(id, M.config.raid.melee.woodDamage)
end

local function repairProp(src, id)
    local cid = characterOf(src)
    local p = props[id]
    if not p or not near(src, p.coords, M.config.targetDistance + 1.0) then return end
    if p.health >= p.max_health then notice(src, 'It is not damaged.'); return end
    if not pieceAccess(cid, p) then notice(src, 'You are not allowed to repair this.'); return end
    local rc = M.config.raid.repair.cost[p.material]
    if not rc then return end
    local why = missingText({ [rc.item] = rc.count }, src)
    if why then notice(src, why); return end
    if not pay(src, { [rc.item] = rc.count }) then return end
    p.health = math.min(p.max_health, p.health + (M.config.raid.repair.amount[p.material] or 0))
    write(SQL.propHealth, { p.health, id }, 'repair')
    TriggerClientEvent('wasteland:basebuilding:client:propHealth', -1, id, p.health)
    notice(src, string.format('Repaired (%d / %d).', p.health, p.max_health))
end

local function repairAll(src, id)
    local c = cupboards[id]
    if not c or not near(src, c.coords, M.config.targetDistance + 1.0) then return end
    if not hasAccess(characterOf(src), c) then notice(src, 'You are not allowed to repair here.'); return end
    local list, total = {}, {}
    for pid, p in pairs(props) do
        if p.cupboard_id == id and p.health < p.max_health then
            local rc = M.config.raid.repair.cost[p.material]
            if rc then
                list[#list + 1] = pid
                total[rc.item] = (total[rc.item] or 0) + rc.count
            end
        end
    end
    if #list == 0 then sendCupboard(src, c, 'Nothing here needs repairing.'); return end
    local why = missingText(total, src)
    if why then sendCupboard(src, c, 'To repair everything: ' .. why); return end
    if not pay(src, total) then return end
    for _, pid in ipairs(list) do
        local p = props[pid]
        p.health = math.min(p.max_health, p.health + (M.config.raid.repair.amount[p.material] or 0))
        write(SQL.propHealth, { p.health, pid }, 'repair all')
        TriggerClientEvent('wasteland:basebuilding:client:propHealth', -1, pid, p.health)
    end
    sendCupboard(src, c, string.format('Repaired %d piece(s).', #list))
end

local function upgrade(src, id)
    local cid = characterOf(src)
    local p = props[id]
    if not p or not near(src, p.coords, M.config.targetDistance + 1.0) then return end
    local u = M.config.upgrades[p.piece]
    local nxt = u and M.config.pieces[u.next]
    if not nxt then notice(src, 'This cannot be upgraded.'); return end
    if not pieceAccess(cid, p) then notice(src, 'You are not allowed to upgrade this.'); return end
    local why = missingText(u.cost, src)
    if why then notice(src, why); return end
    if not pay(src, u.cost) then return end
    p.piece, p.model, p.health, p.max_health, p.material = u.next, nxt.model, nxt.health, nxt.health, nxt.material
    write(SQL.propUpgrade, { p.piece, p.model, p.health, p.max_health, p.material, id }, 'upgrade')
    TriggerClientEvent('wasteland:basebuilding:client:propUpgraded', -1, id, { piece = p.piece, model = p.model, health = p.health,
        max_health = p.max_health, material = p.material })
    notice(src, 'Upgraded to ' .. nxt.label .. '.')
end

-------------------------------------------------------------------------------
-- Lockpicking (doors, garages, storage): the minigame runs on the client
-------------------------------------------------------------------------------

local function raidNotice(c, what)
    local message = string.format('Your base is being raided! A %s was lockpicked.', what)
    local s = sourceOf(c.owner)
    if s then notice(s, message) else write(SQL.insertNotice, { c.owner, message, os.time() }, 'raid notice') end
end

local function lockpickStart(src, id)
    if not M.config.lockpick.enabled then return end
    local p = props[id]
    if not p or (p.category ~= 'door' and p.category ~= 'garage' and p.category ~= 'stash') then return end
    if not near(src, p.coords, M.config.targetDistance + 1.0) then return end
    local key = src .. ':' .. id
    if lockCooldown[key] and now() - lockCooldown[key] < M.config.lockpick.cooldownMs then notice(src, 'Wait a moment before trying again.'); return end
    if (inv():GetItemCount(src, M.config.lockpick.item) or 0) < 1 then notice(src, 'You need a ' .. label(M.config.lockpick.item):lower() .. '.'); return end
    picking[src] = { id = id, at = now() }
    local lp = M.config.lockpick
    TriggerClientEvent('wasteland:basebuilding:client:lockpick', src, { pins = lp.pins, zone = lp.zoneDegrees, speed = lp.speed, speedStep = lp.speedStep })
end

local function lockpickResult(src, success)
    local pk = picking[src]
    picking[src] = nil
    if not pk then return end
    local p = props[pk.id]
    if not p or not near(src, p.coords, M.config.targetDistance + 1.5) then return end
    lockCooldown[src .. ':' .. pk.id] = now()
    if success and now() - pk.at < M.config.lockpick.pins * 250 then
        M.log:warn('player %d finished the base lockpick too fast', src)
        success = false
    end
    if not success then
        inv():RemoveItem(src, M.config.lockpick.item, 1)
        notice(src, 'The lockpick snaps.')
        return
    end
    notice(src, 'Lock picked!')
    local c = Rules.covering(cupboards, p.coords)
    if c then raidNotice(c, p.category == 'stash' and 'storage box' or 'door') end
    if p.category == 'stash' then openStash(src, p.id, true) else setDoor(p, not p.is_open) end
end

-------------------------------------------------------------------------------
-- Upkeep
-------------------------------------------------------------------------------

local function upkeepTick()
    local u = M.config.upkeep
    if not u.enabled then return end
    local fraction = u.tickMinutes / (24 * 60)
    for id, c in pairs(cupboards) do
      if not c.infinite then -- an admin tool cupboard: supplies never run out
        local counts = pieceCounts(id)
        local owed, nextCarry = Rules.upkeepTick(counts, u.perPieceCostPerDay, fraction, carry[id])
        carry[id] = nextCarry
        local stash = inv():EnsureStash(supplyName(id), supplyOpts(c))
        for material, n in pairs(owed) do
            if n > 0 then
                local item = u.items[material]
                local have = stash and inv():GetItemCount(stash, item) or 0
                local take = math.min(have, n)
                if take > 0 then inv():RemoveItem(stash, item, take) end
                if take < n then
                    for pid, p in pairs(props) do
                        if p.cupboard_id == id and p.material == material then damage(pid, u.decayPerTick) end
                    end
                end
            end
        end
      end
    end
end

local function loop(token)
    while runToken == token do
        Citizen.Wait(M.config.upkeep.tickMinutes * 60000)
        if runToken ~= token then return end
        local ok, err = pcall(upkeepTick)
        if not ok then M.log:warn('upkeep: %s', tostring(err)) end
    end
end

local function powerLoop(token)
    while runToken == token do
        Citizen.Wait(60000)
        if runToken ~= token then return end
        local ok, err = pcall(powerTick)
        if not ok then M.log:warn('power: %s', tostring(err)) end
    end
end

-------------------------------------------------------------------------------
-- Players
-------------------------------------------------------------------------------

AddEventHandler('wasteland:players:characterLoaded', function(src, character)
    if not (M and M.active) then return end
    sync(src)
    local cid = type(character) == 'table' and character.id or characterOf(src)
    if not cid then return end
    Citizen.SetTimeout(5000, function()
        Citizen.CreateThread(function()
            local rows = WDB.query(SQL.selectNotices, { cid })
            if rows and #rows > 0 then
                for _, r in ipairs(rows) do notice(src, r.message) end
                WDB.update(SQL.deleteNotices, { cid })
            end
        end)
    end)
end)

for _, ev in ipairs({ 'wasteland:groups:joined', 'wasteland:groups:left', 'wasteland:groups:disbanded', 'wasteland:groups:created' }) do
    AddEventHandler(ev, function() if M and M.active then Citizen.SetTimeout(200, sendMineAll) end end)
end

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then meleeCooldown[src], picking[src], adminBuild[src], wireHurt[src], resting[src] = nil, nil, nil, nil, nil end
end)

local function useBuildItem(src)
    if not characterOf(src) then return false end
    TriggerClientEvent('wasteland:basebuilding:client:build', src, buildView(src))
    return 0
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local ANY = { type = 'table', allowUnknown = true }

M = Wasteland.DefineModule({
    name = 'basebuilding',
    version = '1.0.0',
    description = 'Base building: tool cupboards, snapping pieces, doors, storage, upkeep, raids',
    core = '^1.1.0',
    dependencies = { database = '^0.1.0', players = '^0.1.0', inventory = '^0.1.0' },
    optionalDependencies = { groups = '^0.1.0' },
    async = true,
    config = {
        file = 'basebuilding.lua',
        optional = true,
        schema = { type = 'table', fields = {
            buildItem = { type = 'string', default = 'building_plan', pattern = '^[%w_]+$' },
            propsResource = { type = 'string', default = 'wasteland_buildprops', maxLength = 64,
                description = "The resource with the building props ('' = none to check)" },
            cupboard = { type = 'table', fields = {
                piece = { type = 'string', default = 'toolcupboard' },
                radius = { type = 'number', default = 40.0, min = 5, max = 200 },
                minGap = { type = 'number', default = 10.0, min = 0, max = 200 },
                safeRadius = { type = 'number', default = 12.0, min = 0, max = 100,
                    description = 'Zombies stay out of this many metres around a tool cupboard (0 = off)' },
                safeMinutes = { type = 'number', default = 60, min = 0, max = 100000,
                    description = 'How long (real minutes) after placing the zone lasts (0 = for ever)' },
            } },
            freeBuild = { type = 'table', fields = {
                enabled = { type = 'boolean', default = true },
                categories = { type = 'array', default = { 'structure', 'door', 'garage', 'defense' },
                    items = { type = 'enum', values = { 'structure', 'door', 'garage', 'stash', 'defense' } } },
                hours = { type = 'number', default = 12, min = 0, max = 100000, description = 'How long pieces built without a cupboard last (0 = for ever)' },
            } },
            lockpick = { type = 'table', fields = {
                enabled = { type = 'boolean', default = true },
                item = { type = 'string', default = 'lockpick', pattern = '^[%w_]+$' },
                pins = { type = 'integer', default = 4, min = 1, max = 10 },
                zoneDegrees = { type = 'number', default = 26, min = 5, max = 120 },
                speed = { type = 'number', default = 150, min = 30, max = 720 },
                speedStep = { type = 'number', default = 30, min = 0, max = 360 },
                cooldownMs = { type = 'integer', default = 5000, min = 0, max = 600000 },
            } },
            upkeep = { type = 'table', fields = {
                enabled = { type = 'boolean', default = true },
                tickMinutes = { type = 'number', default = 5, min = 1, max = 1440 },
                perPieceCostPerDay = { type = 'map', default = { wood = 1, stone = 1, metal = 1 }, keys = { type = 'string' },
                    values = { type = 'number', min = 0, max = 100000 } },
                decayPerTick = { type = 'integer', default = 2, min = 0, max = 10000 },
                supplyGrid = { type = 'table', fields = {
                    width = { type = 'integer', default = 8, min = 1, max = 20 },
                    height = { type = 'integer', default = 6, min = 1, max = 20 },
                    maxWeight = { type = 'number', default = 300, min = 1, max = 100000 },
                } },
                items = { type = 'map', default = { wood = 'wood_planks', stone = 'stone', metal = 'metal_sheet' }, keys = { type = 'string' },
                    values = { type = 'string', pattern = '^[%w_]+$' } },
            } },
            interact = { type = 'table', fields = { distance = { type = 'number', default = 2.5, min = 1, max = 10 } } },
            targetDistance = { type = 'number', default = 4.0, min = 1, max = 15 },
            streamRadius = { type = 'number', default = 150.0, min = 30, max = 1000 },
            refund = { type = 'number', default = 0.5, min = 0, max = 1 },
            placement = ANY,
            categoryOrder = { type = 'array', default = { 'structure', 'door', 'garage', 'stash', 'furniture', 'power', 'cupboard' }, items = { type = 'string' } },
            categoryLabels = { type = 'map', default = {}, keys = { type = 'string' }, values = { type = 'string' } },
            pieces = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%w_]+$' }, values = { type = 'table', allowUnknown = true, fields = {
                label = { type = 'string', required = true },
                model = { type = 'string', required = true },
                category = { type = 'enum', values = { 'cupboard', 'structure', 'door', 'garage', 'stash', 'defense', 'power', 'furniture' }, required = true },
                cost = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%w_]+$' }, values = { type = 'integer', min = 1, max = 100000 } },
                health = { type = 'integer', default = 500, min = 1, max = 100000 },
                material = { type = 'enum', values = { 'wood', 'stone', 'metal' }, default = 'wood' },
                family = { type = 'string' },
                hidden = { type = 'boolean', default = false },
                openAngleOffset = { type = 'number' },
                openLift = { type = 'number', min = 0.1, max = 20, description = 'Garage doors: metres they roll up' },
                altModels = { type = 'array', default = {}, items = { type = 'string', pattern = '^[%w_]+$' },
                    description = 'Models tried in order when the game lacks `model`' },
                contactDamage = { type = 'number', min = 0, max = 1000, description = 'Defenses: damage a second to zombies touching it' },
                slow = { type = 'number', min = 0.05, max = 1, description = 'Defenses: speed share of zombies touching it' },
                wearPerTouch = { type = 'number', min = 0, max = 10000, description = 'Defenses: durability lost per zombie touch' },
                touchRadius = { type = 'number', min = 0.3, max = 10, description = 'Defenses: how close counts as touching' },
                scale = { type = 'number', min = 0.2, max = 5, description = 'Drawn this many times bigger (the look only)' },
                interactDistance = { type = 'number', min = 1, max = 20, description = 'Doors: E works from this far (also from a vehicle)' },
                passThrough = { type = 'boolean', description = 'Doors: swing through players and vehicles' },
                ladder = { type = 'boolean', description = 'A ceiling with a ladder hatch: E climbs up or down' },
                wireDamage = { type = 'number', min = 0, max = 1000, description = 'Barbed wire on top: damage a second to anyone touching it' },
                wireBleed = { type = 'number', min = 0, max = 1, description = 'Barbed wire: chance a touch makes a player bleed' },
                wireFrom = { type = 'number', min = 0, max = 50, description = 'Barbed wire: from this height (m above the base)' },
                wireTo = { type = 'number', min = 0, max = 50, description = 'Barbed wire: up to this height' },
                wireReach = { type = 'number', min = 0.1, max = 5, description = 'Barbed wire: this close to the wall line counts' },
                needsPower = { type = 'boolean', description = 'Only works while a running generator is in range (electric fence)' },
                adminOnly = { type = 'boolean', default = false, description = 'Only admins (the F10 admin panel) can build it' },
                infiniteUpkeep = { type = 'boolean', default = false, description = 'A tool cupboard whose upkeep never runs out (nothing to put in it)' },
                bed = { type = 'table', nullable = true, fields = {
                    tickSeconds = { type = 'number', default = 10, min = 1, max = 600 },
                    health = { type = 'number', default = 2, min = 0, max = 200, description = 'Health back each tick' },
                    infection = { type = 'number', default = 1.5, min = 0, max = 100, description = 'Infection taken off each tick' },
                    lie = { type = 'table', nullable = true, fields = {
                        x = { type = 'number', default = 0.0 }, y = { type = 'number', default = 0.0 },
                        up = { type = 'number', default = 0.47 }, turn = { type = 'number', default = 270.0 },
                    } },
                } },
                shock = { type = 'boolean', description = 'Touching it shocks: players stagger, zombies are thrown back' },
                generator = { type = 'table', nullable = true, fields = {
                    tankLitres = { type = 'number', default = 20, min = 1, max = 1000 },
                    litresPerHour = { type = 'number', default = 2, min = 0, max = 1000 },
                    powerRadius = { type = 'number', default = 40, min = 1, max = 500 },
                    noise = { type = 'number', default = 30, min = 0, max = 500, description = 'Zombies this close come to look while it runs' },
                    unlimited = { type = 'boolean', default = false, description = 'Needs no fuel (admin generator)' },
                } },
                light = { type = 'table', nullable = true, fields = {
                    height = { type = 'number', default = 1.5, min = -20, max = 20 },
                    range = { type = 'number', default = 15, min = 1, max = 100 },
                    intensity = { type = 'number', default = 5, min = 0.1, max = 100 },
                    color = { type = 'array', default = { 255, 230, 200 }, items = { type = 'integer', min = 0, max = 255 } },
                } },
                grid = { type = 'table', nullable = true, fields = {
                    width = { type = 'integer', required = true, min = 1, max = 20 },
                    height = { type = 'integer', required = true, min = 1, max = 20 },
                    maxWeight = { type = 'number', default = 100, min = 1, max = 100000 },
                } },
            } } },
            upgrades = { type = 'map', default = {}, keys = { type = 'string' }, values = { type = 'table', fields = {
                next = { type = 'string', required = true },
                cost = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%w_]+$' }, values = { type = 'integer', min = 1, max = 100000 } },
            } } },
            raid = ANY,
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        local c = M.config
        -- defaults for the free-form sections
        c.placement = c.placement or {}
        local pd = { rotateStep = 45.0, fineRotateSpeed = 30.0, fineHeightSpeed = 0.15, heightStep = 0.05, maxPlaceDistance = 15.0, snapDistance = 2.0,
            wallFacesOutward = true, snapOverlap = 0.0 }
        for k, v in pairs(pd) do if c.placement[k] == nil then c.placement[k] = v end end
        if c.placement.noBuildInSafeZones == nil then c.placement.noBuildInSafeZones = true end
        c.raid = c.raid or {}
        c.raid.explosionDamage = c.raid.explosionDamage or {}
        c.raid.explosionRadius = c.raid.explosionRadius or 4.0
        -- only blasts from explosives a player threw count (item -> explosion type)
        if c.raid.requireThrow == nil then c.raid.requireThrow = true end
        c.raid.thrown = c.raid.thrown or { weapon_grenade = 0, weapon_stickybomb = 2, weapon_molotov = 3 }
        c.raid.throwRange = c.raid.throwRange or 80.0
        c.raid.throwSeconds = c.raid.throwSeconds or 30
        c.raid.stickySeconds = c.raid.stickySeconds or 1800
        c.raid.melee = c.raid.melee or { enabled = false, cooldownMs = 850, woodDamage = 5 }
        if c.raid.melee.cupboardDamage == nil then c.raid.melee.cupboardDamage = 10 end
        c.raid.repair = c.raid.repair or { amount = {}, cost = {} }
        -- zombies hitting walls, doors and gates (wasteland_zombies `ai.barricades`)
        c.raid.zombies = c.raid.zombies or {}
        local zd = { enabled = true, damage = { wood = 4, stone = 2, metal = 1 }, noticeMinutes = 3,
            pieces = { 'wall', 'doorway', 'windowframe', 'halfwall', 'door', 'gateframe', 'gatedoor', 'garagedoor' } }
        for k, v in pairs(zd) do if c.raid.zombies[k] == nil then c.raid.zombies[k] = v end end
        if c.raid.enabled == nil then c.raid.enabled = true end
        -- every item named must exist
        local function known(item) return inv():GetItemDefinition(item) ~= nil end
        local need = { c.buildItem, c.lockpick.item }
        for _, item in pairs(c.upkeep.items) do need[#need + 1] = item end
        for _, p in pairs(c.pieces) do for item in pairs(p.cost or {}) do need[#need + 1] = item end end
        for _, u in pairs(c.upgrades) do
            if not c.pieces[u.next] then return false, 'basebuilding.lua: an upgrade leads to unknown piece "' .. u.next .. '"' end
            for item in pairs(u.cost) do need[#need + 1] = item end
        end
        for _, rc in pairs(c.raid.repair.cost or {}) do need[#need + 1] = rc.item end
        for _, item in ipairs(need) do
            if not known(item) then return false, string.format('basebuilding.lua names item "%s", which is not in inventory.lua items', tostring(item)) end
        end
        if not c.pieces[c.cupboard.piece] then return false, 'basebuilding.lua: cupboard.piece is not a piece' end
        if c.propsResource ~= '' and GetResourceState(c.propsResource) ~= 'started' then
            M.log:warn('the props pack "%s" is not running: the pieces will be invisible. Install it and ensure it before wasteland_basebuilding '
                .. "(or set basebuilding.lua propsResource to your own props resource, or to '' for GTA props).", c.propsResource)
        end
        cupboards, props, carry, meleeCooldown, lockCooldown, picking = {}, {}, {}, {}, {}, {}
        local token = {}
        runToken = token
        Citizen.CreateThread(function()
            local ok, err = WDB.migrate('basebuilding', WLBB.MIGRATIONS)
            if runToken ~= token then return end
            if not ok then return M.fail('database migrations failed: ' .. tostring(err)) end
            local cr, e1 = WDB.query(SQL.selectCupboards, {})
            local ar, e2 = WDB.query(SQL.selectAuth, {})
            local pr, e3 = WDB.query(SQL.selectProps, {})
            if runToken ~= token then return end
            if not cr or not ar or not pr then return M.fail('could not load bases: ' .. tostring(e1 or e2 or e3)) end
            for _, r in ipairs(cr) do
                cupboards[r.id] = { id = r.id, owner = r.owner_id, coords = { x = r.x, y = r.y, z = r.z }, heading = r.heading + 0.0,
                    radius = r.radius + 0.0, health = r.health, max_health = r.max_health, auth = {}, created = tonumber(r.created_unix) or 0,
                    infinite = r.infinite == 1 or r.infinite == true }
                cupboards[r.id].safeEnded = safeLeft(cupboards[r.id]) == 0
            end
            for _, r in ipairs(ar) do if cupboards[r.cupboard_id] then cupboards[r.cupboard_id].auth[r.character_id] = r.name end end
            local skipped = 0
            for _, r in ipairs(pr) do
                if c.pieces[r.piece] then
                    props[r.id] = { id = r.id, cupboard_id = r.cupboard_id, owner = r.owner_id, created = tonumber(r.created_unix) or 0,
                        -- the model set for the piece now (so changing props packs updates built bases)
                        category = r.category, piece = r.piece, model = c.pieces[r.piece].model or r.model,
                        coords = { x = r.x, y = r.y, z = r.z }, heading = r.heading + 0.0, is_open = r.is_open == 1 or r.is_open == true,
                        health = r.health, max_health = r.max_health, material = r.material, fuel = tonumber(r.fuel) or 0 }
                else
                    skipped = skipped + 1
                end
            end
            if skipped > 0 then M.log:warn('%d stored pieces were skipped (their kind is gone from basebuilding.lua)', skipped) end
            local nc, np = 0, 0
            for _ in pairs(cupboards) do nc = nc + 1 end
            for _ in pairs(props) do np = np + 1 end
            M.log:info('%d tool cupboards and %d pieces loaded', nc, np)
            local okUse, errUse = inv():RegisterUsable(c.buildItem, useBuildItem)
            if not okUse then M.log:warn('could not register the build item: %s', tostring(errUse)) end
            sync(-1)
            sendMineAll()
            Citizen.CreateThread(function() loop(token) end)
            Citizen.CreateThread(function() powerLoop(token) end)
            M.ready()
        end)
        return true
    end,
    onShutdown = function()
        runToken = nil
        TriggerClientEvent('wasteland:basebuilding:client:sync', -1, { cupboards = {}, props = {} })
    end,
})

local RATE = { burst = 8, perSecond = 3 }
-- /adminbuild: admins toggle free building (no materials, no refunds while on).
RegisterCommand('adminbuild', function(src)
    src = tonumber(src)
    if not src or src <= 0 then print('/adminbuild is for players in game') return end
    local allowed = IsPlayerAceAllowed(tostring(src), 'wasteland.admin')
    if not (allowed == true or allowed == 1) then notice(src, 'Only admins can use admin build.'); return end
    if not (M and M.active) then return end
    adminBuild[src] = not adminBuild[src] or nil
    if adminBuild[src] then
        notice(src, 'Admin build ON: everything is free (no materials, no refunds). Type /adminbuild to turn it off.')
        if characterOf(src) then TriggerClientEvent('wasteland:basebuilding:client:build', src, buildView(src)) end
    else
        notice(src, 'Admin build OFF.')
    end
    M.log:info('player %d turned admin build %s', src, adminBuild[src] and 'on' or 'off')
end, false)

--- IsAdminBuilding(source) -> boolean
exports('IsAdminBuilding', function(src) return adminBuild[tonumber(src) or -1] == true end)

local ID = { type = 'integer', required = true, min = 1 }
local COORD = { type = 'number', required = true, min = -20000, max = 20000 }
local AT = { type = 'table', required = true, fields = { x = COORD, y = COORD, z = COORD } }

M.netEvent('wasteland:basebuilding:server:sync', { rateLimit = { burst = 2, perSecond = 0.2 } }, function(src) sync(src) end)
M.netEvent('wasteland:basebuilding:server:buildMenu', { rateLimit = RATE }, function(src)
    TriggerClientEvent('wasteland:basebuilding:client:build', src, buildView(src))
end)
M.netEvent('wasteland:basebuilding:server:place', {
    args = { { type = 'string', required = true, pattern = '^[%w_]+$', maxLength = 40 }, COORD, COORD, COORD, { type = 'number', required = true, min = -720, max = 720 } },
    rateLimit = { burst = 4, perSecond = 1 },
}, function(src, key, x, y, z, h) Citizen.CreateThread(function() placeProp(src, key, x, y, z, h) end) end)
M.netEvent('wasteland:basebuilding:server:remove', { args = { ID }, rateLimit = RATE }, function(src, id) Citizen.CreateThread(function() removeProp(src, id) end) end)
M.netEvent('wasteland:basebuilding:server:move', { args = { ID, COORD, COORD, COORD, { type = 'number', required = true, min = -720, max = 720 } }, rateLimit = RATE },
    function(src, id, x, y, z, heading) moveProp(src, id, x, y, z, heading) end)
M.netEvent('wasteland:basebuilding:server:removeCupboard', { args = { ID }, rateLimit = RATE }, function(src, id) removeCupboard(src, id) end)
M.netEvent('wasteland:basebuilding:server:generator', { args = { ID }, rateLimit = RATE }, function(src, id) generatorToggle(src, id) end)
M.netEvent('wasteland:basebuilding:server:generatorFuel', { args = { ID }, rateLimit = RATE }, function(src, id) generatorFuel(src, id) end)
M.netEvent('wasteland:basebuilding:server:rest', { args = { ID, { type = 'boolean', required = true } }, rateLimit = RATE },
    function(src, id, on) setResting(src, id, on) end)
M.netEvent('wasteland:basebuilding:server:wire', { args = { ID }, rateLimit = { burst = 3, perSecond = 2 } }, function(src, id) touchWire(src, id) end)
M.netEvent('wasteland:basebuilding:server:moveCupboard', { args = { ID, COORD, COORD, COORD, { type = 'number', required = true, min = -720, max = 720 } }, rateLimit = RATE },
    function(src, id, x, y, z, heading) moveCupboard(src, id, x, y, z, heading) end)
M.netEvent('wasteland:basebuilding:server:door', { args = { ID }, rateLimit = RATE }, function(src, id) toggleDoor(src, id) end)
M.netEvent('wasteland:basebuilding:server:stash', { args = { ID }, rateLimit = RATE }, function(src, id) openStash(src, id) end)
M.netEvent('wasteland:basebuilding:server:supplies', { args = { ID }, rateLimit = RATE }, function(src, id) openSupplies(src, id) end)
M.netEvent('wasteland:basebuilding:server:cupboard', { args = { ID }, rateLimit = RATE }, function(src, id) openCupboard(src, id) end)
M.netEvent('wasteland:basebuilding:server:authorize', { args = { ID, { type = 'integer', required = true, min = 1, max = 65535 } }, rateLimit = RATE },
    function(src, id, target) authorize(src, id, target) end)
M.netEvent('wasteland:basebuilding:server:revoke', { args = { ID, ID }, rateLimit = RATE }, function(src, id, cid) revoke(src, id, cid) end)
M.netEvent('wasteland:basebuilding:server:repair', { args = { ID }, rateLimit = RATE }, function(src, id) repairProp(src, id) end)
M.netEvent('wasteland:basebuilding:server:repairAll', { args = { ID }, rateLimit = RATE }, function(src, id) repairAll(src, id) end)
M.netEvent('wasteland:basebuilding:server:upgrade', { args = { ID }, rateLimit = RATE }, function(src, id) upgrade(src, id) end)
M.netEvent('wasteland:basebuilding:server:lockpick', { args = { ID }, rateLimit = RATE }, function(src, id) lockpickStart(src, id) end)
M.netEvent('wasteland:basebuilding:server:lockpickResult', { args = { { type = 'boolean', required = true } }, rateLimit = RATE },
    function(src, ok) lockpickResult(src, ok) end)
M.netEvent('wasteland:basebuilding:server:explosion', { args = { ID, { type = 'integer', required = true, min = 0, max = 100 }, AT, { type = 'boolean', required = true } },
    rateLimit = { burst = 20, perSecond = 10 } }, function(src, id, kind, at, isCupboard) explosion(src, id, kind, at, isCupboard) end)
M.netEvent('wasteland:basebuilding:server:melee', { args = { ID, { type = 'boolean' } }, rateLimit = { burst = 6, perSecond = 3 } },
    function(src, id, isCupboard) melee(src, id, isCupboard == true) end)

-- Pieces built without a tool cupboard go after freeBuild.hours (unless a
-- cupboard claimed them since).
local function expireFree()
    local fb = M.config.freeBuild
    if not fb or not fb.hours or fb.hours <= 0 then return end
    local t = os.time()
    for id, p in pairs(props) do
        if not p.cupboard_id and p.owner and p.category ~= 'stash' and (p.created or 0) > 0 and t - p.created > fb.hours * 3600 then
            props[id] = nil
            write(SQL.deleteProp, { id }, 'temporary piece gone')
            TriggerClientEvent('wasteland:basebuilding:client:propRemoved', -1, id)
        end
    end
end
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000)
        if M and M.active then pcall(expireFree) end
    end
end)

-- A cupboard's zombie-free zone dropped: tell the owner (once).
local function checkSafeZones()
    for _, c in pairs(cupboards) do
        if not c.safeEnded and safeLeft(c) == 0 then
            c.safeEnded = true
            local s = sourceOf(c.owner)
            if s then notice(s, 'The zombie-free zone round your base has dropped. Zombies can come in now - defend it!') end
            TriggerClientEvent('wasteland:basebuilding:client:safeZoneEnded', -1, c.id)
        end
    end
end
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(15000)
        if M and M.active then pcall(checkSafeZones) end
    end
end)

--- ZombieHit(pieceId, zombieCoords) -> health left | nil   (wasteland_zombies:
--- a zombie that stands at a wall, door or gate hits it; open doors, other
--- pieces and materials that take no zombie damage are left alone)
exports('ZombieHit', function(id, at)
    if not (M and M.active) or type(at) ~= 'table' then return nil end
    local zb = zombieBarricades(M.config)
    local p = props[tonumber(id)]
    if not zb or not p then return nil end
    if not zb.families[familyOf(M.config, p)] or p.is_open then return nil end
    local dmg = tonumber(zb.damage[p.material]) or 0
    if dmg <= 0 then return nil end
    if Rules.dist({ x = at.x, y = at.y, z = at.z or p.coords.z }, p.coords) > 4.0 then return nil end
    damage(p.id, dmg)
    -- tell the owner (not on every hit)
    local c = p.cupboard_id and cupboards[p.cupboard_id]
    local t = now()
    if c and (not zombieNotice[c.id] or t - zombieNotice[c.id] > M.config.raid.zombies.noticeMinutes * 60000) then
        zombieNotice[c.id] = t
        local s = sourceOf(c.owner)
        if s then notice(s, 'Zombies are attacking your base!') end
    end
    return props[p.id] and props[p.id].health or 0
end)

--- IsInBaseZone(coords) -> boolean   (within cupboard.safeRadius of a tool
--- cupboard: zombies do not spawn, chase or hit there; ones inside are removed)
exports('IsInBaseZone', function(coords)
    if not (M and M.active) or type(coords) ~= 'table' then return false end
    local r = M.config.cupboard.safeRadius
    if not r or r <= 0 then return false end
    local p = { x = coords.x, y = coords.y, z = coords.z or 0 }
    for _, c in pairs(cupboards) do
        if Rules.dist(p, c.coords) <= r and safeLeft(c) ~= 0 then return true end
    end
    return false
end)

--- ZombieTouch(pieceId, zombieCoords) -> health left | nil   (wasteland_zombies:
--- a zombie walked into barbed wire or spikes; the piece wears)
exports('ZombieTouch', function(id, at)
    if not (M and M.active) or type(at) ~= 'table' then return nil end
    local p = props[tonumber(id)]
    local piece = p and M.config.pieces[p.piece]
    if not piece or not piece.wearPerTouch then return nil end
    local reach = (piece.touchRadius or 1.8) + 1.5
    if Rules.dist({ x = at.x, y = at.y, z = at.z or p.coords.z }, p.coords) > reach + 1.0 then return nil end
    damage(p.id, piece.wearPerTouch)
    return props[p.id] and props[p.id].health or 0
end)

--- GetCupboardAt(coords) -> { id, owner } | nil
exports('GetCupboardAt', function(coords)
    if not (M and M.active) or type(coords) ~= 'table' then return nil end
    local c = Rules.covering(cupboards, coords)
    return c and { id = c.id, owner = c.owner } or nil
end)
