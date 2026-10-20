-- Moonshine rules (wasteland_moonshine/shared/rules.lua).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_moonshine/shared/rules.lua', 't', env))()
local Rules = env.WLM.Rules
local CFG = { soberPerMinute = 6, blindPerMinute = 10, unmaskBelow = 40 }
local JAR = { drunk = 18, blind = 34 }

describe('moonshine rules', function()
    it('jars fill the meter; full masks you; it never goes past 100', function()
        local st = {}
        Rules.drink(st, JAR); Rules.drink(st, JAR)
        expect(st.blind).toBe(68); expect(st.masked).toBe(nil)
        Rules.drink(st, JAR)
        expect(st.blind).toBe(100); expect(st.masked).toBe(true)
        expect(st.drunk).toBe(54)
    end)

    it('stays masked until the meter drains below the line, then zombies smell you', function()
        local st = { drunk = 30, blind = 100, masked = true }
        Rules.decay(st, 5, CFG)
        expect(st.blind).toBe(50); expect(st.masked).toBe(true)
        Rules.decay(st, 1.5, CFG)
        expect(st.masked).toBe(false)
        Rules.drink(st, JAR)
        expect(st.masked).toBe(false) -- topping up below full does not mask again
    end)

    it('wears off to nothing', function()
        local st = { drunk = 10, blind = 5, masked = false }
        Rules.decay(st, 10, CFG)
        expect(st.drunk).toBe(0); expect(st.blind).toBe(0)
        expect(Rules.idle(st)).toBe(true)
    end)
end)
