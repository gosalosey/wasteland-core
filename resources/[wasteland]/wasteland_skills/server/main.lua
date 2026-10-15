-- wasteland_skills :: server/main.lua
-- Module "skills": every character has XP in each skill (character data
-- "skills", saved with the character - no tables of its own). XP comes from
-- what other modules already report (searching, crafting, harvesting,
-- killing zombies, treating wounds) and from sprinting (the client says how
-- long; capped). Other modules ask GetBonus(source, skill, bonus) for what a
-- level is worth; without this module running they get 0 (no bonus).

local Rules = WLSK.Rules
local DATA_KEY = 'skills'

local M
local xp = {}        -- [characterId] = { [skill] = xp }
local online = {}    -- [characterId] = source
local sprintAt = {}  -- [source] = last sprint report (game time)

local function players() return exports.wasteland_players end

local function characterOf(src)
    local ok, id = pcall(function() return players():GetCharacterId(src) end)
    return ok and id or nil
end

local function notice(src, msg) TriggerClientEvent('wasteland:skills:client:notice', src, msg) end

-- What the client and the skills screen need: every skill with its level,
-- progress and current bonuses.
local function view(cid)
    local c = M.config
    local list = {}
    for name, s in pairs(c.skills) do
        local total = (xp[cid] and xp[cid][name]) or 0
        local level, into, needed = Rules.level(c.xpCurve, c.maxLevel, total)
        local bonus = {}
        for key, max in pairs(s.bonus or {}) do bonus[key] = Rules.bonus(max, level, c.maxLevel) end
        list[#list + 1] = { name = name, label = s.label or name, level = level, into = into, needed = needed,
            xp = total, bonus = bonus }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return { skills = list, maxLevel = c.maxLevel }
end

local function send(src, cid)
    TriggerClientEvent('wasteland:skills:client:view', src, view(cid))
end

local function save(cid)
    if xp[cid] then players():SetCharacterData(cid, DATA_KEY, xp[cid]) end
end

--- Add XP to a skill for a player. -> new level | nil
local function addXP(src, skill, amount, why)
    local cid = characterOf(src)
    local s = M and M.config.skills[skill]
    if not cid or not xp[cid] or not s or type(amount) ~= 'number' or amount <= 0 then return nil end
    local c = M.config
    local before = Rules.level(c.xpCurve, c.maxLevel, xp[cid][skill] or 0)
    xp[cid][skill] = (xp[cid][skill] or 0) + amount * (c.xpMultiplier or 1)
    local after = Rules.level(c.xpCurve, c.maxLevel, xp[cid][skill])
    save(cid)
    if after > before then
        notice(src, string.format('%s is now level %d!', s.label or skill, after))
        TriggerClientEvent('wasteland:skills:client:levelUp', src, skill, s.label or skill, after)
        TriggerEvent('wasteland:skills:levelUp', src, skill, after)
        M.log:info('player %d: %s level %d (%s)', src, skill, after, tostring(why))
    end
    send(src, cid)
    return after
end

local function gain(src, skill, action, why)
    local s = M and M.active and M.config.skills[skill]
    local amount = s and s.xp and s.xp[action]
    if amount then addXP(src, skill, amount, why or action) end
end

-------------------------------------------------------------------------------
-- Loading, saving
-------------------------------------------------------------------------------

local function load(src, cid)
    local stored = players():GetCharacterData(cid, DATA_KEY)
    local mine = {}
    if type(stored) == 'table' then
        for name in pairs(M.config.skills) do
            if type(stored[name]) == 'number' then mine[name] = math.max(0, stored[name]) end
        end
    end
    xp[cid], online[cid] = mine, src
    send(src, cid)
end

AddEventHandler('wasteland:players:characterLoaded', function(src, character)
    if not (M and M.active) or type(character) ~= 'table' then return end
    load(src, character.id)
end)

AddEventHandler('wasteland:players:characterUnloading', function(_, character)
    if type(character) ~= 'table' then return end
    save(character.id)
    xp[character.id], online[character.id] = nil, nil
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then sprintAt[src] = nil end
end)

-------------------------------------------------------------------------------
-- Where XP comes from (events other modules already send)
-------------------------------------------------------------------------------

AddEventHandler('wasteland:loot:searched', function(src) gain(src, 'scavenging', 'search') end)
AddEventHandler('wasteland:crafting:crafted', function(src, recipe) gain(src, 'crafting', 'craft', recipe) end)
AddEventHandler('wasteland:hunting:harvested', function(src) gain(src, 'hunting', 'harvest') end)
AddEventHandler('wasteland:survival:treated', function(src, item) gain(src, 'medicine', 'treat', item) end)
AddEventHandler('wasteland:zombies:died', function(_, _, _, killer)
    killer = tonumber(killer)
    if killer and killer > 0 then gain(killer, 'combat', 'kill') end
end)

