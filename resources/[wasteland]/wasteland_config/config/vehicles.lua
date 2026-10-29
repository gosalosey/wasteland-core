-- Vehicles: abandoned wrecks around the map that anyone can repair and drive.
-- Nobody owns a vehicle. A car lock (item) locks it and makes a key; with
-- the key you lock, unlock and open the trunk. Without it, a lockpick may
-- open it (and breaks the lock).
--
-- A vehicle needs engine parts, a battery, all its wheels (four, or two on a
-- motorbike), fuel and an engine that is not wrecked. Hold Left Alt on a vehicle to see what you can do.
-- Vehicles stay where they are left (saved); destroyed ones are replaced by
-- new wrecks over time.
--
-- VERIFY IN-GAME: spawn points are picked from the map; a point in the
-- wrong place can be moved or removed here.
return {
    maxVehicles = 80,            -- wrecks in the world (cars and motorbikes); one per spawn point at most
    respawnMinutes = 10,         -- a new wreck every ... while under the limit
    spawnDistance = 250,         -- a vehicle appears when a player is this close
    despawnDistance = 350,       -- ... and is put away when nobody is this close
    despawnAfterSeconds = 30,
    saveSeconds = 30,            -- how often positions and damage are saved

    tankLitres = 50,
    jerryCanLitres = 20,
    fuel = { idlePerMinute = 0.1, per100km = 40 },   -- litres; a 50 L tank lasts ~125 km of driving
    repair = { engine = 400, body = 400 },   -- health a toolkit restores (of 1000)

    seconds = { fullRepair = 15, battery = 6, engine = 10, wheel = 6, refuel = 8, repair = 10, fitLock = 6, toggleLock = 1, removeLock = 6, siphon = 10, fillCan = 8,
        repairPart = 8 },

    -- Parts wear out. Engine parts, battery and each tyre have a condition
    -- (shown on the vehicle HUD). Engine parts or battery at 0%: the engine
    -- will not start. A tyre at 0% (or burst) is flat. Fix one part with a
    -- toolkit ("Repair engine parts", "Recondition battery", "Patch this
    -- tyre": +amount, never above cap), or fit a new part (engine parts, car
    -- battery, wheel) for 100%.
    wear = {
        enginePartsPer100km = 12,   -- % lost per 100 km driven
        batteryPer100km = 6,
        tyresPer100km = 15,
        crashEngineParts = 0.6,     -- engine parts % lost per 1% of engine health a crash takes
    },
    partRepair = { amount = 40, cap = 80 },

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
        condition = { 25, 85 },     -- % condition of each part a wreck has
    },

    -- Trunk size (cells) and how much it holds (kg). Pickups and vans hold more.
    trunk = {
        width = 15, height = 12, maxWeight = 300,
        models = {
            bison = { width = 18, height = 14, maxWeight = 450 },
            sadler = { width = 18, height = 14, maxWeight = 450 },
            rebel = { width = 18, height = 14, maxWeight = 450 },
            ratloader = { width = 18, height = 14, maxWeight = 450 },
            bodhi2 = { width = 18, height = 14, maxWeight = 450 },
            dloader = { width = 18, height = 14, maxWeight = 450 },
            surfer2 = { width = 18, height = 14, maxWeight = 450 },
            rumpo = { width = 18, height = 14, maxWeight = 450 },
            youga = { width = 18, height = 14, maxWeight = 450 },
            -- motorbikes: saddlebags
            sanchez = { width = 6, height = 4, maxWeight = 25 }, sanchez2 = { width = 6, height = 4, maxWeight = 25 },
            manchez = { width = 6, height = 4, maxWeight = 25 }, enduro = { width = 6, height = 4, maxWeight = 25 },
            bf400 = { width = 6, height = 4, maxWeight = 25 }, ratbike = { width = 6, height = 4, maxWeight = 25 },
            daemon = { width = 6, height = 4, maxWeight = 25 }, wolfsbane = { width = 6, height = 4, maxWeight = 25 },
            hexer = { width = 6, height = 4, maxWeight = 25 }, faggio2 = { width = 6, height = 4, maxWeight = 25 },
        },
    },

    -- Rusty and ordinary cars (GTA model names).
    models = { 'emperor2', 'rebel', 'tornado3', 'surfer2', 'ratloader', 'bodhi2', 'regina', 'dloader', 'sadler', 'bison',
        'rumpo', 'youga', 'mesa', 'voodoo2', 'asea', 'ingot', 'primo', 'stanier' },

    -- Motorbikes (two wheels; same parts as a car: engine parts, battery,
    -- wheels, fuel). bikeChance: share of new wrecks that are motorbikes.
    bikes = { 'sanchez', 'sanchez2', 'manchez', 'enduro', 'bf400', 'ratbike', 'daemon', 'wolfsbane', 'hexer', 'faggio2' },
    bikeChance = 0.25,

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

        -- More wrecks (picked from the map, not walked: the spot check moves
        -- a wreck to the nearest clear spot, or uses another point)
        -- Blaine County
        { x = 2400.0, y = 3085.0, z = 48.2, heading = 90.0 },      -- Sandy Shores junkyard
        { x = 2748.0, y = 3470.0, z = 55.7, heading = 245.0 },     -- YouTool, Senora Fwy
        { x = 70.0, y = 3700.0, z = 39.7, heading = 180.0 },       -- Stab City
        { x = 1690.0, y = 4920.0, z = 42.1, heading = 55.0 },      -- Grapeseed main street
        { x = 2440.0, y = 4980.0, z = 46.8, heading = 45.0 },      -- O'Neil ranch
        { x = 1700.0, y = 6415.0, z = 32.7, heading = 155.0 },     -- Great Ocean Hwy gas station, north
        { x = 1208.0, y = 2648.0, z = 37.8, heading = 0.0 },       -- Harmony, Route 68
        { x = -2555.0, y = 2334.0, z = 33.1, heading = 90.0 },     -- Route 1 gas station, Zancudo
        { x = -560.0, y = 5330.0, z = 70.2, heading = 70.0 },      -- Paleto Forest sawmill
        { x = -440.0, y = 6020.0, z = 31.5, heading = 315.0 },     -- Paleto Bay sheriff
        -- Los Santos
        { x = 452.0, y = -1020.0, z = 28.3, heading = 90.0 },      -- Mission Row
        { x = -70.0, y = -1760.0, z = 29.4, heading = 50.0 },      -- Grove Street gas station
        { x = -526.0, y = -1211.0, z = 18.2, heading = 160.0 },    -- Little Seoul gas station
        { x = 818.0, y = -1028.0, z = 26.2, heading = 90.0 },      -- La Mesa gas station
        { x = 1208.0, y = -1402.0, z = 35.2, heading = 135.0 },    -- El Burro Heights gas station
        { x = -362.0, y = -132.0, z = 38.7, heading = 70.0 },      -- Burton, LS Customs
        { x = -1185.0, y = -1490.0, z = 4.4, heading = 35.0 },     -- Vespucci Beach car park
        { x = 1150.0, y = -660.0, z = 57.0, heading = 190.0 },     -- Mirror Park
        { x = 340.0, y = -560.0, z = 28.8, heading = 340.0 },      -- below Pillbox Hill hospital
        { x = -1600.0, y = -1000.0, z = 13.0, heading = 140.0 },   -- Del Perro pier car park
        -- Even more wrecks (picked from the map; the spot check moves them to clear ground)
        -- Blaine County / Route 68
        { x = 49.0, y = 2779.0, z = 58.0, heading = 140.0 },      -- Route 68 gas station, Harmony
        { x = 264.0, y = 2606.0, z = 44.9, heading = 10.0 },      -- Harmony garage
        { x = 1040.0, y = 2671.0, z = 39.5, heading = 0.0 },      -- Route 68 east gas station
        { x = 2540.0, y = 2594.0, z = 37.9, heading = 20.0 },     -- Rex's Diner, Senora
        { x = 1785.0, y = 3331.0, z = 41.4, heading = 300.0 },    -- Sandy Shores airfield road
        { x = 1960.0, y = 3840.0, z = 32.0, heading = 30.0 },     -- Sandy Shores north
        { x = 920.0, y = 3650.0, z = 32.6, heading = 90.0 },      -- Alamo Sea, west Sandy
        { x = 330.0, y = 3410.0, z = 36.0, heading = 80.0 },      -- Sandy Shores, Route 68 west
        { x = 1365.0, y = 4370.0, z = 44.5, heading = 170.0 },    -- Millars Fishery, Alamo Sea
        { x = 1960.0, y = 4640.0, z = 40.7, heading = 290.0 },    -- Grapeseed south
        { x = 2160.0, y = 4770.0, z = 41.0, heading = 110.0 },    -- McKenzie airfield, Grapeseed
        { x = 1850.0, y = 2585.0, z = 45.7, heading = 270.0 },    -- Bolingbroke prison car park
        { x = 1990.0, y = 3050.0, z = 47.0, heading = 330.0 },    -- Yellow Jack Inn
        { x = 2770.0, y = 2800.0, z = 41.4, heading = 120.0 },    -- Davis Quartz quarry
        { x = 2690.0, y = 1680.0, z = 24.6, heading = 90.0 },     -- Palmer-Taylor power station
        { x = -1130.0, y = 2690.0, z = 18.7, heading = 130.0 },   -- Route 68, Lago Zancudo
        { x = -2190.0, y = 4250.0, z = 48.3, heading = 150.0 },   -- Hookies, Great Ocean Hwy
        { x = 3330.0, y = 5160.0, z = 18.3, heading = 200.0 },    -- El Gordo lighthouse
        -- Paleto Bay / north coast
        { x = -680.0, y = 5800.0, z = 17.3, heading = 60.0 },     -- Bayview Lodge
        { x = 1580.0, y = 6450.0, z = 25.0, heading = 150.0 },    -- Up-n-Atom, north coast
        { x = 35.0, y = 6290.0, z = 31.2, heading = 30.0 },       -- Paleto chicken factory
        { x = -15.0, y = 6510.0, z = 31.4, heading = 225.0 },     -- Paleto Bay main street
        -- West coast
        { x = -3150.0, y = 1100.0, z = 20.8, heading = 250.0 },   -- Chumash
        { x = -3040.0, y = 590.0, z = 7.6, heading = 10.0 },      -- Banham Canyon store
        { x = -2970.0, y = 400.0, z = 15.0, heading = 175.0 },    -- Great Ocean Hwy, Ineseno Rd
        { x = -1825.0, y = 790.0, z = 138.2, heading = 130.0 },   -- Richman Glen gas station
        { x = -2096.0, y = -320.0, z = 13.2, heading = 80.0 },    -- Pacific Bluffs gas station
        -- Los Santos
        { x = -1437.0, y = -277.0, z = 46.2, heading = 130.0 },   -- Morningwood gas station
        { x = -319.0, y = -1472.0, z = 30.5, heading = 270.0 },   -- Davis Ave gas station
        { x = 175.0, y = -1562.0, z = 29.3, heading = 45.0 },     -- Davis store
        { x = 621.0, y = 269.0, z = 103.1, heading = 250.0 },     -- Vinewood, Clinton Ave
        { x = 100.0, y = -1075.0, z = 29.3, heading = 340.0 },    -- Pillbox south garage
        { x = -1076.0, y = -850.0, z = 4.9, heading = 40.0 },     -- Vespucci police station
        { x = -1180.0, y = -880.0, z = 13.8, heading = 300.0 },   -- Vespucci Burger Shot
        { x = 960.0, y = -140.0, z = 74.4, heading = 60.0 },      -- Mirror Park clubhouse
        { x = 870.0, y = -2340.0, z = 30.4, heading = 175.0 },    -- Cypress Flats
        { x = 1000.0, y = -2350.0, z = 30.5, heading = 85.0 },    -- Cypress Flats east
        { x = -45.0, y = -2520.0, z = 6.0, heading = 235.0 },     -- Elysian Island docks
        { x = 820.0, y = -2990.0, z = 6.0, heading = 270.0 },     -- Terminal docks
        { x = -1270.0, y = -3380.0, z = 13.9, heading = 330.0 },  -- LS airport
    },
}
