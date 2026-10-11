-- wasteland_admin :: server/main.lua
-- Module "admin": the admin panel's server side. Every action is checked
-- against the admin ACE here (the panel itself is just a view), carried out
-- through the other modules' exports, and written to the action log
-- (wl_admin_log) and the console. Bans are kept in wl_bans, cached in
-- memory and checked while a player connects (players admission check).

local SQL = WLA_ADMIN.SQL
local M
local bans = {}            -- license -> active ban
local frozen = {}          -- source -> true
local runToken = nil

local function now() return os.time() end

local function isAdmin(src)
    if src == 0 then return true end
    local allowed = IsPlayerAceAllowed(tostring(src), M.config.adminAce)
    return allowed == true or allowed == 1
end

local function adminName(src)
    if src == 0 then return 'console' end
    return (GetPlayerName(tostring(src)) or ('player ' .. src)):sub(1, 64)
end

local function started(res) return GetResourceState(res) == 'started' end

local function result(src, action, ok, message)
    if src ~= 0 then TriggerClientEvent('wasteland:admin:client:result', src, { action = action, ok = ok, message = message }) end
end

--- Record an admin action (console + database, not waited for).
local function audit(src, action, target, details)
    local who = adminName(src)
    M.log:info('[audit] %s: %s %s %s', who, action, tostring(target or ''), tostring(details or ''))
    Citizen.CreateThread(function()
        local _, err = WDB.insert(SQL.insertLog, { who, action, target and tostring(target):sub(1, 128) or nil,
            details and tostring(details):sub(1, 500) or nil, now() })
        if err then M.log:error('could not write the admin log: %s', err) end
    end)
end

-------------------------------------------------------------------------------
-- Bans
-------------------------------------------------------------------------------

local function banMessage(ban)
    local untilText = ban.expires_unix and os.date('%Y-%m-%d %H:%M', ban.expires_unix) or 'permanently'
    return string.format('You are banned from this server %s%s. Reason: %s (ban #%d)',
        ban.expires_unix and 'until ' or '', untilText, ban.reason, ban.id)
end

local function activeBan(license)
    local ban = bans[license]
    if ban and ban.expires_unix and ban.expires_unix <= now() then
        bans[license] = nil
        return nil
    end
    return ban
end

local function loadBans()
    local rows, err = WDB.query(SQL.selectActiveBans, { now() })
    if err then return false, err end
    bans = {}
    for _, r in ipairs(rows) do
        r.id, r.expires_unix = tonumber(r.id), tonumber(r.expires_unix)
        bans[r.license] = r
    end
    return true
end

--- Ban a license (thread only). minutes = 0 or nil: permanent.
local function ban(src, license, name, reason, minutes)
    local created = now()
    local expires = (minutes and minutes > 0) and (created + minutes * 60) or nil
    local id, err = WDB.insert(SQL.insertBan, { license, name or '', reason, adminName(src), created, expires })
    if err or not id then return false, 'could not store the ban: ' .. tostring(err) end
    local entry = { id = tonumber(id), license = license, name = name or '', reason = reason,
        banned_by = adminName(src), created_unix = created, expires_unix = expires }
    bans[license] = entry
    audit(src, 'ban', string.format('%s (%s)', name or '?', license),
        string.format('%s; %s', reason, expires and (minutes .. ' min') or 'permanent'))
    -- Kick them if they are online.
    for _, s in ipairs(GetPlayers()) do
        if GetPlayerIdentifierByType(s, 'license') == license then DropPlayer(s, banMessage(entry)) end
    end
    return true, entry
end

-------------------------------------------------------------------------------
-- Panel data
-------------------------------------------------------------------------------

