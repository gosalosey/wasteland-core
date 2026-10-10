local env = loadCoreFiles({ 'shared/util.lua', 'shared/logger.lua' })
local Logger = env.WL.Logger
local lines = {}
Logger.sink = function(l) lines[#lines + 1] = l end

describe('logger', function()
    it('filters by global level', function()
        lines = {}
        Logger.configure({ level = 'warn', colors = false, prefix = 'T' })
        local log = Logger.new('m')
        log:info('hidden'); log:warn('shown %d', 1)
        expect(#lines).toBe(1)
        expect(lines[1]).toBe('[T] [WARN ] [m] shown 1')
    end)
    it('applies per-module level overrides', function()
        lines = {}
        Logger.configure({ level = 'error', moduleLevels = { chatty = 'debug' } })
        Logger.new('chatty'):debug('d'); Logger.new('quiet'):warn('w')
        expect(#lines).toBe(1)
        expect(lines[1]).toContain('[chatty] d')
    end)
    it('keeps recent warnings/errors in a bounded buffer even when not printed', function()
        Logger.recent = {}
        Logger.configure({ level = 'off', moduleLevels = {}, recentBufferSize = 10 })
        local log = Logger.new('buf')
        for i = 1, 15 do log:error('e%d', i) end
        local recent = Logger.getRecent()
        expect(#recent).toBe(10)
        expect(recent[1].message).toBe('e6')
        expect(#Logger.getRecent(3)).toBe(3)
    end)
    it('never drops a message with a bad format string', function()
        lines = {}
        Logger.configure({ level = 'debug' })
        Logger.new('fmt'):info('%d items', 'abc')
        expect(lines[1]).toContain('log format error')
        expect(lines[1]).toContain('abc')
    end)
    it('adds colour codes when enabled', function()
        lines = {}
        Logger.configure({ level = 'debug', colors = true })
        Logger.new('c'):error('x')
        expect(lines[1]:sub(1, 2)).toBe('^1')
    end)
end)
