-- wasteland_vehicles (server): wrecks, spawning near players, saving,
-- parts, fuel, repairs, locks and keys, lock picking, trunks, destruction,
-- persistence across restarts, abuse.

local CFG = {
    ['database.lua'] = 'return { connectTimeoutSeconds = 2, queryTimeoutMs = 1000, healthCheckSeconds = 2 }',
    ['players.lua'] = 'return { restoreDelayMs = 200 }',
    ['vehicles.lua'] = [[return {
        maxVehicles = 2, respawnMinutes = 1, spawnDistance = 250, despawnDistance = 350, despawnAfterSeconds = 4, saveSeconds = 4,
        seconds = { battery = 1, engine = 1, wheel = 1, refuel = 1, siphon = 1, repair = 1, fitLock = 1, toggleLock = 1, pickLock = 1, removeLock = 1, fillCan = 1 },
        spotCheck = { enabled = false },
        lockpick = { pins = 4, minSecondsPerPin = 0.35, breakChance = 1, noise = 60 },
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
-- The lockpick minigame: the client gets the game, plays, reports.
local function pick(server, id, success, ms)
    server:clientEvent(id, 'wasteland:vehicles:server:act', veh(server).netId, 'pickLock')
    server:advance(100)
    server:advance(ms or 3000)
    server:clientEvent(id, 'wasteland:vehicles:server:lockpick', success)
    server:advance(200)
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

    it('without the key: no unlocking, no trunk; picking needs a lockpick and the minigame; a failed try may snap it', function()
        thief = player(server, 'thief', { x = 999.0, y = -1.0, z = 30.0 })
        local heard = 0
        server:on('wasteland:noise', function() heard = heard + 1 end)
        act(server, thief, 'toggleLock')
        expect(note(server, thief)).toBe('You do not have the key.')
        server:clientEvent(thief, 'wasteland:vehicles:server:act', veh(server).netId, 'trunk'); server:advance(200)
        expect(note(server, thief)).toBe('It is locked.')
        server:clientEvent(thief, 'wasteland:vehicles:server:act', veh(server).netId, 'pickLock'); server:advance(200)
        expect(note(server, thief)).toBe('You need a lockpick.')
        expect(#events(server, thief, 'wasteland:vehicles:client:lockpick')).toBe(0)
        I(server, 'AddItem', thief, 'lockpick', 2); server:advance(100)
        pick(server, thief, false) -- breakChance 1
        local game = last(events(server, thief, 'wasteland:vehicles:client:lockpick')).args[1]
        expect(game.pins).toBe(4)
        expect(note(server, thief)).toBe('The lockpick snaps.')
        expect(I(server, 'GetItemCount', thief, 'lockpick')).toBe(1)
        expect(heard).toBe(1)
        expect(veh(server).doorLock).toBe(2)
    end)

    it('a minigame result is only taken once, in time, and finish never picks the lock', function()
        -- no minigame running: ignored
        server:clientEvent(thief, 'wasteland:vehicles:server:lockpick', true); server:advance(200)
        expect(veh(server).doorLock).toBe(2)
        -- the progress-bar finish does not count for picking
        server:clientEvent(thief, 'wasteland:vehicles:server:act', veh(server).netId, 'pickLock'); server:advance(2000)
        server:clientEvent(thief, 'wasteland:vehicles:server:finish'); server:advance(200)
        server:clientEvent(thief, 'wasteland:vehicles:server:lockpick', true); server:advance(200)
        expect(veh(server).doorLock).toBe(2)
        -- too fast to be played: rejected
        pick(server, thief, true, 200)
        expect(veh(server).doorLock).toBe(2)
        expect(#server:lines('finished the lockpick minigame too fast')).toBe(1)
        expect(I(server, 'GetItemCount', thief, 'lockpick')).toBe(1)
    end)

    it('only the survivor who fitted the lock can take it off', function()
        act(server, thief, 'removeLock')
        expect(note(server, thief)).toBe('Only the survivor who fitted this lock can take it off.')
        expect(veh(server).state.wlVeh.hasLock).toBe(true)
        expect(type(veh(server).state.wlVeh.lockBy)).toBe('number')
    end)

    it('the key works for whoever holds it (no owners)', function()
        local key = I(server, 'FindItems', id, 'vehicle_key')[1]
        I(server, 'RemoveItem', id, 'vehicle_key', 1)
        I(server, 'AddItem', thief, 'vehicle_key', 1, key.metadata); server:advance(100)
        act(server, thief, 'toggleLock')
        expect(note(server, thief)).toBe('Unlocked.')
        server:clientEvent(thief, 'wasteland:vehicles:server:act', veh(server).netId, 'trunk'); server:advance(300)
        expect(#events(server, thief, 'wasteland:inventory:client:open')).toBe(1)
        -- a big trunk (vehicles.lua trunk: 15 x 12, 300 kg by default)
        local snap = events(server, thief, 'wasteland:inventory:client:sync')
        snap = snap[#snap].args[1]
        local trunk
        for _, i in ipairs(snap.inventories) do if i.label == 'Trunk' then trunk = i end end
        expect(trunk.width .. 'x' .. trunk.height .. ' ' .. trunk.maxWeight).toBe('15x12 300')
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
        'pump = { litres = 30, refillMinutes = 1, litresPerSecond = 10, vehicleDistance = 8 }, models = ', 1))
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

    it('players near a pump see its level and when it is full again', function()
        server:clientEvent(id, 'wasteland:vehicles:server:pumpInfo', PUMP); server:advance(100)
        local info = last(events(server, id, 'wasteland:vehicles:client:pump')).args
        expect(info[1]).toBe('997_3_30')
        expect(info[2].litres).toBe(0); expect(info[2].max).toBe(30); expect(info[2].minutes).toBe(1)
        server:clientEvent(id, 'wasteland:vehicles:server:pumpInfo', { x = 2000.0, y = 0.0, z = 30.0 }); server:advance(100)
        expect(#events(server, id, 'wasteland:vehicles:client:pump')).toBe(2) -- the refuel sent one, the far one is ignored
    end)

    it('a dry pump says when it is full again; then it is full', function()
        server:clientEvent(id, 'wasteland:vehicles:server:pumpRefuel', veh(server).netId, PUMP); server:advance(100)
        expect(note(server, id)).toBe('This pump is dry. It is full again in 1 min.')
        I(server, 'AddItem', id, 'jerry_can', 1); server:advance(100)
        server:clientEvent(id, 'wasteland:vehicles:server:fillCan', PUMP); server:advance(100)
        expect(note(server, id)).toContain('This pump is dry')
        server:advance(61000)
        expect(server:export('wasteland_vehicles', 'GetPumpFuel', PUMP)).toBe(30)
        server:clientEvent(id, 'wasteland:vehicles:server:fillCan', PUMP); server:advance(1100)
        server:clientEvent(id, 'wasteland:vehicles:server:finish'); server:advance(200)
        expect(I(server, 'FindItems', id, 'jerry_can')[1].metadata.fuel).toBe(20)
        expect(server:export('wasteland_vehicles', 'GetPumpFuel', PUMP)).toBe(10)
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

describe('vehicle locks: removing your own lock, winning the lockpick minigame', function()
    local server = world()
    local owner = player(server, 'owner', { x = 1001.0, y = 1.0, z = 30.0 })
    server:advance(2000)
    local other = player(server, 'other', { x = 999.0, y = -1.0, z = 30.0 })

    it('the owner takes the lock off and gets it back; the old key fits nothing', function()
        I(server, 'AddItem', owner, 'vehicle_lock', 1); server:advance(100)
        act(server, owner, 'fitLock')
        expect(veh(server).state.wlVeh.locked).toBe(true)
        local row
        for _, r in pairs(server.db.backend.data.wl_vehicles) do if r.lock_code then row = r end end
        expect(row.lock_owner ~= nil).toBe(true)
        -- someone else holding the key still cannot remove it
        local key = I(server, 'FindItems', owner, 'vehicle_key')[1]
        I(server, 'AddItem', other, 'vehicle_key', 1, key.metadata); server:advance(100)
        act(server, other, 'removeLock')
        expect(note(server, other)).toBe('Only the survivor who fitted this lock can take it off.')
        act(server, owner, 'removeLock')
        expect(note(server, owner)).toContain('You took the lock off')
        expect(I(server, 'GetItemCount', owner, 'vehicle_lock')).toBe(1)
        expect(veh(server).state.wlVeh.hasLock).toBe(false)
        expect(veh(server).doorLock).toBe(1)
        act(server, owner, 'toggleLock')
        expect(note(server, owner)).toBe('It has no lock.')
        server:advance(300)
        for _, r in pairs(server.db.backend.data.wl_vehicles) do expect(r.lock_code == nil and r.lock_owner == nil).toBe(true) end
    end)

    it('a thief who sets every pin opens the lock (and keeps the pick)', function()
        act(server, owner, 'fitLock') -- the lock is back in the owner's pockets
        expect(veh(server).state.wlVeh.locked).toBe(true)
        I(server, 'RemoveItem', other, 'vehicle_key', 1)
        I(server, 'AddItem', other, 'lockpick', 1); server:advance(100)
        pick(server, other, true, 2000)
        expect(note(server, other)).toBe('The lock breaks open.')
        expect(veh(server).doorLock).toBe(1)
        expect(veh(server).state.wlVeh.hasLock).toBe(false)
        expect(I(server, 'GetItemCount', other, 'lockpick')).toBe(1)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)

describe('siphoning fuel', function()
    local server = world()
    local id = player(server, 'siphoner', { x = 1001.0, y = 1.0, z = 30.0 })
    server:advance(2000)

    it('needs fuel in the tank, a siphon hose and a jerry can with room', function()
        local fuel = veh(server).state.wlVeh.fuel
        expect(fuel > 0).toBe(true)
        act(server, id, 'siphon')
        expect(note(server, id)).toBe('You need a siphon hose.')
        I(server, 'AddItem', id, 'siphon_hose', 1); server:advance(100)
        act(server, id, 'siphon')
        expect(note(server, id)).toBe('You need a jerry can that is not full.')
        I(server, 'AddItem', id, 'jerry_can', 1, { fuel = 20 }); server:advance(100)
        act(server, id, 'siphon')
        expect(note(server, id)).toBe('You need a jerry can that is not full.')
    end)

    it('moves the fuel from the tank into the can (the hose is kept); an empty tank gives nothing', function()
        local fuel = veh(server).state.wlVeh.fuel
        I(server, 'AddItem', id, 'jerry_can', 1, { fuel = 0 }); server:advance(100)
        act(server, id, 'siphon')
        expect(note(server, id)).toContain('Siphoned ' .. string.format('%.0f', fuel) .. ' L')
        expect(veh(server).state.wlVeh.fuel).toBe(0)
        local total = 0
        for _, c in ipairs(I(server, 'FindItems', id, 'jerry_can')) do total = total + (c.metadata.fuel or 0) end
        expect(total).toBe(20 + fuel)
        expect(I(server, 'GetItemCount', id, 'siphon_hose')).toBe(1)
        act(server, id, 'siphon')
        expect(note(server, id)).toBe('The tank is empty.')
        server:advance(300)
        local row
        for _, r in pairs(server.db.backend.data.wl_vehicles) do if r.fuel == 0 then row = r end end
        expect(row ~= nil).toBe(true)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)

describe('clear spots for wrecks', function()
    local CFG2 = {}
    for k, v in pairs(CFG) do CFG2[k] = v end
    CFG2['vehicles.lua'] = CFG['vehicles.lua']:gsub('spotCheck = { enabled = false }', 'spotCheck = { enabled = true, radius = 12 }')
    local server = newServer({ config = CFG2 })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_vehicles' })
    local id = player(server, 'scout', { x = 1001.0, y = 1.0, z = 30.0 })
    local function asked() return events(server, id, 'wasteland:vehicles:client:checkSpot') end

    it('asks the nearest player before the wreck first appears', function()
        server:advance(2500)
        expect(#server:entityList('wlVeh')).toBe(0)
        expect(#asked()).toBe(1)
        local a = last(asked()).args
        expect(a[2].x).toBe(1000.0)
    end)

    it('moves it to the clear spot the client found (not too far), then spawns and remembers', function()
        local a = last(asked()).args
        server:clientEvent(id, 'wasteland:vehicles:server:spot', a[1], { x = 1030.0, y = 0.0, z = 30.0 })
        server:advance(100)
        expect(#server:lines('suggested a spot too far')).toBe(1)
        expect(#server:entityList('wlVeh')).toBe(0)
        server:advance(9000) -- unanswered: asked again or spawned in place after the wait
        local again = last(asked()).args
        server:clientEvent(id, 'wasteland:vehicles:server:spot', again[1], { x = 1005.0, y = 2.0, z = 30.5, heading = 90.0 })
        server:advance(2500)
        local e = veh(server)
        expect(e ~= nil).toBe(true)
        expect(e.coords.x).toBe(1005.0)
        local row = server.db.backend.data.wl_vehicles[again[1]]
        expect(row.x).toBe(1005.0); expect(row.spot_checked).toBe(1)
    end)

    it('a vehicle nobody can check still appears after a short wait', function()
        local before = #server:entityList('wlVeh')
        server.players[id].coords = { x = 5001.0, y = 1.0, z = 30.0 }
        server:advance(2500)
        expect(#server:entityList('wlVeh')).toBe(before) -- waiting for the answer
        server:advance(10000)
        expect(#server:entityList('wlVeh') >= before).toBe(true)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)


describe('vehicle parts: condition, repairing one part, replacing worn parts, wear', function()
    local cfg = {}
    for k, v in pairs(CFG) do cfg[k] = v end
    cfg['vehicles.lua'] = CFG['vehicles.lua']:gsub('wreck = %b{}', [[wreck = { batteryMissing = 0, engineMissing = 0, wheelsMissingChance = 0, wheelsMissingMax = 1,
            fuel = { 20, 20 }, engine = { 900, 900 }, body = { 900, 900 }, condition = { 50, 50 } }]], 1)
        :gsub('removeLock = 1, fillCan = 1 }', 'removeLock = 1, fillCan = 1, repairPart = 1 }', 1)
    local server = newServer({ config = cfg })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_vehicles' })
    local id = player(server, 'mechanic', { x = 998.0, y = 0.0, z = 30.0 })
    server:advance(2100)
    local function part(action, which)
        local e = veh(server)
        server:clientEvent(id, 'wasteland:vehicles:server:act', e.netId, action, which)
        server:advance(100); server:advance(1000)
        server:clientEvent(id, 'wasteland:vehicles:server:finish'); server:advance(200)
    end
    local function cond() return veh(server).state.wlVeh.parts.cond end

    it('every part has a condition (a wreck: 50%)', function()
        local c = cond()
        expect(c.engine).toBe(50); expect(c.battery).toBe(50)
        expect(c.tyres[1]).toBe(50); expect(c.tyres[4]).toBe(50)
    end)

    it('a toolkit repairs one tyre only, up to 80%', function()
        I(server, 'AddItem', id, 'vehicle_repair_kit', 1); server:advance(100)
        part('repairPart', 'tyre2')
        expect(cond().tyres[2]).toBe(80); expect(cond().tyres[1]).toBe(50)
        expect(note(server, id)).toBe('Patched the front right tyre: 80%.')
        server:clientEvent(id, 'wasteland:vehicles:server:act', veh(server).netId, 'repairPart', 'tyre2'); server:advance(100)
        expect(note(server, id)).toBe('A toolkit cannot do better than 80%. Fit a new one.')
        expect(I(server, 'GetItemCount', id, 'vehicle_repair_kit')).toBe(0)
    end)

    it('a new battery replaces the worn one (100%)', function()
        I(server, 'AddItem', id, 'car_battery', 1); server:advance(100)
        part('battery')
        expect(cond().battery).toBe(100)
        expect(note(server, id)).toBe('New battery fitted (100%).')
        expect(I(server, 'GetItemCount', id, 'car_battery')).toBe(0)
    end)

    it('a new wheel replaces the tyre you work on', function()
        I(server, 'AddItem', id, 'car_wheel', 1); server:advance(100)
        part('wheel', 'tyre3')
        expect(cond().tyres[3]).toBe(100); expect(cond().tyres[4]).toBe(50)
    end)

    it('driving wears parts; a burst tyre is flat (0%); only the driver reports', function()
        local e = veh(server)
        server:clientEvent(id, 'wasteland:vehicles:server:wear', e.netId, 1.0, { false, false, false, true }); server:advance(100)
        expect(cond().tyres[4]).toBe(50) -- not the driver
        e.driver = server.resources.wasteland_vehicles.env.GetPlayerPed(id)
        server:advance(10000)
        server:clientEvent(id, 'wasteland:vehicles:server:wear', e.netId, 1.0, { false, false, false, true }); server:advance(100)
        local c = cond()
        expect(c.tyres[4]).toBe(0)
        expect(c.engine < 50).toBe(true); expect(c.tyres[1] < 50).toBe(true)
        e.driver = 0
    end)

    it('conditions are saved with the vehicle', function()
        server:advance(4100)
        local row
        for _, r in pairs(server.db.backend.data.wl_vehicles) do if r.x ~= 5000.0 then row = r end end
        expect(row.parts:find('"c":[', 1, true) ~= nil).toBe(true)
        expect(#server:lines('raised:')).toBe(0)
    end)
end)

describe('locking from the inside (L)', function()
    local server = world()
    local id = player(server, 'inside', { x = 1001.0, y = 1.0, z = 30.0 })
    server:advance(2000)
    local function lockInside(who) server:clientEvent(who, 'wasteland:vehicles:server:insideLock', veh(server).netId); server:advance(100) end
    local function getIn(who)
        local e = veh(server)
        server.players[who].vehicle = e.handle
        e.driver = server.resources.wasteland_vehicles.env.GetPlayerPed(who)
    end
    local function getOut(who)
        local e = veh(server)
        server.players[who].vehicle = nil
        e.driver = 0
        server:clientEvent(who, 'wasteland:vehicles:server:leftVehicle', e.netId); server:advance(2000)
    end

    it('only someone sitting in the vehicle can lock it this way', function()
        lockInside(id)
        expect(veh(server).state.wlVeh.locked).toBe(false)
        getIn(id)
        lockInside(id)
        expect(veh(server).state.wlVeh.locked).toBe(true)
        expect(note(server, id)).toBe('Doors locked.')
        lockInside(id)
        expect(veh(server).state.wlVeh.locked).toBe(false)
        expect(note(server, id)).toBe('Doors unlocked.')
    end)

    it('with no lock fitted it opens again once everyone is out', function()
        server:advance(3000)   -- L is rate limited (a few presses a second)
        lockInside(id)
        expect(veh(server).state.wlVeh.locked).toBe(true)
        getOut(id)
        expect(veh(server).state.wlVeh.locked).toBe(false)
    end)

    it('with a lock fitted it stays locked (the key opens it)', function()
        I(server, 'AddItem', id, 'vehicle_lock', 1); server:advance(100)
        act(server, id, 'fitLock')
        act(server, id, 'toggleLock')
        expect(veh(server).state.wlVeh.locked).toBe(false)
        getIn(id)
        lockInside(id)
        expect(veh(server).state.wlVeh.locked).toBe(true)
        getOut(id)
        expect(veh(server).state.wlVeh.locked).toBe(true)
        expect(#server.scriptErrors).toBe(0)
    end)
end)

describe('motorbikes', function()
    local cfg = {}
    for k, v in pairs(CFG) do cfg[k] = v end
    cfg['vehicles.lua'] = (CFG['vehicles.lua']:gsub("models = { 'rebel' },", "models = { 'rebel' }, bikes = { 'sanchez' }, bikeChance = 1,\n        trunk = { width = 15, height = 12, maxWeight = 300, models = { sanchez = { width = 6, height = 4, maxWeight = 25 } } },"))
    local server = newServer({ config = cfg })
    boot(server, { 'wasteland_players', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_vehicles' })
    local id = player(server, 'rider', { x = 1001.0, y = 1.0, z = 30.0 })
    server:advance(2000)

    it('a new wreck can be a motorbike, with two wheels at most', function()
        local s = veh(server).state.wlVeh
        expect(s.wheelsMax).toBe(2)
        expect(s.parts.wheels).toBe(1)   -- the test wreck misses a wheel
    end)

    it('mounting the missing wheel makes it whole: 2 of 2', function()
        I(server, 'AddItem', id, 'car_wheel', 1); server:advance(100)   -- a wheel is big: one at a time
        act(server, id, 'wheel')
        expect(note(server, id)).toBe('Wheel mounted (2 of 2).')
        expect(veh(server).state.wlVeh.parts.wheels).toBe(2)
        I(server, 'AddItem', id, 'car_wheel', 1); server:advance(100)
        act(server, id, 'wheel')                                         -- the worn front tyre is replaced
        expect(note(server, id)).toBe('New front wheel fitted (100%).')
        I(server, 'AddItem', id, 'car_wheel', 1); server:advance(100)
        act(server, id, 'wheel')
        expect(note(server, id)).toBe('Both wheels are on.')
        expect(I(server, 'GetItemCount', id, 'car_wheel')).toBe(1)
        expect(#server.scriptErrors).toBe(0)
    end)
end)
