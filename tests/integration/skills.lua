-- wasteland_skills (server): XP from what other modules report, level-ups,
-- bonuses, the death penalty, sprint reports (capped), kept across a
-- restart; medicine through the survival module.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('skills', function()
    local server = newServer({ config = CFG })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival', 'wasteland_skills' })
    local id = server:connectAndJoin({ name = 'P-skill', license = 'skill' })
    server:advance(200)
    server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
    server:command(id, 'character create Sam Skill'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
    local function S(fn, ...) return server:export('wasteland_skills', fn, ...) end
    local function level(name) return S('GetLevel', id, name) end
    local function skill(name)
        for _, s in ipairs(S('GetSkills', id).skills) do if s.name == name then return s end end
    end
    local function fire(ev, ...) server:triggerEvent('wasteland_loot', ev, ...); server:advance(50) end

    it('runs; everyone starts at level 1 with no bonus', function()
        expect(states(server).skills).toBe('running')
        expect(level('scavenging')).toBe(1)
        expect(S('GetBonus', id, 'scavenging', 'searchTime')).toBe(0)
        expect(#S('GetSkills', id).skills).toBe(6)
        expect(#server:clientEventsFor(id, 'wasteland:skills:client:view') > 0).toBe(true)
    end)

    it('searching gives scavenging XP; ten searches is level 2 (with a level-up message)', function()
        for _ = 1, 10 do fire('wasteland:loot:searched', id, 'dumpster', 'x') end
        expect(level('scavenging')).toBe(2)
        local up = server:clientEventsFor(id, 'wasteland:skills:client:levelUp')
        expect(up[#up].args[1]).toBe('scavenging'); expect(up[#up].args[3]).toBe(2)
        expect(S('GetBonus', id, 'scavenging', 'searchTime') > 0).toBe(true)
    end)

    it('crafting, hunting and zombie kills (only the killer) give their own XP', function()
        fire('wasteland:crafting:crafted', id, 'bandage')
        fire('wasteland:hunting:harvested', id, 'Deer', 3, 1)
        fire('wasteland:zombies:died', 5, 'walker', 'reported', id, { x = 0, y = 0, z = 0 })
        fire('wasteland:zombies:died', 6, 'walker', 'reported', 0, { x = 0, y = 0, z = 0 })
        expect(skill('crafting').xp).toBe(15)
        expect(skill('hunting').xp).toBe(25)
        expect(skill('combat').xp).toBe(8)
    end)

    it('a bandage gives medicine XP (through survival)', function()
        local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
        server:export('wasteland_survival', 'AddBleeding', id, 1)
        I('AddItem', id, 'bandage', 1); server:advance(100)
        local b
        for _, s in ipairs(I('GetTradeable', id)) do if s.name == 'bandage' then b = s end end
        server:clientEvent(id, 'wasteland:inventory:server:use', b.uid, b.inventoryId); server:advance(300)
        expect(skill('medicine').xp).toBe(15)
    end)

    it('sprinting: at most the time since the last report', function()
        server:advance(60000)
        server:clientEvent(id, 'wasteland:skills:server:sprint', 60); server:advance(100)
        expect(math.floor(skill('fitness').xp + 0.5)).toBe(6)
        server:advance(25000)
        server:clientEvent(id, 'wasteland:skills:server:sprint', 60); server:advance(100)
        expect(math.floor(skill('fitness').xp + 0.5)).toBe(9) -- only 25 s counted
    end)

    it('the top level gives the full bonus', function()
        S('AddXP', id, 'hunting', 100000)
        expect(level('hunting')).toBe(10)
        expect(S('GetBonus', id, 'hunting', 'extraMeat')).toBe(0.5)
    end)

    it('dying costs a little progress, never a level', function()
        local before = skill('crafting') -- 15 XP into level 1
        server:triggerEvent('wasteland_survival', 'wasteland:survival:died', id, nil, 'test'); server:advance(100)
        local after = skill('crafting')
        expect(after.level).toBe(before.level)
        expect(after.xp < before.xp).toBe(true)
        expect(level('hunting')).toBe(10)
    end)

    it('is kept across a restart', function()
        local xpBefore = skill('crafting').xp
        server:restart('wasteland_skills'); server:advance(2500)
        expect(states(server).skills).toBe('running')
        expect(skill('crafting').xp).toBe(xpBefore)
        expect(level('hunting')).toBe(10)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
