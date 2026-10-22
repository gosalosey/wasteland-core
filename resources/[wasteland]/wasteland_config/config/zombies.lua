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
        'a_f_y_juggalo_01', 'a_m_m_eastsa_02', 'a_m_m_farmer_01', 'a_m_m_fatlatin_01', 'a_m_m_hillbilly_01',
        'a_m_m_malibu_01', 'a_m_m_mexlabor_01', 'a_m_m_og_boss_01', 'a_m_m_polynesian_01', 'a_m_m_rurmeth_01',
        'a_m_m_salton_02', 'a_m_m_skater_01', 'a_m_m_skidrow_01', 'a_m_m_soucent_04', 'a_m_o_acult_02',
        'a_m_y_genstreet_01', 'a_m_y_genstreet_02', 'a_m_y_methhead_01', 'a_m_y_salton_01', 'a_m_m_tennis_01',
        'a_m_y_stlat_01', 's_m_y_cop_01', 's_m_y_prismuscl_01', 's_m_y_prisoner_01',
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

    -- Melee hit reactions: every melee hit stuns a zombie for stunMs (it
    -- stops, and the swing it was winding up never lands); a hit may knock it
    -- off balance for ragdollMs - more often with heavy weapons.
    hitReaction = {
        enabled = true,
        stunMs = 600,
        staggerChance = 0.15,       -- fists, knives
        heavyStaggerChance = 0.5,   -- the heavy weapons below
        ragdollMs = 900,
        heavyWeapons = { 'WEAPON_BAT', 'WEAPON_HATCHET', 'WEAPON_BATTLEAXE', 'WEAPON_HAMMER', 'WEAPON_WRENCH', 'WEAPON_CROWBAR', 'WEAPON_MACHETE' },
    },

    -- Zombie sounds: groans, swings, being hurt, dying, screams. The sound
    -- files are in their own resource (pack = wasteland_zombiesounds; ensure
    -- it before wasteland_zombies). Without it zombies are silent as before.
    -- Every setting and the file lists: wasteland_zombies/client/sounds.lua.
    sounds = {
        enabled = true,
        pack = 'wasteland_zombiesounds',
        volume = 0.7,          -- 0 - 1, right next to you
        range = 35,            -- metres: heard no further
        callRange = 90,        -- screamer / howler calls
        idleEvery = { 7, 18 }, -- seconds between groans (calm)
        chaseEvery = { 3, 7 }, -- ... (coming at you)
    },

    -- Zombie AI upgrade: personalities, better senses and memory, special
    -- infected, horde responses, day/night behaviour. enabled = false puts
    -- every zombie back to the original behaviour. Anything left out here
    -- uses its default (all settings, explained: wasteland_zombies/shared/ai.lua).
    ai = {
        enabled = true,

        -- Share of zombies with each personality (weight by day, nightWeight
        -- at dusk and night). 0 = none.
        --   wanderer  roams, investigates noises, chases what it finds
        --   stalker   follows you from a distance, circles round, charges later
        --   ambusher  stands still and jumps anyone who comes close
        --   sprinter  slow until it sees you, then bursts of sprinting
        --   sleeper   lies on the ground until you come close or make noise
        --   pack      pack hunters surround you from different sides
        personalities = {
            wanderer = { weight = 45, nightWeight = 35 },
            stalker = { weight = 10, nightWeight = 20 },
            ambusher = { weight = 10, nightWeight = 10 },
            sprinter = { weight = 10, nightWeight = 15 },
            sleeper = { weight = 10, nightWeight = 5 },
            pack = { weight = 15, nightWeight = 15 },
        },

        -- Special infected (percent of zombies each; 0 = off). They keep the
        -- zombie's normal model. Bosses (juggernaut, alpha, butcher,
        -- nightterror) are off until you give them a chance.
        specials = {
            enabled = true,
            screamer = { chance = 3 },     -- screams when it spots you: brings the others
            brute = { chance = 3 },        -- 3x health, slower, slow heavy swings
            howler = { chance = 1 },       -- a long call that brings a horde from far away
            spitter = { chance = 2 },      -- retches, then spits at you from up to 14 m
            hunter = { chance = 2 },       -- stalks players who are on their own
            crawler = { chance = 0 },
            juggernaut = { chance = 0 }, alpha = { chance = 0 }, butcher = { chance = 0 }, nightterror = { chance = 0 },
        },

        -- How many zombies answer one noise (the nearest), and repeated
        -- gunfire in one area reaching further (up to 2.5x).
        horde = { enabled = true, maxResponders = 15, repeatMax = 2.5 },

        -- Zombies break through base walls, doors and gates to reach a player
        -- hiding behind them (damage per material: basebuilding.lua raid.zombies).
        barricades = { enabled = true, giveUpSeconds = 60 },

        -- Ambushers near these points wait there: { x = 0.0, y = 0.0, z = 0.0, radius = 40 }
        ambushPoints = {},
        -- A noise near a building sends zombies to its way in first:
        -- { x = 0.0, y = 0.0, z = 0.0, radius = 15, entry = { x = 0.0, y = 0.0, z = 0.0 } }
        entryPoints = {},
    },
}
