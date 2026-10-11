-- wasteland_admin (server): permission checks, every action, bans (stored,
-- checked on connect, lifted), action log, announcements, world control.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function world()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival',
        'wasteland_world', 'wasteland_admin' })
    return server
end

local function player(server, license, coords)
    local id, err = server:connectAndJoin({ name = 'P-' .. license, license = license })
    assert(id, err)
    server:advance(200)
    server.players[id].coords = coords or { x = 100.0, y = 100.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    return id
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end
local function act(server, admin, action, args)
    server:clientEvent(admin, 'wasteland:admin:server:act', action, args or {})
    server:advance(400)
    return last(events(server, admin, 'wasteland:admin:client:result')).args[1]
end

describe('admin permissions', function()
    local server = world()
    local plain = player(server, 'plain')

    it('runs and records its migrations', function()
        expect(states(server).admin).toBe('running')
        local n = 0
        for _, m in ipairs(server.db.backend.data.wl_migrations) do if m.module_name == 'admin' then n = n + 1 end end
        expect(n).toBe(2)
    end)

    it('refuses the panel and every action without the ACE, and logs the attempt', function()
        server:clientEvent(plain, 'wasteland:admin:server:open')
        server:advance(100)
        expect(#events(server, plain, 'wasteland:admin:client:denied')).toBe(1)
        expect(#events(server, plain, 'wasteland:admin:client:data')).toBe(0)
        local r = act(server, plain, 'heal', { target = plain })
        expect(r.ok).toBe(false)
        expect(r.message).toBe('You are not an admin.')
        expect(#server:lines('tried admin action "heal" without the wasteland.admin ACE')).toBe(1)
        expect(#server.db.backend.data.wl_admin_log).toBe(0)
    end)

    it('rejects unknown actions before the module sees them', function()
        server:clientEvent(plain, 'wasteland:admin:server:act', 'nuke', {})
        expect(#server:lines('rejected "wasteland:admin:server:act" from player 1 (payload)')).toBe(1)
    end)
end)

describe('admin panel and player actions', function()
    local server = world()
    local admin = player(server, 'boss', { x = 0.0, y = 0.0, z = 30.0 })
    server.aces[admin .. '|wasteland.admin'] = true
    local target = player(server, 'guy', { x = 500.0, y = 500.0, z = 40.0 })

    it('sends panel data: players with characters and stats, items, modules, world', function()
        server:clientEvent(admin, 'wasteland:admin:server:open')
        server:advance(100)
        local d = last(events(server, admin, 'wasteland:admin:client:data')).args[1]
        expect(#d.players).toBe(2)
        expect(d.players[2].character.firstName).toBe('John')
        expect(d.players[2].stats.hunger).toBe(100)
        expect(#d.items > 10).toBe(true)
        expect(#d.modules >= 8).toBe(true)
        expect(d.world.weather).toBe('CLEAR')
    end)

    it('teleports to and brings players using server-side positions', function()
        expect(act(server, admin, 'teleportTo', { target = target }).ok).toBe(true)
        expect(last(events(server, admin, 'wasteland:admin:client:teleport')).args[1].x).toBe(500.0)
        expect(act(server, admin, 'bring', { target = target }).ok).toBe(true)
        expect(last(events(server, target, 'wasteland:admin:client:teleport')).args[1].x).toBe(0.0)
    end)

    it('sets survival stats, heals and freezes', function()
        expect(act(server, admin, 'setStat', { target = target, stat = 'infection', value = 55 }).ok).toBe(true)
        expect(server:export('wasteland_survival', 'GetStats', target).infection).toBe(55)
        expect(act(server, admin, 'heal', { target = target }).ok).toBe(true)
        expect(server:export('wasteland_survival', 'GetStats', target).infection).toBe(0)
        expect(act(server, admin, 'freeze', { target = target, enabled = true }).ok).toBe(true)
        expect(last(events(server, target, 'wasteland:admin:client:freeze')).args[1]).toBe(true)
    end)

    it('revives only dead players', function()
        expect(act(server, admin, 'revive', { target = target }).ok).toBe(false)
        server:clientEvent(target, 'wasteland:survival:server:died')
        server:advance(300)
        expect(act(server, admin, 'revive', { target = target }).ok).toBe(true)
        expect(server:export('wasteland_survival', 'IsDead', target)).toBe(false)
        expect(#events(server, target, 'wasteland:survival:client:revive')).toBe(1)
    end)

    it('gives items, opens and clears inventories', function()
        expect(act(server, admin, 'give', { target = target, item = 'antibiotics', count = 2 }).ok).toBe(true)
        expect(server:export('wasteland_inventory', 'GetItemCount', target, 'antibiotics')).toBe(2)
        expect(act(server, admin, 'give', { target = target, item = 'unicorn', count = 1 }).message).toContain('unknown item')
        expect(act(server, admin, 'inventory', { target = target }).ok).toBe(true)
        expect(#events(server, admin, 'wasteland:inventory:client:open')).toBe(1)
        local sync = last(events(server, admin, 'wasteland:inventory:client:sync')).args[1]
        expect(sync.secondary[1]).toBe('player:2')
        expect(act(server, admin, 'clearInventory', { target = target }).ok).toBe(true)
        expect(server:export('wasteland_inventory', 'GetItemCount', target, 'antibiotics')).toBe(0)
    end)

    it('writes every change to the action log (not the read-only ones)', function()
        local actions = {}
        for _, r in ipairs(server.db.backend.data.wl_admin_log) do actions[#actions + 1] = r.action end
        expect(actions).toContain('setStat')
        expect(actions).toContain('give')
        expect(actions).toContain('clearInventory')
        expect(actions).notToContain('teleportTo')
        expect(actions).notToContain('inventory')
        expect(server.db.backend.data.wl_admin_log[1].admin).toBe('P-boss')
        server:clientEvent(admin, 'wasteland:admin:server:list', 'log')
        server:advance(200)
        local list = last(events(server, admin, 'wasteland:admin:client:list'))
        expect(list.args[1]).toBe('log')
        expect(#list.args[2] >= 3).toBe(true)
    end)

    it('announces to everyone and controls time and weather', function()
        expect(act(server, admin, 'announce', { text = 'Storm coming' }).ok).toBe(true)
        local a = last(events(server, -1, 'wasteland:admin:client:announce')).args[1]
        expect(a.text).toBe('Storm coming'); expect(a.by).toBe('P-boss')
        expect(act(server, admin, 'setTime', { hour = 21, minute = 15 }).ok).toBe(true)
        expect((server:export('wasteland_world', 'GetTime'))).toBe(21)
        expect(act(server, admin, 'setWeather', { weather = 'THUNDER' }).ok).toBe(true)
        expect((server:export('wasteland_world', 'GetWeather'))).toBe('THUNDER')
    end)

    it('kicks players', function()
        expect(act(server, admin, 'kick', { target = target, reason = 'testing' }).ok).toBe(true)
        server:advance(100)
        expect(last(server.dropped).reason).toBe('Kicked: testing')
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('bans', function()
    local server = world()
    local admin = player(server, 'boss')
    server.aces[admin .. '|wasteland.admin'] = true
    local target = player(server, 'cheater')

    it('need a reason', function()
        expect(act(server, admin, 'ban', { target = target, minutes = 60 }).message).toBe('a ban needs a reason')
    end)

    it('are stored, kick the player and refuse them on connect', function()
        expect(act(server, admin, 'ban', { target = target, reason = 'speed hacks', minutes = 1440 }).ok).toBe(true)
        server:advance(200)
        local b = server.db.backend.data.wl_bans[1]
        expect(b.license).toBe('license:cheater')
        expect(b.reason).toBe('speed hacks')
        expect(b.expires_unix - b.created_unix).toBe(1440 * 60)
        expect(last(server.dropped).reason).toContain('You are banned from this server until')
        local id, err = server:connectAndJoin({ name = 'again', license = 'cheater' })
        expect(id).toBe(nil)
        expect(err).toContain('Reason: speed hacks (ban #1)')
    end)

    it('can ban an offline license permanently, survive a restart and be lifted', function()
        expect(act(server, admin, 'banLicense', { license = 'license:abc123', name = 'Ghost', reason = 'alt', minutes = 0 }).ok).toBe(true)
        expect(server.db.backend.data.wl_bans[2].expires_unix).toBe(nil)
        server:restart('wasteland_admin')
        server:advance(2000)
        local _, err = server:connectAndJoin({ name = 'Ghost', license = 'abc123' })
        expect(err).toContain('permanently')
        expect(act(server, admin, 'unban', { banId = 2 }).ok).toBe(true)
        expect(server.db.backend.data.wl_bans[2].revoked_by).toBe('P-boss')
        local id = server:connectAndJoin({ name = 'Ghost', license = 'abc123' })
        expect(id ~= nil).toBe(true)
        expect(act(server, admin, 'unban', { banId = 2 }).ok).toBe(false)
    end)

    it('lists bans for the panel', function()
        server:clientEvent(admin, 'wasteland:admin:server:list', 'bans')
        server:advance(200)
        local list = last(events(server, admin, 'wasteland:admin:client:list'))
        expect(list.args[1]).toBe('bans')
        expect(#list.args[2]).toBe(2)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
