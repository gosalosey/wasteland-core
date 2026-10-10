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

        -- Planned modules (added in later milestones). Listing a module here
        -- before its resource exists makes the status report show it as
        -- "missing", so they stay commented out until they are delivered.
        -- inventory = true,   -- Milestone 3
        -- survival  = true,   -- Milestone 4
        -- zombies   = true,   -- Milestone 5
        -- loot      = true,   -- Milestone 6
        -- world     = true,   -- Milestone 7
        -- quests    = true,   -- Milestone 8
        -- vehicles  = true,   -- Milestone 9
    },

    -- What to do with a module that registers but is not listed above:
    -- 'enable' (default; makes add-on modules work out of the box) or 'disable'.
    unlisted = 'enable',
}
