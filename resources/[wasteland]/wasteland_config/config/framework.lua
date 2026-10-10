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

    -- When you run `restart wasteland_core`, FiveM also stops every module
    -- resource that depends on it but does not start them again. With this
    -- on, the core restarts exactly the modules that were running before.
    restartModulesAfterCoreRestart = true,
}
