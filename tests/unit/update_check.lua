-- Update check (wasteland_core/server/updates.lua): the banner and titles.

local env = loadCoreFiles({ 'server/updates.lua' }, {
    Citizen = { CreateThread = function() end, Wait = function() end },
    AddEventHandler = function() end,
})
local U = env.Updates

describe('update check', function()
    it('lists commit titles newest first (first line only)', function()
        local t = U.titles({ { commit = { message = 'Older one\n\nbody' } }, { commit = { message = 'Newest one' } } })
        expect(t[1]).toBe('Newest one'); expect(t[2]).toBe('Older one')
    end)

    it('the console banner says how many, what is installed and how to update', function()
        local lines = U.banner({ count = 3, installed = 'abcdef1234', latest = '1234567abc', date = '2026-10-13T10:00:00Z',
            titles = { 'Bigger trunks', 'Hunting', 'Trading' } })
        local text = table.concat(lines, '\n')
        expect(text).toContain('3 updates available on GitHub')
        expect(text).toContain('Installed: abcdef1   Newest: 1234567 (2026-10-13)')
        expect(text).toContain('- Bigger trunks')
        expect(text).toContain('update_wasteland.bat')
        local many = {}
        for i = 1, 14 do many[i] = 'change ' .. i end
        expect(table.concat(U.banner({ count = 14, installed = 'a1a1a1a', latest = 'b2b2b2b', titles = many }), '\n')).toContain('... and 4 more')
    end)
end)
