-- Wasteland Core :: module activation
-- Turn modules on or off without touching their code. A disabled module's
-- resource may still be started; it will register but never initialise.
-- Modules that depend on a disabled module will fail with a clear reason.
return {
    enabled = {
        -- Development template / SDK example. Safe to disable on live servers.
        template = true,

        -- Persistence (Milestone 2). Required by every gameplay module.
        database = true,
        players  = true,

        -- Screens and the character creator (Milestone 3A).
        ui         = true,
        appearance = true,

        -- Inventory (Milestone 3B).
        inventory  = true,

        -- Survival, HUD, death and respawn (Milestone 4).
        survival   = true,

        -- Empty, silent world with one clock and weather; admin panel.
        world      = true,
        admin      = true,

        -- Weapons (Milestone 5A).
        weapons    = true,

        -- Zombies (Milestone 5B).
        zombies    = true,

        -- Looting (Milestone 6).
        loot       = true,

        -- Camps: safe zones and traders (Milestone 7A).
        camps      = true,

        -- Crafting (Milestone 7B).
        crafting   = true,

        -- Quests (Milestone 8).
        quests     = true,

        -- Persistent vehicles (Milestone 9).
        vehicles   = true,

        -- Tailors: restyle worn clothes for cash.
        tailor     = true,

        -- Supply drops (also the SDK example module, docs/SDK_GUIDE.md).
        supplydrops = true,

        -- World events: helicopter crashes, convoys, bandit hideouts, hordes.
        events     = true,

        -- Player groups: names, invites, members on the map.
        groups     = true,

        -- Planned modules (added in later milestones). Listing a module here
        -- before its resource exists makes the status report show it as
        -- "missing", so they stay commented out until they are delivered.
    },

    -- What to do with a module that registers but is not listed above:
    -- 'enable' (default; makes add-on modules work out of the box) or 'disable'.
    unlisted = 'enable',
}
