-- Vehicles: abandoned wrecks around the map that anyone can repair and drive.
-- Nobody owns a vehicle. A car lock (item) locks it and makes a key; with
-- the key you lock, unlock and open the trunk. Without it, a lockpick may
-- open it (and breaks the lock).
--
-- A vehicle needs engine parts, a battery, four wheels, fuel and an engine
-- that is not wrecked. Hold Left Alt on a vehicle to see what you can do.
-- Vehicles stay where they are left (saved); destroyed ones are replaced by
-- new wrecks over time.
--
-- VERIFY IN-GAME: spawn points are picked from the map; a point in the
-- wrong place can be moved or removed here.
return {
    maxVehicles = 30,            -- wrecks in the world
    respawnMinutes = 20,         -- a new wreck every ... while under the limit
    spawnDistance = 250,         -- a vehicle appears when a player is this close
    despawnDistance = 350,       -- ... and is put away when nobody is this close
    despawnAfterSeconds = 30,
    saveSeconds = 30,            -- how often positions and damage are saved

    tankLitres = 50,
    jerryCanLitres = 20,
    fuel = { idlePerMinute = 0.06, per100km = 14 },
    repair = { engine = 400, body = 400 },   -- health a toolkit restores (of 1000)

    seconds = { battery = 6, engine = 10, wheel = 6, refuel = 8, repair = 10, fitLock = 6, toggleLock = 1, removeLock = 6, siphon = 10, fillCan = 8 },

    -- Before a wreck first appears, the nearest player's game checks its spot
    -- for props, walls, other vehicles and steep ground and moves it to the
    -- nearest clear spot within `radius` metres (a new wreck with no room
    -- goes to another spawn point). Checked once per vehicle.
    spotCheck = { enabled = true, radius = 12, clearance = 3.2 },

    -- Picking a lock needs a lockpick and a minigame: a pick turns around
    -- the lock; press E (or Space / click) while it is in the bright zone
    -- to set a pin. Set every pin to open it; one miss and the try fails.
    lockpick = {
        pins = 4,             -- pins to set
        zoneDegrees = 32,     -- width of the bright zone (smaller = harder)
        speed = 150,          -- how fast the pick turns at first (degrees a second)
        speedStep = 35,       -- and how much faster for every pin
        breakChance = 0.5,    -- chance the lockpick snaps on a failed try
        noise = 60,           -- metres zombies hear the attempt
    },

    wreck = {
        batteryMissing = 0.6, engineMissing = 0.5,
        wheelsMissingChance = 0.4, wheelsMissingMax = 2,
        fuel = { 0, 8 }, engine = { 250, 700 }, body = { 300, 800 },
    },

    -- Rusty and ordinary cars (GTA model names).
    models = { 'emperor2', 'rebel', 'tornado3', 'surfer2', 'ratloader', 'bodhi2', 'regina', 'dloader', 'sadler', 'bison',
        'rumpo', 'youga', 'mesa', 'voodoo2', 'asea', 'ingot', 'primo', 'stanier' },

    -- Gas pumps have limited fuel, shared by everyone. Standing next to one
    -- shows how much it has and when it is full again. Park next to one and
    -- hold Left Alt on the pump: "Refuel vehicle" (no jerry can needed) or
    -- "Fill jerry can".
    pump = {
        litres = 80,              -- fuel in a full pump
        refillMinutes = 120,      -- full again 2 hours (real time) after fuel was first taken
        litresPerSecond = 4,      -- how fast it pours into a vehicle
        vehicleDistance = 8,      -- how close (m) the vehicle must be parked
    },

    -- Gas pump models (GTA names).
    pumps = { 'prop_gas_pump_1a', 'prop_gas_pump_1b', 'prop_gas_pump_1c', 'prop_gas_pump_1d', 'prop_gas_pump_old2',
        'prop_gas_pump_old3', 'prop_vintage_pump' },

    -- Where wrecks appear: { x, y, z, heading }.
    spawnPoints = {
        -- Sandy Shores / Grapeseed / Route 68
        { x = 1960.0, y = 3742.0, z = 32.3, heading = 300.0 },
        { x = 1702.0, y = 3598.0, z = 35.4, heading = 210.0 },
        { x = 1393.0, y = 3604.0, z = 34.9, heading = 200.0 },
        { x = 2003.0, y = 3779.0, z = 32.2, heading = 120.0 },
        { x = 1697.0, y = 4806.0, z = 42.0, heading = 90.0 },
        { x = 1180.0, y = 2691.0, z = 37.9, heading = 180.0 },
        { x = 547.0, y = 2671.0, z = 42.2, heading = 10.0 },
        { x = 1737.0, y = 3290.0, z = 41.1, heading = 195.0 },
        -- Paleto Bay
        { x = -153.0, y = 6302.0, z = 31.4, heading = 315.0 },
        { x = -332.0, y = 6150.0, z = 32.3, heading = 45.0 },
        { x = 170.0, y = 6604.0, z = 31.8, heading = 180.0 },
        { x = -94.0, y = 6400.0, z = 31.5, heading = 45.0 },
        -- Los Santos
        { x = 228.0, y = -787.0, z = 30.7, heading = 160.0 },
        { x = -341.0, y = -756.0, z = 33.9, heading = 90.0 },
        { x = 405.0, y = -1001.0, z = 29.3, heading = 0.0 },
        { x = -45.0, y = -1098.0, z = 26.4, heading = 70.0 },
        { x = 1155.0, y = -331.0, z = 69.0, heading = 100.0 },
        { x = -706.0, y = -918.0, z = 19.0, heading = 90.0 },
        { x = 290.0, y = -1265.0, z = 29.4, heading = 90.0 },
        { x = -1050.0, y = -2650.0, z = 13.8, heading = 330.0 },
        -- Senora Freeway / east
        { x = 2581.0, y = 362.0, z = 108.5, heading = 0.0 },
        { x = 2680.0, y = 3280.0, z = 55.2, heading = 330.0 },
    },
}
