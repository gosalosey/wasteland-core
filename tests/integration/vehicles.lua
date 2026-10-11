-- wasteland_vehicles (server): wrecks, spawning near players, saving,
-- parts, fuel, repairs, locks and keys, lock picking, trunks, destruction,
-- persistence across restarts, abuse.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['vehicles.lua'] = [[return {
        maxVehicles = 2, respawnMinutes = 1, spawnDistance = 250, despawnDistance = 350, despawnAfterSeconds = 4, saveSeconds = 4,
        seconds = { battery = 1, engine = 1, wheel = 1, refuel = 1, repair = 1, fitLock = 1, toggleLock = 1, pickLock = 1, fillCan = 1 },
        lockpick = { chance = 0, breakChance = 1, noise = 60 },
        wreck = { batteryMissing = 1, engineMissing = 0, wheelsMissingChance = 1, wheelsMissingMax = 1,
            fuel = { 2, 2 }, engine = { 500, 500 }, body = { 600, 600 } },
        models = { 'rebel' },
        spawnPoints = { { x = 1000.0, y = 0.0, z = 30.0, heading = 90.0 }, { x = 5000.0, y = 0.0, z = 30.0 } },
    }]],
}

local function defaults(model)
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(RESOURCES .. '/wasteland_appearance/shared/defs.lua', 't', env))()
    return env.WLA.defaults(model)
end

local function world(backend)
    local server = newServer({ config = CFG, dbBackend = backend })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_vehicles' })
    return server
end

local function player(server, license, coords)
    local id = server:connectAndJoin({ name = 'P-' .. license, license = license })
    server:advance(200)
    server.players[id].coords = coords or { x = 0.0, y = 0.0, z = 30.0 }
    server:command(id, 'character create John Doe'); server:advance(300)
    server:command(id, 'character select 1'); server:advance(500)
    server:clientEvent(id, 'wasteland:appearance:server:save', defaults('mp_m_freemode_01'))
    server:advance(500)
    return id
end

