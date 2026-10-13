-- Every module starts with the config files that ship in wasteland_config
-- (the other tests mostly use small test configs).

describe('shipped configs', function()
    local server = newServer({ config = {
        ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    } })
    local list = { 'wasteland_players', 'wasteland_ui', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival',
        'wasteland_world', 'wasteland_admin', 'wasteland_weapons', 'wasteland_zombies', 'wasteland_loot', 'wasteland_camps',
        'wasteland_crafting', 'wasteland_quests', 'wasteland_vehicles', 'wasteland_tailor', 'wasteland_supplydrops', 'wasteland_events', 'wasteland_groups', 'wasteland_trade', 'wasteland_hunting', 'wasteland_basebuilding' }
    boot(server, list)

    it('every module is running', function()
        local s = states(server)
        for _, name in ipairs({ 'players', 'ui', 'appearance', 'inventory', 'survival', 'world', 'admin', 'weapons', 'zombies',
            'loot', 'camps', 'crafting', 'quests', 'vehicles', 'tailor', 'supplydrops', 'events', 'groups', 'trade', 'hunting', 'basebuilding' }) do
            if s[name] ~= 'running' then
                for _, l in ipairs(server:lines('[' .. name .. ']')) do print('       ' .. l) end
            end
            expect(name .. ':' .. tostring(s[name])).toBe(name .. ':running')
        end
        expect(#server.scriptErrors).toBe(0)
    end)
end)
