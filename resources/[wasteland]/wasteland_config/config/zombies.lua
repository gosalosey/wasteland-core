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

    -- Kinds of zombies. Any name; 'walker' is required (the usual zombie,
    -- and what is left after every other kind's chance).
    --   chance / nightChance  percent of new zombies that are this kind (day / night)
    --   speed                 1 = walk, 2.6 = run
    --   damage                health points per hit (players have 100)
    --   infectionChance, bleedingChance   per hit (0 - 1)
    --   infection             infection points added when a hit infects (0 - 100)
    --   shamble = true        stagger like a drunk when walking
    --   models = { ... }      models for this kind only (else the list below)
    kinds = {
        walker = { speed = 1.15, damage = { 7, 11 }, infectionChance = 0.25, infection = { 6, 12 }, bleedingChance = 0.15,
            shamble = true },
        runner = { speed = 2.7, chance = 25, nightChance = 45, damage = { 6, 9 }, infectionChance = 0.2, infection = { 5, 10 },
            bleedingChance = 0.2 },

        -- An example of your own kind (remove the -- to use it): a slow,
        -- hard-hitting brute with its own models (custom models: put them in
        -- resources/[wasteland]/wasteland_zombiemodels/stream).
        -- brute = { speed = 1.3, chance = 5, nightChance = 8, damage = { 15, 22 }, infectionChance = 0.3,
        --     infection = { 8, 14 }, bleedingChance = 0.4, models = { 'u_m_y_zombie_01' } },
    },

    -- What zombies look like (ambient GTA models; the first is GTA's zombie).
    models = {
        'u_m_y_zombie_01', 'a_m_m_skidrow_01', 'a_m_y_methhead_01', 'a_f_m_skidrow_01', 'a_m_m_tramp_01',
        'a_m_o_tramp_01', 'a_f_m_tramp_01', 'a_m_m_hillbilly_01', 'a_m_y_salton_01', 'a_f_y_rurmeth_01',
        'a_m_m_rurmeth_01', 'a_m_m_salton_02', 'a_m_y_hippy_01', 'a_f_m_fatcult_01',
    },

    -- How zombies notice players (metres). Sight needs a clear line.
    detection = {
        sightDay = 70, sightNight = 40,
        hearSprint = 45, hearWalk = 18, hearCrouch = 6,
        loseSeconds = 25,          -- give up a target not seen or heard this long
        alertRadius = 25,          -- a zombie that spots a player brings the others this close (0 = off)
    },

    -- A zombie this close (range) starts a swing; windupMs later the swing
    -- lands and hits only if you are still within hitReach, in front of it,
    -- with nothing in between. Step back in time and it misses.
    attack = { range = 2.2, hitReach = 1.7, windupMs = 450, cooldownMs = 1100 },

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