local function events(server, id, name) return server:clientEventsFor(id, name) end
local function last(list) return list[#list] end
local function I(server, fn, ...) return server:export('wasteland_inventory', fn, ...) end
local function note(server, id) return last(events(server, id, 'wasteland:vehicles:client:notice')).args[1] end
local function veh(server) return server:entityList('wlVeh')[1] end
-- What the client running the vehicle does after applying the state.
local function ack(server)
    local e = veh(server)
    server:clientEvent(e.owner, 'wasteland:vehicles:server:applied', e.netId, e.state.wlVeh.seq)
    server:advance(50)
end
local function act(server, id, action)
    local e = veh(server)
    server:clientEvent(id, 'wasteland:vehicles:server:act', e.netId, action)
    server:advance(100)
    server:advance(1000)
    server:clientEvent(id, 'wasteland:vehicles:server:finish')
    server:advance(200)
end

describe('vehicles', function()
    local server = world()
    local id = player(server, 'driver')
    local thief

    it('runs; fills the world with wrecks at the spawn points (stored)', function()
        expect(states(server).vehicles).toBe('running')
        expect(server:export('wasteland_vehicles', 'GetVehicleCount')).toBe(2)
        local rows = 0
        for _ in pairs(server.db.backend.data.wl_vehicles) do rows = rows + 1 end
        expect(rows).toBe(2)
        expect(#server:entityList('wlVeh')).toBe(0) -- nobody near
    end)

    it('a wreck appears when a player comes near, with its state', function()
        server.players[id].coords = { x = 990.0, y = 0.0, z = 30.0 }
        server:advance(2100)
        local e = veh(server)
        expect(e ~= nil).toBe(true)
        local s = e.state.wlVeh
        expect(s.parts.battery).toBe(false); expect(s.parts.engine).toBe(true); expect(s.parts.wheels).toBe(3)
        expect(s.fuel).toBe(2); expect(s.engine).toBe(500)
        expect(e.doorLock).toBe(1)
    end)

    it('installing a battery and a wheel needs the parts and uses them up', function()
        server.players[id].coords = { x = 998.0, y = 0.0, z = 30.0 }
        local e = veh(server)
        server:clientEvent(id, 'wasteland:vehicles:server:act', e.netId, 'battery'); server:advance(100)
        expect(note(server, id)).toBe('You need a car battery.')
        I(server, 'AddItem', id, 'car_battery', 1); server:advance(100)
        act(server, id, 'battery')
        I(server, 'AddItem', id, 'car_wheel', 1); server:advance(100)
        act(server, id, 'wheel')
        expect(I(server, 'GetItemCount', id, 'car_wheel')).toBe(0)
        expect(I(server, 'GetItemCount', id, 'car_battery')).toBe(0)
        local s = veh(server).state.wlVeh
        expect(s.parts.battery).toBe(true); expect(s.parts.wheels).toBe(4)
    end)

    it('finishing too early or from too far does nothing', function()
        local e = veh(server)
        I(server, 'AddItem', id, 'vehicle_repair_kit', 1); server:advance(100)
        server:clientEvent(id, 'wasteland:vehicles:server:act', e.netId, 'repair'); server:advance(100)
        server:clientEvent(id, 'wasteland:vehicles:server:finish'); server:advance(100)
        expect(#server:lines('finished "repair" too early')).toBe(1)
        server.players[id].coords = { x = 1050.0, y = 0.0, z = 30.0 }
        server:clientEvent(id, 'wasteland:vehicles:server:act', e.netId, 'repair'); server:advance(100)
        expect(note(server, id)).toBe('You are too far away.')
        server.players[id].coords = { x = 998.0, y = 0.0, z = 30.0 }
        expect(I(server, 'GetItemCount', id, 'vehicle_repair_kit')).toBe(1)
    end)

    it('damage is not read from a fresh entity (full health) until the client applied the saved state', function()
        server:advance(4100) -- a save: the entity still says 1000
        local row
        for _, r in pairs(server.db.backend.data.wl_vehicles) do if r.x ~= 5000.0 then row = r end end
        expect(row.engine).toBe(500)
    end)

    it('a toolkit repairs engine and body', function()
        act(server, id, 'repair')
        local s = veh(server).state.wlVeh
        expect(s.engine).toBe(900); expect(s.body).toBe(1000)
        expect(I(server, 'GetItemCount', id, 'vehicle_repair_kit')).toBe(0)
    end)

    it('jerry cans: fill at a pump, pour into the tank', function()
        I(server, 'AddItem', id, 'jerry_can', 1); server:advance(100)
        act(server, id, 'refuel')
        expect(note(server, id)).toBe('You need a jerry can with fuel.')
        server:clientEvent(id, 'wasteland:vehicles:server:fillCan', { x = 999.0, y = 1.0, z = 30.0 }); server:advance(1100)
        server:clientEvent(id, 'wasteland:vehicles:server:finish'); server:advance(200)
        expect(I(server, 'FindItems', id, 'jerry_can')[1].metadata.fuel).toBe(20)
        act(server, id, 'refuel')
        expect(veh(server).state.wlVeh.fuel).toBe(22)
        expect(I(server, 'FindItems', id, 'jerry_can')[1].metadata.fuel).toBe(0)
    end)

    it('fuel reports only from the driver, and only down', function()
        local e = veh(server)
        server:clientEvent(id, 'wasteland:vehicles:server:fuel', e.netId, 10.0); server:advance(100)
        expect(veh(server).state.wlVeh.fuel).toBe(22) -- not the driver
        e.driver = server.resources.wasteland_vehicles.env.GetPlayerPed(id)
        server:clientEvent(id, 'wasteland:vehicles:server:fuel', e.netId, 30.0); server:advance(100)
        expect(veh(server).state.wlVeh.fuel).toBe(22) -- cannot go up
        server:clientEvent(id, 'wasteland:vehicles:server:fuel', e.netId, 18.5); server:advance(100)
        expect(veh(server).state.wlVeh.fuel).toBe(18.5)
        e.driver = 0
    end)

    it('a car lock locks it and makes the only key', function()
        I(server, 'AddItem', id, 'vehicle_lock', 1); server:advance(100)
        act(server, id, 'fitLock')
        expect(note(server, id)).toContain('Lock fitted and locked')
        local key = I(server, 'FindItems', id, 'vehicle_key')[1]
        expect(key ~= nil).toBe(true); expect(#key.metadata.code).toBe(8)
        expect(veh(server).doorLock).toBe(2)
        expect(veh(server).state.wlVeh.locked).toBe(true)
        act(server, id, 'toggleLock')
        expect(veh(server).doorLock).toBe(1)
        act(server, id, 'toggleLock')
        expect(veh(server).doorLock).toBe(2)
    end)

    it('without the key: no unlocking, no trunk; a lockpick may fail and break (and makes noise)', function()
        thief = player(server, 'thief', { x = 999.0, y = -1.0, z = 30.0 })
        local heard = 0
        server:on('wasteland:noise', function() heard = heard + 1 end)
        act(server, thief, 'toggleLock')
        expect(note(server, thief)).toBe('You do not have the key.')
        server:clientEvent(thief, 'wasteland:vehicles:server:act', veh(server).netId, 'trunk'); server:advance(200)
        expect(note(server, thief)).toBe('It is locked.')
        I(server, 'AddItem', thief, 'lockpick', 1); server:advance(100)
        act(server, thief, 'pickLock') -- chance 0, breakChance 1
        expect(note(server, thief)).toBe('The lockpick snaps.')
        expect(I(server, 'GetItemCount', thief, 'lockpick')).toBe(0)
        expect(heard).toBe(1)
        expect(veh(server).doorLock).toBe(2)
    end)

    it('the key works for whoever holds it (no owners)', function()
        local key = I(server, 'FindItems', id, 'vehicle_key')[1]
        I(server, 'RemoveItem', id, 'vehicle_key', 1)
        I(server, 'AddItem', thief, 'vehicle_key', 1, key.metadata); server:advance(100)
        act(server, thief, 'toggleLock')
        expect(note(server, thief)).toBe('Unlocked.')
        server:clientEvent(thief, 'wasteland:vehicles:server:act', veh(server).netId, 'trunk'); server:advance(300)
        expect(#events(server, thief, 'wasteland:inventory:client:open')).toBe(1)
    end)

    it('position and damage are saved; the vehicle is put away when nobody is near', function()
        ack(server)
        local e = veh(server)
        e.coords = { x = 1020.0, y = 5.0, z = 30.0 }
        e.engine = 300.0
        server:advance(4100)
        local row
        for _, r in pairs(server.db.backend.data.wl_vehicles) do if r.engine == 300.0 then row = r end end
        expect(row ~= nil).toBe(true); expect(row.x).toBe(1020.0)
        server.players[id].coords = { x = -3000.0, y = 0.0, z = 30.0 }
        server.players[thief].coords = { x = -3000.0, y = 0.0, z = 30.0 }
        server:advance(8000)
        expect(#server:entityList('wlVeh')).toBe(0)
        expect(#server.scriptErrors).toBe(0)
    end)

    it('a destroyed vehicle is gone for good (record and trunk), and a new wreck comes later', function()
        server.players[id].coords = { x = 1010.0, y = 0.0, z = 30.0 }
        server:advance(2100)
        ack(server)
        local e = veh(server)
        e.engine = -4000.0
        server:advance(2100)
        expect(server:export('wasteland_vehicles', 'GetVehicleCount')).toBe(1)
        server.players[id].coords = { x = -3000.0, y = 0.0, z = 30.0 }
        server:advance(61000)
        expect(server:export('wasteland_vehicles', 'GetVehicleCount')).toBe(2)
        expect(#server.scriptErrors).toBe(0)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)

describe('gas pumps', function()
    local cfg = {}
    for k, v in pairs(CFG) do cfg[k] = v end
    cfg['vehicles.lua'] = (CFG['vehicles.lua']:gsub('models = ',
        'pump = { litres = 30, refillLitres = 10, refillMinutes = 1, litresPerSecond = 10, vehicleDistance = 8 }, models = ', 1))
    local server = newServer({ config = cfg })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_vehicles' })
    local id = player(server, 'pumper', { x = 996.0, y = 0.0, z = 30.0 })
    server:advance(2100)
    local PUMP = { x = 997.0, y = 3.0, z = 30.0 }
    local function pumpRefuel()
        server:clientEvent(id, 'wasteland:vehicles:server:pumpRefuel', veh(server).netId, PUMP); server:advance(100)
        local p = last(events(server, id, 'wasteland:vehicles:client:progress'))
        server:advance(math.ceil(p.args[1].seconds * 1000) + 100)
        server:clientEvent(id, 'wasteland:vehicles:server:finish'); server:advance(200)
    end

    it('a vehicle parked at the pump fills from the pump, up to what the pump has', function()
        pumpRefuel() -- tank 2 of 50, pump 30
        expect(veh(server).state.wlVeh.fuel).toBe(32)
        expect(note(server, id)).toContain('the pump has 0 L left')
        expect(server:export('wasteland_vehicles', 'GetPumpFuel', PUMP)).toBe(0)
    end)

    it('a dry pump says when it refills; it refills on its timer', function()
        server:clientEvent(id, 'wasteland:vehicles:server:pumpRefuel', veh(server).netId, PUMP); server:advance(100)
        expect(note(server, id)).toBe('This pump is dry. It refills in about 1 min.')
        I(server, 'AddItem', id, 'jerry_can', 1); server:advance(100)
        server:clientEvent(id, 'wasteland:vehicles:server:fillCan', PUMP); server:advance(100)
        expect(note(server, id)).toContain('This pump is dry')
        server:advance(61000)
        expect(server:export('wasteland_vehicles', 'GetPumpFuel', PUMP)).toBe(10)
        server:clientEvent(id, 'wasteland:vehicles:server:fillCan', PUMP); server:advance(1100)
        server:clientEvent(id, 'wasteland:vehicles:server:finish'); server:advance(200)
        expect(I(server, 'FindItems', id, 'jerry_can')[1].metadata.fuel).toBe(10) -- only what the pump had
        expect(server:export('wasteland_vehicles', 'GetPumpFuel', PUMP)).toBe(0)
    end)

    it('the vehicle must be parked at the pump, the player at the pump', function()
        server:advance(61000)
        server:clientEvent(id, 'wasteland:vehicles:server:pumpRefuel', veh(server).netId, { x = 980.0, y = 0.0, z = 30.0 }); server:advance(100)
        expect(note(server, id)).toBe('You are too far away.')
        server.players[id].coords = { x = 1020.0, y = 0.0, z = 30.0 }
        server:clientEvent(id, 'wasteland:vehicles:server:pumpRefuel', veh(server).netId, { x = 1021.0, y = 0.0, z = 30.0 }); server:advance(100)
        expect(note(server, id)).toBe('Park the vehicle next to the pump.')
        expect(#server.scriptErrors).toBe(0)
        expect(#server:lines('raised:')).toBe(0) -- no handler failed (e.g. a database write outside a thread)
    end)
end)

describe('vehicles are saved at once when the driver gets out or leaves', function()
    it('getting out saves position, damage and fuel straight away', function()
        local server = world()
        local id = player(server, 'quick', { x = 990.0, y = 0.0, z = 30.0 })
        server:advance(2100)
        ack(server)
        local e = veh(server)
        e.driver = server.resources.wasteland_vehicles.env.GetPlayerPed(id)
        server:clientEvent(id, 'wasteland:vehicles:server:fuel', e.netId, 1.5); server:advance(100)
        e.coords = { x = 1040.0, y = 7.0, z = 30.0 }
        e.engine = 410.0
        e.driver = 0 -- got out; the client reports the last fuel
        server:clientEvent(id, 'wasteland:vehicles:server:fuel', e.netId, 1.25); server:advance(200)
        local row
        for _, r in pairs(server.db.backend.data.wl_vehicles) do if r.x == 1040.0 then row = r end end
        expect(row ~= nil).toBe(true); expect(row.engine).toBe(410.0); expect(row.fuel).toBe(1.25)
    end)

    it('a player leaving the server saves the vehicles that are out', function()
        local server = world()
        local id = player(server, 'gone', { x = 990.0, y = 0.0, z = 30.0 })
        server:advance(2100)
        ack(server)
        veh(server).coords = { x = 1060.0, y = 3.0, z = 30.0 }
        server:dropPlayer(id); server:advance(300)
        local found = false
        for _, r in pairs(server.db.backend.data.wl_vehicles) do if r.x == 1060.0 then found = true end end
        expect(found).toBe(true)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('vehicles after a restart', function()
    it('come back as they were left', function()
        local server = world()
        local id = player(server, 'keep', { x = 990.0, y = 0.0, z = 30.0 })
        server:advance(2100)
        ack(server)
        local e = veh(server)
        e.coords = { x = 1003.0, y = 2.0, z = 30.0 }
        e.body = 444.0
        server:stop('wasteland_vehicles'); server:advance(200)
        expect(#server:entityList('wlVeh')).toBe(0)
        server:start('wasteland_vehicles'); server:advance(2500)
        expect(server:export('wasteland_vehicles', 'GetVehicleCount')).toBe(2)
        local back = veh(server)
        expect(back.coords.x).toBe(1003.0)
        expect(back.state.wlVeh.body).toBe(444.0)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
