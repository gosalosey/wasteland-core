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
        status = 'approved',
    },

    -- 4. Scrap pump shotgun: pipe barrel over a pipe magazine tube, welded
    -- sheet-steel receiver, a pump made from wood wrapped in inner tube, plank
    -- stock with spare shells. Pumps like the game's pump shotgun; holds 4.
    scrap_pump_shotgun = {
        item = { label = 'Scrap pump shotgun', category = 'weapon', width = 5, height = 2, weight = 2.2, durability = 250,
            description = 'A welded receiver, two pipes and a plank. Holds four shells; pump between shots.' },
        weapon = { hash = 'WEAPON_WL_SCRAPPUMP', ammo = 'ammo_12g', noise = 180 },
        recipe = { label = 'Scrap pump shotgun', result = { name = 'scrap_pump_shotgun', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 10 }, { name = 'metal_sheet', count = 2 }, { name = 'wood_planks', count = 2 },
                { name = 'nails', count = 4 }, { name = 'duct_tape', count = 2 } }, seconds = 15 },
        labelKey = 'WT_WL_SCRAPPUMP', label = 'Scrap Pump Shotgun',
        status = 'approved',
    },

    -- 5. Scrap bolt rifle: long pipe barrel strapped to a full wooden stock,
    -- pipe receiver with a working bolt, tin box magazine, washer sights.
    -- Handles like the game's precision rifle (bolt cycled between shots); 5 rounds.
    scrap_bolt_rifle = {
        item = { label = 'Scrap bolt rifle', category = 'weapon', width = 6, height = 2, weight = 3.0, durability = 300,
            description = 'A pipe barrel on a hand-cut stock with a working bolt. Five rounds of .308; hits hard at range.' },
        weapon = { hash = 'WEAPON_WL_SCRAPBOLT', ammo = 'ammo_308', noise = 300, wear = 2 },
        recipe = { label = 'Scrap bolt rifle', result = { name = 'scrap_bolt_rifle', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 12 }, { name = 'metal_sheet', count = 1 }, { name = 'wood_planks', count = 3 },
                { name = 'nails', count = 4 }, { name = 'duct_tape', count = 2 } }, seconds = 18 },
        labelKey = 'WT_WL_SCRAPBOLT', label = 'Scrap Bolt Rifle',
        status = 'approved',
    },

    -- 6. Pipe club: steel pipe with a cast-iron tee screwed on as a hammer
    -- head, bolts through a coupling, a bike grip and cord. One-handed, swings
    -- like the game's crowbar, hits harder.
    scrap_pipe_club = {
        item = { label = 'Pipe club', category = 'weapon', width = 1, height = 3, weight = 1.1, durability = 450,
            description = 'A pipe with a cast-iron tee on the end. Heavy, simple, hard to break.' },
        weapon = { hash = 'WEAPON_WL_PIPECLUB', noise = 9 },
        recipe = { label = 'Pipe club', result = { name = 'scrap_pipe_club', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 5 }, { name = 'duct_tape', count = 1 }, { name = 'rag', count = 1 } }, seconds = 8 },
        labelKey = 'WT_WL_PIPECLUB', label = 'Pipe Club',
        damage = 1.3,
        status = 'approved',
    },

    -- 7. Scrap machete: a blade cut from steel plate with a ground edge, saw
    -- teeth on the spine, a bent-bar guard, cord-wrapped handle, nut pommel.
    -- Swings like the game's machete, a little harder.
    scrap_machete = {
        item = { label = 'Scrap machete', category = 'weapon', width = 1, height = 3, weight = 0.6, durability = 320,
            description = 'A blade ground out of scrap plate with teeth cut in the back. Fast and nasty.' },
        weapon = { hash = 'WEAPON_WL_SCRAPMACHETE', noise = 6 },
        recipe = { label = 'Scrap machete', result = { name = 'scrap_machete', count = 1 },
            ingredients = { { name = 'metal_sheet', count = 1 }, { name = 'scrap_metal', count = 3 }, { name = 'wood_planks', count = 1 },
                { name = 'rag', count = 1 }, { name = 'duct_tape', count = 1 } }, seconds = 10 },
        labelKey = 'WT_WL_SCRAPMACH', label = 'Scrap Machete',
        damage = 1.25,
        status = 'approved',
    },

    -- 8. Scrap lever rifle: octagonal barrel over a tube magazine, brass side
    -- plates, a loop lever, hammer, saddle ring, tack-studded stock. The game
    -- has no lever action: it handles like the precision rifle, faster and
    -- lighter (7 rounds of .44, 65 damage, a shot a second).
    scrap_lever_rifle = {
        item = { label = 'Scrap lever rifle', category = 'weapon', width = 6, height = 2, weight = 2.8, durability = 350,
            description = 'An old-style lever gun put back together from scrap. Seven .44 rounds, quick follow-up shots.' },
        weapon = { hash = 'WEAPON_WL_SCRAPLEVER', ammo = 'ammo_44', noise = 220 },
        recipe = { label = 'Scrap lever rifle', result = { name = 'scrap_lever_rifle', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 12 }, { name = 'metal_sheet', count = 2 }, { name = 'wood_planks', count = 3 },
                { name = 'nails', count = 6 }, { name = 'duct_tape', count = 1 } }, seconds = 18 },
        labelKey = 'WT_WL_SCRAPLEVER', label = 'Scrap Lever Rifle',
        status = 'approved',
    },

    -- 9. Heavy scrap maul: a chunk of steel I-beam welded to a thick pipe
    -- with gusset plates, rebar studs on both faces, chain round the neck.
    -- Two-handed (the game's bat swings), hits much harder.
    scrap_maul = {
        item = { label = 'Heavy scrap maul', category = 'weapon', width = 2, height = 5, weight = 4.5, durability = 500,
            description = 'A lump of I-beam on a pipe. Slow to carry, brutal to be hit with.' },
        weapon = { hash = 'WEAPON_WL_SCRAPMAUL', noise = 14 },
        recipe = { label = 'Heavy scrap maul', result = { name = 'scrap_maul', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 10 }, { name = 'metal_sheet', count = 2 },
                { name = 'duct_tape', count = 2 }, { name = 'rag', count = 1 } }, seconds = 15 },
        labelKey = 'WT_WL_SCRAPMAUL', label = 'Heavy Scrap Maul',
        damage = 1.7,
        status = 'approved',
    },

    -- 10. Improvised double-barrel: two thick pipes painted teal-green and
    -- worn to rust, a chunky breech block with a spare brass shell wired on
    -- top, a long rag-wrapped stock. The game's sawed-off: two shells, the
    -- barrels swing open to reload.
    scrap_double_barrel = {
        item = { label = 'Improvised double-barrel', category = 'weapon', width = 5, height = 2, weight = 2.3, durability = 200,
            description = 'Two pipes, two hammers, two shells. Break it open and load both.' },
        weapon = { hash = 'WEAPON_WL_SCRAPDOUBLE', ammo = 'ammo_12g', noise = 180, wear = 2 },
        recipe = { label = 'Improvised double-barrel', result = { name = 'scrap_double_barrel', count = 1 },
            ingredients = { { name = 'scrap_metal', count = 10 }, { name = 'metal_sheet', count = 1 }, { name = 'wood_planks', count = 2 },
                { name = 'nails', count = 4 }, { name = 'duct_tape', count = 2 } }, seconds = 15 },
        labelKey = 'WT_WL_SCRAPDBL', label = 'Improvised Double-Barrel',
        status = 'testing',
    },
}

return WLSW.catalog
