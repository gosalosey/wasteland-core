-- wasteland_quests :: shared/rules.lua
-- Pure rules (no natives): objective progress, completion, quest status.
-- Unit-tested.
--
-- Objectives (quests.lua):
--   { type = 'bring',  item, count }              carried when handing in (taken)
--   { type = 'kill',   count, near? = { x, y, z, radius }, label? }
--   { type = 'visit',  coords = { x, y, z }, radius, label }
--   { type = 'search', container?, count, near?, label? }   (loot container type)
--   { type = 'craft',  recipe, count }
-- Progress: list of numbers, one per objective (bring: unused, read live).

WLQ = WLQ or {}
local Rules = {}
WLQ.Rules = Rules

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
Rules.dist = dist

local function need(o)
    if o.type == 'visit' then return 1 end
    return o.count or 1
end
Rules.need = need

function Rules.fresh(quest)
    local p = {}
    for i = 1, #quest.objectives do p[i] = 0 end
    return p
end

--- How far objective i is: have, need. count(item) -> carried amount.
function Rules.objective(quest, progress, i, count)
    local o = quest.objectives[i]
    if o.type == 'bring' then return math.min(count(o.item) or 0, o.count), o.count end
    return math.min(progress[i] or 0, need(o)), need(o)
end

function Rules.complete(quest, progress, count)
    for i in ipairs(quest.objectives) do
        local have, n = Rules.objective(quest, progress, i, count)
        if have < n then return false end
    end
    return true
end

local function near(o, coords)
    if not o.near then return true end
    return coords ~= nil and dist(o.near, coords) <= o.near.radius
end

--- Apply something that happened to an active quest's progress.
--- ev = { type = 'kill', coords } | { type = 'search', container, coords }
---    | { type = 'craft', recipe, count } | { type = 'visit', coords }
--- Returns true if anything changed.
function Rules.apply(quest, progress, ev)
    local changed = false
    for i, o in ipairs(quest.objectives) do
        local cur = progress[i] or 0
        if cur < need(o) and o.type == ev.type then
            local add = 0
            if ev.type == 'kill' and near(o, ev.coords) then add = 1
            elseif ev.type == 'search' and (not o.container or o.container == ev.container) and near(o, ev.coords) then add = 1
            elseif ev.type == 'craft' and o.recipe == ev.recipe then add = ev.count or 1
            elseif ev.type == 'visit' and ev.coords and dist(o.coords, ev.coords) <= o.radius then add = 1 end
            if add > 0 then
                progress[i] = math.min(need(o), cur + add)
                changed = true
            end
        end
    end
    return changed
end

--- Status of a quest for a character: 'active' | 'ready' | 'cooldown' | 'available'.
--- state = { active = { [id] = { progress } }, done = { [id] = unixTime } }
--- Returns status, minutes left (cooldown).
function Rules.status(id, quest, state, nowUnix, count)
    local a = state.active and state.active[id]
    if a then return Rules.complete(quest, a.progress, count) and 'ready' or 'active' end
    local doneAt = state.done and state.done[id]
    if doneAt then
        local left = doneAt + quest.cooldownMinutes * 60 - nowUnix
        if left > 0 then return 'cooldown', math.ceil(left / 60) end
    end
    return 'available'
end

--- Text for an objective line, e.g. "Scrap metal 3/5", "Zombies 7/15".
function Rules.text(o, have, n, itemLabel)
    if o.type == 'bring' then return string.format('Bring %s %d/%d', itemLabel or o.item, have, n) end
    if o.type == 'kill' then return string.format('Kill zombies%s %d/%d', o.label and (' at ' .. o.label) or '', have, n) end
    if o.type == 'visit' then return string.format('Go to %s%s', o.label or 'the marked place', have >= n and ' (done)' or '') end
    if o.type == 'search' then return string.format('Search %s %d/%d', o.label or (o.container and (o.container .. 's')) or 'containers', have, n) end
    if o.type == 'craft' then return string.format('Make %s %d/%d', itemLabel or o.recipe, have, n) end
    return '?'
end

--- How to do an objective, one short line for the tracker and the job log.
--- info: { itemLabel, craftable = bool, needsBlueprint = bool }
function Rules.hint(o, info)
    info = info or {}
    local what = info.itemLabel or o.item or o.recipe
    if o.type == 'bring' then
        return string.format('Carry %s back to camp. %s', what,
            info.craftable and 'Found while looting, or craft it (K).' or 'Found while looting.')
    end
    if o.type == 'kill' then
        if o.near then return string.format('Kill them near %s (marked on your map).', o.label or 'the marked place') end
        return 'Kill zombies anywhere; every kill counts.'
    end
    if o.type == 'visit' then return string.format('Go to %s: marked on your map with a route.', o.label or 'the marked place') end
    if o.type == 'search' then
        return string.format('Search %s: hold Left Alt on one and choose Search.', o.label or (o.container and (o.container .. 's')) or 'containers')
    end
    if o.type == 'craft' then
        return string.format('Craft %s in the crafting menu (K).%s', what, info.needsBlueprint and ' You need its blueprint first.' or '')
    end
    return ''
end

--- "just now", "5 min", "2 h 10 min" (how long ago, or how long until).
function Rules.duration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 60 then return 'just now' end
    local m = math.floor(seconds / 60)
    if m < 60 then return m .. ' min' end
    local hrs = math.floor(m / 60)
    return string.format('%d h %d min', hrs, m % 60)
end

return Rules
