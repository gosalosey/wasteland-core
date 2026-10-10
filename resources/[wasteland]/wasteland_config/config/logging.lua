-- Wasteland Core :: logging
return {
    -- Minimum level printed to the server console:
    -- 'debug' | 'info' | 'warn' | 'error' | 'off'
    level = 'info',

    -- Per-module overrides, e.g. { registry = 'debug', template = 'warn' }
    moduleLevels = {},

    -- Use FiveM console colour codes (^1 red, ^3 yellow ...).
    colors = true,

    -- Number of recent warnings/errors kept for `wasteland issues`. 10 - 5000.
    recentBufferSize = 200,
}
