-- wasteland_guide :: server/main.lua
-- Module "guide": the survivor's guide. Counts what every character does
-- (character data "guide": stats and finished milestones - no tables of its
-- own) from events the other modules already send, ticks off milestones,
-- and sends each player their guide: milestones, stats, what to try next,
-- and the how-to pages from guide.lua.

local DATA_KEY = 'guide'

local M
local data = {}     -- [characterId] = { stats = {}, done = { [milestone] = os.time() }, life = seconds alive now }
local runToken = nil

local function players() return exports.wasteland_players end

local function characterOf(src)
    local ok, id = pcall(function() return players():GetCharacterId(src) end)
    return ok and id or nil
end

local function sourceOf(cid)
    local ok, s = pcall(function() return players():GetSourceByCharacterId(cid) end)
    return ok and s or nil
end

local function save(cid)
    if data[cid] then players():SetCharacterData(cid, DATA_KEY, data[cid]) end
end

--- Progress of one milestone: value, done.
local function progress(d, m)
    local v = d.stats[m.stat] or 0
    return math.min(v, m.count), d.done[m.id] ~= nil or v >= m.count
end

local function view(cid)
    local d = data[cid]
    local list, next_ = {}, {}
    for _, m in ipairs(M.config.milestones) do
        local v, done = progress(d, m)
        list[#list + 1] = { id = m.id, label = m.label, hint = m.hint, value = v, count = m.count, done = done }
        if not done and #next_ < 3 then next_[#next_ + 1] = m.id end
    end
    return { milestones = list, next = next_, stats = d.stats, lifeMinutes = math.floor((d.life or 0) / 60),
        pages = M.config.pages, key = M.config.key }
end

local function send(src, cid)
    if src and data[cid] then TriggerClientEvent('wasteland:guide:client:view', src, view(cid)) end
end

-- Newly finished milestones: remembered, and the player is told.
local function check(src, cid)
    local d = data[cid]
    local changed = false
    for _, m in ipairs(M.config.milestones) do
        if not d.done[m.id] and (d.stats[m.stat] or 0) >= m.count then
            d.done[m.id] = os.time()
            changed = true
            TriggerClientEvent('wasteland:guide:client:milestone', src, m.label)
            TriggerEvent('wasteland:guide:milestone', src, m.id)
        end
    end
    return changed
end

--- Count something for a player (by source or, with `isCid`, character id).
local function count(who, stat, amount, isCid, setMax)
    if not (M and M.active) then return end
    local cid = isCid and who or characterOf(who)
    local src = isCid and sourceOf(who) or who
    local d = cid and data[cid]
    if not d then return end
    if setMax then
        if (d.stats[stat] or 0) >= amount then return end
        d.stats[stat] = amount
    else
        d.stats[stat] = (d.stats[stat] or 0) + (amount or 1)
    end
    check(src, cid)
    save(cid)
    send(src, cid)
end

-------------------------------------------------------------------------------
-- Loading
-------------------------------------------------------------------------------

local function load(src, cid)
    local stored = players():GetCharacterData(cid, DATA_KEY)
    local d = { stats = {}, done = {}, life = 0 }
    if type(stored) == 'table' then
        if type(stored.stats) == 'table' then for k, v in pairs(stored.stats) do if type(v) == 'number' then d.stats[k] = v end end end
        if type(stored.done) == 'table' then for k, v in pairs(stored.done) do d.done[k] = v end end
        d.life = tonumber(stored.life) or 0
    end
    data[cid] = d
    check(src, cid) -- milestones added to guide.lua since: already earned?
    send(src, cid)
end

AddEventHandler('wasteland:players:characterLoaded', function(src, character)
    if not (M and M.active) or type(character) ~= 'table' then return end
    load(src, character.id)
end)

AddEventHandler('wasteland:players:characterUnloading', function(_, character)
    if type(character) ~= 'table' then return end
    save(character.id)
    data[character.id] = nil
end)

-------------------------------------------------------------------------------
-- What counts (events other modules send)
-------------------------------------------------------------------------------

local ON = {
    ['wasteland:loot:searched'] = 'searches',
    ['wasteland:survival:treated'] = 'treated',
    ['wasteland:crafting:crafted'] = 'crafts',
    ['wasteland:crafting:learned'] = 'blueprints',
    ['wasteland:camps:traded'] = 'trades',
    ['wasteland:hunting:fireLit'] = 'fires',
    ['wasteland:hunting:harvested'] = 'harvests',
    ['wasteland:hunting:cooked'] = 'cooked',
    ['wasteland:basebuilding:cupboardPlaced'] = 'cupboards',
    ['wasteland:quests:completed'] = 'jobs',
    ['wasteland:supplydrops:opened'] = 'drops',
    ['wasteland:events:looted'] = 'events',
}
for ev, stat in pairs(ON) do
    AddEventHandler(ev, function(src) count(src, stat) end)
end

AddEventHandler('wasteland:survival:consumed', function(src, _, food) if food then count(src, 'meals') end end)
AddEventHandler('wasteland:zombies:died', function(_, _, _, killer)
    killer = tonumber(killer)
    if killer and killer > 0 then count(killer, 'kills') end
end)
AddEventHandler('wasteland:groups:created', function(_, cid) count(cid, 'groups', 1, true) end)
AddEventHandler('wasteland:groups:joined', function(_, cid) count(cid, 'groups', 1, true) end)
AddEventHandler('wasteland:trade:done', function(a, _, b) count(a, 'playerTrades'); count(b, 'playerTrades') end)
local LOCKS = { toggleLock = true, pickLock = true, fitLock = true, removeLock = true }
AddEventHandler('wasteland:vehicles:action', function(src, action) if not LOCKS[action] then count(src, 'vehicleWork') end end)
AddEventHandler('wasteland:skills:levelUp', function(src, _, level) count(src, 'bestSkill', level, false, true) end)
AddEventHandler('wasteland:survival:died', function(src, cid)
    cid = cid or characterOf(src)
    local d = cid and data[cid]
    if not d then return end
    d.life = 0 -- a new life
    count(src, 'deaths')
end)

-- Time alive: a minute at a time while playing (and not dead).
local function tick()
    for cid, d in pairs(data) do
        local src = sourceOf(cid)
        local dead = false
        if src and GetResourceState('wasteland_survival') == 'started' then
            local ok, yes = pcall(function() return exports.wasteland_survival:IsDead(src) end)
            dead = ok and yes == true
        end
        if src and not dead then
            d.life = (d.life or 0) + 60
            local minutes = math.floor(d.life / 60)
            if minutes > (d.stats.lifeMinutes or 0) then d.stats.lifeMinutes = minutes end
            check(src, cid)
            save(cid)
            send(src, cid)
        end
    end
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local MILESTONE = { type = 'table', fields = {
    id = { type = 'string', required = true, pattern = '^[%w_]+$', maxLength = 32 },
    label = { type = 'string', required = true, minLength = 1, maxLength = 80 },
    hint = { type = 'string', default = '', maxLength = 300 },
    stat = { type = 'string', required = true, pattern = '^[%a][%w_]*$' },
    count = { type = 'integer', default = 1, min = 1, max = 1000000 },
} }
local PAGE = { type = 'table', fields = {
    title = { type = 'string', required = true, minLength = 1, maxLength = 60 },
    lines = { type = 'array', default = {}, items = { type = 'string', maxLength = 400 } },
} }

M = Wasteland.DefineModule({
    name = 'guide',
    version = '0.1.0',
    description = "Survivor's guide: milestones, stats, what to try next, how-to pages (F2)",
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', ui = '^0.1.0' },
    config = {
        file = 'guide.lua',
        optional = true,
        schema = { type = 'table', fields = {
            key = { type = 'string', default = 'F2', pattern = '^[%w_]+$', maxLength = 16 },
            milestones = { type = 'array', default = {}, items = MILESTONE },
            pages = { type = 'array', default = {}, items = PAGE },
        } },
    },
    onInit = function(mod)
        M = mod
        data = {}
        local ok, list = pcall(function() return players():GetOnlineCharacters() end)
        if ok and type(list) == 'table' then
            for _, c in ipairs(list) do if c.source and c.id then load(c.source, c.id) end end
        end
        local token = {}
        runToken = token
        Citizen.CreateThread(function()
            while runToken == token do
                Citizen.Wait(60000)
                if runToken == token then tick() end
            end
        end)
        return true
    end,
    onShutdown = function()
        runToken = nil
        for cid in pairs(data) do save(cid) end
        data = {}
    end,
})

M.netEvent('wasteland:guide:server:view', { rateLimit = { burst = 3, perSecond = 1 } }, function(src)
    local cid = characterOf(src)
    if cid and data[cid] then send(src, cid) end
end)

-------------------------------------------------------------------------------
-- Exports (guide api 0.1)
-------------------------------------------------------------------------------

--- AddStat(source, stat, amount?) -> nil   (other scripts count their own things)
exports('AddStat', function(src, stat, amount)
    if type(stat) == 'string' then count(tonumber(src), stat, tonumber(amount) or 1) end
end)

--- GetGuide(source) -> { milestones, next, stats, lifeMinutes } | nil
exports('GetGuide', function(src)
    local cid = characterOf(tonumber(src))
    if not (M and M.active) or not cid or not data[cid] then return nil end
    return view(cid)
end)
