-- Zombies: how many, what kinds, how they find you, what a hit does.
return {
    population = {
        perPlayer = 8,             -- zombies kept around each player (day)
        nightMultiplier = 1.5,     -- more at night (21:00 - 06:00)
        maxTotal = 60,             -- in the whole world (server and client load)
        spawnMin = 70,             -- metres from the player: never closer
        spawnMax = 140,            -- ... and never further
        spawnBatch = 3,            -- at most this many per player per round
        spawnIntervalSeconds = 6,  -- how often each player is topped up
        despawnDistance = 230,     -- removed when no player is this close ...
        despawnAfterSeconds = 20,  -- ... for this long
        corpseSeconds = 90,        -- dead zombies lie this long
    },

    -- chance / nightChance: percent of new zombies that are runners.
    -- damage: health points per hit (players have 100).
    -- infectionChance, bleedingChance: per hit (0 - 1).
    -- infection: infection points added when a hit infects (infection 0 - 100).
    kinds = {
        walker = { speed = 1.0, damage = { 6, 10 }, infectionChance = 0.25, infection = { 6, 12 }, bleedingChance = 0.15 },
        runner = { speed = 2.6, chance = 15, nightChance = 30, damage = { 5, 8 }, infectionChance = 0.2, infection = { 5, 10 },
            bleedingChance = 0.2 },
    },

    -- What zombies look like (ambient GTA models; the first is GTA's zombie).
    models = {
        'u_m_y_zombie_01', 'a_m_m_skidrow_01', 'a_m_y_methhead_01', 'a_f_m_skidrow_01', 'a_m_m_tramp_01',
        'a_m_o_tramp_01', 'a_f_m_tramp_01', 'a_m_m_hillbilly_01', 'a_m_y_salton_01', 'a_f_y_rurmeth_01',
        'a_m_m_rurmeth_01', 'a_m_m_salton_02', 'a_m_y_hippy_01', 'a_f_m_fatcult_01',
    },

    -- How zombies notice players (metres). Sight needs a clear line.
    detection = {
        sightDay = 35, sightNight = 18,
        hearSprint = 25, hearWalk = 9, hearCrouch = 3,
        loseSeconds = 10,          -- give up a target not seen or heard this long
    },

    attack = { range = 1.7, cooldownMs = 1500 },

    -- Gunshots (and other weapon noise, weapons.lua `noise`): zombies within
    -- the noise radius walk to it.
    noise = { investigateSeconds = 40 },

    -- Dead zombies may leave a small bag of loot.
    loot = {
        chance = 0.25,
        lifetimeMinutes = 15,
        items = {
            { name = 'cash', min = 5, max = 40, weight = 30 },
            { name = 'ammo_9mm', min = 3, max = 10, weight = 15 },
            { name = 'ammo_12g', min = 2, max = 5, weight = 8 },
            { name = 'bandage', min = 1, max = 2, weight = 15 },
            { name = 'canned_beans', min = 1, max = 1, weight = 12 },
            { name = 'soda_can', min = 1, max = 1, weight = 10 },
            { name = 'scrap_metal', min = 1, max = 2, weight = 10 },
        },
    },

    adminCommand = 'zombies',      -- /zombies count | clear | spawn <n>
}
