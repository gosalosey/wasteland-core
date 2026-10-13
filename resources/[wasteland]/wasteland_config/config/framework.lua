-- Wasteland Core :: framework settings
-- Every setting is optional; the value shown is the default.
-- Changes take effect after restarting wasteland_core.
return {
    -- Display name used in logs, UI and diagnostics.
    name = 'Wasteland Core',

    -- Lowercase identifier. Also the admin console command name
    -- (e.g. `wasteland status`). Letters, digits and underscores only.
    shortName = 'wasteland',

    -- Seconds to wait for enabled modules to register at startup before
    -- reporting missing or stuck modules. 1 - 600.
    startupTimeoutSeconds = 30,

    -- ACE permission that grants access to admin commands.
    -- server.cfg example:  add_ace group.admin wasteland.admin allow
    adminAce = 'wasteland.admin',

    -- Run the ordered module shutdown when txAdmin announces a scheduled
    -- restart or shutdown (recommended: protects data from Milestone 2 on).
    shutdownOnTxAdminRestart = true,

    -- When you restart a resource (e.g. `restart wasteland_core` or
    -- `restart wasteland_database`), FiveM also stops every module resource
    -- that depends on it but does not start them again. With this on, the
    -- core restarts exactly the modules that were running before.
    restartModulesAfterCoreRestart = true,

    -- Update check: after the server starts (and every few hours) the
    -- console shows a banner when GitHub has a newer Wasteland Core than the
    -- one installed (resources/[wasteland]/VERSION.txt, written by the
    -- updater); admins also get a line in chat when they join.
    updateCheck = {
        enabled = true,
        repo = 'gosalosey/wasteland-core',
        branch = 'main',
        everyHours = 6,
    },

    -- Client requests that fail validation (bad data, spam, invalid sender)
    -- are always rejected and logged. Optionally kick repeat offenders.
    security = {
        -- Kick after this many rejected requests within the window.
        -- 0 = never kick (only log). Try 20 on a live server.
        kickAfterViolations = 0,
        -- Window in seconds for counting rejected requests. 1 - 3600.
        violationWindowSeconds = 60,
    },
}
