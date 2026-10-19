-- Base building (module "basebuilding", resource wasteland_basebuilding).
--
-- The building pieces need props (3D models). By default they come from
-- wasteland_buildprops: free, original models made for Wasteland (wood, stone
-- and metal), included. Ensure it before wasteland_basebuilding.
--
-- The paid "sinor-buildingProps-v2" pack by SinorSystem (https://sinorsystem.tebex.io/)
-- still works if you own it: set propsResource = 'sinor-buildingProps-v2' and
-- use its model names (sinor_prop_wall_wood, ...).
--
-- YOUR OWN PROPS instead: stream them in a resource of your own (ensure it
-- before wasteland_basebuilding), set `propsResource` below to its name, and
-- change each piece's `model` (and the upgrade tiers') to your model names.
-- Snapping measures each model, so any sensible sizes work. GTA's own
-- props (names starting prop_ ...) work too: then set propsResource = ''.
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

    -- The resource with the building props ('' = none to check, e.g. GTA's
    -- own props). Only used to warn at start when it is not running.
    propsResource = 'wasteland_buildprops',

    -- radius: the claim (building, access). safeRadius: zombies stay out of
    -- this many metres around the cupboard (no spawning, chasing or hits; ones
    -- that wander in are removed) - so you can build in peace. 0 = off.
    -- safeRadius: zombies stay out of this many metres round a new tool
    -- cupboard, for safeMinutes (real time) after it is placed - time to build.
    -- After that the zone drops and zombies can come in and attack. 0 minutes
    -- = the zone never drops.
    cupboard = { piece = 'toolcupboard', radius = 40.0, minGap = 10.0, safeRadius = 20.0, safeMinutes = 60 },

    lockpick = {
        enabled = true,
        item = 'lockpick',          -- used up when the try fails
        pins = 4, zoneDegrees = 26, speed = 150, speedStep = 30,
        cooldownMs = 5000,
    },

    upkeep = {
        enabled = true,
        tickMinutes = 5,
        perPieceCostPerDay = { wood = 0.25, stone = 0.25, metal = 0.25 }, -- per piece per day (a 40-piece base: 10 a day)
        decayPerTick = 2,             -- health lost per tick by every piece of a material that is short
        supplyGrid = { width = 10, height = 10, maxWeight = 1000 },
        -- which item pays for which material
        items = { wood = 'wood_planks', stone = 'stone', metal = 'metal_sheet' },
    },

    -- Building without a tool cupboard (barricading an old building for a
    -- night): pieces of these categories can go anywhere nobody has claimed.
    -- They belong to whoever built them (and their group), have no upkeep and
    -- no zombie-free zone, and are gone after `hours` - unless a tool
    -- cupboard placed later claims them (then they stay like any other piece).
    freeBuild = { enabled = true, categories = { 'structure', 'door', 'garage', 'defense' }, hours = 12 },

    interact = { distance = 2.5 },    -- doors open with E within this distance
    targetDistance = 4.0,             -- Left Alt options (remove, upgrade, repair...)
    streamRadius = 150.0,
    refund = 0.5,                     -- removing gives back this share of the cost

    placement = {
        rotateStep = 45.0, fineRotateSpeed = 30.0, heightStep = 0.05,
        fineHeightSpeed = 0.15,       -- metres a second with the Up / Down arrows
        maxPlaceDistance = 15.0, snapDistance = 2.0, wallFacesOutward = true, snapOverlap = 0.0,
        -- Gaps between snapped pieces: metres each piece is pulled in, per piece
        -- (default snapOverlap). Tune in game with Ctrl+wheel while placing
        -- (remembered on that computer), then /bbsnap prints the values to copy here.
        overlap = {},
        -- Walls, doorways, window frames and half walls stand on the foundation
        -- edge (outer face flush with it), so two walls meet at a corner with
        -- no gap. false: outside the edge, as before.
        wallsInset = true,
    },

    categoryOrder = { 'structure', 'door', 'garage', 'defense', 'stash', 'cupboard' },
    categoryLabels = { structure = 'Structures', door = 'Doors', garage = 'Garage', defense = 'Defenses', stash = 'Storage', cupboard = 'Tool Cupboard' },

    pieces = {
        toolcupboard = { label = 'Tool Cupboard', model = 'wl_bp_toolcupboard', category = 'cupboard',
            cost = { wood_planks = 10, scrap_metal = 5 }, health = 500, material = 'wood' },
        foundation = { label = 'Foundation', model = 'wl_bp_foundation_wood', category = 'structure',
            cost = { wood_planks = 8 }, health = 500, material = 'wood' },
        wall = { label = 'Wall', model = 'wl_bp_wall_wood', category = 'structure', cost = { wood_planks = 6 }, health = 500, material = 'wood' },
        doorway = { label = 'Doorway', model = 'wl_bp_doorway_wood', category = 'structure', cost = { wood_planks = 5 }, health = 500, material = 'wood' },
        windowframe = { label = 'Window Frame', model = 'wl_bp_windowframe_wood', category = 'structure', cost = { wood_planks = 5 }, health = 500, material = 'wood' },
        halfwall = { label = 'Half Wall', model = 'wl_bp_halfwall_wood', category = 'structure', cost = { wood_planks = 4 }, health = 500, material = 'wood' },
        ceiling = { label = 'Ceiling', model = 'wl_bp_ceiling_wood', category = 'structure', cost = { wood_planks = 6 }, health = 500, material = 'wood' },
        frame = { label = 'Frame', model = 'wl_bp_frame_wood', category = 'structure', cost = { wood_planks = 5, metal_sheet = 1 }, health = 500, material = 'wood' },
        ramp = { label = 'Ramp', model = 'wl_bp_ramp_wood', category = 'structure', cost = { wood_planks = 5 }, health = 500, material = 'wood' },
        -- More floors: stairs stand on a foundation or a ceiling and go one floor
        -- up (leave the square above them open); a ladder hatch is a ceiling with
        -- an opening and a ladder: E at the ladder climbs up, E at the opening down.
        stairs = { label = 'Stairs', model = 'wl_bp_stairs_wood', category = 'structure', cost = { wood_planks = 14 }, health = 500, material = 'wood' },
        hatch = { label = 'Ladder Hatch', model = 'wl_bp_hatch_wood', category = 'structure', cost = { wood_planks = 8 }, health = 500, material = 'wood',
            family = 'ceiling', ladder = true },
        gateframe = { label = 'Gate Frame', model = 'wl_bp_gate_frame', category = 'structure', cost = { wood_planks = 20 }, health = 700, material = 'wood' },
        door = { label = 'Wooden Door', model = 'wl_bp_door_wood', category = 'door', cost = { wood_planks = 10 }, health = 600,
            material = 'wood', openAngleOffset = 100.0 },
        metaldoor = { label = 'Metal Door', model = 'wl_bp_door_metal', category = 'door', cost = { metal_sheet = 6 }, health = 1500,
            material = 'metal', openAngleOffset = 100.0, family = 'door', hidden = true },
        -- interactDistance: E works from this far (metres), also from a vehicle;
        -- passThrough: swings through players and vehicles instead of pushing them.
        gatedoor = { label = 'Gate Door', model = 'wl_bp_gate_door', category = 'door', cost = { wood_planks = 20, metal_sheet = 2 }, health = 700,
            material = 'wood', openAngleOffset = 100.0, interactDistance = 8.0, passThrough = true },
        -- Garage doors roll up when opened (openLift: metres; leave it out to use the door's own height).
        garagedoor = { label = 'Garage Door', model = 'wl_bp_garage_wood', category = 'garage', cost = { wood_planks = 20 }, health = 600,
            material = 'wood' },
        -- Window bars snap into a window frame (wood upgrades to metal).
        windowbar = { label = 'Window Bars', model = 'wl_bp_windowbar_wood', category = 'structure', cost = { wood_planks = 4 },
            health = 400, material = 'wood' },
        windowbar_metal = { label = 'Metal Window Bars', model = 'wl_bp_windowbar_metal', category = 'structure', health = 1200,
            material = 'metal', family = 'windowbar', hidden = true },

        -- Defenses (placed anywhere on your land). Zombies that walk into
        -- barbed wire or spikes are hurt (contactDamage a second) and slowed
        -- (slow: their speed share); every touch wears the piece
        -- (wearPerTouch). Sandbags are a tough wall zombies must break.
        -- altModels: tried in order when the game cannot spawn `model`.
        -- (GTA has no barbed wire coil that can be spawned - the coils are part of the map -
        -- so this is a chain-link fence with barbed wire on top.)
        barbedwire = { label = 'Barbed Wire Fence', model = 'prop_fnclink_04g', altModels = { 'prop_fnclink_09e', 'prop_fnclink_10a', 'prop_fnclink_05c' },
            category = 'defense', cost = { scrap_metal = 4, wood_planks = 2 }, health = 300, material = 'metal',
            contactDamage = 12, slow = 0.4, wearPerTouch = 4, touchRadius = 2.5 },
        -- scale: drawn this many times bigger (the look only)
        spikes = { label = 'Spike Strip', model = 'p_stinger_piece_01', scale = 2.0,
            category = 'defense', cost = { scrap_metal = 6 }, health = 400, material = 'metal',
            contactDamage = 25, slow = 0.8, wearPerTouch = 6, touchRadius = 2.5 },
        sandbags = { label = 'Sandbag Wall', model = 'v_ind_cf_flour', altModels = { 'prop_mb_sandblock_02', 'prop_conc_sacks_02a' },
            category = 'defense', cost = { stone = 10, rag = 4 }, health = 1500, material = 'stone' },

        stash_small = { label = 'Small Storage Box', model = 'wl_bp_stash_small', category = 'stash', cost = { wood_planks = 6, scrap_metal = 2 },
            health = 400, material = 'wood', grid = { width = 8, height = 6, maxWeight = 100 } },
        stash_large = { label = 'Large Storage Container', model = 'wl_bp_stash_large', category = 'stash', cost = { wood_planks = 15, metal_sheet = 4 },
            health = 600, material = 'wood', grid = { width = 12, height = 10, maxWeight = 400 } },
        weaponlocker = { label = 'Weapon Locker', model = 'wl_bp_weaponlocker', category = 'stash', cost = { wood_planks = 6, metal_sheet = 2 },
            health = 400, material = 'wood', grid = { width = 8, height = 5, maxWeight = 120 } },

        -- Upgrade tiers (reached through `upgrades`, not built directly)
        foundation_stone = { label = 'Stone Foundation', model = 'wl_bp_foundation_stone', category = 'structure', health = 1000, material = 'stone', family = 'foundation', hidden = true },
        foundation_metal = { label = 'Metal Foundation', model = 'wl_bp_foundation_metal', category = 'structure', health = 2000, material = 'metal', family = 'foundation', hidden = true },
        wall_stone = { label = 'Stone Wall', model = 'wl_bp_wall_stone', category = 'structure', health = 1000, material = 'stone', family = 'wall', hidden = true },
        wall_metal = { label = 'Metal Wall', model = 'wl_bp_wall_metal', category = 'structure', health = 2000, material = 'metal', family = 'wall', hidden = true },
        doorway_stone = { label = 'Stone Doorway', model = 'wl_bp_doorway_stone', category = 'structure', health = 1000, material = 'stone', family = 'doorway', hidden = true },
        doorway_metal = { label = 'Metal Doorway', model = 'wl_bp_doorway_metal', category = 'structure', health = 2000, material = 'metal', family = 'doorway', hidden = true },
        windowframe_stone = { label = 'Stone Window Frame', model = 'wl_bp_windowframe_stone', category = 'structure', health = 1000, material = 'stone', family = 'windowframe', hidden = true },
        windowframe_metal = { label = 'Metal Window Frame', model = 'wl_bp_windowframe_metal', category = 'structure', health = 2000, material = 'metal', family = 'windowframe', hidden = true },
        halfwall_stone = { label = 'Stone Half Wall', model = 'wl_bp_halfwall_stone', category = 'structure', health = 1000, material = 'stone', family = 'halfwall', hidden = true },
        halfwall_metal = { label = 'Metal Half Wall', model = 'wl_bp_halfwall_metal', category = 'structure', health = 2000, material = 'metal', family = 'halfwall', hidden = true },
        ceiling_stone = { label = 'Stone Ceiling', model = 'wl_bp_ceiling_stone', category = 'structure', health = 1000, material = 'stone', family = 'ceiling', hidden = true },
        ceiling_metal = { label = 'Metal Ceiling', model = 'wl_bp_ceiling_metal', category = 'structure', health = 2000, material = 'metal', family = 'ceiling', hidden = true },
        frame_metal = { label = 'Metal Frame', model = 'wl_bp_frame_metal', category = 'structure', health = 2000, material = 'metal', family = 'frame', hidden = true },
        ramp_metal = { label = 'Metal Ramp', model = 'wl_bp_ramp_metal', category = 'structure', health = 2000, material = 'metal', family = 'ramp', hidden = true },
        stairs_stone = { label = 'Stone Stairs', model = 'wl_bp_stairs_stone', category = 'structure', health = 1000, material = 'stone', family = 'stairs', hidden = true },
        stairs_metal = { label = 'Metal Stairs', model = 'wl_bp_stairs_metal', category = 'structure', health = 2000, material = 'metal', family = 'stairs', hidden = true },
        hatch_stone = { label = 'Stone Ladder Hatch', model = 'wl_bp_hatch_stone', category = 'structure', health = 1000, material = 'stone', family = 'ceiling', ladder = true, hidden = true },
        hatch_metal = { label = 'Metal Ladder Hatch', model = 'wl_bp_hatch_metal', category = 'structure', health = 2000, material = 'metal', family = 'ceiling', ladder = true, hidden = true },
    },

    upgrades = {
        windowbar = { next = 'windowbar_metal', cost = { metal_sheet = 3 } },
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
        stairs = { next = 'stairs_stone', cost = { stone = 10 } },
        stairs_stone = { next = 'stairs_metal', cost = { metal_sheet = 6 } },
        hatch = { next = 'hatch_stone', cost = { stone = 7 } },
        hatch_stone = { next = 'hatch_metal', cost = { metal_sheet = 4 } },
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
        -- Zombies hit walls, doors and gates that stand between them and a
        -- player (needs wasteland_zombies ai.barricades). Damage per hit by
        -- material (0 = they cannot hurt it); the owner is told at most every
        -- noticeMinutes. pieces: the kinds of pieces they attack.
        zombies = { enabled = true, damage = { wood = 4, stone = 2, metal = 1 }, noticeMinutes = 3,
            pieces = { 'wall', 'doorway', 'windowframe', 'halfwall', 'door', 'gateframe', 'gatedoor', 'garagedoor', 'windowbar', 'sandbags' } },
        repair = {
            amount = { wood = 250, stone = 300, metal = 350 },
            cost = { wood = { item = 'wood_planks', count = 3 }, stone = { item = 'stone', count = 2 }, metal = { item = 'metal_sheet', count = 1 } },
        },
    },
}
