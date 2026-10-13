-- wasteland_groups (server): make a group, invite, accept or decline,
-- markers for members, leave, kick, new leader, rename, kept across a
-- restart, disband.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['groups.lua'] = 'return { maxMembers = 3, inviteSeconds = 60, markerSeconds = 1 }',
}

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end

describe('groups', function()
    local server = newServer({ config = CFG })
    -- a stand-in for pma-voice: records the radio channels it is told
    server:addVirtualResource('pma-voice', { fx_version = { 'cerulean' }, game = { 'gta5' }, server_script = { 'server.lua' } }, {
        ['server.lua'] = [[
            local calls = {}
            exports('setPlayerRadio', function(src, channel) calls[#calls + 1] = { src = src, channel = channel } end)
            exports('Calls', function() return calls end)
        ]],
    })
    boot(server, { 'pma-voice', 'wasteland_players', 'wasteland_groups' })
    local function radioOf(id)
        local ch = nil
        for _, c in ipairs(server:export('pma-voice', 'Calls')) do if c.src == id then ch = c.channel end end
        return ch
    end
    local function player(license, first, x)
        local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
        server:advance(200)
        server.players[id].coords = { x = x, y = 0.0, z = 30.0 }
        server:command(id, 'character create ' .. first .. ' Test'); server:advance(300)
        server:command(id, 'character select 1'); server:advance(500)
        return id
    end
    local a = player('ga', 'Anna', 0.0)
    local b = player('gb', 'Bert', 100.0)
    local c = player('gc', 'Cleo', 200.0)
    local function note(id) return last(events(server, id, 'wasteland:groups:client:notice')).args[1] end
    local function view(id) server:clientEvent(id, 'wasteland:groups:server:view'); server:advance(100); return last(events(server, id, 'wasteland:groups:client:view')).args[1] end
    local function act(id, what, ...) server:clientEvent(id, 'wasteland:groups:server:' .. what, ...); server:advance(1100) end

    it('runs; checks the name; makes a group with its maker as leader', function()
        expect(states(server).groups).toBe('running')
        act(a, 'create', 'x')
        expect(note(a)).toBe('The name must be 3 to 24 characters.')
        act(a, 'create', '  The   Survivors ')
        expect(note(a)).toBe('Group "The Survivors" created. Invite players from /group.')
        local v = view(a)
        expect(v.group.name).toBe('The Survivors'); expect(v.group.leader).toBe(true); expect(#v.group.members).toBe(1)
        act(b, 'create', 'the survivors')
        expect(note(b)).toBe('A group with that name already exists.')
        expect(radioOf(a)).toBe(1001) -- group 1 talks on radio channel 1001
    end)

    it('only the leader invites; the invited player accepts and joins', function()
        act(a, 'invite', b)
        expect(note(b)).toBe('Anna Test invites you to the group "The Survivors". Type /group to accept.')
        local v = view(b)
        expect(v.invite.name).toBe('The Survivors')
        act(b, 'respond', v.invite.group, true)
        expect(note(a)).toBe('Bert Test joined the group.')
        expect(radioOf(b)).toBe(1001)
        expect(#view(a).group.members).toBe(2)
        act(b, 'invite', c)
        expect(note(b)).toBe('Only the leader can invite players.')
    end)

    it('members get each other on the map, not themselves', function()
        server:advance(1100)
        local pa = last(events(server, a, 'wasteland:groups:client:positions')).args[1]
        expect(pa.group).toBe('The Survivors')
        expect(#pa.members).toBe(1); expect(pa.members[1].name).toBe('Bert Test'); expect(pa.members[1].x).toBe(100.0)
        local pb = last(events(server, b, 'wasteland:groups:client:positions')).args[1]
        expect(pb.members[1].leader).toBe(true)
    end)

    it('a declined invite; a full group', function()
        act(a, 'invite', c)
        act(c, 'respond', view(c).invite.group, false)
        expect(note(a)).toBe('Cleo Test declined the invitation.')
        expect(#view(a).group.members).toBe(2)
    end)

    it('kick, new leader, rename', function()
        local bId = server:export('wasteland_players', 'GetCharacterId', b)
        act(a, 'promote', bId)
        expect(view(b).group.leader).toBe(true)
        act(a, 'leave')
        expect(note(a)).toBe('You left "The Survivors".')
        expect(view(a).group == nil).toBe(true)
        act(b, 'rename', 'Dead End')
        expect(view(b).group.name).toBe('Dead End')
        -- the leader removes a member
        act(b, 'invite', c)
        act(c, 'respond', view(c).invite.group, true)
        local cId = server:export('wasteland_players', 'GetCharacterId', c)
        act(c, 'kick', server:export('wasteland_players', 'GetCharacterId', b))
        expect(note(c)).toBe('Only the leader can do that.')
        act(b, 'kick', cId)
        expect(note(c)).toBe('You were removed from "Dead End".')
        expect(radioOf(c)).toBe(0) -- off the group radio
        expect(view(c).group == nil).toBe(true)
    end)

    it('is kept across a restart of the module', function()
        act(b, 'invite', a)
        act(a, 'respond', view(a).invite.group, true)
        server:restart('wasteland_groups'); server:advance(2000)
        local v = view(a)
        expect(v.group.name).toBe('Dead End'); expect(#v.group.members).toBe(2)
        expect(view(b).group.leader).toBe(true)
    end)

    it('the leader disbands it: everyone is out, the markers go', function()
        act(b, 'disband')
        expect(note(a)).toBe('The group "Dead End" was disbanded.')
        expect(radioOf(a)).toBe(0); expect(radioOf(b)).toBe(0)
        expect(view(a).group == nil).toBe(true)
        expect(last(events(server, a, 'wasteland:groups:client:positions')).args[1] == nil).toBe(true)
        local n = 0
        for _ in pairs(server.db.backend.data.wl_groups) do n = n + 1 end
        expect(n).toBe(0)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)