-- Death: the penalty (skills.lua deathPenalty).
AddEventHandler('wasteland:survival:died', function(src, cid)
    if not (M and M.active) then return end
    cid = cid or characterOf(src)
    local mine = cid and xp[cid]
    if not mine then return end
    local c = M.config
    local lost = false
    for name, value in pairs(mine) do
        local after = Rules.afterDeath(c.xpCurve, c.maxLevel, value, c.deathPenalty)
        if after < value then lost = true end
        mine[name] = after
    end
    save(cid)
    if lost then notice(src, c.deathPenalty.mode == 'all' and 'You lost all your skills.' or 'Dying cost you some skill progress.') end
    send(src, cid)
end)

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local NUM = function(default, min, max) return { type = 'number', default = default, min = min, max = max } end
local SKILL = { type = 'table', fields = {
    label = { type = 'string', minLength = 1, maxLength = 32 },
    xp = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%a][%w_]*$' }, values = NUM(0, 0, 100000) },
    bonus = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[%a][%w_]*$' }, values = NUM(0, 0, 10) },
} }

M = Wasteland.DefineModule({
    name = 'skills',
    version = '0.1.0',
    description = 'Skills: scavenging, crafting, medicine, hunting, fitness, combat - level up by doing',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', ui = '^0.1.0' },
    config = {
        file = 'skills.lua',
        optional = true,
        schema = { type = 'table', fields = {
            maxLevel = { type = 'integer', default = 10, min = 2, max = 100 },
            xpCurve = { type = 'table', fields = { base = NUM(100, 1, 1000000), growth = NUM(1.5, 0, 5) } },
            deathPenalty = { type = 'table', fields = {
                mode = { type = 'enum', values = { 'none', 'some', 'all' }, default = 'some' },
                percent = NUM(10, 0, 100),
            } },
            skills = { type = 'map', default = {}, keys = { type = 'string', pattern = '^[a-z][a-z0-9_]*$', maxLength = 24 }, values = SKILL },
            xpMultiplier = NUM(1, 0, 100),
        } },
    },
    onInit = function(mod)
        M = mod
        xp, online, sprintAt = {}, {}, {}
        -- characters already in the game (a module restart)
        local ok, list = pcall(function() return players():GetOnlineCharacters() end)
        if ok and type(list) == 'table' then
            for _, c in ipairs(list) do if c.source and c.id then load(c.source, c.id) end end
        end
        return true
    end,
    onShutdown = function()
        for cid in pairs(xp) do save(cid) end
        xp, online = {}, {}
    end,
})

-- Sprinting (fitness): the client reports seconds sprinted, at most once a
-- minute; never more than the time since the last report.
M.netEvent('wasteland:skills:server:sprint', {
    args = { { type = 'number', required = true, min = 0, max = 120 } },
    rateLimit = { burst = 2, perSecond = 0.05 },
}, function(src, seconds)
    local t = GetGameTimer()
    local last = sprintAt[src] or (t - 60000)
    sprintAt[src] = t
    seconds = math.min(seconds, (t - last) / 1000)
    local s = M.config.skills.fitness
    local perMinute = s and s.xp and s.xp.sprintMinute
    if perMinute and seconds >= 1 then addXP(src, 'fitness', perMinute * seconds / 60, 'sprinting') end
end)

M.netEvent('wasteland:skills:server:view', { rateLimit = { burst = 3, perSecond = 1 } }, function(src)
    local cid = characterOf(src)
    if cid and xp[cid] then send(src, cid) end
end)

-------------------------------------------------------------------------------
-- Exports (skills api 0.1)
-------------------------------------------------------------------------------

--- GetBonus(source, skill, bonus) -> share (0.3 = 30 %), 0 when unknown
exports('GetBonus', function(src, skill, key)
    if not (M and M.active) then return 0 end
    local s = M.config.skills[skill]
    local cid = characterOf(tonumber(src))
    if not s or not cid or not xp[cid] then return 0 end
    local level = Rules.level(M.config.xpCurve, M.config.maxLevel, xp[cid][skill] or 0)
    return Rules.bonus(s.bonus and s.bonus[key], level, M.config.maxLevel)
end)

--- GetLevel(source, skill) -> level (1 when unknown)
exports('GetLevel', function(src, skill)
    local cid = characterOf(tonumber(src))
    if not (M and M.active) or not cid or not xp[cid] or not M.config.skills[skill] then return 1 end
    return (Rules.level(M.config.xpCurve, M.config.maxLevel, xp[cid][skill] or 0))
end)

--- GetSkills(source) -> { skills = { { name, label, level, into, needed, xp, bonus } }, maxLevel } | nil
exports('GetSkills', function(src)
    local cid = characterOf(tonumber(src))
    if not (M and M.active) or not cid or not xp[cid] then return nil end
    return view(cid)
end)

--- AddXP(source, skill, amount, reason?) -> new level | nil   (quests, events, admin)
exports('AddXP', function(src, skill, amount, why) return addXP(tonumber(src), skill, tonumber(amount), why) end)
