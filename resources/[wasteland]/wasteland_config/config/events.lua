-- World events (module "events", resource wasteland_events).
--
-- Every intervalMinutes (while at least minPlayers are online) an event
-- starts at one of the points below (not in a camp, minGap metres from
-- other events). Everyone gets a message and a map marker. When a player
-- comes within activateDistance, the zombies and bandits appear. Bandits
-- shoot players and drop a small bag (banditDrop) when killed. Once every
-- bandit and event zombie is dead, the loot can be searched (Left Alt on
-- the loot prop) and the marker turns green; the event ends lootMinutes
-- later, or when its own `minutes` are up.
--
-- Admins: /event                    list types and running events
--         /event helicrash          start one at a random point
--         /event helicrash here     start one 25 m from you
--         /event end                end every event
--
-- Event types:
--   label, weight (how often, compared to the others), minutes (how long)
--   message / clearedMessage: %s is the place
--   lootLabel, lootTable (loot.lua), lootRolls (times the table is rolled)
--   zombies = { count, runnerShare }
--   bandits = { count, accuracy (1-100), armor (0-100), models, weapons (GTA weapon names) }
--   props: { model, x, y (metres from the centre), heading, loot = true (search it), fx (fire / smoke) }
--
-- VERIFY IN-GAME: points and props are picked from the map.
return {
    intervalMinutes = 35,
    maxActive = 1,
    minPlayers = 1,
    minGap = 800,
    activateDistance = 150,
    zombieAreaRadius = 90,     -- event zombies further away than this do not block the loot
    lootReach = 8,
    lootMinutes = 15,

    -- What a bandit drops (each line: chance 0-1).
    banditDrop = {
        { name = 'ammo_9mm', min = 6, max = 15, chance = 0.8 },
        { name = 'cash', min = 10, max = 60, chance = 0.6 },
        { name = 'bandage', min = 1, max = 1, chance = 0.25 },
        { name = 'painkillers', min = 1, max = 1, chance = 0.15 },
    },

    types = {
        helicrash = {
            label = 'Helicopter crash', weight = 3, minutes = 40,
            message = 'A helicopter went down near %s. Survivors report armed bandits closing in.',
            clearedMessage = 'The bandits at the crash near %s are dead. The wreckage can be searched.',
            lootLabel = 'Helicopter wreckage', lootTable = 'helicrash', lootRolls = 3,
            zombies = { count = 16, runnerShare = 0.3 },
            bandits = { count = 4, accuracy = 30, armor = 25,
                models = { 'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_lost_03', 'a_m_m_hillbilly_02' },
                weapons = { 'WEAPON_PISTOL' } },
            props = {
                { model = 'prop_crashed_heli', heading = 40.0, loot = true, fx = 'fire_wrecked_plane_cockpit' },
                { model = 'prop_mil_crate_01', x = 4.0, y = -3.0, heading = 15.0 },
                { model = 'prop_rub_tyre_01', x = -5.0, y = 2.0 },
            },
        },

        convoy = {
            label = 'Ambushed convoy', weight = 2, minutes = 40,
            message = 'A supply convoy was ambushed near %s. The attackers are still there.',
            clearedMessage = 'The ambushers near %s are dead. The convoy cargo can be searched.',
            lootLabel = 'Convoy cargo', lootTable = 'military', lootRolls = 3,
            zombies = { count = 8, runnerShare = 0.25 },
            bandits = { count = 6, accuracy = 35, armor = 40,
                models = { 'g_m_y_salvagoon_01', 'g_m_y_salvagoon_02', 'g_m_y_salvaboss_01', 'g_m_y_lost_01' },
                weapons = { 'WEAPON_PISTOL', 'WEAPON_PISTOL', 'WEAPON_MICROSMG' } },
            props = {
                { model = 'prop_rub_trukwreck_2', heading = 90.0 },
                { model = 'prop_rub_trukwreck_1', x = 12.0, y = 3.0, heading = 70.0 },
                { model = 'prop_mil_crate_02', x = 5.0, y = -4.0, heading = 0.0, loot = true, fx = 'exp_grd_flare' },
                { model = 'prop_mil_crate_01', x = 6.5, y = -5.5, heading = 30.0 },
                { model = 'prop_barrier_work06a', x = -8.0, y = 1.0, heading = 90.0 },
            },
        },

        hideout = {
            label = 'Bandit hideout', weight = 2, minutes = 45,
            message = 'Smoke near %s: a bandit hideout full of stolen supplies.',
            clearedMessage = 'The bandits near %s are dead. Their stash can be searched.',
            lootLabel = 'Bandit stash', lootTable = 'bandit_stash', lootRolls = 2,
            zombies = { count = 4, runnerShare = 0.2 },
            bandits = { count = 7, accuracy = 28, armor = 15,
                models = { 'a_m_m_hillbilly_01', 'a_m_m_hillbilly_02', 'g_m_y_lost_02', 'a_m_y_methhead_01' },
                weapons = { 'WEAPON_PISTOL', 'WEAPON_PISTOL', 'WEAPON_SAWNOFFSHOTGUN' } },
            props = {
                { model = 'prop_skid_tent_01', heading = 0.0 },
                { model = 'prop_skid_tent_01', x = 8.0, y = 2.0, heading = 200.0 },
                { model = 'prop_beach_fire', x = 4.0, y = -5.0 },
                { model = 'prop_box_wood02a', x = -3.0, y = -3.0, heading = 20.0, loot = true },
                { model = 'prop_box_wood05a', x = -4.5, y = -1.5, heading = 70.0 },
            },
        },

        horde = {
            label = 'Horde', weight = 2, minutes = 35,
            message = 'A large horde was seen near %s. Someone left a supply cache there.',
            clearedMessage = 'The horde near %s is gone. The cache can be searched.',
            lootLabel = 'Survivor cache', lootTable = 'survivor_cache', lootRolls = 2,
            zombies = { count = 32, runnerShare = 0.35 },
            bandits = { count = 0 },
            props = {
                { model = 'prop_rub_carwreck_3', heading = 120.0 },
                { model = 'prop_box_ammo04a', x = 3.0, y = 2.0, heading = 0.0, loot = true, fx = 'exp_grd_flare' },
            },
        },
    },

    points = {
        { x = 2400.0, y = 3300.0, z = 47.0, label = 'the Grand Senora desert' },
        { x = 2350.0, y = 4950.0, z = 43.0, label = 'the Grapeseed farms' },
        { x = -800.0, y = 5450.0, z = 34.0, label = 'Paleto Forest' },
        { x = 700.0, y = 2700.0, z = 40.0, label = 'Harmony' },
        { x = 2750.0, y = 1550.0, z = 24.0, label = 'the power station' },
        { x = 1400.0, y = -1900.0, z = 70.0, label = 'the oil fields' },
        { x = -1000.0, y = -2900.0, z = 13.8, label = 'the airport' },
        { x = 230.0, y = -3000.0, z = 6.0, label = 'the docks' },
        { x = 1500.0, y = 3150.0, z = 40.5, label = 'the Sandy Shores airfield' },
        { x = 1300.0, y = 4300.0, z = 36.0, label = 'the Alamo Sea shore' },
    },
}
