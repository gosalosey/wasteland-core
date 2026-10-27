-- wasteland_scrapweapons :: shared/catalog.lua
-- Every scrap weapon this resource brings. Weapons are added here one at a
-- time, each only once its model, data and icon are finished.
--
-- Per weapon (key = the inventory item name, scrap_*):
--   item      inventory item definition (as in inventory.lua items; category = 'weapon')
--   weapon    { hash = 'WEAPON_WL_...', ammo?, wear?, noise? } (as in weapons.lua)
--   recipe    { label, result, ingredients, seconds?, blueprint?, station? } (as in crafting.lua)
--             (optional; leave out for loot-only weapons)
--   labelKey  text key the game shows for the weapon (HumanNameHash in its weapons meta), and label its text
--   damage    damage compared with the game weapon it is based on (1 = same)
--   status    'testing' | 'approved'   (kept in step with docs/scrapweapons.md)

WLSW = WLSW or {}

WLSW.catalog = {
    -- 1. Spiked baseball bat: a bat with nails driven through it and wire
    -- wrapped round. Swings like the game's bat, hits harder.
    scrap_spiked_bat = {
        item = { label = 'Spiked bat', category = 'weapon', width = 1, height = 4, weight = 0.7, durability = 300,
            description = 'A baseball bat with nails driven through it. Hits harder than a plain bat.' },
        weapon = { hash = 'WEAPON_WL_SPIKEDBAT', noise = 10 },
        recipe = { label = 'Spiked bat', result = { name = 'scrap_spiked_bat', count = 1 },
            ingredients = { { name = 'weapon_bat', count = 1 }, { name = 'nails', count = 10 },
                { name = 'scrap_metal', count = 1 }, { name = 'duct_tape', count = 1 } }, seconds = 8 },
        labelKey = 'WT_WL_SPKBAT', label = 'Spiked Bat',
        damage = 1.35,
        status = 'testing',
    },
}

return WLSW.catalog
