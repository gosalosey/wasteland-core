-- Admin command: authorisation, logging and output.

describe('admin command', function()
    local server = newServer()
    server:start('wasteland_template')

    it('console can view status', function()
        server:clearOutput()
        expect(server:command(0, 'wasteland status')).toBe(true)
        expect(#server:lines('template       1.0.0     running') > 0).toBe(true)
        expect(#server:lines('admin command "wasteland status" by console') > 0).toBe(true)
    end)

    it('players without the ACE are denied and the attempt is logged', function()
        server:clearOutput()
        server:command(7, 'wasteland status')
        expect(#server:lines('denied admin command "wasteland status" for player 7') > 0).toBe(true)
        local ev = server.clientEvents[#server.clientEvents]
        expect(ev.target).toBe(7)
        expect(ev.args[1][1]).toBe('You are not authorised to use this command.')
    end)

    it('players with the ACE receive output in their F8 console', function()
        server.aces['8|wasteland.admin'] = true
        server:command(8, 'wasteland module template')
        local ev = server.clientEvents[#server.clientEvents]
        expect(ev.name).toBe('wasteland:core:client:consoleOutput')
        expect(ev.args[1]).toContain('module:      template')
    end)

    it('config validate lists every file including module configs', function()
        server:clearOutput()
        server:command(0, 'wasteland config validate')
        expect(#server:lines('[ OK ] wasteland_config/config/framework.lua') > 0).toBe(true)
        expect(#server:lines('[ OK ] wasteland_config/config/template.lua (template)') > 0).toBe(true)
        expect(#server:lines('All configuration files are valid.') > 0).toBe(true)
    end)

    it('config validate reports bad edits without applying them', function()
        server:setFile('wasteland_config', 'config/template.lua', 'return { heartbeatSeconds = -5 }')
        server:clearOutput()
        server:command(0, 'wasteland config validate')
        expect(#server:lines("error: wasteland_config/config/template.lua: setting 'heartbeatSeconds': expected an integer between 0 and 3600, got -5") > 0).toBe(true)
        expect(states(server).template).toBe('running')
    end)

    it('issues lists recent warnings and errors', function()
        server:clearOutput()
        server:command(0, 'wasteland issues')
        expect(#server:lines('WARN  [admin]') > 0).toBe(true)
    end)

    it('unknown subcommands print help', function()
        server:clearOutput()
        server:command(0, 'wasteland nope')
        expect(#server:lines('usage: wasteland <subcommand>') > 0).toBe(true)
    end)

    it('no script errors', function() expect(#server.scriptErrors).toBe(0) end)
end)
