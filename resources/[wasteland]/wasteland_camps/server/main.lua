-- wasteland_camps :: server/main.lua
-- Module "camps": safe zones (zombies use IsInSafeZone), map blips and
-- entry messages (client), and traders that buy and sell for cash with a
-- stock that refills over time. Every trade is checked here: the player
-- stands at the trader, the trader deals in that item, the stock, the
-- cash and the room in the inventory. Stock lives in memory (full again
-- after a restart).

local Zones = WLC.Zones
local M
local camps = {}       -- list of camps (config, with index)
local stock = {}       -- "<camp>:<trader>" -> { [item] = count }
local runToken = nil

local function inv() return exports.wasteland_inventory end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

local function traderOf(campId, index)
    for _, c in ipairs(camps) do
        if c.id == campId then return c, c.traders[index] end
    end
    return nil
end

local function stockKey(campId, index) return campId .. ':' .. index end

local function entryOf(shop, name)
    for _, e in ipairs(shop.items) do if e.name == name then return e end end
    return nil
end

local function initStock()
    stock = {}
    for _, c in ipairs(camps) do
        for i, t in ipairs(c.traders) do
            local s = {}
            for _, e in ipairs(M.config.shops[t.shop].items) do
                if e.stock then s[e.name] = e.stock end
            end
            stock[stockKey(c.id, i)] = s
        end
    end
end

-------------------------------------------------------------------------------
-- Trading
-------------------------------------------------------------------------------

-- What the trade screen shows: the shop, prices, stock, what the player
-- carries and their cash.
local function screenData(src, camp, index)
    local t = camp.traders[index]
    local shop = M.config.shops[t.shop]
    local s = stock[stockKey(camp.id, index)]
    local images, labels = {}, {}
    for _, it in ipairs(inv():GetItemList()) do images[it.name], labels[it.name] = it.image, it.label end
    local items = {}
    for _, e in ipairs(shop.items) do
        items[#items + 1] = {
            name = e.name, label = labels[e.name] or e.name, image = images[e.name],
            buy = e.buy, sell = e.sell, stock = e.stock and (s[e.name] or 0) or nil,
            have = inv():GetItemCount(src, e.name) or 0,
        }
    end
    return { camp = camp.id, trader = index, title = shop.label, place = camp.label, cash = inv():GetCash(src) or 0, items = items }
end

local function atTrader(src, campId, index)
    local camp, t = traderOf(campId, index)
    if not camp or not t then return nil end
    local p = playerCoords(src)
    if not p or Zones.dist3d(p, t.coords) > M.config.tradeDistance then return nil end
    return camp, t
end

local function send(src, camp, index, message, ok)
    local data = screenData(src, camp, index)
    data.message, data.ok = message, ok
    TriggerClientEvent('wasteland:camps:client:trader', src, data)
end

local function buy(src, campId, index, name, count)
    local camp, t = atTrader(src, campId, index)
    if not camp then return end
    local shop = M.config.shops[t.shop]
    local entry = entryOf(shop, name)
    local s = stock[stockKey(campId, index)]
    local left = entry and entry.stock and (s[name] or 0) or math.huge
    local price, why = Zones.buyCheck(entry, count, left, inv():GetCash(src) or 0)
    if not price then send(src, camp, index, why, false); return end
    local ok, err = inv():RemoveCash(src, price)
    if not ok then send(src, camp, index, 'Payment failed: ' .. tostring(err), false); return end
    local added, addErr = inv():AddItem(src, name, count)
    if not added then
        inv():AddCash(src, price) -- give the money back
        send(src, camp, index, addErr and addErr:find('room') and 'Not enough room in your inventory.' or tostring(addErr), false)
        return
    end
    if entry.stock then s[name] = left - count end
    M.log:info('player %d bought %d x %s for $%d at %s', src, count, name, price, campId)
    TriggerEvent('wasteland:camps:traded', src, 'buy', name, count, price, campId)
    send(src, camp, index, string.format('Bought %d x %s for $%d.', count, inv():GetItemDefinition(name).label, price), true)
end

