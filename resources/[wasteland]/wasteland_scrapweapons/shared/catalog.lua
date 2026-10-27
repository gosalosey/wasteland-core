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
        status = 'approved',
    },

    -- 2. Pipe shotgun: one shell in a length of galvanised pipe, hinged on a
    -- door hinge, nail firing pin, 2x4 grip. Handles like the game's sawed-off
    -- but holds one shell: the barrel swings open to load each shot.
    scrap_pipe_shotgun = {
        item = { label = 'Pipe shotgun', category = 'weapon', width = 4, height = 2, weight = 1.4, durability = 120,
            description = 'One shell in a length of pipe. Crude, loud and hits hard up close. Reload after every shot.' },
        weapon = { hash = 'WEAPON_WL_PIPESHOTGUN', ammo = 'ammo_12g', noise = 180, wear = 2 },
        recipe = { label = 'Pipe shotgun', result = { name = 'scrap_pipe_shotgun', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 6 }, { name = 'wood_planks', count = 1 },
                { name = 'nails', count = 4 }, { name = 'duct_tape', count = 2 } }, seconds = 12 },
        labelKey = 'WT_WL_PIPESG', label = 'Pipe Shotgun',
        status = 'approved',
    },

    -- 3. Scrap-made axe: a head cut from steel plate with a ground edge, bolted
    -- through a rough handle, wire and a rag round it, a rebar spike on the
    -- back. Swings like the game's hatchet, a little harder.
    scrap_axe = {
        item = { label = 'Scrap axe', category = 'weapon', width = 1, height = 3, weight = 0.9, durability = 350,
            description = 'A steel plate head bolted to a branch. Heavier than a hatchet.' },
        weapon = { hash = 'WEAPON_WL_SCRAPAXE', noise = 8 },
        recipe = { label = 'Scrap axe', result = { name = 'scrap_axe', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 4 }, { name = 'wood_log', count = 1 },
                { name = 'nails', count = 2 }, { name = 'rag', count = 1 }, { name = 'duct_tape', count = 1 } }, seconds = 10 },
        labelKey = 'WT_WL_SCRAPAXE', label = 'Scrap Axe',
        damage = 1.2,
        status = 'testing',
    },
}

return WLSW.catalog
