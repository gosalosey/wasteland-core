-- wasteland_story :: shared/rules.lua
-- Pure rules (no natives): the step machine of a story act, dialogue lines
-- by flags, the journal, and checking an act's config. Unit-tested.
--
-- State of one character: { step = step id | nil (done), flags = { [flag] = true },
--   progress = number (kills, seconds defended), log = { step ids done, in order },
--   ending = ending id | nil }

WLST = WLST or {}
local Rules = {}
WLST.Rules = Rules

local TYPES = { talk = true, visit = true, collect = true, read = true, kill = true, defend = true }

function Rules.index(act)
    local out = {}
    for i, s in ipairs(act.steps) do out[s.id] = i end
    return out
end

function Rules.newState(act)
    return { step = act.steps[1] and act.steps[1].id or nil, flags = {}, progress = 0, log = {} }
end

--- A loaded state made safe (steps removed from the config are skipped).
function Rules.clean(act, st)
    if type(st) ~= 'table' then return Rules.newState(act) end
    st.flags = type(st.flags) == 'table' and st.flags or {}
    st.log = type(st.log) == 'table' and st.log or {}
    st.progress = tonumber(st.progress) or 0
    if st.step ~= nil and not Rules.index(act)[st.step] then st.step = nil end
    if st.step == nil and not st.ending and #st.log == 0 then return Rules.newState(act) end
    return st
end

function Rules.current(act, st)
    if not st or not st.step then return nil end
    local i = Rules.index(act)[st.step]
    return i and act.steps[i] or nil
end

--- Finish the current step: log it, then go to `gotoId`, the next step, or the end.
function Rules.advance(act, st, gotoId)
    local idx = Rules.index(act)
    local i = idx[st.step]
    if not i then return st end
    st.log[#st.log + 1] = st.step
    st.progress = 0
    if gotoId and idx[gotoId] then st.step = gotoId
    else st.step = act.steps[i + 1] and act.steps[i + 1].id or nil end
    return st
end

local function flagOk(line, flags)
    if line.ifFlag and not flags[line.ifFlag] then return false end
    if line.ifNotFlag and flags[line.ifNotFlag] then return false end
    return true
end

--- Dialogue lines for these flags: { { who, text } }.
function Rules.lines(dialogue, flags)
    local out = {}
    for _, l in ipairs(dialogue and dialogue.lines or {}) do
        if flagOk(l, flags or {}) then out[#out + 1] = { who = l.who, text = l.text } end
    end
    return out
end

--- The choices offered with these flags.
function Rules.choices(step, flags)
    local out = {}
    for _, c in ipairs(step.dialogue and step.dialogue.choices or {}) do
        if flagOk(c, flags or {}) then out[#out + 1] = c end
    end
    return out
end

function Rules.choice(step, id, flags)
    for _, c in ipairs(Rules.choices(step, flags)) do
        if c.id == id then return c end
    end
    return nil
end

--- Is this NPC in the world for a player at this point of the story?
function Rules.npcVisible(npc, st)
    if not npc.onlyDuring then return true end
    for _, id in ipairs(npc.onlyDuring) do if st and st.step == id then return true end end
    return false
end

--- Journal entries for the steps done: { { title, text } }.
function Rules.journal(act, st)
    local idx, out = Rules.index(act), {}
    for _, id in ipairs(st.log or {}) do
        local s = act.steps[idx[id] or 0]
        if s then
            local text = s.journal or ''
            for flag, extra in pairs(s.journalIf or {}) do
                if st.flags[flag] then text = text .. ' ' .. extra end
            end
            out[#out + 1] = { title = s.title or s.id, text = text }
        end
    end
    return out
end

function Rules.dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

--- Errors in an act's config (empty = fine). itemExists(name) -> bool.
function Rules.validate(act, itemExists)
    local errs = {}
    local function e(msg, ...) errs[#errs + 1] = string.format(msg, ...) end
    if type(act) ~= 'table' or type(act.steps) ~= 'table' or #act.steps == 0 then return { 'the act has no steps' } end
    local idx = {}
    for i, s in ipairs(act.steps) do
        if type(s.id) ~= 'string' then e('step %d has no id', i)
        elseif idx[s.id] then e('step id "%s" is used twice', s.id)
        else idx[s.id] = i end
    end
    local function items(list, where)
        for _, it in ipairs(list or {}) do
            if not itemExists(it.name) then e('%s: unknown item "%s"', where, tostring(it.name)) end
        end
    end
    for _, s in ipairs(act.steps) do
        local w = 'step "' .. tostring(s.id) .. '"'
        if not TYPES[s.type] then e('%s: unknown type "%s"', w, tostring(s.type)) end
        if s.type == 'talk' then
            if not (act.npcs and act.npcs[s.npc]) then e('%s: unknown npc "%s"', w, tostring(s.npc)) end
            local choices = s.dialogue and s.dialogue.choices or {}
            if #choices == 0 then e('%s: a talk step needs choices', w) end
            for _, c in ipairs(choices) do
                items(c.bring, w .. ' choice ' .. tostring(c.id)); items(c.give, w .. ' choice ' .. tostring(c.id))
                if c['goto'] and not idx[c['goto']] then e('%s: choice "%s" goes to unknown step "%s"', w, tostring(c.id), c['goto']) end
                if c.ending and not (act.endings and act.endings[c.ending]) then e('%s: unknown ending "%s"', w, c.ending) end
            end
            for _, l in ipairs(s.dialogue and s.dialogue.lines or {}) do
                if not (act.npcs and act.npcs[l.who]) then e('%s: line by unknown npc "%s"', w, tostring(l.who)) end
            end
        elseif s.type == 'visit' or s.type == 'collect' or s.type == 'read' or s.type == 'defend' then
            if type(s.coords) ~= 'table' or not tonumber(s.coords.x) then e('%s: needs coords', w) end
        end
        if s.type == 'collect' and not (s.item and itemExists(s.item)) then e('%s: unknown item "%s"', w, tostring(s.item)) end
        if s.type == 'read' and not (s.note and s.note.text) then e('%s: a read step needs a note', w) end
        if s.type == 'kill' and not (tonumber(s.count) and s.count > 0) then e('%s: a kill step needs a count', w) end
        if s.type == 'defend' and not (tonumber(s.seconds) and s.seconds > 0) then e('%s: a defend step needs seconds', w) end
        if s.needs and not itemExists(s.needs) then e('%s: unknown item "%s"', w, s.needs) end
    end
    return errs
end

return Rules
