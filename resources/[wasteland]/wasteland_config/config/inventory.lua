-- Wasteland Core :: inventory (module "inventory", resource wasteland_inventory)
-- Grid inventories: every item takes up width x height cells and can be
-- rotated. Pockets are small; a worn backpack adds its own grid.
return {
    -- The pockets every character has (cells and kilograms). They grow with
    -- what is worn: each worn slot in `bonus` adds its cells (a shirt and
    -- pants and armor: 3x3 -> 5x5 -> 7x7 -> 9x9), up to maxWidth x maxHeight.
    -- Taking something off is refused while the smaller pockets could not
    -- hold what is in them.
    pockets = {
        width = 3, height = 3, maxWeight = 200.0,
        maxWidth = 10, maxHeight = 10,
        bonus = {
            torso = { width = 2, height = 2 },   -- a shirt / top
            legs = { width = 2, height = 2 },    -- pants
            armor = { width = 2, height = 2 },   -- an armor plate
        },
    },

    -- Size of the grid for items lying on the ground.
    dropGrid = { width = 10, height = 10 },

    -- Metres a player may be from a drop or stash to use it.
    reachDistance = 3.0,
    vicinityMax = 4,  -- piles on the ground shown when the inventory opens (within reachDistance)

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
        { name = 'cash', count = 50 },
        { name = 'water_bottle', count = 1 },
        { name = 'canned_beans', count = 2 },
        { name = 'bandage', count = 2 },
        { name = 'weapon_knife', count = 1 },
        { name = 'full_vehicle_repair', count = 1 },
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

    -- How a worn backpack looks on the body: the bag clothing slot (ped
    -- component 5), { drawable, texture } per backpack item and model. A
    -- backpack not listed here shows no bag. Players hide or show it with
    -- /backpack. VERIFY IN-GAME: values differ between game builds.
    bagLooks = {
        backpack_small = { mp_m_freemode_01 = { 45, 0 }, mp_f_freemode_01 = { 45, 0 } },
        backpack_large = { mp_m_freemode_01 = { 82, 0 }, mp_f_freemode_01 = { 82, 0 } },
    },

    -- Item definitions. Fields (all optional except label):
    --   label, description
    --   category    food | drink | medical | material | tool | clothing | container | weapon | ammo | misc
    --   width, height   cells (1 - 10)
    --   weight      kilograms per unit
    --   stack       units per stack (default 250; weapons, tools with
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
        water_bottle = { label = 'Water bottle', category = 'drink', width = 1, height = 2, weight = 0.3,
            description = 'Half a litre of probably clean water.' },
        canned_beans = { label = 'Canned beans', image = 'canned_peas', category = 'food', width = 1, height = 1, weight = 0.2 },
        bandage = { label = 'Bandage', category = 'medical', width = 1, height = 1, weight = 0.025, stack = 250 },
        painkillers = { label = 'Painkillers', category = 'medical', width = 1, height = 1, weight = 0.05, stack = 250 },
        antibiotics = { label = 'Antibiotics', image = 'antibiotic', category = 'medical', width = 1, height = 1, weight = 0.05,
            description = 'Slows and fights an infection.' },
        rag = { label = 'Clean rag', image = 'cloth', category = 'medical', width = 1, height = 1, weight = 0.025, stack = 250,
            description = 'Can stop light bleeding.' },
        soda_can = { label = 'Soda', image = 'ecola', category = 'drink', width = 1, height = 1, weight = 0.175 },
        energy_bar = { label = 'Energy bar', image = 'chocolate', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250 },
        canned_peaches = { label = 'Canned peaches', image = 'canned_pears', category = 'food', width = 1, height = 1, weight = 0.225 },
        canned_tuna = { label = 'Canned tuna', image = 'canned_tuna', category = 'food', width = 1, height = 1, weight = 0.1,
            description = 'Salty, oily, filling.' },
        canned_salmon = { label = 'Canned salmon', image = 'canned_salmon', category = 'food', width = 1, height = 1, weight = 0.125,
            description = 'Pink and boneless, mostly.' },
        canned_soup = { label = 'Canned chicken soup', image = 'canned_chicken_soup', category = 'food', width = 1, height = 1, weight = 0.225,
            description = 'Warms you up a little.' },
        canned_stew = { label = 'Canned country stew', image = 'canned_country_soup', category = 'food', width = 1, height = 1, weight = 0.25,
            description = 'Thick and hearty. Warms you up.' },
        mre_beef = { label = 'MRE (beef)', image = 'ration_beef', category = 'food', width = 1, height = 2, weight = 0.3,
            description = 'Military ration. A full meal.' },
        mre_chicken = { label = 'MRE (chicken)', image = 'ration_chicken', category = 'food', width = 1, height = 2, weight = 0.3,
            description = 'Military ration. A full meal.' },
        crisps = { label = 'Bag of chips', image = 'chips', category = 'food', width = 1, height = 1, weight = 0.05,
            description = 'Stale but crunchy. Makes you thirsty.' },
        peanut_butter = { label = 'Peanut butter', image = 'peanut_butter', category = 'food', width = 1, height = 1, weight = 0.175,
            description = 'A jar of calories.' },
        bread = { label = 'Bread', image = 'bread', category = 'food', width = 1, height = 1, weight = 0.15,
            description = 'Hard as a brick, still edible.' },
        -- Moonshine (moonshine.lua): sugar, the still, and the jars.
        sugar = { label = 'Sugar', image = 'sugar', category = 'food', width = 1, height = 1, weight = 0.1, stack = 250,
            description = 'A bag of sugar. Brew it into moonshine.' },
        moonshine_still = { label = 'Moonshine still', image = 'moonshine_still', category = 'tool', width = 2, height = 2, weight = 6, stack = 1,
            description = 'A copper pot still. Place it, then brew crops, sugar, water and firewood into moonshine.' },
        moonshine_corn = { label = 'Corn moonshine', image = 'moonshine_corn', category = 'drink', width = 1, height = 2, weight = 0.4, stack = 250,
            description = 'Sweet and rough, like a cornfield on fire. Heals a little, eases the infection, hides your smell from zombies. Gets you drunk.' },
        moonshine_strawberry = { label = 'Strawberry moonshine', image = 'moonshine_strawberry', category = 'drink', width = 1, height = 2, weight = 0.4, stack = 250,
            description = 'Pink, sweet and far stronger than it tastes. Heals a little, eases the infection, hides your smell from zombies. Gets you drunk.' },
        moonshine_cucumber = { label = 'Cucumber moonshine', image = 'moonshine_cucumber', category = 'drink', width = 1, height = 2, weight = 0.4, stack = 250,
            description = 'Oddly fresh. Still burns. Heals a little, eases the infection, hides your smell from zombies. Gets you drunk.' },
        moonshine_blueberry = { label = 'Blueberry moonshine', image = 'moonshine_blueberry', category = 'drink', width = 1, height = 2, weight = 0.4, stack = 250,
            description = 'Dark purple and smooth. Heals a little, eases the infection, hides your smell from zombies. Gets you drunk.' },
        moonshine_cranberry = { label = 'Cranberry moonshine', image = 'moonshine_cranberry', category = 'drink', width = 1, height = 2, weight = 0.4, stack = 250,
            description = 'Tart and red. Heals a little, eases the infection, hides your smell from zombies. Gets you drunk.' },
        moonshine_potato = { label = 'Potato moonshine', image = 'moonshine_potato', category = 'drink', width = 1, height = 2, weight = 0.4, stack = 250,
            description = 'Basically vodka. Strong. Heals a little, eases the infection, hides your smell from zombies. Gets you drunk.' },
        moonshine_watermelon = { label = 'Watermelon moonshine', image = 'moonshine_watermelon', category = 'drink', width = 1, height = 2, weight = 0.4, stack = 250,
            description = 'Summer in a jar. Heals a little, eases the infection, hides your smell from zombies. Gets you drunk.' },
        -- Farming (farming.lua): farm plots, seeds and what they grow.
        rain_catcher = { label = 'Rain catcher', image = 'rain_catcher', category = 'tool', width = 2, height = 3, weight = 2.5, stack = 1,
            description = 'A drum under a tarp funnel. Place it outdoors: it fills with water while it rains.' },
        farm_plot_small = { label = 'Small farm plot', image = 'farm_plot_small', category = 'tool', width = 2, height = 2, weight = 1.5, stack = 1,
            description = 'A small planter box (1 spot). Use it to place it, inside or outside.' },
        farm_plot_medium = { label = 'Medium farm plot', image = 'farm_plot_medium', category = 'tool', width = 2, height = 2, weight = 2.5, stack = 1,
            description = 'A planter box with 4 spots. Use it to place it, inside or outside.' },
        farm_plot_large = { label = 'Large farm plot', image = 'farm_plot_large', category = 'tool', width = 3, height = 2, weight = 4, stack = 1,
            description = 'A big planter box with 9 spots. Use it to place it, inside or outside.' },
        seeds_lettuce = { label = 'Lettuce seeds', image = 'seeds_lettuce', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_strawberry = { label = 'Strawberries seeds', image = 'seeds_strawberry', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_carrot = { label = 'Carrot seeds', image = 'seeds_carrot', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_cucumber = { label = 'Cucumber seeds', image = 'seeds_cucumber', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_onion = { label = 'Onion seeds', image = 'seeds_onion', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_tomato = { label = 'Tomato seeds', image = 'seeds_tomato', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_bell_pepper = { label = 'Bell pepper seeds', image = 'seeds_bell_pepper', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_banana = { label = 'Banana seeds', image = 'seeds_banana', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_blueberry = { label = 'Blueberries seeds', image = 'seeds_blueberry', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_cranberry = { label = 'Cranberries seeds', image = 'seeds_cranberry', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_beetroot = { label = 'Beetroot seeds', image = 'seeds_beetroot', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_corn = { label = 'Corn seeds', image = 'seeds_corn', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_potato = { label = 'Potato seeds', image = 'seeds_potato', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_cabbage = { label = 'Cabbage seeds', image = 'seeds_cabbage', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_watermelon = { label = 'Watermelon seeds', image = 'seeds_watermelon', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        seeds_pumpkin = { label = 'Pumpkin seeds', image = 'seeds_pumpkin', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 250,
            description = 'Plant them in a farm plot and keep it watered.' },
        lettuce = { label = 'Lettuce', image = 'lettuce', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'Crisp and watery.' },
        strawberry = { label = 'Strawberries', image = 'strawberry', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'Sweet, a little sour.' },
        carrot = { label = 'Carrot', image = 'farm_carrot', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'Crunchy. Good for your eyes, they say.' },
        cucumber = { label = 'Cucumber', image = 'farm_cucumber', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'Mostly water. Very refreshing.' },
        onion = { label = 'Onion', image = 'onion', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'Makes your eyes water.' },
        tomato = { label = 'Tomato', image = 'tomato', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'Ripe and juicy.' },
        bell_pepper = { label = 'Bell pepper', image = 'pepper', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'Sweet and crunchy.' },
        blueberry = { label = 'Blueberries', image = 'blueberry', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'A handful of berries.' },
        cranberry = { label = 'Cranberries', image = 'cranberry', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'Tart little berries.' },
        beetroot = { label = 'Beetroot', image = 'farm_beetroot', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'Earthy and filling. Stains everything.' },
        corn = { label = 'Corn', image = 'corn_on_cob', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'A whole cob. Filling.' },
        potato = { label = 'Potato', image = 'potato', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'Raw, but it fills you up.' },
        cabbage = { label = 'Cabbage', image = 'cabbage', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'A big head of cabbage.' },
        watermelon = { label = 'Watermelon', image = 'farm_watermelon', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'Heavy and full of water.' },
        pumpkin = { label = 'Pumpkin', image = 'pumpkin', category = 'food', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'A whole pumpkin. Feeds you for a while.' },
        apple = { label = 'Apple', image = 'apple_red', category = 'food', width = 1, height = 1, weight = 0.075,
            description = 'A bit of food and a bit of water.' },
        banana = { label = 'Banana', image = 'banana', category = 'food', width = 1, height = 1, weight = 0.075,
            description = 'Brown, but fine.' },
        orange = { label = 'Orange', image = 'orange', category = 'food', width = 1, height = 1, weight = 0.075,
            description = 'Juicy.' },
        sprunk = { label = 'Sprunk', image = 'sprunk', category = 'drink', width = 1, height = 1, weight = 0.175,
            description = 'Lemon-lime soda.' },
        coffee = { label = 'Coffee', image = 'coffee', category = 'drink', width = 1, height = 1, weight = 0.15,
            description = 'Hot, bitter and warming.' },
        milk = { label = 'Long-life milk', image = 'milk', category = 'drink', width = 1, height = 1, weight = 0.25,
            description = 'Still good. Probably.' },
        grape_juice = { label = 'Grape juice', image = 'grapejuice', category = 'drink', width = 1, height = 1, weight = 0.2,
            description = 'Sweet and quenching.' },
        beer = { label = 'Beer', image = 'beer', category = 'drink', width = 1, height = 1, weight = 0.2,
            description = 'Warm beer. Better than nothing.' },
        whiskey = { label = 'Whiskey', image = 'whiskey', category = 'drink', width = 1, height = 2, weight = 0.4,
            description = 'Warms you inside, dries you out.' },
        scrap_metal = { label = 'Scrap metal', image = 'metalscrap', category = 'material', width = 2, height = 1, weight = 0.5, stack = 250 },
        duct_tape = { label = 'Duct tape', category = 'material', width = 1, height = 1, weight = 0.1 },

        -- Hunting (wasteland_hunting)
        raw_meat = { label = 'Raw meat', image = 'raw_meat', category = 'food', width = 1, height = 1, weight = 0.2, stack = 250,
            description = 'Cook it on a campfire. Eaten raw it can make you sick.' },
        cooked_meat = { label = 'Cooked meat', image = 'grilled_meat', category = 'food', width = 1, height = 1, weight = 0.175, stack = 250,
            description = 'Filling and safe to eat.' },
        animal_pelt = { label = 'Animal pelt', image = 'pelt', category = 'misc', width = 2, height = 2, weight = 0.6, stack = 250,
            description = 'Traders pay for these.' },
        matches = { label = 'Matches', category = 'tool', width = 1, height = 1, weight = 0.005, stack = 250,
            description = 'One match lights a campfire.' },
        wood_log = { label = 'Log', image = 'log', category = 'material', width = 2, height = 1, weight = 1.5, stack = 50,
            description = 'Saw it into 4 wood planks (crafting). Chop trees with a hatchet or battle axe.' },
        firewood = { label = 'Firewood', image = 'woodlog_small', category = 'material', width = 2, height = 1, weight = 0.5, stack = 250,
            description = 'Two pieces keep a campfire going.' },
        campfire = { label = 'Campfire', image = 'log', category = 'tool', width = 2, height = 2, weight = 1.5, stack = 1,
            description = 'Use it to make a fire (needs a match and 2 firewood). Cook on it, then pick it up again.' },
        -- Base building (wasteland_basebuilding)
        building_plan = { label = 'Building plan', image = '2-blank-blurprint', category = 'tool', width = 1, height = 1, weight = 0.05, stack = 1,
            description = 'Use it to open the build menu. Place a Tool Cupboard first.' },
        stone = { label = 'Stone', image = 'rock', category = 'material', width = 1, height = 1, weight = 0.5, stack = 250,
            description = 'For stone upgrades and base upkeep.' },
        wood_planks = { label = 'Wood planks', image = 'woodplank', category = 'material', width = 2, height = 1, weight = 0.25, stack = 250,
            description = 'For building. Found in trash, sheds and crates.' },
        nails = { label = 'Nails', category = 'material', width = 1, height = 1, weight = 0.005, stack = 250,
            description = 'For building. Make more from scrap metal.' },
        metal_sheet = { label = 'Metal sheet', image = 'zinc-sheet', category = 'material', width = 2, height = 2, weight = 1.5, stack = 250,
            description = 'For metal walls and doors. Made at a workbench.' },
        base_flag = { label = 'Base flag', image = 'flag_green', category = 'tool', width = 1, height = 3, weight = 1.25,
            description = 'Use it to claim a spot for your base. Then /base (F7) to build.' },
        flashlight = { label = 'Flashlight', image = 'weapon_flashlight', category = 'tool', width = 1, height = 2, weight = 0.2, durability = 100 },

        -- Weapons (what each one does is in weapons.lua). Durability is
        -- shots (guns) or hits (melee) until the weapon breaks.
        survivor_cache = { label = "Survivor's Cache", image = 'burriedtreasure', category = 'misc', width = 2, height = 2, weight = 2.0, stack = 10,
            description = 'Very rare: found once in a thousand trees or rocks. Use it to open: a rifle, ammo, armor, a big backpack, medicine and food.' },
        -- Story items (story.lua)
        story_courier_case = { label = 'Sealed steel case', image = 'original_case', category = 'misc', width = 2, height = 2, weight = 3.0, stack = 1,
            description = 'LAZARUS-9 / HUMANE LABS / BIOHAZARD. Locked. Hollis at Sandy Shores wants to see it.' },
        story_keycard = { label = "Dr. Ward's keycard", image = 'labkey', category = 'misc', width = 1, height = 1, weight = 0.01, stack = 1,
            description = 'Humane Labs, cold store access.' },
        story_lazarus_sample = { label = 'LAZARUS sample', image = 'bdsample', category = 'misc', width = 1, height = 1, weight = 0.05, stack = 1,
            description = 'One vial, frost on the glass. L-9 / FINAL / CURE?' },
        lazarus_serum = { label = 'Lazarus serum', image = 'adrenaline', category = 'medical', width = 1, height = 1, weight = 0.05, stack = 5,
            description = 'Made from the last LAZARUS sample. Clears infection completely.' },
        pickaxe = { label = 'Pickaxe', image = 'pickaxe', category = 'tool', width = 1, height = 3, weight = 1.2, stack = 1,
            description = 'Mine the big rocks in rock zones for stone (see the map: "Mining").' },
        crowbar = { label = 'Crowbar', image = 'weapon_crowbar', category = 'weapon', width = 1, height = 3, weight = 0.75, durability = 400,
            description = 'Heavy, quiet, hard to break.' },
        weapon_knife = { label = 'Knife', category = 'weapon', width = 1, height = 2, weight = 0.15, durability = 300 },
        weapon_bat = { label = 'Baseball bat', category = 'weapon', width = 1, height = 4, weight = 0.5, durability = 250 },
        weapon_hatchet = { label = 'Hatchet', category = 'weapon', width = 1, height = 3, weight = 0.6, durability = 300 },
        weapon_machete = { label = 'Machete', category = 'weapon', width = 1, height = 3, weight = 0.4, durability = 300 },
        weapon_hammer = { label = 'Hammer', category = 'weapon', width = 1, height = 2, weight = 0.3, durability = 300 },
        weapon_wrench = { label = 'Pipe wrench', category = 'weapon', width = 1, height = 2, weight = 0.45, durability = 350 },
        weapon_battleaxe = { label = 'Battle axe', category = 'weapon', width = 1, height = 3, weight = 0.8, durability = 350 },
        weapon_knuckle = { label = 'Brass knuckles', category = 'weapon', width = 1, height = 1, weight = 0.15, durability = 400 },
        weapon_switchblade = { label = 'Switchblade', category = 'weapon', width = 1, height = 1, weight = 0.1, durability = 250 },
        weapon_pistol = { label = 'Pistol', category = 'weapon', width = 2, height = 2, weight = 0.45, durability = 600,
            description = 'Uses 9mm rounds.',
            attachments = { suppressor = 'COMPONENT_AT_PI_SUPP_02', flashlight = 'COMPONENT_AT_PI_FLSH', extmag = 'COMPONENT_PISTOL_CLIP_02' } },
        weapon_revolver = { label = 'Heavy revolver', category = 'weapon', width = 2, height = 2, weight = 0.65, durability = 500,
            description = 'Uses .44 rounds.' },
        weapon_dbshotgun = { label = 'Sawed-off shotgun', category = 'weapon', width = 3, height = 2, weight = 1.25, durability = 300,
            description = 'Uses 12 gauge shells.' },
        weapon_pumpshotgun = { label = 'Pump shotgun', category = 'weapon', width = 5, height = 2, weight = 1.6, durability = 400,
            description = 'Uses 12 gauge shells.',
            attachments = { suppressor = 'COMPONENT_AT_SR_SUPP', flashlight = 'COMPONENT_AT_AR_FLSH' } },
        weapon_microsmg = { label = 'Micro SMG', category = 'weapon', width = 3, height = 2, weight = 1, durability = 700,
            description = 'Uses 9mm rounds.',
            attachments = { suppressor = 'COMPONENT_AT_AR_SUPP_02', flashlight = 'COMPONENT_AT_PI_FLSH', scope = 'COMPONENT_AT_SCOPE_MACRO', extmag = 'COMPONENT_MICROSMG_CLIP_02' } },
        weapon_smg = { label = 'SMG', category = 'weapon', width = 3, height = 2, weight = 1.3, durability = 800,
            description = 'Uses 9mm rounds.',
            attachments = { suppressor = 'COMPONENT_AT_PI_SUPP', flashlight = 'COMPONENT_AT_AR_FLSH', scope = 'COMPONENT_AT_SCOPE_MACRO_02', extmag = 'COMPONENT_SMG_CLIP_02' } },
        weapon_carbine = { label = 'Carbine rifle', image = 'weapon_carbinerifle', category = 'weapon', width = 5, height = 2, weight = 1.7, durability = 1000,
            description = 'Uses 5.56 rounds.',
            attachments = { suppressor = 'COMPONENT_AT_AR_SUPP', flashlight = 'COMPONENT_AT_AR_FLSH', scope = 'COMPONENT_AT_SCOPE_MEDIUM', grip = 'COMPONENT_AT_AR_AFGRIP', extmag = 'COMPONENT_CARBINERIFLE_CLIP_02' } },
        weapon_assaultrifle = { label = 'Assault rifle', category = 'weapon', width = 5, height = 2, weight = 1.75, durability = 900,
            description = 'Uses 7.62 rounds.',
            attachments = { suppressor = 'COMPONENT_AT_AR_SUPP_02', flashlight = 'COMPONENT_AT_AR_FLSH', scope = 'COMPONENT_AT_SCOPE_MACRO', grip = 'COMPONENT_AT_AR_AFGRIP', extmag = 'COMPONENT_ASSAULTRIFLE_CLIP_02' } },
        weapon_huntingrifle = { label = 'Hunting rifle', image = 'weapon_sniperrifle', category = 'weapon', width = 6, height = 2, weight = 2.25, durability = 500,
            description = 'Uses .308 rounds.',
            attachments = { suppressor = 'COMPONENT_AT_AR_SUPP_02' } },

        -- Weapon attachments: right-click one -> Attach to... (a gun it fits);
        -- right-click a gun -> Remove attachments. What fits which gun is the
        -- gun's `attachments` (slot = GTA component). A suppressor halves how
        -- far zombies hear the shot (weapons.lua suppressorNoise).
        att_suppressor = { label = 'Suppressor', image = 'pistol_suppressor', category = 'misc', width = 2, height = 1, weight = 0.15, stack = 1,
            attachment = 'suppressor', description = 'Fits pistols, SMGs, rifles and the pump shotgun. Zombies hear your shots only half as far.' },
        att_flashlight = { label = 'Weapon flashlight', image = 'smg_flashlight', category = 'misc', width = 1, height = 1, weight = 0.1, stack = 1,
            attachment = 'flashlight', description = 'Fits pistols, SMGs, rifles and the pump shotgun.' },
        att_scope = { label = 'Scope', image = 'smg_scope', category = 'misc', width = 2, height = 1, weight = 0.2, stack = 1,
            attachment = 'scope', description = 'Fits SMGs and rifles.' },
        att_grip = { label = 'Grip', image = 'ar_grip', category = 'misc', width = 1, height = 1, weight = 0.1, stack = 1,
            attachment = 'grip', description = 'Fits the carbine and assault rifle. Steadier aim.' },
        att_extmag = { label = 'Extended magazine', image = 'pistol_extendedclip', category = 'misc', width = 1, height = 2, weight = 0.15, stack = 1,
            attachment = 'extmag', description = 'Fits pistols, SMGs and rifles. More rounds before reloading.' },

        ammo_9mm = { label = '9mm rounds', image = 'ammo9mmbulletball', category = 'ammo', width = 1, height = 1, weight = 0.006, stack = 250, color = '#8a7a4a' },
        ammo_44 = { label = '.44 rounds', image = 'ammo44magnumbulletball', category = 'ammo', width = 1, height = 1, weight = 0.01, stack = 250, color = '#8a6a3a' },
        ammo_12g = { label = '12 gauge shells', image = 'shotgun_ammo', category = 'ammo', width = 1, height = 1, weight = 0.02, stack = 250, color = '#8a3a2a' },
        ammo_556 = { label = '5.56 rounds', image = 'rifle_ammo', category = 'ammo', width = 1, height = 1, weight = 0.006, stack = 250, color = '#6a7a4a' },
        ammo_762 = { label = '7.62 rounds', image = 'ammo762mmbulletball', category = 'ammo', width = 1, height = 1, weight = 0.008, stack = 250, color = '#5a6a3a' },
        ammo_308 = { label = '.308 rounds', image = 'ammo762mmbullethp', category = 'ammo', width = 1, height = 1, weight = 0.013, stack = 250, color = '#4a5a3a' },

        -- Vehicles (vehicles.lua): parts, fuel, tools, locks.
        car_battery = { label = 'Car battery', image = 'car-battery', category = 'material', width = 2, height = 2, weight = 6, stack = 1,
            description = 'A vehicle needs one to start.' },
        engine_parts = { label = 'Engine parts', image = 'engine_parts_a', category = 'material', width = 2, height = 2, weight = 3, stack = 1,
            description = 'Belts, plugs and hoses. A vehicle needs them to run.' },
        car_wheel = { label = 'Wheel', image = 'wheel_1', category = 'material', width = 3, height = 3, weight = 7, stack = 1,
            description = 'A car needs four.' },
        jerry_can = { label = 'Jerry can', category = 'tool', width = 2, height = 3, weight = 1, stack = 1,
            description = 'Holds 20 L of fuel. Fill it at a gas pump.' },
        -- limit: a player can carry at most this many (one at a time).
        full_vehicle_repair = { label = 'Full vehicle repair', image = 'repairkit3', category = 'tool', width = 2, height = 2, weight = 1.5,
            stack = 1, limit = 1,
            description = 'Use it on any wreck (Left Alt on the vehicle: Full vehicle repair): every part fitted, fully repaired and half a tank of fuel. One use; you can only carry one.' },
        vehicle_repair_kit = { label = 'Toolkit', image = 'repairkit', category = 'tool', width = 3, height = 2, weight = 2, stack = 1,
            description = 'Repairs a damaged vehicle (engine and body).' },
        vehicle_lock = { label = 'Car lock', image = 'elock', category = 'tool', width = 1, height = 1, weight = 0.25,
            description = 'Fit it to a vehicle to lock it. You get the only key.' },
        vehicle_key = { label = 'Car key', image = 'key', category = 'misc', width = 1, height = 1, weight = 0.025, stack = 1,
            description = 'Opens the lock it was made for.' },
        lockpick = { label = 'Lockpick', category = 'tool', width = 1, height = 1, weight = 0.025,
            description = 'Can open a locked vehicle. Often breaks.' },
        siphon_hose = { label = 'Siphon hose', image = 'siphon_hose', category = 'tool', width = 2, height = 1, weight = 0.2,
            description = 'Drains fuel from a vehicle into a jerry can.' },

        -- Blueprints: use one to learn a crafting recipe (crafting.lua).
        blueprint_repair_kit = { label = 'Blueprint: repair kit', image = '1-blank-blurprint', category = 'misc', width = 1, height = 1,
            weight = 0.025, description = 'Use to learn how to make weapon repair kits.' },
        blueprint_knife = { label = 'Blueprint: knife', image = 'bpknife', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a knife.' },
        blueprint_hatchet = { label = 'Blueprint: hatchet', image = 'bphatchet', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a hatchet.' },
        blueprint_machete = { label = 'Blueprint: machete', image = 'bpmachete', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a machete.' },
        blueprint_crowbar = { label = 'Blueprint: crowbar', image = '2-blank-blurprint', category = 'misc', width = 1, height = 1,
            weight = 0.025, description = 'Use to learn how to make a crowbar.' },
        blueprint_bat = { label = 'Blueprint: baseball bat', image = 'bpbat', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a baseball bat.' },
        blueprint_hammer = { label = 'Blueprint: hammer', image = 'bphammer', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a hammer.' },
        blueprint_wrench = { label = 'Blueprint: pipe wrench', image = 'bpwrench', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a pipe wrench.' },
        blueprint_battleaxe = { label = 'Blueprint: battle axe', image = 'bpbattleaxe', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a battle axe.' },
        blueprint_knuckle = { label = 'Blueprint: brass knuckles', image = 'bpbrassknuckles', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make brass knuckles.' },
        blueprint_switchblade = { label = 'Blueprint: switchblade', image = 'bpswitchblade', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a switchblade.' },
        blueprint_pistol = { label = 'Blueprint: pistol', image = 'bppistol', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a pistol.' },
        blueprint_revolver = { label = 'Blueprint: heavy revolver', image = 'bprevolver', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a heavy revolver.' },
        blueprint_dbshotgun = { label = 'Blueprint: sawed-off shotgun', image = 'bpsawnoffshotgun', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a sawed-off shotgun.' },
        blueprint_pumpshotgun = { label = 'Blueprint: pump shotgun', image = 'bppumpshotgun', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a pump shotgun.' },
        blueprint_microsmg = { label = 'Blueprint: micro SMG', image = 'bpmicrosmg', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a micro SMG.' },
        blueprint_smg = { label = 'Blueprint: SMG', image = 'bpsmg', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make an SMG.' },
        blueprint_huntingrifle = { label = 'Blueprint: hunting rifle', image = 'bpsniperrifle', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a hunting rifle.' },
        blueprint_carbine = { label = 'Blueprint: carbine rifle', image = 'bpcarbinerifle', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make a carbine rifle.' },
        blueprint_assaultrifle = { label = 'Blueprint: assault rifle', image = 'bpassaultrifle', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make an assault rifle.' },
        blueprint_ammo_pistol = { label = 'Blueprint: pistol ammo', image = '1-blank-blurprint', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make 9mm and .44 rounds.' },
        blueprint_ammo_shotgun = { label = 'Blueprint: shotgun shells', image = '2-blank-blurprint', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make 12 gauge shells.' },
        blueprint_ammo_rifle = { label = 'Blueprint: rifle ammo', image = '1-blank-blurprint', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make 5.56, 7.62 and .308 rounds.' },

        -- Explosives: thrown (hold one like a weapon, attack to throw). Each
        -- throw uses one. For raiding bases (basebuilding.lua raid).
        weapon_molotov = { label = 'Molotov', image = 'weapon_molotov', category = 'weapon', width = 1, height = 2, weight = 0.5,
            description = 'A bottle of fuel with a burning rag. Burns wooden base pieces.' },
        weapon_grenade = { label = 'Grenade', image = 'weapon_grenade', category = 'weapon', width = 1, height = 1, weight = 0.4,
            description = 'Pull the pin, throw. Damages wooden and stone base pieces.' },
        weapon_stickybomb = { label = 'Sticky bomb', image = 'weapon_stickybomb', category = 'weapon', width = 1, height = 1, weight = 0.6,
            description = 'Sticks where it lands; press G to set it off. Breaks wood, stone and metal base pieces.' },
        blueprint_explosives = { label = 'Blueprint: explosives', image = '1-blank-blurprint', category = 'misc', width = 1, height = 1, weight = 0.025,
            description = 'Use to learn how to make grenades and sticky bombs.' },

        -- Gun crafting materials
        gun_parts = { label = 'Gun parts', image = 'trigger', category = 'material', width = 1, height = 1, weight = 0.15, stack = 250,
            description = 'Springs, pins, triggers and barrels. For crafting guns.' },
        gunpowder = { label = 'Gunpowder', image = 'gunpowder', category = 'material', width = 1, height = 1, weight = 0.05, stack = 250,
            description = 'For crafting ammo.' },

        weapon_repair_kit = { label = 'Weapon repair kit', image = 'repairkit2', category = 'tool', width = 2, height = 1, weight = 0.4,
            description = 'Repairs the weapon in your hands.' },

        backpack_small = { label = 'Small backpack', image = 'bag', category = 'container', width = 3, height = 3, weight = 0.4,
            equip = 'back', container = { width = 8, height = 8, maxWeight = 400 } },
        backpack_large = { label = 'Hiking backpack', image = 'duffelbag', category = 'container', width = 4, height = 4, weight = 0.9,
            equip = 'back', container = { width = 12, height = 10, maxWeight = 750 } },

        clothing_top = { label = 'Top', image = 'clothe', category = 'clothing', width = 2, height = 2, weight = 0.25, equip = 'torso', warmth = 6, durability = 100 },
        clothing_pants = { label = 'Pants', image = 'jeans', category = 'clothing', width = 2, height = 2, weight = 0.25, equip = 'legs', warmth = 4, durability = 100 },
        clothing_shoes = { label = 'Shoes', image = 'shoes_blue', category = 'clothing', width = 2, height = 1, weight = 0.4, equip = 'feet', warmth = 2, durability = 100 },
        clothing_hat = { label = 'Hat', image = 'cap', category = 'clothing', width = 1, height = 1, weight = 0.1, equip = 'head', warmth = 2, durability = 100 },
        clothing_glasses = { label = 'Glasses', image = 'sunglasses', category = 'clothing', width = 1, height = 1, weight = 0.025, equip = 'eyes', durability = 100 },
        -- The vest (item name kept from when it was called a plate). Its 3 slots
        -- take armor plates (armor_insert), which take hits before the vest.
        armor_plate = { label = 'Armor vest', image = 'heavyarmor', category = 'armor', width = 2, height = 2, weight = 1.5,
            equip = 'armor', durability = 100, container = { width = 3, height = 2, maxWeight = 10, accepts = { 'armor_insert' } },
            description = 'Wear it (Armor slot) to stop incoming damage. Holds 3 armor plates, which take hits first. It wears down as it takes hits; repair it with an armor repair kit.' },
        armor_insert = { label = 'Armor plate', image = 'iron', category = 'armor', width = 1, height = 2, weight = 1.2,
            durability = 100,
            description = 'Put it in your armor vest (open your inventory: Armor plates). Takes hits before the vest. Cannot be repaired: when it breaks it is gone.' },
        armor_repair_kit = { label = 'Armor repair kit', image = 'repair_kit', category = 'tool', width = 2, height = 1, weight = 0.5,
            repairs = 'armor', description = 'Repairs a damaged armor vest (not plates). Right-click the vest: "Repair with Armor repair kit".' },
        blueprint_armor_plate = { label = 'Blueprint: armor plate', image = '1-blank-blurprint', category = 'misc', width = 1, height = 1,
            weight = 0.025, description = 'Use to learn how to make armor plates.' },
        sewing_kit = { label = 'Sewing kit', category = 'tool', width = 1, height = 1, weight = 0.1, repairs = 'clothing',
            description = 'Mends worn or ruined clothing. Right-click a damaged piece: "Repair with Sewing kit".' },
    },
}
