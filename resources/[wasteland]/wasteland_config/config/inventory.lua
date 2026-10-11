-- Wasteland Core :: inventory (module "inventory", resource wasteland_inventory)
-- Grid inventories: every item takes up width x height cells and can be
-- rotated. Pockets are small; a worn backpack adds its own grid.
return {
    -- The pockets every character has (cells and kilograms).
    pockets = { width = 6, height = 4, maxWeight = 12.0 },

    -- Size of the grid for items lying on the ground.
    dropGrid = { width = 10, height = 10 },

    -- Metres a player may be from a drop or stash to use it.
    reachDistance = 3.0,

    -- Items dropped this close to an existing pile join it.
    dropMergeDistance = 1.5,

    -- Items on the ground disappear after this many minutes. 1 - 10080.
    dropLifetimeMinutes = 60,

    -- Body bags: when a character dies, everything except hotbar items goes
    -- into a bag at the body (the owner gets a map marker). Grid and lifetime.
    deathBagGrid = { width = 12, height = 12 },
    deathBagLifetimeMinutes = 120,

    -- Admin command to spawn items: /give <server id> <item> [count]
    giveCommand = 'give',
    adminAce = 'wasteland.admin',

    -- What a brand-new character starts with (item names from `items`).
    startingItems = {
        { name = 'water_bottle', count = 1 },
        { name = 'canned_beans', count = 2 },
        { name = 'bandage', count = 2 },
    },

    -- Item used for each clothing slot. A character's starting outfit from
    -- the creator becomes these items, worn.
    clothingItems = {
        torso = 'clothing_top',
        legs = 'clothing_pants',
        feet = 'clothing_shoes',
        head = 'clothing_hat',
        eyes = 'clothing_glasses',
    },

    -- The look of a worn clothing item that carries no look of its own
    -- (given with /give or the admin panel, or loot), per model and part.
    -- Clothing from the character creator keeps its own look.
    -- VERIFY IN-GAME: values differ between game builds.
    plain = {
        mp_m_freemode_01 = { top = { 0, 0 }, undershirt = { 15, 0 }, arms = { 0, 0 }, legs = { 0, 0 }, shoes = { 1, 0 },
            hat = { 2, 0 }, glasses = { 5, 0 } },
        mp_f_freemode_01 = { top = { 0, 0 }, undershirt = { 14, 0 }, arms = { 0, 0 }, legs = { 0, 0 }, shoes = { 1, 0 },
            hat = { 5, 0 }, glasses = { 11, 0 } },
    },

    -- What the body shows when a clothing slot is empty: { drawable, texture }
    -- per part. VERIFY IN-GAME: values differ between game builds.
    naked = {
        mp_m_freemode_01 = { top = { 15, 0 }, undershirt = { 15, 0 }, arms = { 15, 0 }, legs = { 61, 0 }, shoes = { 34, 0 } },
        mp_f_freemode_01 = { top = { 15, 0 }, undershirt = { 14, 0 }, arms = { 15, 0 }, legs = { 17, 0 }, shoes = { 35, 0 } },
    },

    -- Item definitions. Fields (all optional except label):
    --   label, description
    --   category    food | drink | medical | material | tool | clothing | container | weapon | ammo | misc
    --   width, height   cells (1 - 10)
    --   weight      kilograms per unit
    --   stack       units per stack (1 = does not stack)
    --   durability  starting durability (0 = none; such items never stack)
    --   equip       head | eyes | torso | back | legs | feet   (can be worn there)
    --   container   { width, height, maxWeight }  a bag; must have equip = 'back'
    --   color       '#rrggbb' tile colour in the inventory screen
    --   warmth      degrees C of insulation while worn (body temperature)
    -- Other modules add their own items through the RegisterItem export.
    items = {
        water_bottle = { label = 'Water bottle', category = 'drink', width = 1, height = 2, weight = 0.6,
            description = 'Half a litre of probably clean water.' },
        canned_beans = { label = 'Canned beans', category = 'food', width = 1, height = 1, weight = 0.4, stack = 4 },
        bandage = { label = 'Bandage', category = 'medical', width = 1, height = 1, weight = 0.05, stack = 10 },
        painkillers = { label = 'Painkillers', category = 'medical', width = 1, height = 1, weight = 0.1, stack = 10 },
        antibiotics = { label = 'Antibiotics', category = 'medical', width = 1, height = 1, weight = 0.1, stack = 5,
            description = 'Slows and fights an infection.' },
        rag = { label = 'Clean rag', category = 'medical', width = 1, height = 1, weight = 0.05, stack = 5,
            description = 'Can stop light bleeding.' },
        soda_can = { label = 'Soda', category = 'drink', width = 1, height = 1, weight = 0.35, stack = 4 },
        energy_bar = { label = 'Energy bar', category = 'food', width = 1, height = 1, weight = 0.1, stack = 6 },
        canned_peaches = { label = 'Canned peaches', category = 'food', width = 1, height = 1, weight = 0.45, stack = 4 },
        scrap_metal = { label = 'Scrap metal', category = 'material', width = 2, height = 1, weight = 1.0, stack = 10 },
        duct_tape = { label = 'Duct tape', category = 'material', width = 1, height = 1, weight = 0.2, stack = 5 },
        flashlight = { label = 'Flashlight', category = 'tool', width = 1, height = 2, weight = 0.4, durability = 100 },
        crowbar = { label = 'Crowbar', category = 'tool', width = 1, height = 3, weight = 1.5, durability = 300 },

        backpack_small = { label = 'Small backpack', category = 'container', width = 3, height = 3, weight = 0.8,
            equip = 'back', container = { width = 5, height = 4, maxWeight = 15 } },
        backpack_large = { label = 'Hiking backpack', category = 'container', width = 4, height = 4, weight = 1.8,
            equip = 'back', container = { width = 7, height = 6, maxWeight = 30 } },

        clothing_top = { label = 'Top', category = 'clothing', width = 2, height = 2, weight = 0.5, equip = 'torso', warmth = 6 },
        clothing_pants = { label = 'Pants', category = 'clothing', width = 2, height = 2, weight = 0.5, equip = 'legs', warmth = 4 },
        clothing_shoes = { label = 'Shoes', category = 'clothing', width = 2, height = 1, weight = 0.8, equip = 'feet', warmth = 2 },
        clothing_hat = { label = 'Hat', category = 'clothing', width = 1, height = 1, weight = 0.2, equip = 'head', warmth = 2 },
        clothing_glasses = { label = 'Glasses', category = 'clothing', width = 1, height = 1, weight = 0.05, equip = 'eyes' },
    },
}
