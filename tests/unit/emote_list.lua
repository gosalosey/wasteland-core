-- The emote list (wasteland_emotes/shared/emotes.lua): every entry is complete
-- and names are unique, so /e and the menu cannot break on a typo.

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_emotes/shared/emotes.lua', 't', env))()
local WLE = env.WLE

describe('emote list', function()
    it('every emote has a unique lower-case name, a label, a known category and an animation or scenario', function()
        local cats, seen = {}, {}
        for _, c in ipairs(WLE.CATEGORIES) do cats[c] = true end
        for _, e in ipairs(WLE.EMOTES) do
            expect(e.name:match('^[a-z][a-z0-9]*$') ~= nil).toBe(true)
            expect(seen[e.name] == nil).toBe(true)
            seen[e.name] = true
            expect(e.name ~= 'c' and e.name ~= 'cancel' and e.name ~= 'stop' and e.name ~= 'list').toBe(true)
            expect(type(e.label)).toBe('string')
            expect(cats[e.cat] == true).toBe(true)
            expect((e.scenario ~= nil) ~= (e.dict ~= nil and e.anim ~= nil)).toBe(true)
        end
        expect(#WLE.EMOTES >= 40).toBe(true)
    end)
end)
