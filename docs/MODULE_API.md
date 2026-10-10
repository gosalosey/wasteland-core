# Module API and SDK (core api 1.0.0)

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
| `M.register()` | re-register manually (normally automatic) |
| `M.registered`, `M.registerError` | outcome of the last registration attempt |

### Rules for module authors

* `onInit` and `onShutdown` must be symmetric: init may run again after a shutdown (for example, when a dependency restarts). Use a token to stop threads, as the template shows.
* Do not `Citizen.Wait` inside `onInit`. Start a thread, set `async = true` and call `M.ready()`.
* Never read another module's files or globals. Use its exports and events.
* The SDK already handles your own resource stopping and core restarts (it re-registers automatically).

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

States: framework `booting | config_error | ready | shutting_down | stopped`; module `waiting | initializing | running | failed | disabled | stopped`.

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
