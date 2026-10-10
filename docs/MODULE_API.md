# Module API and SDK (core api 1.1.0)

This is the stable interface for writing Wasteland modules. Anything not documented here is internal and may change.

## Quick start: a new module

1. Copy `resources/[wasteland]/wasteland_template` to `resources/[wasteland]/wasteland_mymodule`.
2. In `server/main.lua`, set `name = 'mymodule'` and write your `onInit` and `onShutdown`.
3. If you need settings, create `wasteland_config/config/mymodule.lua` and declare a schema.
4. Add `ensure wasteland_mymodule` to server.cfg after `wasteland_core`.
5. Optionally list it in `wasteland_config/config/modules.lua` (`mymodule = true`).

fxmanifest.lua:

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'
version '1.0.0'
dependency 'wasteland_core'
server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}
```

server/main.lua:

```lua
local M = Wasteland.DefineModule({
    name = 'mymodule',            -- required, [a-z][a-z0-9_]*, unique
    version = '1.0.0',            -- required, semver
    api = '1.0.0',                -- optional interface version (defaults to version)
    description = 'What it does',
    core = '^1.0.0',              -- required core api range (SDK default ^1.0.0)
    dependencies = { inventory = '^1.0.0' },      -- must be running first
    optionalDependencies = { quests = '^1.0.0' }, -- waited for only if registered
    async = false,                -- true: call M.ready() when setup finishes
    config = {
        file = 'mymodule.lua',    -- in wasteland_config/config/
        optional = true,          -- missing file => defaults (+ warning)
        schema = { type = 'table', fields = {
            interval = { type = 'integer', default = 30, min = 1, max = 3600,
                         description = 'Seconds between ticks' },
        } },
    },
    onInit = function(M, ctx)
        -- M.config is the validated config (defaults applied).
        -- ctx.framework = FrameworkInfo
        -- Return false, 'reason' (or raise an error) to fail.
    end,
    onShutdown = function(M, reason)
        -- Undo everything onInit did. Must be safe to call once per init.
        -- reason: 'resource_stop' | 'core_stopped' | 'server_shutdown' |
        --         'dependency_unavailable:<name>' | 'init_failed'
    end,
})
```

### The module handle `M`

| Field / function | Meaning |
|---|---|
| `M.name` | module name |
| `M.config` | validated config table (set before `onInit`) |
| `M.framework` | FrameworkInfo at init time |
| `M.active` | `true` between init and shutdown |
| `M.log:debug/info/warn/error(fmt, ...)` | logging through the core (central levels apply) |
| `M.ready()` | async modules: report successful initialisation |
| `M.fail(reason)` | report failure (running modules are stopped and dependents cascaded) |
| `M.setHealth(status, detail)` | running modules: `'degraded'` with a reason, or `'ok'` (api 1.1) |
| `M.netEvent(name, opts, handler)` | register a guarded client → server event (api 1.1, see below) |
| `M.register()` | re-register manually (normally automatic) |
| `M.registered`, `M.registerError` | outcome of the last registration attempt |

### Rules for module authors

* `onInit` and `onShutdown` must be symmetric: init may run again after a shutdown (for example, when a dependency restarts). Use a token to stop threads, as the template shows.
* Do not `Citizen.Wait` inside `onInit`. Start a thread, set `async = true` and call `M.ready()`.
* Never read another module's files or globals. Use its exports and events.
* The SDK already handles your own resource stopping and core restarts (it re-registers automatically).

### Guarded net events (`M.netEvent`)

Client → server events are the only network entry points, and every one goes through the guard. Never use `RegisterNetEvent` directly in a module.

```lua
M.netEvent('wasteland:shop:server:buy', {
    args = {                                   -- one schema node per argument (config schema DSL)
        { type = 'string', required = true, pattern = '^[a-z_]+$', maxLength = 32 },
        { type = 'integer', required = true, min = 1, max = 10 },
    },
    rateLimit = { burst = 3, perSecond = 1 },  -- default { burst = 10, perSecond = 5 }
}, function(source, item, count)
    -- runs only for valid input from a connected player while the module is running
end)
```

The name must be `wasteland:<module>:server:<action>`. The guard checks these, in order:

1. The sender is a connected player.
2. The module is running. Events that arrive while it is down are dropped.
3. A token-bucket rate limit, per player and event.
4. No more arguments than declared, and each argument is valid against its schema. Defaults are applied, and unknown table keys are dropped.

Rejections are logged (at most once per 10 s per player, event and kind). They are reported to the core as `wasteland:core:netViolation`, which kicks a player after `framework.security.kickAfterViolations` rejections (0, the default, never kicks). A handler that raises an error is logged and does not affect other events. The handler still has to check anything that depends on game state, such as ownership and distance.

## Configuration schema DSL

Schemas are plain data (no functions). Node fields:

| Field | Applies to | Meaning |
|---|---|---|
| `type` | all | `any` `string` `number` `integer` `boolean` `enum` `table` `array` `map` `vector3` |
| `default` | all | value used when absent (deep-copied) |
| `required` | all | absent with no default → error |
| `description` | all | documentation |
| `min`, `max` | number, integer | inclusive bounds |
| `minLength`, `maxLength`, `pattern` | string | length and Lua pattern |
| `values` | enum | allowed values (list) |
| `fields`, `allowUnknown` | table | child nodes; unknown keys warn unless `allowUnknown` |
| `nullable` | table | an absent table stays `nil` instead of `{}` |
| `items`, `minItems`, `maxItems` | array | element node and size |
| `keys`, `values` | map | key node (default string) and value node |

Absent tables are materialised as `{}` so nested defaults apply. Schemas are checked when a module registers, so an invalid schema or invalid default is rejected with a precise message.

## Core exports (server)

Call as `exports.wasteland_core:Name(...)`. The caller's resource is identified by the platform (`GetInvokingResource`), not by arguments.

| Export | Returns | Notes |
|---|---|---|
| `RegisterModule(definition)` | `ok, err` | Normally called by the SDK |
| `ReportModuleReady(name)` | `ok, err` | Only the owning resource; only while `initializing` |
| `ReportModuleFailed(name, reason)` | `ok, err` | Only the owning resource |
| `ReportModuleHealth(name, status, detail)` | `ok, err` | api 1.1. `'ok'` or `'degraded'`; only the owning resource; shown in `status` |
| `GetModuleStatus(name)` | ModuleStatus or `nil` | |
| `GetModuleStatuses()` | ModuleStatus[] sorted by name | |
| `IsModuleRunning(name)` | boolean | |
| `GetModuleConfig(name)` | config copy or `nil` | Validated config of any module |
| `GetFrameworkInfo()` | FrameworkInfo | |
| `IsReady()` | boolean | Startup window finished |
| `Log(module, level, message)` | boolean | level: debug/info/warn/error |
| `GetRecentIssues(limit)` | records `{time, module, level, message, source}` | Recent warnings and errors |

## Core events (server-local, `AddEventHandler`)

| Event | Arguments | When |
|---|---|---|
| `wasteland:core:booting` | FrameworkInfo | Core loaded (also in config_error) |
| `wasteland:core:frameworkState` | state, previousState | Framework state change |
| `wasteland:core:moduleState` | name, state, previousState, reason | Any module state change |
| `wasteland:core:ready` | FrameworkInfo | Startup window finished |
| `wasteland:core:shutdown` | reason | Before modules are shut down |
| `wasteland:core:moduleHealth` | name, status, previousStatus, detail | A module reported a health change (api 1.1) |
| `wasteland:core:netViolation` | source, module, eventName, kind, detail | The guard rejected a client event; kind is `source`, `rate` or `payload` (api 1.1) |

States: framework `booting | config_error | ready | shutting_down | stopped`; module `waiting | initializing | running | failed | disabled | stopped`. A running module also has a health: `ok` or `degraded` (with a detail).

ModuleStatus (api 1.1) adds `health` and `healthDetail`.

## Admin command

`wasteland <subcommand>` (the name follows `framework.shortName`). Available from the server console or to players with the `wasteland.admin` ACE. Output for players appears in F8.

| Subcommand | Effect |
|---|---|
| `status` | framework and module table |
| `module <name>` | details, dependencies, config warnings |
| `config validate` | validate every config file without applying anything |
| `config reload` | in config_error: retry startup; otherwise validate only |
| `issues [n]` | recent warnings and errors |
| `version` | framework version |

To grant the ACE in server.cfg: `add_ace group.admin wasteland.admin allow`.

## Database (`wasteland_database`, database api 0.1)

Modules never call a database driver directly. They include the library and declare the dependency:

```lua
-- fxmanifest.lua
dependencies { 'wasteland_core', 'wasteland_database' }
server_scripts {
    '@wasteland_core/sdk/module.lua',
    '@wasteland_database/lib/db.lua',
    'server/main.lua',
}
-- module definition
dependencies = { database = '^0.1.0' },
```

Call these from a thread or an event handler, because they wait for the answer. Every function returns `value, err`. Check `err`, not the value: a query can legitimately return `nil`.

| Function | Returns |
|---|---|
| `WDB.query(sql, params)` | list of rows (`{ column = value }`) |
| `WDB.single(sql, params)` | first row or `nil` |
| `WDB.scalar(sql, params)` | first column of the first row or `nil` |
| `WDB.insert(sql, params)` | insert id |
| `WDB.update(sql, params)` | affected rows |
| `WDB.transaction({ { sql, params }, ... })` | `true`; all or nothing |
| `WDB.migrate(moduleName, migrations)` | `{ applied, version }` |
| `WDB.isUp()` | boolean, no waiting |

* Use `?` placeholders and pass values in `params`. Never build SQL from player input.
* Read timestamps with `UNIX_TIMESTAMP(col)` so you always get a number.
* While the database is down, every call fails at once with `database unavailable: ...`. A call that gets no answer fails after `database.queryTimeoutMs`. **A write that timed out may still have been applied**: design writes to be idempotent (upserts and absolute values, not increments).
* Server event `wasteland:database:health (up, detail)` fires when the connection is lost or restored.
* Exports (callback style, used by the library): `Execute(kind, sql, params, cb)`, `Transaction(statements, cb)`, `Migrate(module, list, cb)`, `IsUp()`, `GetHealth()`.

### Migrations

Pass the full list on every start. It is usually the first thing an async module does in `onInit`:

```lua
local MIGRATIONS = {
    { version = 1, name = 'create_things', up = [[CREATE TABLE IF NOT EXISTS wl_things (...)]] },
    { version = 2, name = 'add_owner', up = [[ALTER TABLE wl_things ADD COLUMN owner INT NULL]] },
}
-- in onInit (async = true):
Citizen.CreateThread(function()
    local result, err = WDB.migrate('mymodule', MIGRATIONS)
    if not result then return M.fail('migrations failed: ' .. err) end
    M.ready()
end)
```

* Versions are 1, 2, 3 ... with no gaps. They are applied in order, one module at a time, and each one is recorded in `wl_migrations` together with a checksum.
* **Never edit an applied migration.** The checksum check refuses to start the module. Add a new migration instead.
* A database with more migrations than the module knows (a downgrade) is refused.
* MySQL/MariaDB commit DDL implicitly, so a migration is only fully atomic for data statements. Use **one DDL statement per migration** and make it idempotent (`IF NOT EXISTS`).
* Prefix table names with `wl_`.

## Players (`wasteland_players`, players api 0.1)

Identity: an **account** per Rockstar license, a **session** per connected player (`source`), and up to `players.maxCharacters` **characters** per account. One character is loaded per session. Session APIs take `source`; persistent APIs take `characterId`.

Exports:

| Export | Returns |
|---|---|
| `GetSession(source)` | `{ source, accountId, license, name, state, characterId }` or `nil` |
| `GetCharacter(source)` | `{ id, slot, firstName, lastName, source }` or `nil` |
| `GetCharacterId(source)` / `GetSourceByCharacterId(id)` | id / source or `nil` |
| `GetOnlineCharacters()` | list of characters |
| `IsCharacterLoaded(source)` | boolean |
| `GetCharacterData(characterId, key)` | stored value (copy) or `nil, err` |
| `SetCharacterData(characterId, key, value)` | `ok, err`; JSON-serialisable values, `nil` deletes, size limit `players.maxCharacterDataBytes` |
| `SaveCharacter(characterId, cb)` | starts a save; `cb(ok, err)` after the write |

Character data is a per-character key-value store. Use your module name as the key (or `module.sub`). It is saved:

* every `players.saveIntervalSeconds`
* when the character unloads (player leaves, switches character, resource stops, txAdmin shutdown)
* immediately, when you call `SaveCharacter`. Do this after **valuable** changes, and only confirm the action to the player when `cb` reports `ok`.

Server events (`AddEventHandler`):

| Event | Arguments | When |
|---|---|---|
| `wasteland:players:sessionStarted` | source, accountId | A player joined and has a session |
| `wasteland:players:characterLoaded` | source, character, restored | A character is loaded (`restored` = after a resource restart) |
| `wasteland:players:characterUnloading` | source, character, reason | Before the final save. Write your last data **synchronously** here |
| `wasteland:players:characterUnloaded` | source, characterId, reason | The final save succeeded |
| `wasteland:players:sessionEnded` | source, accountId, reason | The player left |

Client events (for the UI): `wasteland:players:client:characters`, `wasteland:players:client:result`, `wasteland:players:client:characterLoaded`. Guarded server events: `wasteland:players:server:requestCharacters`, `createCharacter(first, last)`, `selectCharacter(slot)`, `deleteCharacter(slot, confirmFirstName)`.
