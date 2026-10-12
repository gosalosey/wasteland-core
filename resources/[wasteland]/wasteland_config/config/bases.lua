-- Bases: players claim a spot with a base flag and build on it.
--
-- How it works for players:
--   * Craft a Base flag and use it from the inventory: place it (preview,
--     Q/E to turn, Enter to place). That claims a circle of `claimRadius`.
--   * /base (or F7) opens the base screen: pick a piece and place it.
--     Walls, doors and gates snap to a grid laid out from the flag; other
--     pieces go anywhere inside the claim.
--   * One base per group (or per player who is not in a group). Everyone in
--     the owner's group can build, use doors and storage.
--   * Upkeep: put the upkeep item in the flag's upkeep box. Once a day the
--     base takes what it needs. Unpaid, it lasts `decayHours` more, then
--     it is removed with everything in it.
--
-- Pieces are built from game props: `parts` are what you see, and walls get
-- hidden solid panels (`solid`) so they block players perfectly whatever
-- the props look like. Admins can check every piece with /basepreview.
-- A part: { model, x, y, z (metres: right, forward, up), rx, ry, rz (degrees) }.
-- A part with door = true is the door leaf: it swings round the hinge.
return {
    command = 'base',          -- /base opens the base screen (key F7)
    claimRadius = 30.0,        -- metres around the flag you can build in
    grid = 3.0,                -- width of one wall piece
    wallHeight = 3.0,
    campDistance = 150.0,      -- no claims this close to a camp (from its edge)
    baseDistance = 150.0,      -- or to another base's flag
    maxPieces = 60,            -- per base (flag not counted)
    refund = 0.5,              -- demolishing gives back this share of the cost
    streamDistance = 150.0,    -- players see a base's pieces from this far
    respawnCooldownMinutes = 5, -- between respawns at a sleeping bag

    -- Hidden solid panels: a flat prop tiled to fill each wall (made
    -- invisible). Its size is measured in game.
    solidModel = 'prop_cons_plyboard_01',

    upkeep = {
        item = 'scrap_metal',
        base = 1,              -- per day for the flag
        perPieces = 10,        -- plus perBlock for every started 10 pieces
        perBlock = 1,
        decayHours = 72,       -- unpaid for this long: the base is removed
        firstDays = 3,         -- a new base is paid for this many days
        box = { width = 4, height = 3, maxWeight = 60 },
    },

    flag = {
        label = 'Base flag',
        parts = {
            { model = 'prop_flagpole_1a' },
        },
    },

    pieces = {
        -- Walls (grid). tier: a higher tier can be built over a lower one of
        -- the same family (upgrading it in place).
        wall_scrap = {
            label = 'Scrap wall', slot = 'edge', family = 'wall', tier = 1,
            cost = { { name = 'wood_planks', count = 4 }, { name = 'nails', count = 10 } },
            parts = {
                { model = 'prop_cons_plyboard_01', x = -0.75, z = 0.0, rz = 0.0 },
                { model = 'prop_cons_plyboard_01', x = 0.75, z = 0.0, ry = 3.0 },
                { model = 'prop_pallet_02a', x = 0.3, y = -0.2, z = 0.0, rx = 90.0 },
            },
        },
        wall_metal = {
            label = 'Metal wall', slot = 'edge', family = 'wall', tier = 2,
            cost = { { name = 'metal_sheet', count = 2 }, { name = 'scrap_metal', count = 2 }, { name = 'nails', count = 10 } },
            parts = {
                { model = 'prop_fnccorgm_02a', x = 0.0, z = 0.0 },
                { model = 'prop_cons_plyboard_01', x = -0.9, y = 0.08, z = 0.0, ry = -2.0 },
            },
        },
        wall_fortified = {
            label = 'Fortified wall', slot = 'edge', family = 'wall', tier = 3,
            cost = { { name = 'metal_sheet', count = 4 }, { name = 'scrap_metal', count = 4 }, { name = 'duct_tape', count = 2 } },
            parts = {
                { model = 'prop_fnccorgm_02a', x = 0.0, z = 0.0 },
                { model = 'prop_mb_sandblock_01', x = -0.75, y = -0.3, z = 0.0 },
                { model = 'prop_mb_sandblock_01', x = 0.75, y = -0.3, z = 0.0 },
            },
        },

        -- Doors and gates (grid). door: the opening; the leaf swings round
        -- `hinge` (metres from the middle). Only the owner's group opens them.
        door_scrap = {
            label = 'Scrap door', slot = 'edge', family = 'door', tier = 1,
            cost = { { name = 'wood_planks', count = 5 }, { name = 'nails', count = 15 }, { name = 'scrap_metal', count = 1 } },
            door = { hinge = -0.6, width = 1.2, height = 2.2 },
            parts = {
                { model = 'prop_cons_plyboard_01', x = -1.05, z = 0.0 },
                { model = 'prop_cons_plyboard_01', x = 1.05, z = 0.0 },
                { model = 'prop_cons_plyboard_01', x = 0.0, z = 0.0, door = true },
            },
        },
        door_metal = {
            label = 'Metal door', slot = 'edge', family = 'door', tier = 2,
            cost = { { name = 'metal_sheet', count = 3 }, { name = 'scrap_metal', count = 3 }, { name = 'nails', count = 10 } },
            door = { hinge = -0.6, width = 1.2, height = 2.2 },
            parts = {
                { model = 'prop_fnccorgm_02a', x = -1.05, z = 0.0 },
                { model = 'prop_fnccorgm_02a', x = 1.05, z = 0.0 },
                { model = 'prop_fnccorgm_02a', x = 0.0, z = 0.0, door = true },
            },
        },
        gate = {
            label = 'Gate (vehicles)', slot = 'edge', family = 'gate', tier = 1,
            cost = { { name = 'metal_sheet', count = 4 }, { name = 'scrap_metal', count = 6 }, { name = 'duct_tape', count = 2 } },
            door = { hinge = -1.5, width = 3.0, height = 2.4 },
            parts = {
                { model = 'prop_fnclink_02gate1', x = 0.0, z = 0.0, door = true },
            },
        },

        -- Free pieces: anywhere inside the claim, any direction.
        storage_small = {
            label = 'Storage crate', slot = 'free', max = 4,
            cost = { { name = 'wood_planks', count = 4 }, { name = 'nails', count = 10 } },
            stash = { width = 6, height = 5, maxWeight = 80 },
            parts = { { model = 'prop_box_wood02a' } },
        },
        storage_large = {
            label = 'Metal locker', slot = 'free', max = 2,
            cost = { { name = 'metal_sheet', count = 3 }, { name = 'scrap_metal', count = 4 } },
            stash = { width = 10, height = 6, maxWeight = 200 },
            parts = { { model = 'prop_toolchest_05' } },
        },
        workbench = {
            label = 'Workbench', slot = 'free', max = 1,
            cost = { { name = 'wood_planks', count = 6 }, { name = 'scrap_metal', count = 4 }, { name = 'nails', count = 20 } },
            station = 'workbench',     -- crafting.lua recipes with station = 'workbench'
            parts = { { model = 'prop_tool_bench02' } },
        },
        campfire = {
            label = 'Campfire', slot = 'free', max = 2,
            cost = { { name = 'wood_planks', count = 3 } },
            warmth = 10.0,             -- degrees of warmth within warmthRadius
            warmthRadius = 6.0,
            parts = { { model = 'prop_beach_fire' } },
        },
        sleeping_bag = {
            label = 'Sleeping bag', slot = 'free', max = 4,
            cost = { { name = 'rag', count = 6 }, { name = 'duct_tape', count = 1 } },
            respawn = true,            -- your group respawns here after dying
            parts = { { model = 'prop_skid_sleepbag_1' } },
        },
        rain_collector = {
            label = 'Rain collector', slot = 'free', max = 2,
            cost = { { name = 'metal_sheet', count = 1 }, { name = 'scrap_metal', count = 2 }, { name = 'duct_tape', count = 1 } },
            produces = { item = 'water_bottle', everyMinutes = 30, max = 4 },
            stash = { width = 2, height = 4, maxWeight = 10 },
            parts = { { model = 'prop_barrel_02a' } },
        },
    },
}
