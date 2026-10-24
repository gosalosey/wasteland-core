-- Crafting: anywhere (key K, or the Crafting button in the inventory).
-- A recipe with a `blueprint` must be learned first: use the blueprint item
-- (found while looting) and the character knows it for good. Recipes
-- without a blueprint are known from the start.
--
-- Recipe fields:
--   label        name in the crafting screen
--   result       { name, count }      what you get
--   ingredients  list of { name, count } (all taken from your inventory)
--   seconds      how long it takes (moving cancels)
--   blueprint    item that teaches it (nil = known from the start)
return {
    recipes = {
        rag = { label = 'Rags (tear a top)', result = { name = 'rag', count = 3 },
            ingredients = { { name = 'clothing_top', count = 1 } }, seconds = 3 },
        rag_pants = { label = 'Rags (tear pants)', result = { name = 'rag', count = 3 },
            ingredients = { { name = 'clothing_pants', count = 1 } }, seconds = 3 },
        rag_shoes = { label = 'Rags (cut up shoes)', result = { name = 'rag', count = 2 },
            ingredients = { { name = 'clothing_shoes', count = 1 } }, seconds = 3 },
        rag_hat = { label = 'Rags (tear a hat)', result = { name = 'rag', count = 1 },
            ingredients = { { name = 'clothing_hat', count = 1 } }, seconds = 2 },
        bandage = { label = 'Bandage', result = { name = 'bandage', count = 1 },
            ingredients = { { name = 'rag', count = 2 } }, seconds = 3 },
        armor_repair_kit = { label = 'Armor repair kit', result = { name = 'armor_repair_kit', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 2 }, { name = 'duct_tape', count = 1 } }, seconds = 5 },
        armor_plate = { label = 'Armor vest', result = { name = 'armor_plate', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 6 }, { name = 'duct_tape', count = 2 }, { name = 'rag', count = 2 } }, seconds = 10,
            blueprint = 'blueprint_armor_plate' },
        armor_insert = { label = 'Armor plate', result = { name = 'armor_insert', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 4 }, { name = 'duct_tape', count = 1 } }, seconds = 8,
            blueprint = 'blueprint_armor_plate' },
        sewing_kit = { label = 'Sewing kit', result = { name = 'sewing_kit', count = 1 },
            ingredients = { { name = 'rag', count = 2 }, { name = 'scrap_metal', count = 1 } }, seconds = 4 },
        campfire = { label = 'Campfire', result = { name = 'campfire', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 3 } }, seconds = 5 },
        -- Base building (wasteland_basebuilding)
        -- Moonshine (moonshine.lua)
        moonshine_still = { label = 'Moonshine still', result = { name = 'moonshine_still', count = 1 },
            ingredients = { { name = 'metal_sheet', count = 6 }, { name = 'scrap_metal', count = 10 }, { name = 'wood_planks', count = 4 } }, seconds = 12 },
        -- Farming: planter boxes and a rain catcher (farming.lua)
        rain_catcher = { label = 'Rain catcher', result = { name = 'rain_catcher', count = 1 },
            ingredients = { { name = 'wood_planks', count = 8 }, { name = 'scrap_metal', count = 4 }, { name = 'rag', count = 3 } }, seconds = 8 },
        farm_plot_small = { label = 'Small farm plot', result = { name = 'farm_plot_small', count = 1 },
            ingredients = { { name = 'wood_planks', count = 6 } }, seconds = 6 },
        farm_plot_medium = { label = 'Medium farm plot', result = { name = 'farm_plot_medium', count = 1 },
            ingredients = { { name = 'wood_planks', count = 12 }, { name = 'scrap_metal', count = 2 } }, seconds = 9 },
        farm_plot_large = { label = 'Large farm plot', result = { name = 'farm_plot_large', count = 1 },
            ingredients = { { name = 'wood_planks', count = 20 }, { name = 'scrap_metal', count = 4 } }, seconds = 12 },
        saw_planks = { label = 'Wood planks (saw a log)', result = { name = 'wood_planks', count = 4 },
            ingredients = { { name = 'wood_log', count = 1 } }, seconds = 3 },
        saw_planks_5 = { label = 'Wood planks x20 (saw 5 logs)', result = { name = 'wood_planks', count = 20 },
            ingredients = { { name = 'wood_log', count = 5 } }, seconds = 12 },
        building_plan = { label = 'Building plan', result = { name = 'building_plan', count = 1 },
            ingredients = { { name = 'rag', count = 1 }, { name = 'duct_tape', count = 1 } }, seconds = 4 },
        metal_sheet = { label = 'Metal sheet', result = { name = 'metal_sheet', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 4 }, { name = 'duct_tape', count = 1 } }, seconds = 8 },
        lockpick = { label = 'Lockpicks', result = { name = 'lockpick', count = 2 },
            ingredients = { { name = 'scrap_metal', count = 1 } }, seconds = 4 },

        weapon_repair_kit = { label = 'Weapon repair kit', result = { name = 'weapon_repair_kit', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 3 }, { name = 'duct_tape', count = 2 } }, seconds = 6,
            blueprint = 'blueprint_repair_kit' },
        weapon_knife = { label = 'Knife', result = { name = 'weapon_knife', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 2 }, { name = 'duct_tape', count = 1 }, { name = 'rag', count = 1 } },
            seconds = 5, blueprint = 'blueprint_knife' },
        weapon_hatchet = { label = 'Hatchet', result = { name = 'weapon_hatchet', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 3 }, { name = 'duct_tape', count = 2 } }, seconds = 7,
            blueprint = 'blueprint_hatchet' },
        weapon_machete = { label = 'Machete', result = { name = 'weapon_machete', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 4 }, { name = 'duct_tape', count = 2 }, { name = 'rag', count = 1 } },
            seconds = 8, blueprint = 'blueprint_machete' },
        crowbar = { label = 'Crowbar', result = { name = 'crowbar', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 4 } }, seconds = 6, blueprint = 'blueprint_crowbar' },

        -- Melee weapons (blueprints)
        weapon_bat = { label = 'Baseball bat', result = { name = 'weapon_bat', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 3 }, { name = 'duct_tape', count = 2 } }, seconds = 6, blueprint = 'blueprint_bat' },
        weapon_hammer = { label = 'Hammer', result = { name = 'weapon_hammer', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 2 }, { name = 'duct_tape', count = 1 }, { name = 'rag', count = 1 } }, seconds = 5, blueprint = 'blueprint_hammer' },
        weapon_wrench = { label = 'Pipe wrench', result = { name = 'weapon_wrench', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 3 } }, seconds = 5, blueprint = 'blueprint_wrench' },
        weapon_battleaxe = { label = 'Battle axe', result = { name = 'weapon_battleaxe', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 6 }, { name = 'duct_tape', count = 2 }, { name = 'rag', count = 1 } }, seconds = 10, blueprint = 'blueprint_battleaxe' },
        weapon_knuckle = { label = 'Brass knuckles', result = { name = 'weapon_knuckle', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 2 } }, seconds = 4, blueprint = 'blueprint_knuckle' },
        weapon_switchblade = { label = 'Switchblade', result = { name = 'weapon_switchblade', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 2 }, { name = 'duct_tape', count = 1 } }, seconds = 5, blueprint = 'blueprint_switchblade' },

        -- Guns (blueprints). Gun parts and gunpowder are found in crates, crash sites and bandit stashes.
        weapon_pistol = { label = 'Pistol', result = { name = 'weapon_pistol', count = 1 },
            ingredients = { { name = 'gun_parts', count = 3 }, { name = 'scrap_metal', count = 4 }, { name = 'duct_tape', count = 1 } }, seconds = 15, blueprint = 'blueprint_pistol' },
        weapon_revolver = { label = 'Heavy revolver', result = { name = 'weapon_revolver', count = 1 },
            ingredients = { { name = 'gun_parts', count = 4 }, { name = 'scrap_metal', count = 5 }, { name = 'duct_tape', count = 1 } }, seconds = 18, blueprint = 'blueprint_revolver' },
        weapon_dbshotgun = { label = 'Sawed-off shotgun', result = { name = 'weapon_dbshotgun', count = 1 },
            ingredients = { { name = 'gun_parts', count = 3 }, { name = 'scrap_metal', count = 6 }, { name = 'duct_tape', count = 2 } }, seconds = 18, blueprint = 'blueprint_dbshotgun' },
        weapon_pumpshotgun = { label = 'Pump shotgun', result = { name = 'weapon_pumpshotgun', count = 1 },
            ingredients = { { name = 'gun_parts', count = 5 }, { name = 'scrap_metal', count = 8 }, { name = 'duct_tape', count = 2 } }, seconds = 22, blueprint = 'blueprint_pumpshotgun' },
        weapon_microsmg = { label = 'Micro SMG', result = { name = 'weapon_microsmg', count = 1 },
            ingredients = { { name = 'gun_parts', count = 6 }, { name = 'scrap_metal', count = 6 }, { name = 'duct_tape', count = 2 } }, seconds = 22, blueprint = 'blueprint_microsmg' },
        weapon_smg = { label = 'SMG', result = { name = 'weapon_smg', count = 1 },
            ingredients = { { name = 'gun_parts', count = 7 }, { name = 'scrap_metal', count = 8 }, { name = 'duct_tape', count = 2 } }, seconds = 25, blueprint = 'blueprint_smg' },
        weapon_huntingrifle = { label = 'Hunting rifle', result = { name = 'weapon_huntingrifle', count = 1 },
            ingredients = { { name = 'gun_parts', count = 6 }, { name = 'scrap_metal', count = 8 }, { name = 'duct_tape', count = 2 } }, seconds = 25, blueprint = 'blueprint_huntingrifle' },
        weapon_carbine = { label = 'Carbine rifle', result = { name = 'weapon_carbine', count = 1 },
            ingredients = { { name = 'gun_parts', count = 9 }, { name = 'scrap_metal', count = 10 }, { name = 'duct_tape', count = 3 } }, seconds = 30, blueprint = 'blueprint_carbine' },
        weapon_assaultrifle = { label = 'Assault rifle', result = { name = 'weapon_assaultrifle', count = 1 },
            ingredients = { { name = 'gun_parts', count = 10 }, { name = 'scrap_metal', count = 10 }, { name = 'duct_tape', count = 3 } }, seconds = 30, blueprint = 'blueprint_assaultrifle' },

        -- Explosives (base raiding). Molotovs need no blueprint.
        weapon_molotov = { label = 'Molotov', result = { name = 'weapon_molotov', count = 1 },
            ingredients = { { name = 'whiskey', count = 1 }, { name = 'rag', count = 1 } }, seconds = 5 },
        weapon_grenade = { label = 'Grenade', result = { name = 'weapon_grenade', count = 1 },
            ingredients = { { name = 'gunpowder', count = 4 }, { name = 'scrap_metal', count = 2 }, { name = 'duct_tape', count = 1 } }, seconds = 10, blueprint = 'blueprint_explosives' },
        weapon_stickybomb = { label = 'Sticky bomb', result = { name = 'weapon_stickybomb', count = 1 },
            ingredients = { { name = 'gunpowder', count = 10 }, { name = 'gun_parts', count = 2 }, { name = 'duct_tape', count = 2 }, { name = 'scrap_metal', count = 2 } }, seconds = 15, blueprint = 'blueprint_explosives' },

        -- Ammo (blueprints)
        ammo_9mm = { label = '9mm rounds', result = { name = 'ammo_9mm', count = 10 },
            ingredients = { { name = 'gunpowder', count = 1 }, { name = 'scrap_metal', count = 1 } }, seconds = 4, blueprint = 'blueprint_ammo_pistol' },
        ammo_44 = { label = '.44 rounds', result = { name = 'ammo_44', count = 6 },
            ingredients = { { name = 'gunpowder', count = 1 }, { name = 'scrap_metal', count = 1 } }, seconds = 4, blueprint = 'blueprint_ammo_pistol' },
        ammo_12g = { label = '12 gauge shells', result = { name = 'ammo_12g', count = 5 },
            ingredients = { { name = 'gunpowder', count = 2 }, { name = 'scrap_metal', count = 1 } }, seconds = 4, blueprint = 'blueprint_ammo_shotgun' },
        ammo_556 = { label = '5.56 rounds', result = { name = 'ammo_556', count = 10 },
            ingredients = { { name = 'gunpowder', count = 2 }, { name = 'scrap_metal', count = 1 } }, seconds = 4, blueprint = 'blueprint_ammo_rifle' },
        ammo_762 = { label = '7.62 rounds', result = { name = 'ammo_762', count = 10 },
            ingredients = { { name = 'gunpowder', count = 2 }, { name = 'scrap_metal', count = 1 } }, seconds = 4, blueprint = 'blueprint_ammo_rifle' },
        ammo_308 = { label = '.308 rounds', result = { name = 'ammo_308', count = 5 },
            ingredients = { { name = 'gunpowder', count = 2 }, { name = 'scrap_metal', count = 1 } }, seconds = 4, blueprint = 'blueprint_ammo_rifle' },
    },
}
