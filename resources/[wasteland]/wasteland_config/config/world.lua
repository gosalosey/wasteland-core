-- Wasteland Core :: world (module "world", resource wasteland_world)
-- One clock and one weather for everyone, an empty world and silence.
return {
    -- GTA's idle camera starts panning around when you stand still for a
    -- while. Off (false) keeps your camera where you left it.
    idleCamera = false,

    -- What lives in the world besides players (false = removed).
    -- Zombies and other scripted characters are not affected.
    population = {
        peds = false,            -- pedestrians
        vehicles = false,        -- traffic, trains, boats, planes
        parkedVehicles = false,  -- parked cars
        police = false,          -- police, dispatch and wanted levels
    },

    -- Background sound (false = off). Gunshots, footsteps, doors and your
    -- own vehicle are never affected.
    audio = {
        ambience = false,  -- city and nature background
        music = false,     -- radio, score and flight music, music from buildings
        scanner = false,   -- police scanner and distant sirens
        -- More static emitters (music sources) to switch off, by name.
        emitters = {},
    },

    time = {
        startHour = 12,     -- game hour when the server starts
        msPerMinute = 2000, -- real milliseconds per game minute (2000 = 48-minute day)
        frozen = false,     -- true = time stands still
    },

    weather = {
        start = 'CLEAR',
        dynamic = true,        -- change by itself
        changeMinutes = 30,    -- real minutes between changes
        transitionSeconds = 30,
        -- Chance weights (higher = more often). Possible: EXTRASUNNY CLEAR NEUTRAL SMOG
        -- FOGGY OVERCAST CLOUDS CLEARING RAIN THUNDER SNOW BLIZZARD SNOWLIGHT XMAS HALLOWEEN
        pool = { CLEAR = 30, EXTRASUNNY = 15, CLOUDS = 20, OVERCAST = 15, FOGGY = 8, RAIN = 8, THUNDER = 4 },
    },
}
