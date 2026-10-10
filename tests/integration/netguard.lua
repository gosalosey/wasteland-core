-- Core net-event guard (SDK: M.netEvent) and module health reporting.

local GUARDED = [[
local M
M = Wasteland.DefineModule({ name = 'shop', version = '1.0.0', core = '^1.1.0' })
M.netEvent('wasteland:shop:server:buy', {
    args = {
        { type = 'string', required = true, pattern = '^[a-z_]+$', maxLength = 32 },
        { type = 'integer', required = true, min = 1, max = 10 },
        { type = 'table', fields = { note = { type = 'string', maxLength = 10 } } },
    },
    rateLimit = { burst = 3, perSecond = 1 },
}, function(src, item, count, opts)
    track(string.format('buy %d %s x%d %s', src, item, count, tostring(opts.note)))
end)
M.netEvent('wasteland:shop:server:crash', {}, function() error('boom') end)
AddEventHandler('wasteland:core:netViolation', function(src, module, ev, kind) track('violation ' .. tostring(src) .. ' ' .. kind) end)
exports('Health', function(status, detail) return M.setHealth(status, detail) end)
]]

local function setup(config)
    local server = newServer({ config = config })
    addModule(server, 'fx_shop', GUARDED)
    server:start('fx_shop')
    local id = server:connectAndJoin({ name = 'Tester' })
    return server, id
end

local function calls(server) return server:export('fx_shop', 'Calls') end

