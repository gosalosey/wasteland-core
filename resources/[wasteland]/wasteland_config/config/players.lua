-- Wasteland Core :: players (module "players", resource wasteland_players)
-- Accounts, sessions and characters. Every setting is optional; the value
-- shown is the default.
return {
    -- Identifier that defines an account: 'license' (Rockstar license) or 'license2'.
    identifier = 'license',

    -- Character slots per account. 1 - 10.
    maxCharacters = 5,

    -- When an account connects while it is already connected:
    --   'kick_old'   drop the old session, save it, then let the new one in
    --   'reject_new' refuse the new connection
    --   'test_second_account'  TESTING ONLY: the second game (FiveM started
    --                with -cl2) plays as a separate account with its own
    --                characters. Never use this on a public server.
    duplicateSession = 'kick_old',

    -- How long (seconds) a connection waits for the previous session of the
    -- same account to finish saving before it is refused. 1 - 120.
    sessionReleaseTimeoutSeconds = 20,

    -- Seconds between automatic saves of every loaded character. 10 - 3600.
    -- Characters are also saved when they unload, when the player leaves and
    -- when the server shuts down via txAdmin.
    saveIntervalSeconds = 60,

    -- Remember where each character was, and how often (seconds) to sample
    -- the position in memory between saves. 1 - 600.
    savePosition = true,
    positionSampleSeconds = 10,

    -- After `restart wasteland_players`, wait this long (ms) before reloading
    -- characters so the previous instance's final saves have landed. 0 - 10000.
    restoreDelayMs = 1000,

    -- Largest value (bytes of JSON) a module may store per character and key.
    maxCharacterDataBytes = 65536,

    -- Let players delete their own characters (they must type the first name).
    allowCharacterDeletion = true,

    -- Chat command: /character list | create <first> <last> | select <slot> | delete <slot> <first>
    commandName = 'character',

    -- Rules for first and last names. `pattern` is a Lua pattern.
    names = {
        minLength = 2,
        maxLength = 20,
        pattern = "^[%a][%a' %-]*$",
    },

    -- Where new characters start (Sandy Shores airfield).
    defaultSpawn = vector3(1734.0, 3297.0, 41.2),
    defaultHeading = 195.0,
}
