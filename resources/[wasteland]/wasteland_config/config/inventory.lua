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

    -- The item that is money. Cash is the only currency (no bank): it is
    -- carried, dropped, looted and lost on death like any other item.
    cashItem = 'cash',

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
    --   stack       units per stack (default 50; weapons, tools with
    --               durability, backpacks and clothing never stack)
    --   durability  starting durability (0 = none; such items never stack)
    --   equip       head | eyes | torso | back | legs | feet   (can be worn there)
    --   container   { width, height, maxWeight }  a bag; must have equip = 'back'
    --   color       '#rrggbb' tile colour in the inventory screen
    --   warmth      degrees C of insulation while worn (body temperature)
    --   image       picture from wasteland_images (file name without .webp);
    --               default: the picture named like the item, if there is one
    -- Other modules add their own items through the RegisterItem export.
    items = {
        cash = { label = 'Cash', category = 'misc', width = 1, height = 1, weight = 0, stack = 1000000, image = 'cashroll',
            description = 'Dollars. The only money there is.' },
        water_bottle = { label = 'Water bottle', category = 'drink', width = 1, height = 2, weight = 0.6,
            description = 'Half a litre of probably clean water.' },
        canned_beans = { label = 'Canned beans', image = 'canned_peas', category = 'food', width = 1, height = 1, weight = 0.4 },
        bandage = { label = 'Bandage', category = 'medical', width = 1, height = 1, weight = 0.05, stack = 100 },
        painkillers = { label = 'Painkillers', category = 'medical', width = 1, height = 1, weight = 0.1, stack = 100 },
        antibiotics = { label = 'Antibiotics', image = 'antibiotic', category = 'medical', width = 1, height = 1, weight = 0.1,
            description = 'Slows and fights an infection.' },
        rag = { label = 'Clean rag', image = 'cloth', category = 'medical', width = 1, height = 1, weight = 0.05, stack = 100,
            description = 'Can stop light bleeding.' },
        soda_can = { label = 'Soda', image = 'ecola', category = 'drink', width = 1, height = 1, weight = 0.35 },
        energy_bar = { label = 'Energy bar', image = 'chocolate', category = 'food', width = 1, height = 1, weight = 0.1, stack = 100 },
        canned_peaches = { label = 'Canned peaches', image = 'canned_pears', category = 'food', width = 1, height = 1, weight = 0.45 },
        scrap_metal = { label = 'Scrap metal', image = 'metalscrap', category = 'material', width = 2, height = 1, weight = 1.0, stack = 100 },
        duct_tape = { label = 'Duct tape', category = 'material', width = 1, height = 1, weight = 0.2 },
        flashlight = { label = 'Flashlight', image = 'weapon_flashlight', category = 'tool', width = 1, height = 2, weight = 0.4, durability = 100 },

        -- Weapons (what each one does is in weapons.lua). Durability is
        -- shots (guns) or hits (melee) until the weapon breaks.
        crowbar = { label = 'Crowbar', image = 'weapon_crowbar', category = 'weapon', width = 1, height = 3, weight = 1.5, durability = 400,
            description = 'Heavy, quiet, hard to break.' },
        weapon_knife = { label = 'Knife', category = 'weapon', width = 1, height = 2, weight = 0.3, durability = 300 },
        weapon_bat = { label = 'Baseball bat', category = 'weapon', width = 1, height = 4, weight = 1.0, durability = 250 },
        weapon_hatchet = { label = 'Hatchet', category = 'weapon', width = 1, height = 3, weight = 1.2, durability = 300 },
        weapon_machete = { label = 'Machete', category = 'weapon', width = 1, height = 3, weight = 0.8, durability = 300 },
        weapon_pistol = { label = 'Pistol', category = 'weapon', width = 2, height = 2, weight = 0.9, durability = 600,
            description = 'Uses 9mm rounds.' },
        weapon_revolver = { label = 'Heavy revolver', category = 'weapon', width = 2, height = 2, weight = 1.3, durability = 500,
            description = 'Uses .44 rounds.' },
        weapon_dbshotgun = { label = 'Sawed-off shotgun', category = 'weapon', width = 3, height = 2, weight = 2.5, durability = 300,
            description = 'Uses 12 gauge shells.' },
        weapon_pumpshotgun = { label = 'Pump shotgun', category = 'weapon', width = 5, height = 2, weight = 3.2, durability = 400,
            description = 'Uses 12 gauge shells.' },
        weapon_microsmg = { label = 'Micro SMG', category = 'weapon', width = 3, height = 2, weight = 2.0, durability = 700,
            description = 'Uses 9mm rounds.' },
        weapon_smg = { label = 'SMG', category = 'weapon', width = 3, height = 2, weight = 2.6, durability = 800,
            description = 'Uses 9mm rounds.' },
        weapon_carbine = { label = 'Carbine rifle', image = 'weapon_carbinerifle', category = 'weapon', width = 5, height = 2, weight = 3.4, durability = 1000,
            description = 'Uses 5.56 rounds.' },
        weapon_assaultrifle = { label = 'Assault rifle', category = 'weapon', width = 5, height = 2, weight = 3.5, durability = 900,
            description = 'Uses 7.62 rounds.' },
        weapon_huntingrifle = { label = 'Hunting rifle', image = 'weapon_sniperrifle', category = 'weapon', width = 6, height = 2, weight = 4.5, durability = 500,
            description = 'Uses .308 rounds.' },

        ammo_9mm = { label = '9mm rounds', image = 'ammo9mmbulletball', category = 'ammo', width = 1, height = 1, weight = 0.012, stack = 250, color = '#8a7a4a' },
        ammo_44 = { label = '.44 rounds', image = 'ammo44magnumbulletball', category = 'ammo', width = 1, height = 1, weight = 0.02, stack = 100, color = '#8a6a3a' },
        ammo_12g = { label = '12 gauge shells', image = 'shotgun_ammo', category = 'ammo', width = 1, height = 1, weight = 0.04, stack = 100, color = '#8a3a2a' },
        ammo_556 = { label = '5.56 rounds', image = 'rifle_ammo', category = 'ammo', width = 1, height = 1, weight = 0.012, stack = 250, color = '#6a7a4a' },
        ammo_762 = { label = '7.62 rounds', image = 'ammo762mmbulletball', category = 'ammo', width = 1, height = 1, weight = 0.016, stack = 250, color = '#5a6a3a' },
        ammo_308 = { label = '.308 rounds', image = 'ammo762mmbullethp', category = 'ammo', width = 1, height = 1, weight = 0.025, stack = 100, color = '#4a5a3a' },

        weapon_repair_kit = { label = 'Weapon repair kit', image = 'repairkit2', category = 'tool', width = 2, height = 1, weight = 0.8,
            description = 'Repairs the weapon in your hands.' },

        backpack_small = { label = 'Small backpack', image = 'bag', category = 'container', width = 3, height = 3, weight = 0.8,
            equip = 'back', container = { width = 5, height = 4, maxWeight = 15 } },
        backpack_large = { label = 'Hiking backpack', image = 'duffelbag', category = 'container', width = 4, height = 4, weight = 1.8,
            equip = 'back', container = { width = 7, height = 6, maxWeight = 30 } },

        clothing_top = { label = 'Top', image = 'clothe', category = 'clothing', width = 2, height = 2, weight = 0.5, equip = 'torso', warmth = 6 },
        clothing_pants = { label = 'Pants', image = 'jeans', category = 'clothing', width = 2, height = 2, weight = 0.5, equip = 'legs', warmth = 4 },
        clothing_shoes = { label = 'Shoes', image = 'shoes_blue', category = 'clothing', width = 2, height = 1, weight = 0.8, equip = 'feet', warmth = 2 },
        clothing_hat = { label = 'Hat', image = 'cap', category = 'clothing', width = 1, height = 1, weight = 0.2, equip = 'head', warmth = 2 },
        clothing_glasses = { label = 'Glasses', image = 'sunglasses', category = 'clothing', width = 1, height = 1, weight = 0.05, equip = 'eyes' },
    },
}