describe('net-event guard', function()
    it('delivers valid events with validated arguments (defaults applied)', function()
        local server, id = setup()
        server:clientEvent(id, 'wasteland:shop:server:buy', 'water', 2, { note = 'hi' })
        server:clientEvent(id, 'wasteland:shop:server:buy', 'bandage', 1)
        expect(calls(server)).toContain('buy 1 water x2 hi')
        expect(calls(server)).toContain('buy 1 bandage x1 nil')
    end)

    it('rejects wrong types, ranges and patterns with the argument named', function()
        local server, id = setup()
        -- spaced out so the rate limit (checked first) does not interfere
        local function send(...) server:clientEvent(id, 'wasteland:shop:server:buy', ...); server:advance(1000) end
        send('water', '2')
        send('water', 99)
        send('DROP TABLE', 1)
        send(nil, 1)
        send('water', 1, { note = string.rep('x', 50) })
        local c = calls(server)
        -- Only the first is logged (throttled per player, event and kind);
        -- every one is reported to the core.
        expect(#server:lines('rejected "wasteland:shop:server:buy" from player 1 (payload): argument 2: expected an integer')).toBe(1)
        local violations = 0
        for _, entry in ipairs(c) do
            expect(entry:sub(1, 4) ~= 'buy ').toBe(true)
            if entry == 'violation 1 payload' then violations = violations + 1 end
        end
        expect(violations).toBe(5)
    end)

    it('rejects extra arguments', function()
        local server, id = setup()
        server:clientEvent(id, 'wasteland:shop:server:buy', 'water', 1, {}, 'extra')
        expect(#server:lines('expected at most 3 argument(s), got 4') > 0).toBe(true)
    end)

    it('rate-limits per player and event, then refills over time', function()
        local server, id = setup()
        for _ = 1, 5 do server:clientEvent(id, 'wasteland:shop:server:buy', 'water', 1) end
        local bought = 0
        for _, e in ipairs(calls(server)) do if e:find('^buy') then bought = bought + 1 end end
        expect(bought).toBe(3)
        expect(calls(server)).toContain('violation 1 rate')
        server:advance(2000)
        server:clientEvent(id, 'wasteland:shop:server:buy', 'water', 1)
        bought = 0
        for _, e in ipairs(calls(server)) do if e:find('^buy') then bought = bought + 1 end end
        expect(bought).toBe(4)
    end)

    it('throttles the warning log for repeated violations', function()
        local server, id = setup()
        for _ = 1, 20 do server:clientEvent(id, 'wasteland:shop:server:buy', 1, 1) end
        expect(#server:lines('rejected "wasteland:shop:server:buy" from player 1 (payload)')).toBe(1)
    end)

    it('rejects events from a source that is not a connected player', function()
        local server = setup()
        server:clientEvent(42, 'wasteland:shop:server:buy', 'water', 1)
        expect(calls(server)).toContain('violation 42 source')
    end)

    it('drops events while the module is not running', function()
        local server, id = setup({ ['modules.lua'] = 'return { enabled = { shop = false } }' })
        server:clientEvent(id, 'wasteland:shop:server:buy', 'water', 1)
        for _, e in ipairs(calls(server)) do expect(e:find('^buy') == nil).toBe(true) end
    end)

    it('logs handler errors without a script error', function()
        local server, id = setup()
        server:clientEvent(id, 'wasteland:shop:server:crash')
        expect(#server:lines('handler for "wasteland:shop:server:crash" (player 1) raised') > 0).toBe(true)
        expect(#server.scriptErrors).toBe(0)
    end)

    it('only reaches events registered with the guard (no plain handlers)', function()
        local server, id = setup()
        server:clientEvent(id, 'wasteland:core:netViolation', 1, 'x', 'y', 'z', 'w')
        expect(#calls(server)).toBe(0)
    end)

    it('refuses badly named events and invalid schemas at registration', function()
        local server = newServer()
        addModule(server, 'fx_badname', [[
local M = Wasteland.DefineModule({ name = 'badname', version = '1.0.0' })
local ok1, e1 = pcall(M.netEvent, 'wasteland:other:server:x', {}, function() end)
local ok2, e2 = pcall(M.netEvent, 'wasteland:badname:server:y', { args = { { type = 'nope' } } }, function() end)
track(tostring(ok1) .. ' ' .. tostring(e1)); track(tostring(ok2) .. ' ' .. tostring(e2))
]])
        server:start('fx_badname')
        local c = server:export('fx_badname', 'Calls')
        expect(c[1]).toContain('must be named "wasteland:badname:server:<action>"')
        expect(c[2]).toContain('invalid schema')
    end)

    it('kicks repeat offenders when framework.security.kickAfterViolations is set', function()
        local server, id = setup({ ['framework.lua'] = 'return { security = { kickAfterViolations = 3, violationWindowSeconds = 60 } }' })
        for _ = 1, 3 do server:clientEvent(id, 'wasteland:shop:server:buy', false, 1) end
        server:advance(0)
        expect(server.dropped[1].id).toBe(id)
        expect(server.dropped[1].reason).toContain('too many invalid requests')
    end)

    it('never kicks by default', function()
        local server, id = setup()
        for _ = 1, 50 do server:clientEvent(id, 'wasteland:shop:server:buy', false, 1) end
        server:advance(0)
        expect(#server.dropped).toBe(0)
    end)
end)

describe('module health', function()
    local server = setup()
    it('a running module can report itself degraded with a detail', function()
        expect(server:export('fx_shop', 'Health', 'degraded', 'supplier offline')).toBe(true)
        local s = server:export('wasteland_core', 'GetModuleStatus', 'shop')
        expect(s.state).toBe('running')
        expect(s.health).toBe('degraded')
        expect(s.healthDetail).toBe('supplier offline')
        expect(#server:lines('module "shop" is degraded: supplier offline')).toBe(1)
    end)
    it('appears in the status table and module details', function()
        server:clearOutput()
        server:command(0, 'wasteland status')
        expect(#server:lines('DEGRADED: supplier offline')).toBe(1)
        server:command(0, 'wasteland module shop')
        expect(#server:lines('health:      degraded - supplier offline')).toBe(1)
    end)
    it('recovers with status ok', function()
        expect(server:export('fx_shop', 'Health', 'ok')).toBe(true)
        local s = server:export('wasteland_core', 'GetModuleStatus', 'shop')
        expect(s.health).toBe('ok')
        expect(s.healthDetail).toBe(nil)
        expect(#server:lines('module "shop" recovered')).toBe(1)
    end)
    it('rejects invalid statuses and other resources', function()
        local ok, err = server:export('fx_shop', 'Health', 'on fire')
        expect(ok).toBe(false)
        expect(err).toContain('invalid health status')
        addModule(server, 'fx_other', [[ track({ exports.wasteland_core:ReportModuleHealth('shop', 'degraded', 'x') }) ]])
        server:start('fx_other')
        expect(server:export('fx_other', 'Calls')[1][2]).toContain('does not own module "shop"')
    end)
end)