local function sell(src, campId, index, name, count)
    local camp, t = atTrader(src, campId, index)
    if not camp then return end
    local shop = M.config.shops[t.shop]
    local entry = entryOf(shop, name)
    local pay, why = Zones.sellCheck(entry, count, inv():GetItemCount(src, name) or 0)
    if not pay then send(src, camp, index, why, false); return end
    local ok, err = inv():RemoveItem(src, name, count)
    if not ok then send(src, camp, index, tostring(err), false); return end
    local paid, payErr = inv():AddCash(src, pay)
    if not paid then
        inv():AddItem(src, name, count) -- give the items back
        send(src, camp, index, 'Make room for the cash first (' .. tostring(payErr) .. ').', false)
        return
    end
    if entry.stock then
        local s = stock[stockKey(campId, index)]
        s[name] = math.min(entry.stock, (s[name] or 0) + count)
    end
    M.log:info('player %d sold %d x %s for $%d at %s', src, count, name, pay, campId)
    TriggerEvent('wasteland:camps:traded', src, 'sell', name, count, pay, campId)
    send(src, camp, index, string.format('Sold %d x %s for $%d.', count, inv():GetItemDefinition(name).label, pay), true)
end

local function loop(token)
    local elapsed = 0
    while runToken == token do
        Citizen.Wait(60000)
        if runToken ~= token then return end
        elapsed = elapsed + 1
        if elapsed >= M.config.restockMinutes then
            elapsed = 0
            for _, c in ipairs(camps) do
                for i, t in ipairs(c.traders) do Zones.restock(M.config.shops[t.shop].items, stock[stockKey(c.id, i)]) end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local XYZ = { type = 'table', required = true, fields = {
    x = { type = 'number', required = true }, y = { type = 'number', required = true }, z = { type = 'number', required = true },
    heading = { type = 'number', default = 0 },
} }

local function clientConfig()
    local out = {}
    for _, c in ipairs(camps) do
        local traders = {}
        for i, t in ipairs(c.traders) do
            traders[i] = { label = M.config.shops[t.shop].label, model = t.model, coords = t.coords }
        end
        out[#out + 1] = { id = c.id, label = c.label, coords = c.coords, radius = c.radius, safe = c.safe, blip = c.blip, traders = traders }
    end
    return { camps = out }
end

M = Wasteland.DefineModule({
    name = 'camps',
    version = '0.1.0',
    description = 'Camps: safe zones, map blips, traders (cash, limited stock)',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', inventory = '^0.1.0' },
    config = {
        file = 'camps.lua',
        optional = true,
        schema = { type = 'table', fields = {
            restockMinutes = { type = 'integer', default = 10, min = 1, max = 1440 },
            chooseSpawnOnLogin = { type = 'boolean', default = true,
                description = 'Returning characters choose: last known position or a safe camp' },
            tradeDistance = { type = 'number', default = 4.0, min = 1, max = 20 },
            shops = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%a][%w_]*$' }, values = { type = 'table', fields = {
                label = { type = 'string', required = true, minLength = 1, maxLength = 40 },
                items = { type = 'array', default = {}, items = { type = 'table', fields = {
                    name = { type = 'string', required = true, pattern = '^[%w_]+$' },
                    buy = { type = 'integer', min = 1, max = 10000000 },
                    sell = { type = 'integer', min = 1, max = 10000000 },
                    stock = { type = 'integer', min = 0, max = 100000 },
                    restock = { type = 'integer', default = 1, min = 0, max = 100000 },
                } } },
            } } },
            camps = { type = 'array', default = {}, items = { type = 'table', fields = {
                id = { type = 'string', required = true, pattern = '^[%a][%w_]*$' },
                label = { type = 'string', required = true, minLength = 1, maxLength = 48 },
                coords = XYZ,
                radius = { type = 'number', required = true, min = 5, max = 1000 },
                safe = { type = 'boolean', default = true },
                -- Where a new character who picks this camp appears (default: the centre).
                spawn = { type = 'table', nullable = true, fields = {
                    x = { type = 'number', required = true }, y = { type = 'number', required = true },
                    z = { type = 'number', required = true }, heading = { type = 'number', default = 0 },
                } },
                blip = { type = 'table', fields = { sprite = { type = 'integer', default = 40 }, color = { type = 'integer', default = 2 } } },
                traders = { type = 'array', default = {}, items = { type = 'table', fields = {
                    shop = { type = 'string', required = true },
                    model = { type = 'string', default = 's_m_m_trucker_01', pattern = '^[%w_]+$' },
                    coords = XYZ,
                } } },
            } } },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        local ids = {}
        for _, c in ipairs(M.config.camps) do
            if ids[c.id] then return false, string.format('camps.lua: two camps have the id "%s"', c.id) end
            ids[c.id] = true
            for _, t in ipairs(c.traders) do
                if not M.config.shops[t.shop] then return false, string.format('camps.lua: camp "%s" has a trader with unknown shop "%s"', c.id, t.shop) end
            end
        end
        for shopName, shop in pairs(M.config.shops) do
            for _, e in ipairs(shop.items) do
                if not inv():GetItemDefinition(e.name) then
                    return false, string.format('camps.lua: shop "%s" names item "%s", which is not in inventory.lua items', shopName, e.name)
                end
                if not e.buy and not e.sell then return false, string.format('camps.lua: shop "%s" item "%s" has neither buy nor sell', shopName, e.name) end
            end
        end
        camps = M.config.camps
        initStock()
        local token = {}
        runToken = token
        Citizen.CreateThread(function() loop(token) end)
        TriggerClientEvent('wasteland:camps:client:config', -1, clientConfig())
        return true
    end,
    onShutdown = function() runToken = nil end,
})

