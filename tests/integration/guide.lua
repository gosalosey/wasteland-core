-- wasteland_guide (server): counts what a character does from other
-- modules' events, ticks off milestones (with a message), suggests what to
-- try next, time alive, kept across a restart.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe("survivor's guide", function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival', 'wasteland_skills', 'wasteland_guide',
        'wasteland_weapons', 'wasteland_zombies' })
    local function join(license, first)
        local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
        server:advance(200)
        server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
        server:command(id, 'character create ' .. first .. ' Guide'); server:advance(300)
        server:command(id, 'character select 1'); server:advance(500)
        server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
        return id
    end
    local id = join('guide', 'Gail')
    local other = join('guide2', 'Gus')
    local function G(who) return server:export('wasteland_guide', 'GetGuide', who or id) end
    local function m(who, mid) for _, x in ipairs(G(who).milestones) do if x.id == mid then return x end end end
    local function fire(ev, ...) server:triggerEvent('wasteland_loot', ev, ...); server:advance(50) end

    it('runs; a new survivor has nothing done and is told to search first', function()
        expect(states(server).guide).toBe('running')
        local g = G()
        expect(#g.milestones > 10).toBe(true)
        expect(m(id, 'search').done).toBe(false)
        expect(g.next[1]).toBe('search')
        expect(#g.pages > 0).toBe(true)
        expect(#server:clientEventsFor(id, 'wasteland:guide:client:view') > 0).toBe(true)
    end)

    it('searching ticks off the first milestone, with a message; the next one moves up', function()
        fire('wasteland:loot:searched', id, 'dumpster', 'x')
        expect(m(id, 'search').done).toBe(true)
        local msg = server:clientEventsFor(id, 'wasteland:guide:client:milestone')
        expect(msg[#msg].args[1]).toBe('Search a container')
        expect(G().next[1]).toBe('eat')
        expect(G().stats.searches).toBe(1)
    end)

    it('counted milestones show progress (kills, only for the killer)', function()
        for _ = 1, 3 do fire('wasteland:zombies:died', 1, 'walker', 'reported', id, { x = 0, y = 0, z = 0 }) end
        fire('wasteland:zombies:died', 2, 'walker', 'reported', 0, { x = 0, y = 0, z = 0 })
        expect(m(id, 'kill1').done).toBe(true)
        expect(m(id, 'kill25').value).toBe(3); expect(m(id, 'kill25').done).toBe(false)
    end)

    it('eating counts as a meal (through survival); a trade counts for both players', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        server:export('wasteland_survival', 'ModifyStats', id, { hunger = -50 })
        I('AddItem', id, 'canned_beans', 1); server:advance(100)
        local b
        for _, s in ipairs(I('GetTradeable', id)) do if s.name == 'canned_beans' then b = s end end
        server:clientEvent(id, 'wasteland:inventory:server:use', b.uid, b.inventoryId); server:advance(300)
        expect(m(id, 'eat').done).toBe(true)
        fire('wasteland:trade:done', id, {}, other, {})
        expect(m(id, 'playertrade').done).toBe(true)
        expect(m(other, 'playertrade').done).toBe(true)
    end)

    it('time alive counts a minute at a time; dying starts a new life but keeps the longest', function()
        server:advance(180500)
        expect(G().lifeMinutes >= 3).toBe(true)
        local longest = G().stats.lifeMinutes
        server:triggerEvent('wasteland_survival', 'wasteland:survival:died', id, nil, 'test'); server:advance(100)
        expect(G().lifeMinutes).toBe(0)
        expect(G().stats.lifeMinutes).toBe(longest)
        expect(G().stats.deaths).toBe(1)
    end)

    it('a skill level counts towards "level 5 in any skill"', function()
        server:export('wasteland_skills', 'AddXP', id, 'combat', 2000)
        server:advance(100)
        expect(m(id, 'skill5').done).toBe(true)
    end)

    it('a real zombie kill counts even when the server sees it dead before the kill report arrives', function()
        local before = G().stats.kills or 0
        local netId = server:export('wasteland_zombies', 'SpawnZombie', { x = 5.0, y = 0.0, z = 30.0 })
        local z
        for _, e in ipairs(server:entityList('wlZombie')) do if e.netId == netId then z = e end end
        z.owner = id
        z.health = 0
        server:advance(1500)                     -- the server's own check sees it at 0 health first
        server:clientEvent(id, 'wasteland:zombies:server:died', netId, id); server:advance(200)
        expect(G().stats.kills).toBe(before + 1)
    end)

    it('a character older than the guide gets credit for what its skills show (kills from combat XP)', function()
        server:export('wasteland_skills', 'AddXP', other, 'combat', 80) -- 10 kills worth
        server:restart('wasteland_guide'); server:advance(4000)
        expect(server:export('wasteland_guide', 'GetGuide', other).stats.kills >= 10).toBe(true)
        expect(m(other, 'kill1').done).toBe(true)
    end)

    it('is kept across a restart', function()
        server:restart('wasteland_guide'); server:advance(2500)
        expect(states(server).guide).toBe('running')
        expect(m(id, 'search').done).toBe(true)
        expect(G().stats.kills >= 4).toBe(true) -- 4 real kills, more from combat XP (backfill)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
