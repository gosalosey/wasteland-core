# Coding conventions

## Lua

* Lua 5.4 (`lua54 'yes'` in every manifest). Use standard Lua syntax only, with no CfxLua extensions (backtick hashes, compound operators), so files parse under a stock interpreter for automated tests.
* Indent with 4 spaces and use single quotes. Name locals and functions `camelCase`, modules/tables `PascalCase` and constants `UPPER_SNAKE`.
* Each resource keeps its internals in a single resource-local namespace table (`WL` in the core). Resources never share globals; they are isolated anyway.
* Every file starts with a header comment: `-- <resource> :: <path>` plus one line describing its purpose.
* Avoid per-frame loops. Use events, or threads with configurable intervals (milliseconds from config, never hard-coded).

## Naming

| Thing | Pattern | Example |
|---|---|---|
| Resource | `wasteland_<area>` | `wasteland_inventory` |
| Module name | lowercase `[a-z][a-z0-9_]*`, ≤32 chars | `inventory` |
| Config file | `<module>.lua` in `wasteland_config/config/` | `inventory.lua` |
| Server-local event | `wasteland:<module>:<event>` | `wasteland:core:moduleState` |
| Server → client event | `wasteland:<module>:client:<event>` | `wasteland:core:client:consoleOutput` |
| Client → server event | `wasteland:<module>:server:<action>` | `wasteland:inventory:server:moveItem` (M3) |
| NUI callback | `<module>:<action>` | `inventory:move` (M3) |
| Export | PascalCase verb phrase | `GetModuleStatus` |
| ACE | `<shortName>.<area>` | `wasteland.admin` |

Client → server events are the only network entry points. Each one must validate the payload against a schema, rate-limit per player, and check distance or ownership where relevant (the guard helper arrives in M2).

## Versioning

* **Resource version** (`version` in fxmanifest) follows semver and is bumped on every release of that resource.
* **Module version** is the implementation version. **Module api** is the interface version other modules depend on. Bump the api *major* version for breaking interface changes, *minor* for additions and *patch* for fixes. If omitted, api equals version.
* **Core api** (`WL.API_VERSION`, currently `1.0.0`) versions the exports and events in `MODULE_API.md`. Modules declare `core = '^1.0.0'`.
* **Database schema** (M2) uses numbered, forward-only migrations per module, tracked in a migrations table.

## Error handling

1. Never swallow an error. Every `pcall` either re-raises or logs with context (module, operation, reason).
2. Return `ok, err` from functions that can fail for expected reasons (bad input, missing data). Raise only for programming errors.
3. User-facing configuration errors must name the file, the setting path and the expected value.
4. A module that cannot work correctly must fail (return `false, reason` from init or call `M.fail(reason)`) instead of running degraded without saying so.
5. When persistence fails (M2+), report it and refuse the valuable operation. Never fall back to memory silently.

## Logging

Use `M.log:debug|info|warn|error(fmt, ...)` in modules and `WL.Logger.new('area')` inside the core. Use `info` for lifecycle facts, `warn` for recoverable problems an admin should see, `error` for failures, and `debug` for diagnostics (off by default). Warnings and errors go to the ring buffer shown by `wasteland issues`.

## Tests

Every behaviour that can run outside the game gets an automated test in `tests/`. Behaviour that needs the game gets a numbered step in `docs/IN_GAME_TESTS.md`. See `TESTING.md`.
