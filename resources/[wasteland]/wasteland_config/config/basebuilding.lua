-- Base building (module "basebuilding", resource wasteland_basebuilding).
--
-- NEEDS the building props pack "sinor-buildingProps-v2" on the server (it is
-- not part of Wasteland Core: it is a licensed asset pack, tied to the Cfx
-- account that owns it). Put it in resources and `ensure` it before
-- wasteland_basebuilding.
--
-- How it works for players:
--   * Use a Building plan (craft it, or buy it) to open the build menu.
--   * Place a Tool Cupboard first: it claims `cupboard.radius` metres. Only
--     its owner, players they authorize, and the owner's group (/group) can
--     build, open doors and storage, repair and remove there.
--   * Walls, doorways, ceilings... snap to foundations and to each other.
--     E places, the mouse wheel turns, Shift+wheel raises/lowers, Tab turns
--     snapping off, Ctrl+wheel closes gaps, Backspace cancels. Ramps: R turns
--     them up/down, Q puts them beside the foundation (walk up onto it) or on
--     top of it.
--   * Upgrade pieces wood -> stone -> metal; repair damaged ones (hold Left
--     Alt on a piece). Doors open with E when you stand next to them.
--   * Upkeep: keep wood planks / stone / metal sheets in the cupboard's
--     supplies; every piece costs some each day. Short of a material, the
--     pieces of that material slowly decay.
--   * Raiding: explosives damage pieces (wood also takes melee hits); doors
--     and storage can be lockpicked (the lockpick minigame). Owners are told
--     when their base is lockpicked (also when they were offline).
--
-- Costs: { item = count }, item names from inventory.lua.
return {
    buildItem = 'building_plan',

    -- radius: the claim (building, access). safeRadius: zombies stay out of
    -- this many metres around the cupboard (no spawning, chasing or hits; ones
    -- that wander in are removed) - so you can build in peace. 0 = off.
    cupboard = { piece = 'toolcupboard', radius = 40.0, minGap = 10.0, safeRadius = 12.0 },

    lockpick = {
        enabled = true,
        item = 'lockpick',          -- used up when the try fails
        pins = 4, zoneDegrees = 26, speed = 150, speedStep = 30,
        cooldownMs = 5000,
    },

    upkeep = {
        enabled = true,
        tickMinutes = 5,
        perPieceCostPerDay = { wood = 1, stone = 1, metal = 1 },
        decayPerTick = 2,             -- health lost per tick by every piece of a material that is short
        supplyGrid = { width = 8, height = 6, maxWeight = 300 },
        -- which item pays for which material
        items = { wood = 'wood_planks', stone = 'stone', metal = 'metal_sheet' },
    },

    interact = { distance = 2.5 },    -- doors open with E within this distance
    targetDistance = 4.0,             -- Left Alt options (remove, upgrade, repair...)
    streamRadius = 150.0,
    refund = 0.5,                     -- removing gives back this share of the cost

    placement = {
        rotateStep = 45.0, fineRotateSpeed = 30.0, heightStep = 0.05,
        maxPlaceDistance = 15.0, snapDistance = 2.0, wallFacesOutward = true, snapOverlap = 0.15,
        -- Gaps between snapped pieces: metres each piece is pulled in, per piece
        -- (default snapOverlap). Tune in game with Ctrl+wheel while placing
        -- (remembered on that computer), then /bbsnap prints the values to copy here.
        overlap = {},
        -- Walls, doorways, window frames and half walls stand on the foundation
        -- edge (outer face flush with it), so two walls meet at a corner with
        -- no gap. false: outside the edge, as before.
        wallsInset = true,
    },

    categoryOrder = { 'structure', 'door', 'garage', 'stash', 'cupboard' },
    categoryLabels = { structure = 'Structures', door = 'Doors', garage = 'Garage', stash = 'Storage', cupboard = 'Tool Cupboard' },

    pieces = {
        toolcupboard = { label = 'Tool Cupboard', model = 'sinor_prop_toolcupboard', category = 'cupboard',
            cost = { wood_planks = 10, scrap_metal = 5 }, health = 500, material = 'wood' },
        foundation = { label = 'Foundation', model = 'sinor_prop_foundation_square_wood', category = 'structure',
            cost = { wood_planks = 8 }, health = 500, material = 'wood' },
        wall = { label = 'Wall', model = 'sinor_prop_wall_wood', category = 'structure', cost = { wood_planks = 6 }, health = 500, material = 'wood' },
        doorway = { label = 'Doorway', model = 'sinor_prop_doorway_wood', category = 'structure', cost = { wood_planks = 5 }, health = 500, material = 'wood' },
        windowframe = { label = 'Window Frame', model = 'sinor_prop_windowframe_wood', category = 'structure', cost = { wood_planks = 5 }, health = 500, material = 'wood' },
        halfwall = { label = 'Half Wall', model = 'sinor_prop_halfwall_wood', category = 'structure', cost = { wood_planks = 4 }, health = 500, material = 'wood' },
        ceiling = { label = 'Ceiling', model = 'sinor_prop_ceiling_square_wood', category = 'structure', cost = { wood_planks = 6 }, health = 500, material = 'wood' },
        frame = { label = 'Frame', model = 'sinor_prop_frame_wood', category = 'structure', cost = { wood_planks = 5, metal_sheet = 1 }, health = 500, material = 'wood' },
        ramp = { label = 'Ramp', model = 'sinor_prop_ramp_wood', category = 'structure', cost = { wood_planks = 5 }, health = 500, material = 'wood' },
        gateframe = { label = 'Gate Frame', model = 'sinor_prop_gate_frame', category = 'structure', cost = { wood_planks = 20 }, health = 700, material = 'wood' },
        door = { label = 'Wooden Door', model = 'sinor_prop_door_wood', category = 'door', cost = { wood_planks = 10 }, health = 600,
            material = 'wood', openAngleOffset = 100.0 },
        metaldoor = { label = 'Metal Door', model = 'sinor_prop_door_metal', category = 'door', cost = { metal_sheet = 6 }, health = 1500,
            material = 'metal', openAngleOffset = 100.0, family = 'door', hidden = true },
        gatedoor = { label = 'Gate Door', model = 'sinor_prop_gate_door', category = 'door', cost = { wood_planks = 20, metal_sheet = 2 }, health = 700,
            material = 'wood', openAngleOffset = 100.0 },
        -- Garage doors roll up when opened (openLift: metres; leave it out to use the door's own height).
        garagedoor = { label = 'Garage Door', model = 'sinor_prop_garage_wood', category = 'garage', cost = { wood_planks = 20 }, health = 600,
            material = 'wood' },
        stash_small = { label = 'Small Storage Box', model = 'prop_cs_lester_crate', category = 'stash', cost = { wood_planks = 6, scrap_metal = 2 },
            health = 400, material = 'wood', grid = { width = 8, height = 6, maxWeight = 100 } },
        stash_large = { label = 'Large Storage Container', model = 'v_res_tre_storagebox', category = 'stash', cost = { wood_planks = 15, metal_sheet = 4 },
            health = 600, material = 'wood', grid = { width = 12, height = 10, maxWeight = 400 } },
        weaponlocker = { label = 'Weapon Locker', model = 'prop_gun_case_02', category = 'stash', cost = { wood_planks = 6, metal_sheet = 2 },
            health = 400, material = 'wood', grid = { width = 8, height = 5, maxWeight = 120 } },

        -- Upgrade tiers (reached through `upgrades`, not built directly)
        foundation_stone = { label = 'Stone Foundation', model = 'sinor_prop_foundation_square_stone', category = 'structure', health = 1000, material = 'stone', family = 'foundation', hidden = true },
        foundation_metal = { label = 'Metal Foundation', model = 'sinor_prop_foundation_square_metal', category = 'structure', health = 2000, material = 'metal', family = 'foundation', hidden = true },
        wall_stone = { label = 'Stone Wall', model = 'sinor_prop_wall_stone', category = 'structure', health = 1000, material = 'stone', family = 'wall', hidden = true },
        wall_metal = { label = 'Metal Wall', model = 'sinor_prop_wall_metal', category = 'structure', health = 2000, material = 'metal', family = 'wall', hidden = true },
        doorway_stone = { label = 'Stone Doorway', model = 'sinor_prop_doorway_stone', category = 'structure', health = 1000, material = 'stone', family = 'doorway', hidden = true },
        doorway_metal = { label = 'Metal Doorway', model = 'sinor_prop_doorway_metal', category = 'structure', health = 2000, material = 'metal', family = 'doorway', hidden = true },
        windowframe_stone = { label = 'Stone Window Frame', model = 'sinor_prop_windowframe_stone', category = 'structure', health = 1000, material = 'stone', family = 'windowframe', hidden = true },
        windowframe_metal = { label = 'Metal Window Frame', model = 'sinor_prop_windowframe_metal', category = 'structure', health = 2000, material = 'metal', family = 'windowframe', hidden = true },
        halfwall_stone = { label = 'Stone Half Wall', model = 'sinor_prop_halfwall_stone', category = 'structure', health = 1000, material = 'stone', family = 'halfwall', hidden = true },
        halfwall_metal = { label = 'Metal Half Wall', model = 'sinor_prop_halfwall_metal', category = 'structure', health = 2000, material = 'metal', family = 'halfwall', hidden = true },
        ceiling_stone = { label = 'Stone Ceiling', model = 'sinor_prop_ceiling_square_stone', category = 'structure', health = 1000, material = 'stone', family = 'ceiling', hidden = true },
        ceiling_metal = { label = 'Metal Ceiling', model = 'sinor_prop_ceiling_square_metal', category = 'structure', health = 2000, material = 'metal', family = 'ceiling', hidden = true },
        frame_metal = { label = 'Metal Frame', model = 'sinor_prop_frame_metal', category = 'structure', health = 2000, material = 'metal', family = 'frame', hidden = true },
        ramp_metal = { label = 'Metal Ramp', model = 'sinor_prop_ramp_metal', category = 'structure', health = 2000, material = 'metal', family = 'ramp', hidden = true },
    },

    upgrades = {
        foundation = { next = 'foundation_stone', cost = { stone = 10 } },
        foundation_stone = { next = 'foundation_metal', cost = { metal_sheet = 6 } },
        wall = { next = 'wall_stone', cost = { stone = 8 } },
        wall_stone = { next = 'wall_metal', cost = { metal_sheet = 5 } },
        doorway = { next = 'doorway_stone', cost = { stone = 7 } },
        doorway_stone = { next = 'doorway_metal', cost = { metal_sheet = 4 } },
        windowframe = { next = 'windowframe_stone', cost = { stone = 7 } },
        windowframe_stone = { next = 'windowframe_metal', cost = { metal_sheet = 4 } },
        halfwall = { next = 'halfwall_stone', cost = { stone = 6 } },
        halfwall_stone = { next = 'halfwall_metal', cost = { metal_sheet = 3 } },
        ceiling = { next = 'ceiling_stone', cost = { stone = 8 } },
        ceiling_stone = { next = 'ceiling_metal', cost = { metal_sheet = 5 } },
        frame = { next = 'frame_metal', cost = { metal_sheet = 4 } },
        ramp = { next = 'ramp_metal', cost = { metal_sheet = 4 } },
        door = { next = 'metaldoor', cost = { metal_sheet = 6 } },
    },

    raid = {
        enabled = true,
        -- damage per explosion type (0 grenade, 2 sticky bomb, 3 molotov, 4 rocket, 43 pipe bomb)
        explosionDamage = {
            wood = { [0] = 30, [2] = 250, [3] = 100, [4] = 250, [43] = 250 },
            stone = { [0] = 30, [2] = 200, [4] = 200, [43] = 200 },
            metal = { [2] = 200, [4] = 200, [43] = 200 },
        },
        explosionRadius = 4.0,
        melee = { enabled = true, cooldownMs = 850, woodDamage = 5 },   -- wood only
        repair = {
            amount = { wood = 250, stone = 300, metal = 350 },
            cost = { wood = { item = 'wood_planks', count = 3 }, stone = { item = 'stone', count = 2 }, metal = { item = 'metal_sheet', count = 1 } },
        },
    },
}
