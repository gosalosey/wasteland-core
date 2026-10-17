-- New characters start with a knife and a Full vehicle repair; the repair
-- (one use, one carried at a time) turns any wreck into a working car with
-- half a tank.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['vehicles.lua'] = [[return {
        maxVehicles = 1, respawnMinutes = 1, spawnDistance = 250, despawnDistance = 350, despawnAfterSeconds = 4, saveSeconds = 4,
        seconds = { fullRepair = 1, battery = 1, engine = 1, wheel = 1, refuel = 1, siphon = 1, repair = 1, fitLock = 1, toggleLock = 1,
            pickLock = 1, removeLock = 1, fillCan = 1 },
        spotCheck = { enabled = false },
        wreck = { batteryMissing = 1, engineMissing = 1, wheelsMissingChance = 1, wheelsMissingMax = 2,
            fuel = { 2, 2 }, engine = { 300, 300 }, body = { 400, 400 } },
        models = { 'rebel' },
        spawnPoints = { { x = 1000.0, y = 0.0, z = 30.0, heading = 90.0 } },
    }]],
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

describe('starting kit and the full vehicle repair', function()
    -- shippedPockets: the real starting items and pockets
    local server = newServer({ config = CFG, shippedPockets = true })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_vehicles' })
    local function join(license)
        local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
        server:advance(200)
        server.players[id].coords = { x = 0.0, y = 0.0, z = 30.0 }
        server:command(id, 'character create Rae Repair'); server:advance(300)
        server:command(id, 'character select 1'); server:advance(500)
        server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01')); server:advance(500)
        return id
    end
    local id = join('rep')
    local other = join('rep2')
    local function I(fn, ...) return server:export('wasteland_inventory', fn, ...) end
    local function note() local l = server:clientEventsFor(id, 'wasteland:vehicles:client:notice'); return l[#l].args[1] end

    it('a new character starts with a knife and a Full vehicle repair', function()
        expect(I('GetItemCount', id, 'weapon_knife')).toBe(1)
        expect(I('GetItemCount', id, 'full_vehicle_repair')).toBe(1)
    end)

    it('you can only carry one: a second is refused (given, or traded)', function()
        local ok, err = I('AddItem', id, 'full_vehicle_repair', 1)
        expect(ok).toBe(false); expect(err).toContain('only carry 1')
        expect(I('GetItemCount', id, 'full_vehicle_repair')).toBe(1)
        local kit
        for _, s in ipairs(I('GetTradeable', other)) do if s.name == 'full_vehicle_repair' then kit = s end end
        local tok, terr = I('Trade', other, { { uid = kit.uid, count = 1 } }, id, {})
        expect(tok).toBe(false); expect(terr).toContain('only carry 1')
    end)

    it('used on a wreck: every part, like new, half a tank - and it is used up', function()
        server.players[id].coords = { x = 998.0, y = 0.0, z = 30.0 }
        server:advance(2100)
        local e = server:entityList('wlVeh')[1]
        expect(e.state.wlVeh.parts.battery).toBe(false)
        server:clientEvent(e.owner, 'wasteland:vehicles:server:applied', e.netId, e.state.wlVeh.seq); server:advance(50)
        server:clientEvent(id, 'wasteland:vehicles:server:act', e.netId, 'fullRepair'); server:advance(1100)
        server:clientEvent(id, 'wasteland:vehicles:server:finish'); server:advance(200)
        local s = server:entityList('wlVeh')[1].state.wlVeh
        expect(s.parts.battery).toBe(true); expect(s.parts.engine).toBe(true); expect(s.parts.wheels).toBe(4)
        expect(s.engine).toBe(1000); expect(s.body).toBe(1000)
        expect(s.fuel).toBe(25) -- half of the 50 L tank
        expect(I('GetItemCount', id, 'full_vehicle_repair')).toBe(0)
        expect(note()).toContain('Fully repaired')
    end)

    it('not needed on a car in good shape; without the kit it says so', function()
        local e = server:entityList('wlVeh')[1]
        server:clientEvent(id, 'wasteland:vehicles:server:act', e.netId, 'fullRepair'); server:advance(200)
        expect(note()).toBe('This vehicle is already in good shape.')
        expect(#server.scriptErrors).toBe(0)
    end)
end)
