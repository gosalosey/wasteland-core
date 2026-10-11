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
        bandage = { label = 'Bandage', result = { name = 'bandage', count = 1 },
            ingredients = { { name = 'rag', count = 2 } }, seconds = 3 },

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
    },
}
