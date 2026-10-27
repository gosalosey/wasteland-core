-- Supply drops (module "supplydrops", resource wasteland_supplydrops - also
-- the SDK example module, see docs/SDK_GUIDE.md).
--
-- Every intervalMinutes (while at least minPlayers are online) a crate comes
-- down at one of the points below: a map blip, a message for everyone and
-- red smoke. The first player to open it fills it; everyone shares what is
-- inside. It is gone after lifetimeMinutes. Admins: /supplydrop (random
-- point) or /supplydrop here.
--
-- VERIFY IN-GAME: points are picked from the map (open ground).
return {
    intervalMinutes = 45,
    lifetimeMinutes = 20,
    maxActive = 1,
    minPlayers = 1,
    minGap = 300,          -- metres between two drops that are out at once

    -- What is inside: a loot.lua table, or "" to use `items` and `rolls`.
    lootTable = 'supplydrop',
    grid = { 10, 8 },      -- the crate's size (cells), room for a full drop
    rolls = { 3, 5 },
    items = {
        { name = 'ammo_12g', min = 10, max = 25, weight = 10 },
        { name = 'bandage', min = 2, max = 4, weight = 8 },
        { name = 'antibiotics', min = 1, max = 2, weight = 4 },
        { name = 'water_bottle', min = 2, max = 3, weight = 8 },
        { name = 'canned_beans', min = 2, max = 3, weight = 8 },
        { name = 'armor_plate', min = 1, max = 1, weight = 2 },
        { name = 'scrap_pipe_shotgun', min = 1, max = 1, weight = 1 },
    },

    points = {
        { x = 1733.0, y = 3275.0, z = 41.1, label = 'the Sandy Shores airfield' },
        { x = 2135.0, y = 4782.0, z = 40.9, label = 'the Grapeseed airstrip' },
        { x = 1360.0, y = 3140.0, z = 40.4, label = 'the Grand Senora desert' },
        { x = -126.0, y = 6290.0, z = 31.4, label = 'Paleto Bay' },
        { x = 1180.0, y = 2650.0, z = 37.8, label = 'Harmony' },
        { x = -1120.0, y = 4920.0, z = 218.0, label = 'the Altruist hills' },
        { x = 2550.0, y = 2600.0, z = 37.9, label = 'the quarry road' },
        { x = 330.0, y = -1590.0, z = 29.3, label = 'Strawberry' },
    },
}
