-- Quests (jobs): given by camp traders (hold Left Alt on a trader, "Jobs").
-- Every quest is repeatable after its cooldown. Progress is shown in the
-- tracker on screen; places are marked on the map.
--
-- Quest fields:
--   label, description
--   camps            camp ids that offer it (camps.lua); leave out = every camp
--   cooldownMinutes  how long before it can be done again (real minutes)
--   objectives       list (see below)
--   rewards          { cash = n, items = { { name, count } } }
--
-- Objectives:
--   { type = 'bring', item = 'scrap_metal', count = 6 }           handed in (taken) at the camp
--   { type = 'kill', count = 10 }                                 zombies you kill
--   { type = 'kill', count = 8, near = { x, y, z, radius = 80 }, label = 'Pillbox Hospital' }
--   { type = 'visit', coords = { x, y, z }, radius = 40, label = 'the airfield' }
--   { type = 'search', container = 'crate', count = 3 }           loot.lua container types
--   { type = 'craft', recipe = 'bandage', count = 2 }             crafting.lua recipes
--
-- VERIFY IN-GAME: places are picked from the map.
return {
    maxActive = 3,

    quests = {
        scrap_run = {
            label = 'Scrap run', cooldownMinutes = 45,
            description = 'We need metal for the walls. Bring scrap.',
            objectives = { { type = 'bring', item = 'scrap_metal', count = 6 } },
            rewards = { cash = 50, items = { { name = 'duct_tape', count = 1 } } },
        },
        food_drive = {
            label = 'Food drive', cooldownMinutes = 60,
            description = 'People here are hungry. Bring food and water.',
            objectives = { { type = 'bring', item = 'canned_beans', count = 2 }, { type = 'bring', item = 'water_bottle', count = 2 } },
            rewards = { cash = 80 },
        },
        thin_the_herd = {
            label = 'Thin the herd', cooldownMinutes = 60,
            description = 'Too many of them out there. Kill zombies anywhere.',
            objectives = { { type = 'kill', count = 10 } },
            rewards = { cash = 120, items = { { name = 'ammo_12g', count = 10 } } },
        },
        field_dressing = {
            label = 'Field dressings', cooldownMinutes = 90,
            description = 'Make bandages, then bring some for the infirmary.',
            objectives = { { type = 'craft', recipe = 'bandage', count = 3 }, { type = 'bring', item = 'bandage', count = 3 } },
            rewards = { cash = 90, items = { { name = 'antibiotics', count = 1 } } },
        },
        crate_scavenger = {
            label = 'Crate scavenger', cooldownMinutes = 60,
            description = 'Search wooden crates for anything useful.',
            objectives = { { type = 'search', container = 'crate', count = 3, label = 'crates' } },
            rewards = { cash = 60 },
        },

        -- Camp-specific
        airfield_check = {
            label = 'Check the airfield', camps = { 'sandy' }, cooldownMinutes = 120,
            description = 'Someone reported a plane. Go and look at the Sandy Shores airfield.',
            objectives = { { type = 'visit', coords = { x = 1730.0, y = 3300.0, z = 41.2 }, radius = 45, label = 'Sandy Shores Airfield' } },
            rewards = { cash = 70 },
        },
        sawmill_check = {
            label = 'Check the sawmill', camps = { 'paleto' }, cooldownMinutes = 120,
            description = 'The sawmill crew stopped answering. Find out what happened.',
            objectives = { { type = 'visit', coords = { x = -565.0, y = 5300.0, z = 73.0 }, radius = 60, label = 'the Paleto sawmill' } },
            rewards = { cash = 70 },
        },
        clear_pillbox = {
            label = 'Clear Pillbox Hospital', camps = { 'legion' }, cooldownMinutes = 120,
            description = 'We need the hospital. Kill the zombies around Pillbox.',
            objectives = {
                { type = 'visit', coords = { x = 300.0, y = -585.0, z = 43.3 }, radius = 50, label = 'Pillbox Hospital' },
                { type = 'kill', count = 8, near = { x = 300.0, y = -585.0, z = 43.3, radius = 120 }, label = 'Pillbox Hospital' },
            },
            rewards = { cash = 150, items = { { name = 'painkillers', count = 2 } } },
        },
    },
}
