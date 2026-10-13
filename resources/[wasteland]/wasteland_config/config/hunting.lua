-- Hunting (module "hunting", resource wasteland_hunting).
--
-- Animals: a few wander near every player (spawned out of sight, removed when
-- nobody is near). Kill one, hold Left Alt on it: Harvest (needs a blade):
-- raw meat, and a pelt from the bigger animals (traders buy pelts). Any
-- animal can be harvested, also ones this module did not spawn.
--
-- Campfire: craft one (scrap metal) and use it from the inventory. Lighting
-- it takes `needs` (a match and firewood). Anyone can cook on it and it
-- keeps you warm; the player who made it can put it out and pick it up to use
-- again. It keeps burning while anyone is within 30 m; left alone for
-- idleMinutes it goes out (the fire pit goes back to its owner).
--
-- Cooking: Left Alt on the fire: Cook. Choose how many; each piece takes
-- `seconds`. Raw meat can be eaten but may make you sick (survival.lua).
return {
    animals = {
        -- model, name, how often (weight), meat { min, max }, pelts
        { model = 'a_c_deer', label = 'Deer', weight = 40, meat = { 2, 4 }, pelt = 1 },
        { model = 'a_c_boar', label = 'Boar', weight = 25, meat = { 2, 3 }, pelt = 1 },
        { model = 'a_c_rabbit_01', label = 'Rabbit', weight = 25, meat = { 1, 1 }, pelt = 0 },
        { model = 'a_c_coyote', label = 'Coyote', weight = 10, meat = { 1, 2 }, pelt = 1 },
    },
    otherAnimalMeat = { 1, 2 },   -- any other animal (a cow, a chicken, a dog...)

    spawn = {
        enabled = true,
        perPlayer = 3,           -- animals near each player
        max = 40,                -- on the whole map
        minDistance = 90,        -- metres from the player (out of sight)
        maxDistance = 200,
        everySeconds = 20,
        despawnDistance = 350,   -- no player this close: removed
        deadMinutes = 10,        -- a carcass lasts this long
    },

    harvest = {
        seconds = 6,
        tools = { 'weapon_knife', 'weapon_switchblade', 'weapon_machete', 'weapon_hatchet', 'weapon_battleaxe' },
        meatItem = 'raw_meat',
        peltItem = 'animal_pelt',
    },

    campfire = {
        item = 'campfire',
        model = 'prop_beach_fire',
        needs = { { name = 'matches', count = 1 }, { name = 'firewood', count = 2 } },
        idleMinutes = 15,       -- nobody within 30 m this long: it goes out
        warmth = 8,             -- degrees of warmth within warmthRadius
        warmthRadius = 5,
    },

    cooking = {
        seconds = 5,            -- per piece
        maxBatch = 50,
        recipes = { raw_meat = 'cooked_meat' },
    },
}