local CAMP_ARGS = { { type = 'string', required = true, pattern = '^[%a][%w_]*$', maxLength = 48 }, { type = 'integer', required = true, min = 1, max = 100 } }
local TRADE_ARGS = { CAMP_ARGS[1], CAMP_ARGS[2], { type = 'string', required = true, pattern = '^[%w_]+$', maxLength = 48 },
    { type = 'integer', required = true, min = 1, max = 10000 } }
local RATE = { burst = 8, perSecond = 4 }

-------------------------------------------------------------------------------
-- New characters pick the camp they start at. They stay protected (no
-- damage, zombies and bandits ignore them) until they have arrived.
-------------------------------------------------------------------------------

local choosing = {}  -- source -> true while the choice is open

local function protect(src, on)
    if GetPlayerName(tostring(src)) then Player(src).state:set('wlProtected', on == true, true) end
end

AddEventHandler('wasteland:appearance:saved', function(src, characterId, appearance, reason)
    if reason ~= 'new' or not (M and M.active) then return end
    local list = {}
    for _, c in ipairs(M.config.camps) do
        if c.safe then list[#list + 1] = { id = c.id, label = c.label, traders = #c.traders } end
    end
    if #list == 0 then protect(src, false); return end
    choosing[src] = true
    protect(src, true)
    TriggerClientEvent('wasteland:camps:client:chooseSpawn', src, list)
end)

-- A returning character (not new, not a resource restart) chooses between
-- where they logged out and the safe camps.
AddEventHandler('wasteland:players:characterLoaded', function(src, character, restored)
    if restored or not (M and M.active) or not M.config.chooseSpawnOnLogin then return end
    if type(character) ~= 'table' then return end
    local hasLook = false
    if GetResourceState('wasteland_appearance') == 'started' then
        local ok, a = pcall(function() return exports.wasteland_appearance:GetAppearance(character.id) end)
        hasLook = ok and a ~= nil
    end
    if not hasLook then return end -- a new character: they choose after the creator
    local ok, last = pcall(function() return exports.wasteland_players:GetSavedPosition(src) end)
    last = ok and last or nil
    local list = {}
    if last then list[#list + 1] = { id = 'last', label = 'Last known position', last = true } end
    for _, c in ipairs(M.config.camps) do
        if c.safe then list[#list + 1] = { id = c.id, label = c.label, traders = #c.traders } end
    end
    if #list <= 1 then return end
    choosing[src] = { last = last, characterId = character.id }
    protect(src, true)
    -- after the players module has placed the ped (and survival knows if they are dead)
    Citizen.SetTimeout(1500, function()
        if not choosing[src] or choosing[src].characterId ~= character.id then return end
        if GetResourceState('wasteland_survival') == 'started' then
            local okDead, dead = pcall(function() return exports.wasteland_survival:IsDead(src) end)
            if okDead and dead then choosing[src] = nil; protect(src, false); return end
        end
        TriggerClientEvent('wasteland:camps:client:chooseSpawn', src, list, true)
    end)
end)

AddEventHandler('wasteland:players:characterUnloaded', function(src)
    if choosing[src] then choosing[src] = nil end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then choosing[src] = nil end
end)

M.netEvent('wasteland:camps:server:chooseSpawn', {
    args = { { type = 'string', required = true, pattern = '^[%a][%w_]*$', maxLength = 48 } },
    rateLimit = { burst = 3, perSecond = 1 },
}, function(src, campId)
    local open = choosing[src]
    if not open then return end
    if campId == 'last' and type(open) == 'table' and open.last then
        choosing[src] = nil
        M.log:info('player %d goes back to where they left', src)
        TriggerClientEvent('wasteland:camps:client:spawnAt', src, open.last, nil)
        Citizen.SetTimeout(8000, function() if not choosing[src] then protect(src, false) end end)
        TriggerEvent('wasteland:camps:spawnChosen', src, 'last')
        return
    end
    local camp
    for _, c in ipairs(M.config.camps) do if c.id == campId and c.safe then camp = c end end
    if not camp then return end
    choosing[src] = nil
    local at = camp.spawn or { x = camp.coords.x, y = camp.coords.y, z = camp.coords.z, heading = 0.0 }
    M.log:info('player %d starts at %s', src, camp.label)
    TriggerClientEvent('wasteland:camps:client:spawnAt', src, at, camp.label)
    -- Protected a little longer, until they have arrived and the ground loaded.
    Citizen.SetTimeout(8000, function() if not choosing[src] then protect(src, false) end end)
    TriggerEvent('wasteland:camps:spawnChosen', src, camp.id)
end)

M.netEvent('wasteland:camps:server:config', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    TriggerClientEvent('wasteland:camps:client:config', src, clientConfig())
end)

M.netEvent('wasteland:camps:server:open', { args = CAMP_ARGS, rateLimit = RATE }, function(src, campId, index)
    local camp = atTrader(src, campId, index)
    if not camp then return end
    send(src, camp, index)
end)

M.netEvent('wasteland:camps:server:buy', { args = TRADE_ARGS, rateLimit = RATE }, function(src, campId, index, name, count)
    buy(src, campId, index, name, count)
end)

M.netEvent('wasteland:camps:server:sell', { args = TRADE_ARGS, rateLimit = RATE }, function(src, campId, index, name, count)
    sell(src, campId, index, name, count)
end)

-------------------------------------------------------------------------------
-- Exports (camps api 0.1)
-------------------------------------------------------------------------------

--- IsInSafeZone(coords) -> boolean   (zombies: no spawning, no chasing)
exports('IsInSafeZone', function(coords)
    return type(coords) == 'table' and Zones.isSafe(camps, coords) or false
end)

--- GetCampAt(coords) -> { id, label } | nil
exports('GetCampAt', function(coords)
    local c = type(coords) == 'table' and Zones.campAt(camps, coords) or nil
    return c and { id = c.id, label = c.label } or nil
end)

--- GetCamps() -> list of { id, label, coords, radius, safe, traders = { { shop, coords } } }
exports('GetCamps', function()
    local out = {}
    for _, c in ipairs(camps) do
        local traders = {}
        for i, t in ipairs(c.traders) do traders[i] = { shop = t.shop, coords = t.coords } end
        out[#out + 1] = { id = c.id, label = c.label, coords = c.coords, radius = c.radius, safe = c.safe, traders = traders }
    end
    return out
end)
