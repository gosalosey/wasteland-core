-- Group rules (wasteland_groups/shared/rules.lua).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_groups/shared/rules.lua', 't', env))()
local Rules = env.WLG.Rules

describe('group rules', function()
    it('cleans names and refuses bad ones', function()
        expect(Rules.cleanName('  Dead   End ', 3, 24)).toBe('Dead End')
        expect(select(2, Rules.cleanName('ab', 3, 24))).toBe('The name must be 3 to 24 characters.')
        expect(select(2, Rules.cleanName('<b>bad</b>', 3, 24))).toContain('letters, numbers')
        expect(Rules.cleanName("Bob's Crew!", 3, 24)).toBe("Bob's Crew!")
    end)
    it('names are unique whatever the case', function()
        local groups = { [1] = { name = 'Dead End' } }
        expect(Rules.nameTaken(groups, 'dead end')).toBe(true)
        expect(Rules.nameTaken(groups, 'dead end', 1)).toBe(false)
        expect(Rules.nameTaken(groups, 'Other')).toBe(false)
    end)
end)