local function playerList()
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local entry = { id = src, name = GetPlayerName(s), ping = GetPlayerPing(s), frozen = frozen[src] == true }
        if started('wasteland_players') then
            local c = exports.wasteland_players:GetCharacter(src)
            if c then entry.character = { id = c.id, firstName = c.firstName, lastName = c.lastName } end
        end
        if started('wasteland_survival') then entry.stats = exports.wasteland_survival:GetStats(src) end
        if entry.character then
            if started('wasteland_inventory') then entry.cash = exports.wasteland_inventory:GetCash(src) end
            if started('wasteland_quests') then entry.quests = exports.wasteland_quests:GetQuestSummary(src) end
            if started('wasteland_crafting') then entry.recipes = exports.wasteland_crafting:GetRecipeSummary(src) end
        end
        out[#out + 1] = entry
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function panelData()
    local data = { players = playerList(), items = {}, modules = {}, issues = {} }
    for _, s in ipairs(exports.wasteland_core:GetModuleStatuses()) do
        data.modules[#data.modules + 1] = { name = s.name, version = s.version, state = s.state,
            health = s.health, detail = s.healthDetail or s.reason }
    end
    for _, r in ipairs(exports.wasteland_core:GetRecentIssues(30)) do data.issues[#data.issues + 1] = r end
    if started('wasteland_inventory') then data.items = exports.wasteland_inventory:GetItemList() end
    -- Live view: what the world is doing right now.
    local live = { players = #data.players, uptimeMinutes = math.floor(GetGameTimer() / 60000) }
    if started('wasteland_zombies') then
        local total, alive = exports.wasteland_zombies:GetZombieCount()
        live.zombies = { total = total, alive = alive }
    end
    if started('wasteland_vehicles') then live.vehicles = exports.wasteland_vehicles:GetVehicleStats() end
    if started('wasteland_loot') then
        live.loot = exports.wasteland_loot:GetLootStats()
        data.loot = exports.wasteland_loot:GetLootAdminData()
    end
    data.live = live
    if started('wasteland_world') then
        local h, m, f = exports.wasteland_world:GetTime()
        local w, dyn = exports.wasteland_world:GetWeather()
        data.world = { hour = h, minute = m, frozen = f, weather = w, dynamic = dyn,
            weathers = exports.wasteland_world:GetWeatherNames() }
    end
    return data
end

local function sendPanel(src)
    TriggerClientEvent('wasteland:admin:client:data', src, panelData())
end

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------

local function targetOnline(target)
    return target and GetPlayerName(tostring(target)) ~= nil
end

local function coordsOf(src)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

local ACTIONS = {}

ACTIONS.teleportTo = function(src, p)
    local c = coordsOf(p.target)
    if not c then return false, 'their position is unknown (OneSync is required)' end
    TriggerClientEvent('wasteland:admin:client:teleport', src, c)
    return true, 'Teleported to player ' .. p.target
end

ACTIONS.bring = function(src, p)
    local c = coordsOf(src)
    if not c then return false, 'your position is unknown (OneSync is required)' end
    TriggerClientEvent('wasteland:admin:client:teleport', p.target, c)
    return true, 'Brought player ' .. p.target
end

ACTIONS.heal = function(src, p)
    if not started('wasteland_survival') then return false, 'survival module is not running' end
    if not exports.wasteland_survival:Heal(p.target) then return false, 'cannot heal (dead or no character)' end
    return true, 'Healed player ' .. p.target
end

ACTIONS.revive = function(src, p)
    if not started('wasteland_survival') then return false, 'survival module is not running' end
    if not exports.wasteland_survival:Revive(p.target) then return false, 'that player is not dead' end
    return true, 'Revived player ' .. p.target
end

ACTIONS.freeze = function(src, p)
    frozen[p.target] = p.enabled == true or nil
    TriggerClientEvent('wasteland:admin:client:freeze', p.target, p.enabled == true)
    return true, (p.enabled and 'Froze' or 'Unfroze') .. ' player ' .. p.target
end

ACTIONS.kick = function(src, p)
    local reason = (p.reason and p.reason ~= '') and p.reason or 'Kicked by an admin'
    DropPlayer(tostring(p.target), 'Kicked: ' .. reason)
    return true, 'Kicked player ' .. p.target
end

ACTIONS.ban = function(src, p)
    if not p.reason or p.reason == '' then return false, 'a ban needs a reason' end
    local license = GetPlayerIdentifierByType(tostring(p.target), 'license')
    if not license then return false, 'that player has no license identifier' end
    local ok, err = ban(src, license, GetPlayerName(tostring(p.target)), p.reason, p.minutes)
    if not ok then return false, err end
    return true, 'Banned player ' .. p.target
end

ACTIONS.banLicense = function(src, p)
    if not p.license or not p.license:match('^license:%x+$') then return false, 'enter a license like license:abc123...' end
    if not p.reason or p.reason == '' then return false, 'a ban needs a reason' end
    local ok, err = ban(src, p.license, p.name, p.reason, p.minutes)
    if not ok then return false, err end
    return true, 'Banned ' .. p.license
end

ACTIONS.unban = function(src, p)
    local affected, err = WDB.update(SQL.revokeBan, { now(), adminName(src), p.banId })
    if err then return false, 'database error: ' .. err end
    if (affected or 0) < 1 then return false, 'no active ban with that number' end
    for license, b in pairs(bans) do if b.id == p.banId then bans[license] = nil end end
    return true, 'Lifted ban #' .. p.banId
end

local STATS = { hunger = true, thirst = true, infection = true, bleeding = true, temperature = true }
ACTIONS.setStat = function(src, p)
    if not STATS[p.stat] or type(p.value) ~= 'number' then return false, 'choose a stat and a value' end
    if not started('wasteland_survival') then return false, 'survival module is not running' end
    local s = exports.wasteland_survival:GetStats(p.target)
    if not s then return false, 'that player has no character' end
    local delta = p.value - (s[p.stat] or 0)
    local ok
    if p.stat == 'bleeding' then
        ok = exports.wasteland_survival:AddBleeding(p.target, math.floor(delta))
    else
        ok = exports.wasteland_survival:ModifyStats(p.target, { [p.stat] = delta })
    end
    if not ok then return false, 'could not change it (dead?)' end
    return true, string.format('Set %s of player %d to %s', p.stat, p.target, tostring(p.value))
end

ACTIONS.give = function(src, p)
    if not started('wasteland_inventory') then return false, 'inventory module is not running' end
    local ok, err = exports.wasteland_inventory:AddItem(p.target, p.item, p.count or 1)
    if not ok then return false, err end
    return true, string.format('Gave %d x %s to player %d', p.count or 1, p.item, p.target)
end

ACTIONS.inventory = function(src, p)
    if src == 0 then return false, 'open it from the panel in game' end
    if not started('wasteland_inventory') then return false, 'inventory module is not running' end
    local ok, err = exports.wasteland_inventory:OpenForAdmin(src, p.target)
    if not ok then return false, err end
    return true, 'Opened the inventory of player ' .. p.target
end

ACTIONS.clearInventory = function(src, p)
    if not started('wasteland_inventory') then return false, 'inventory module is not running' end
    local ok, err = exports.wasteland_inventory:ClearInventory(p.target)
    if not ok then return false, err end
    return true, 'Cleared the inventory of player ' .. p.target
end

ACTIONS.announce = function(src, p)
    if not p.text or p.text == '' then return false, 'write a message' end
    TriggerClientEvent('wasteland:admin:client:announce', -1, { text = p.text, by = adminName(src) })
    return true, 'Announcement sent'
end

ACTIONS.setTime = function(src, p)
    if not started('wasteland_world') then return false, 'world module is not running' end
    local ok, err = exports.wasteland_world:SetTime(p.hour, p.minute or 0)
    return ok, ok and string.format('Time set to %02d:%02d', p.hour, p.minute or 0) or err
end

ACTIONS.freezeTime = function(src, p)
    if not started('wasteland_world') then return false, 'world module is not running' end
    exports.wasteland_world:FreezeTime(p.enabled == true)
    return true, p.enabled and 'Time frozen' or 'Time runs'
end

ACTIONS.setWeather = function(src, p)
    if not started('wasteland_world') then return false, 'world module is not running' end
    local ok, err = exports.wasteland_world:SetWeather(p.weather)
    return ok, ok and ('Weather set to ' .. p.weather) or err
end

ACTIONS.weatherDynamic = function(src, p)
    if not started('wasteland_world') then return false, 'world module is not running' end
    exports.wasteland_world:SetWeatherDynamic(p.enabled == true)
    return true, p.enabled and 'Weather changes by itself' or 'Weather stays as it is'
end

ACTIONS.noclip = function(src, p)
    if src == 0 then return false, 'in game only' end
    TriggerClientEvent('wasteland:admin:client:noclip', src, p.enabled == true)
    return true, p.enabled and 'Noclip on' or 'Noclip off'
end

ACTIONS.invisible = function(src, p)
    if src == 0 then return false, 'in game only' end
    TriggerClientEvent('wasteland:admin:client:invisible', src, p.enabled == true)
    return true, p.enabled and 'Invisible' or 'Visible'
end

-- World tools ------------------------------------------------------------------

-- A spot a few metres in front of the admin.
local function inFront(src, metres)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 then return nil end
    local c, h = GetEntityCoords(ped), math.rad(GetEntityHeading(ped))
    return { x = c.x - math.sin(h) * metres, y = c.y + math.cos(h) * metres, z = c.z, heading = GetEntityHeading(ped) }
end

ACTIONS.zombieSpawn = function(src, p)
    if not started('wasteland_zombies') then return false, 'zombies module is not running' end
    if src == 0 then return false, 'in game only' end
    exports.wasteland_zombies:SpawnNear(src, p.count or 5)
    return true, string.format('Spawning up to %d zombies around you', p.count or 5)
end

ACTIONS.zombieClear = function()
    if not started('wasteland_zombies') then return false, 'zombies module is not running' end
    return true, string.format('Removed %d zombies', exports.wasteland_zombies:ClearZombies())
end

ACTIONS.vehicleWreck = function(src, p)
    if not started('wasteland_vehicles') then return false, 'vehicles module is not running' end
    local c = inFront(src, 6)
    if not c then return false, 'in game only' end
    local id = exports.wasteland_vehicles:SpawnWreck(c)
    return id ~= nil, id and 'A wreck appears in front of you' or 'could not spawn it'
end

ACTIONS.vehicleWorking = function(src, p)
    if not started('wasteland_vehicles') then return false, 'vehicles module is not running' end
    local c = inFront(src, 6)
    if not c then return false, 'in game only' end
    local id = exports.wasteland_vehicles:SpawnWorking(c)
    return id ~= nil, id and 'A working car appears in front of you' or 'could not spawn it'
end

ACTIONS.vehicleFix = function(src, p)
    if not started('wasteland_vehicles') then return false, 'vehicles module is not running' end
    if not p.netId then return false, 'sit in a vehicle or stand next to one' end
    local ok, err = exports.wasteland_vehicles:FixVehicle(p.netId)
    return ok, ok and 'Vehicle fixed and refuelled' or err
end

ACTIONS.refillPumps = function()
    if not started('wasteland_vehicles') then return false, 'vehicles module is not running' end
    return true, string.format('Refilled %d gas pumps', exports.wasteland_vehicles:RefillPumps())
end

ACTIONS.tpWaypoint = function(src)
    if src == 0 then return false, 'in game only' end
    TriggerClientEvent('wasteland:admin:client:tpWaypoint', src)
    return true, 'Teleporting to your waypoint'
end

-- Debug overlays: the client draws them; the server sends what it needs.
local OVERLAYS = { zombies = true, vehicles = true, camps = true, loot = true }
ACTIONS.overlay = function(src, p)
    if src == 0 then return false, 'in game only' end
    if not OVERLAYS[p.overlay or ''] then return false, 'unknown overlay' end
    local data = nil
    if p.enabled then
        if p.overlay == 'vehicles' and started('wasteland_vehicles') then data = { spawnPoints = exports.wasteland_vehicles:GetSpawnPoints() }
        elseif p.overlay == 'camps' and started('wasteland_camps') then data = { camps = exports.wasteland_camps:GetCamps() }
        elseif p.overlay == 'loot' and started('wasteland_loot') then data = { containers = exports.wasteland_loot:GetContainerModels() } end
    end
    TriggerClientEvent('wasteland:admin:client:overlay', src, p.overlay, p.enabled == true, data)
    return true, (p.enabled and 'Showing ' or 'Hiding ') .. p.overlay
end

-- Loot props: make the prop the admin looks at searchable (or not).
ACTIONS.lootAdd = function(src, p)
    if not started('wasteland_loot') then return false, 'loot module is not running' end
    if not p.model or not p.container then return false, 'look at a prop and pick what it should be' end
    local ok, err = exports.wasteland_loot:AddContainerModel(p.model, p.container, p.propName)
    return ok, ok and string.format('Every prop of this model (%d) can now be searched as "%s"', p.model, p.container) or err
end

ACTIONS.lootTypeSave = function(src, p)
    if not started('wasteland_loot') then return false, 'loot module is not running' end
    if not p.container or not p.lootType then return false, 'nothing to save' end
    local ok, err = exports.wasteland_loot:SaveLootCategory(p.container, p.lootType)
    return ok, ok and string.format('Loot category "%s" saved', p.lootType.label) or err
end

ACTIONS.lootTypeDelete = function(src, p)
    if not started('wasteland_loot') then return false, 'loot module is not running' end
    local ok, err = exports.wasteland_loot:DeleteLootCategory(p.container)
    return ok, ok and string.format('Loot category "%s" deleted', p.container) or err
end

ACTIONS.lootRemove = function(src, p)
    if not started('wasteland_loot') then return false, 'loot module is not running' end
    if not p.model then return false, 'no model' end
    local ok, err = exports.wasteland_loot:RemoveContainerModel(p.model)
    return ok, ok and string.format('Props of model %d can no longer be searched', p.model) or err
end

-- Player tools -------------------------------------------------------------------

ACTIONS.spectate = function(src, p)
    if src == 0 then return false, 'in game only' end
    if p.enabled and p.target == src then return false, 'you cannot spectate yourself' end
    local c = p.enabled and coordsOf(p.target) or nil
    if p.enabled and not c then return false, 'their position is unknown' end
    TriggerClientEvent('wasteland:admin:client:spectate', src, p.enabled == true, p.target, c)
    return true, p.enabled and ('Spectating player ' .. p.target) or 'Stopped spectating'
end

ACTIONS.giveCash = function(src, p)
    if not started('wasteland_inventory') then return false, 'inventory module is not running' end
    local ok, err = exports.wasteland_inventory:AddCash(p.target, p.count or 0)
    return ok, ok and string.format('Gave $%d to player %d', p.count, p.target) or err
end

ACTIONS.takeCash = function(src, p)
    if not started('wasteland_inventory') then return false, 'inventory module is not running' end
    local ok, err = exports.wasteland_inventory:RemoveCash(p.target, p.count or 0)
    return ok, ok and string.format('Took $%d from player %d', p.count, p.target) or (err == 'not enough items' and 'they do not have that much' or err)
end

ACTIONS.dropQuest = function(src, p)
    if not started('wasteland_quests') then return false, 'quests module is not running' end
    local ok = exports.wasteland_quests:DropQuest(p.target, p.quest)
    return ok, ok and 'Job dropped' or 'they do not have that job'
end

ACTIONS.resetCooldowns = function(src, p)
    if not started('wasteland_quests') then return false, 'quests module is not running' end
    return true, string.format('Reset %d job cooldowns', exports.wasteland_quests:ResetCooldowns(p.target))
end

ACTIONS.teachRecipe = function(src, p)
    if not started('wasteland_crafting') then return false, 'crafting module is not running' end
    local ok = exports.wasteland_crafting:TeachRecipe(p.target, p.recipe)
    return ok, ok and ('Taught ' .. p.recipe) or 'unknown recipe'
end

ACTIONS.forgetRecipe = function(src, p)
    if not started('wasteland_crafting') then return false, 'crafting module is not running' end
    local ok = exports.wasteland_crafting:ForgetRecipe(p.target, p.recipe)
    return ok, ok and ('Forgot ' .. p.recipe) or 'unknown recipe'
end

-- A stuck player goes to the nearest camp.
ACTIONS.sendToCamp = function(src, p)
    if not started('wasteland_camps') then return false, 'camps module is not running' end
    local c = coordsOf(p.target)
    local best, bestD
    for _, camp in ipairs(exports.wasteland_camps:GetCamps()) do
        local d = c and ((camp.coords.x - c.x) ^ 2 + (camp.coords.y - c.y) ^ 2) or 0
        if not best or d < bestD then best, bestD = camp, d end
    end
    if not best then return false, 'there are no camps' end
    TriggerClientEvent('wasteland:admin:client:teleport', p.target, best.coords)
    return true, string.format('Sent player %d to %s', p.target, best.label)
end

-- Actions on a player need that player online; these do not.
local NO_TARGET = { banLicense = true, unban = true, announce = true, setTime = true, freezeTime = true,
    setWeather = true, weatherDynamic = true, noclip = true, invisible = true, zombieSpawn = true, zombieClear = true,
    vehicleWreck = true, vehicleWorking = true, vehicleFix = true, refillPumps = true, tpWaypoint = true, overlay = true,
    lootAdd = true, lootRemove = true, lootTypeSave = true, lootTypeDelete = true }
-- Read-only actions are not written to the action log.
local QUIET = { teleportTo = true, inventory = true, overlay = true, tpWaypoint = true }

--- Run an admin action. Returns ok, message.
local function act(src, action, p)
    if not isAdmin(src) then
        M.log:warn('player %d tried admin action "%s" without the %s ACE', src, tostring(action), M.config.adminAce)
        return false, 'You are not an admin.'
    end
    local fn = ACTIONS[action]
    if not fn then return false, 'unknown action' end
    p = p or {}
    if not NO_TARGET[action] and not targetOnline(p.target) then return false, 'that player is not online' end
    local ok, message = fn(src, p)
    if ok and not QUIET[action] then
        local target = p.target and string.format('player %d (%s)', p.target, tostring(GetPlayerName(tostring(p.target)))) or nil
        local details = {}
        for _, k in ipairs({ 'reason', 'minutes', 'stat', 'value', 'item', 'count', 'text', 'hour', 'minute', 'weather', 'enabled', 'banId',
            'license', 'quest', 'recipe', 'netId', 'model', 'container', 'propName' }) do
            if p[k] ~= nil then details[#details + 1] = k .. '=' .. tostring(p[k]) end
        end
        audit(src, action, target, table.concat(details, ' '))
    end
    return ok, message
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

M = Wasteland.DefineModule({
    name = 'admin',
    version = '0.1.0',
    description = 'Admin panel: players, items, bans, server and world tools, action log',
    core = '^1.1.0',
    dependencies = { database = '^0.1.0', players = '^0.1.0', ui = '^0.1.0' },
    optionalDependencies = { inventory = '^0.1.0', survival = '^0.1.0', world = '^0.1.0' },
    async = true,
    config = {
        file = 'admin.lua',
        optional = true,
        schema = { type = 'table', fields = {
            adminAce = { type = 'string', default = 'wasteland.admin', minLength = 1 },
        } },
    },
    onInit = function(mod)
        M = mod
        local token = {}
        runToken = token
        Citizen.CreateThread(function()
            local migrated, err = WDB.migrate('admin', WLA_ADMIN.MIGRATIONS)
            if runToken ~= token then return end
            if not migrated then return M.fail('database migrations failed: ' .. tostring(err)) end
            local ok, berr = loadBans()
            if runToken ~= token then return end
            if not ok then return M.fail('could not load bans: ' .. tostring(berr)) end
            exports.wasteland_players:RegisterAdmissionCheck('bans', function(info)
                local b = activeBan(info.license)
                if b then return banMessage(b) end
                return nil
            end)
            local n = 0
            for _ in pairs(bans) do n = n + 1 end
            M.log:info('%d active ban(s) loaded', n)
            M.ready()
        end)
        return true
    end,
    onShutdown = function()
        runToken = nil
    end,
})

-------------------------------------------------------------------------------
-- Net events
-------------------------------------------------------------------------------

local PAYLOAD = { type = 'table', fields = {
    target = { type = 'integer', min = 1, max = 65535 },
    reason = { type = 'string', maxLength = 200 },
    minutes = { type = 'integer', min = 0, max = 5256000 },
    stat = { type = 'string', maxLength = 16 },
    value = { type = 'number', min = -1000, max = 1000 },
    item = { type = 'string', pattern = '^[a-z][a-z0-9_]*$', maxLength = 48 },
    count = { type = 'integer', min = 1, max = 1000000 },
    enabled = { type = 'boolean' },
    text = { type = 'string', maxLength = 300 },
    hour = { type = 'integer', min = 0, max = 23 },
    minute = { type = 'integer', min = 0, max = 59 },
    weather = { type = 'string', pattern = '^[A-Z]+$', maxLength = 16 },
    banId = { type = 'integer', min = 1 },
    license = { type = 'string', maxLength = 64 },
    name = { type = 'string', maxLength = 64 },
    netId = { type = 'integer', min = 1 },
    model = { type = 'integer', min = -2147483648, max = 4294967295 },
    container = { type = 'string', pattern = '^[%a][%w_]*$', maxLength = 48 },
    propName = { type = 'string', pattern = "^[%w _%-%.'%(%)]*$", maxLength = 40 },
    lootType = { type = 'table', fields = {
        label = { type = 'string', maxLength = 40 },
        searchSeconds = { type = 'number', min = 0.5, max = 60 }, refillMinutes = { type = 'number', min = 1, max = 100000 },
        gridW = { type = 'integer', min = 1, max = 12 }, gridH = { type = 'integer', min = 1, max = 12 },
        emptyChance = { type = 'number', min = 0, max = 1 },
        rollsMin = { type = 'integer', min = 0, max = 20 }, rollsMax = { type = 'integer', min = 0, max = 20 },
        items = { type = 'array', maxItems = 40, items = { type = 'table', fields = {
            name = { type = 'string', required = true, pattern = '^[%w_]+$', maxLength = 48 },
            min = { type = 'integer', min = 1, max = 1000000 }, max = { type = 'integer', min = 1, max = 1000000 },
            weight = { type = 'integer', min = 1, max = 100000 },
        } } },
    } },
    overlay = { type = 'string', pattern = '^[a-z]+$', maxLength = 16 },
    quest = { type = 'string', pattern = '^[%a][%w_]*$', maxLength = 48 },
    recipe = { type = 'string', pattern = '^[%a][%w_]*$', maxLength = 48 },
} }

local ACTION_NAMES = {}
for name in pairs(ACTIONS) do ACTION_NAMES[#ACTION_NAMES + 1] = name end
table.sort(ACTION_NAMES)

-- The client shows the admin target option only to admins (the server
-- still checks every action).
M.netEvent('wasteland:admin:server:amIAdmin', { rateLimit = { burst = 3, perSecond = 0.2 } }, function(src)
    TriggerClientEvent('wasteland:admin:client:isAdmin', src, isAdmin(src))
end)

-- Admin target on a prop: what it can become.
M.netEvent('wasteland:admin:server:lootPick', { rateLimit = { burst = 4, perSecond = 1 } }, function(src)
    if not isAdmin(src) then TriggerClientEvent('wasteland:admin:client:denied', src); return end
    if not started('wasteland_loot') then TriggerClientEvent('wasteland:admin:client:result', src, { ok = false, message = 'loot module is not running' }); return end
    TriggerClientEvent('wasteland:admin:client:lootPick', src, exports.wasteland_loot:GetLootAdminData())
end)

M.netEvent('wasteland:admin:server:open', { rateLimit = { burst = 5, perSecond = 1 } }, function(src)
    if not isAdmin(src) then
        M.log:warn('player %d tried to open the admin panel without the %s ACE', src, M.config.adminAce)
        TriggerClientEvent('wasteland:admin:client:denied', src)
        return
    end
    sendPanel(src)
end)

M.netEvent('wasteland:admin:server:act', {
    args = { { type = 'enum', required = true, values = ACTION_NAMES }, PAYLOAD },
    rateLimit = { burst = 10, perSecond = 3 },
}, function(src, action, payload)
    Citizen.CreateThread(function() -- some actions wait for the database
        local ok, message = act(src, action, payload)
        result(src, action, ok, message)
        if isAdmin(src) then sendPanel(src) end
    end)
end)

M.netEvent('wasteland:admin:server:list', {
    args = { { type = 'enum', required = true, values = { 'bans', 'log' } } },
    rateLimit = { burst = 5, perSecond = 1 },
}, function(src, which)
    if not isAdmin(src) then return end
    Citizen.CreateThread(function()
        local rows, err = WDB.query(which == 'bans' and SQL.selectRecentBans or SQL.selectLog, {})
        if err then result(src, which, false, 'database error: ' .. err); return end
        TriggerClientEvent('wasteland:admin:client:list', src, which, rows, now())
    end)
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then frozen[src] = nil end
end)

-------------------------------------------------------------------------------
-- Exports (admin api 0.1)
-------------------------------------------------------------------------------

--- IsAdmin(source) -> boolean
exports('IsAdmin', function(src) return M.active and isAdmin(tonumber(src) or -1) end)

--- IsBanned(license) -> ban | nil
exports('IsBanned', function(license) return activeBan(license) end)
