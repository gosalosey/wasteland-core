-- Story rules (wasteland_story/shared/rules.lua) and the shipped story.lua.

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_story/shared/rules.lua', 't', env))()
local Rules = env.WLST.Rules

local function shipped()
    local f = assert(io.open(RESOURCES .. '/wasteland_config/config/story.lua', 'rb'))
    local src = f:read('a'); f:close()
    return assert(load(src, '@story.lua', 't', {}))()
end

local act = {
    npcs = { a = { name = 'A' }, b = { name = 'B', onlyDuring = { 'two' } } },
    endings = { good = { title = 'Good' } },
    steps = {
        { id = 'one', type = 'talk', npc = 'a', title = 'One', journal = 'Did one.', journalIf = { kind = 'Kindly.' },
            dialogue = { lines = { { who = 'a', text = 'hi' }, { who = 'a', text = 'nice', ifFlag = 'kind' }, { who = 'a', text = 'rude', ifNotFlag = 'kind' } },
                choices = { { id = 'x', text = 'X' }, { id = 'secret', text = 'S', ifFlag = 'kind' } } } },
        { id = 'two', type = 'kill', count = 3, title = 'Two', journal = 'Did two.' },
        { id = 'three', type = 'visit', coords = { x = 0, y = 0, z = 0 }, title = 'Three' },
    },
}

describe('story steps', function()
    it('a new character starts at the first step', function()
        local st = Rules.newState(act)
        expect(st.step).toBe('one'); expect(#st.log).toBe(0)
    end)

    it('advancing logs the step, resets progress, and ends after the last', function()
        local st = Rules.newState(act)
        st.progress = 2
        Rules.advance(act, st); expect(st.step).toBe('two'); expect(st.progress).toBe(0)
        Rules.advance(act, st, 'three'); expect(st.step).toBe('three')
        Rules.advance(act, st); expect(st.step).toBe(nil)
        expect(table.concat(st.log, ',')).toBe('one,two,three')
    end)

    it('dialogue lines and choices depend on flags', function()
        local s = act.steps[1]
        expect(#Rules.lines(s.dialogue, {})).toBe(2)
        expect(Rules.lines(s.dialogue, { kind = true })[2].text).toBe('nice')
        expect(Rules.choice(s, 'secret', {})).toBe(nil)
        expect(Rules.choice(s, 'secret', { kind = true }).id).toBe('secret')
    end)

    it('NPCs that only belong to one step, and the journal', function()
        local st = Rules.newState(act)
        expect(Rules.npcVisible(act.npcs.b, st)).toBe(false)
        Rules.advance(act, st)
        expect(Rules.npcVisible(act.npcs.b, st)).toBe(true)
        st.flags.kind = true
        local j = Rules.journal(act, st)
        expect(j[1].text).toBe('Did one. Kindly.')
    end)

    it('a saved state with a removed step is cleaned', function()
        local st = Rules.clean(act, { step = 'gone', flags = {}, log = { 'one' } })
        expect(st.step).toBe(nil)
        expect(Rules.clean(act, nil).step).toBe('one')
    end)

    it('config mistakes are found', function()
        local bad = { npcs = {}, steps = { { id = 'a', type = 'talk', npc = 'nobody' }, { id = 'a', type = 'fly' } } }
        local errs = table.concat(Rules.validate(bad, function() return true end), ' | ')
        expect(errs:find('unknown npc', 1, true) ~= nil).toBe(true)
        expect(errs:find('used twice', 1, true) ~= nil).toBe(true)
        expect(errs:find('unknown type', 1, true) ~= nil).toBe(true)
    end)
end)

describe('the shipped story (Patient Zero)', function()
    local cfg = shipped()
    it('every act is valid, with two endings; Act I has about ten steps', function()
        expect(#cfg.acts >= 2).toBe(true)
        for _, a in ipairs(cfg.acts) do
            local errs = Rules.validate(a, function() return true end)
            expect(a.id .. ':' .. table.concat(errs, '; ')).toBe(a.id .. ':')
            local n = 0
            for _ in pairs(a.endings) do n = n + 1 end
            expect(n).toBe(2)
        end
        expect(#cfg.acts[1].steps >= 10).toBe(true)
    end)
end)
