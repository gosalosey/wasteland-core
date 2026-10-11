-- Looting: searchable world props (every copy on the map) and zombie bodies.
-- Containers are shared: what one player takes is gone for everyone until
-- the container refills (only once it is empty, after refillMinutes).
-- Searching takes searchSeconds (moving cancels); then the container opens
-- next to the inventory.
--
-- Prop names are GTA model names; VERIFY IN-GAME that each one exists on
-- the map you play (a missing name simply never matches).
return {
    containers = {
        dumpster = { label = 'Dumpster', table = 'trash', searchSeconds = 5, refillMinutes = 45, grid = { 6, 5 }, anim = 'bin',
            models = { 'prop_dumpster_01a', 'prop_dumpster_02a', 'prop_dumpster_02b', 'prop_dumpster_3a', 'prop_dumpster_4a',
                'prop_dumpster_4b' } },
        bin = { label = 'Trash can', table = 'trash', searchSeconds = 3, refillMinutes = 40, grid = { 4, 3 }, anim = 'bin',
            models = { 'prop_bin_01a', 'prop_bin_02a', 'prop_bin_03a', 'prop_bin_04a', 'prop_bin_05a', 'prop_bin_06a',
                'prop_bin_07a', 'prop_bin_07b', 'prop_bin_07c', 'prop_bin_07d', 'prop_bin_08a', 'prop_bin_08open',
                'prop_cs_bin_01', 'prop_cs_bin_02', 'prop_cs_bin_03', 'prop_recyclebin_01a', 'prop_recyclebin_02a',
                'prop_recyclebin_03a', 'prop_recyclebin_04a', 'prop_recyclebin_05a' } },
        fridge = { label = 'Fridge', table = 'food', searchSeconds = 3, refillMinutes = 60, grid = { 4, 4 }, anim = 'search',
            models = { 'prop_fridge_01', 'prop_fridge_03', 'prop_trailr_fridge', 'prop_bar_fridge_01', 'prop_bar_fridge_02',
                'prop_bar_fridge_03', 'prop_bar_fridge_04' } },
        vending = { label = 'Vending machine', table = 'vending', searchSeconds = 4, refillMinutes = 60, grid = { 4, 3 }, anim = 'search',
            models = { 'prop_vend_soda_01', 'prop_vend_soda_02', 'prop_vend_snak_01', 'prop_vend_snak_01_tu', 'prop_vend_water_01',
                'prop_vend_coffe_01' } },
        toolbox = { label = 'Tool chest', table = 'tools', searchSeconds = 4, refillMinutes = 60, grid = { 5, 4 }, anim = 'search',
            models = { 'prop_toolchest_01', 'prop_toolchest_02', 'prop_toolchest_03', 'prop_toolchest_04', 'prop_toolchest_05',
                'prop_tool_box_02', 'prop_tool_box_04' } },
        crate = { label = 'Crate', table = 'crate', searchSeconds = 4, refillMinutes = 50, grid = { 5, 4 }, anim = 'search',
            models = { 'prop_box_wood01a', 'prop_box_wood02a', 'prop_box_wood04a', 'prop_box_wood05a', 'prop_box_wood07a',
                'prop_box_wood08a' } },
        mailbox = { label = 'Mailbox', table = 'mail', searchSeconds = 3, refillMinutes = 90, grid = { 3, 3 }, anim = 'search',
            models = { 'prop_postbox_01a', 'prop_letterbox_01', 'prop_letterbox_02', 'prop_letterbox_03', 'prop_letterbox_04' } },

        -- Dead zombies (no models): the body itself is searched. It is gone
        -- with the body (zombies.lua population.corpseSeconds).
        body = { label = 'Body', table = 'zombie', searchSeconds = 3, refillMinutes = 9999, grid = { 4, 4 }, anim = 'kneel' },
    },

    -- Loot tables. emptyChance: chance the container has nothing at all.
    -- rolls: how many picks; items: { name, min, max, weight } (weight =
    -- how likely compared to the others in the same table).
    tables = {
        trash = { emptyChance = 0.55, rolls = { 1, 2 }, items = {
            { name = 'scrap_metal', min = 1, max = 2, weight = 25 },
            { name = 'sewing_kit', min = 1, max = 1, weight = 4 },
            { name = 'rag', min = 1, max = 2, weight = 15 },
            { name = 'duct_tape', min = 1, max = 1, weight = 10 },
            { name = 'soda_can', min = 1, max = 1, weight = 10 },
            { name = 'cash', min = 1, max = 15, weight = 10 },
            { name = 'canned_beans', min = 1, max = 1, weight = 6 },
            { name = 'energy_bar', min = 1, max = 1, weight = 6 },
            { name = 'bandage', min = 1, max = 1, weight = 4 },
            { name = 'clothing_top', min = 1, max = 1, weight = 3 },
            { name = 'clothing_pants', min = 1, max = 1, weight = 3 },
            { name = 'clothing_shoes', min = 1, max = 1, weight = 3 },
            { name = 'clothing_hat', min = 1, max = 1, weight = 3 },
            { name = 'ammo_9mm', min = 2, max = 6, weight = 3 },
            { name = 'weapon_knife', min = 1, max = 1, weight = 2 },
            { name = 'weapon_bat', min = 1, max = 1, weight = 2 },
            { name = 'blueprint_knife', min = 1, max = 1, weight = 1 },
            { name = 'jerry_can', min = 1, max = 1, weight = 2 },
            { name = 'lockpick', min = 1, max = 1, weight = 2 },
            { name = 'siphon_hose', min = 1, max = 1, weight = 2 },
        } },
        food = { emptyChance = 0.45, rolls = { 1, 2 }, items = {
            { name = 'water_bottle', min = 1, max = 1, weight = 25 },
            { name = 'soda_can', min = 1, max = 2, weight = 25 },
            { name = 'canned_beans', min = 1, max = 1, weight = 15 },
            { name = 'canned_peaches', min = 1, max = 1, weight = 15 },
            { name = 'energy_bar', min = 1, max = 2, weight = 15 },
        } },
        vending = { emptyChance = 0.5, rolls = { 1, 2 }, items = {
            { name = 'soda_can', min = 1, max = 2, weight = 50 },
            { name = 'energy_bar', min = 1, max = 2, weight = 30 },
            { name = 'water_bottle', min = 1, max = 1, weight = 20 },
        } },
        tools = { emptyChance = 0.45, rolls = { 1, 1 }, items = {
            { name = 'duct_tape', min = 1, max = 2, weight = 25 },
            { name = 'scrap_metal', min = 1, max = 3, weight = 25 },
            { name = 'flashlight', min = 1, max = 1, weight = 10 },
            { name = 'weapon_repair_kit', min = 1, max = 1, weight = 6 },
            { name = 'crowbar', min = 1, max = 1, weight = 6 },
            { name = 'weapon_hatchet', min = 1, max = 1, weight = 4 },
            { name = 'weapon_machete', min = 1, max = 1, weight = 2 },
            { name = 'blueprint_repair_kit', min = 1, max = 1, weight = 3 },
            { name = 'blueprint_hatchet', min = 1, max = 1, weight = 2 },
            { name = 'blueprint_crowbar', min = 1, max = 1, weight = 2 },
            { name = 'vehicle_repair_kit', min = 1, max = 1, weight = 3 },
            { name = 'engine_parts', min = 1, max = 1, weight = 3 },
            { name = 'car_battery', min = 1, max = 1, weight = 2 },
            { name = 'lockpick', min = 1, max = 2, weight = 4 },
            { name = 'vehicle_lock', min = 1, max = 1, weight = 2 },
        } },
        crate = { emptyChance = 0.5, rolls = { 1, 2 }, items = {
            { name = 'sewing_kit', min = 1, max = 1, weight = 3 },
            { name = 'scrap_metal', min = 1, max = 3, weight = 30 },
            { name = 'duct_tape', min = 1, max = 1, weight = 15 },
            { name = 'rag', min = 1, max = 2, weight = 15 },
            { name = 'canned_beans', min = 1, max = 2, weight = 10 },
            { name = 'ammo_9mm', min = 5, max = 12, weight = 6 },
            { name = 'ammo_12g', min = 2, max = 6, weight = 6 },
            { name = 'backpack_small', min = 1, max = 1, weight = 3 },
            { name = 'weapon_pistol', min = 1, max = 1, weight = 1 },
            { name = 'blueprint_knife', min = 1, max = 1, weight = 2 },
            { name = 'blueprint_machete', min = 1, max = 1, weight = 2 },
            { name = 'car_wheel', min = 1, max = 1, weight = 3 },
            { name = 'jerry_can', min = 1, max = 1, weight = 3 },
            { name = 'siphon_hose', min = 1, max = 1, weight = 2 },
        } },
        mail = { emptyChance = 0.7, rolls = { 1, 1 }, items = {
            { name = 'cash', min = 5, max = 60, weight = 70 },
            { name = 'painkillers', min = 1, max = 2, weight = 15 },
            { name = 'bandage', min = 1, max = 2, weight = 10 },
            { name = 'antibiotics', min = 1, max = 1, weight = 5 },
        } },
        zombie = { emptyChance = 0.6, rolls = { 1, 1 }, items = {
            { name = 'cash', min = 5, max = 40, weight = 30 },
            { name = 'ammo_9mm', min = 3, max = 10, weight = 12 },
            { name = 'bandage', min = 1, max = 2, weight = 12 },
            { name = 'canned_beans', min = 1, max = 1, weight = 10 },
            { name = 'soda_can', min = 1, max = 1, weight = 10 },
            { name = 'painkillers', min = 1, max = 1, weight = 8 },
            { name = 'scrap_metal', min = 1, max = 2, weight = 8 },
            { name = 'ammo_12g', min = 2, max = 5, weight = 6 },
            { name = 'clothing_top', min = 1, max = 1, weight = 4 },
            { name = 'clothing_shoes', min = 1, max = 1, weight = 4 },
            { name = 'antibiotics', min = 1, max = 1, weight = 2 },
            { name = 'weapon_pistol', min = 1, max = 1, weight = 1 },
            { name = 'blueprint_repair_kit', min = 1, max = 1, weight = 1 },
            { name = 'blueprint_machete', min = 1, max = 1, weight = 1 },
        } },
    },
}
