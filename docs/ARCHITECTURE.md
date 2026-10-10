# Wasteland Core: Architecture

Status: **Milestones 1 and 2 implemented**, tested in simulation and (Milestone 2 SQL) against a real MariaDB. Runtime (in-game) verification of Milestone 2 is pending. Everything marked "Planned" is design, not code.

## 1. Design principles

1. **Standalone.** The only platform is the FiveM server and client runtime and its documented natives. No QBCore, Qbox, ESX, ox_lib, ox_inventory, ox_target or other gameplay framework is used.
2. **Kernel plus modules.** `wasteland_core` contains no gameplay. It provides the module registry, configuration, lifecycle, logging and the public API. Each gameplay system is its own resource and its own module.
3. **Contracts, not internals.** Modules talk only through documented exports, events and data contracts (see `MODULE_API.md`). A module never reads another module's globals or files.
4. **Server authority.** Clients send *requests*. The server validates and decides every outcome that has value: items, rewards, damage, quest progress, vehicle state and zone membership.
5. **Configuration over code.** Every gameplay value lives in `wasteland_config/config/*.lua`, is validated against a schema at startup, and gives a precise error (file, setting, expected value) when wrong.
6. **Fail loudly and safely.** No silent `pcall`. An invalid config stops modules from initialising instead of letting them run on guesses. A failed dependency blocks its dependents with a stated reason.

## 2. Resource map

All resources live in `resources/[wasteland]/`. Arrows mean "requires" (`dependency` in fxmanifest plus a module dependency).

```
                         wasteland_config   (owner-edited config files, no scripts)
                                 │
                         wasteland_core     (kernel: registry, config, lifecycle, logging, SDK)
                                 │
          ┌──────────────────────┼─────────────────────────────┐
  wasteland_database        wasteland_ui                 wasteland_admin
  (adapter, migrations,     (NUI shell, design system,   (diagnostics, commands;
   health)                   HUD, menus)                  optional deps on all)
          │                          │
  wasteland_players                  │
  (accounts, sessions,               │
   characters, char data)            │
          ├───────────────┬──────────┘
  wasteland_inventory ◄───┘
          │                             │
  ┌───────┼──────────┬───────────┬──────┴─────┬─────────────┐
survival  loot     world       crafting     vehicles      quests
(needs)  (search) (zones,camps, (recipes,   (persistent   (objectives,
                  NPC trade)    stations)   wrecks,parts)  rewards)
                    │
                 zombies  (optional deps: world for safe zones,
                           survival for infection, loot for drops)
```

| Resource | Module name | Hard dependencies | Optional dependencies | Milestone |
|---|---|---|---|---|
| wasteland_config | (none, data only) | none | none | 1 ✅ |
| wasteland_core | `core` | wasteland_config | none | 1 ✅ |
| wasteland_template | `template` | core | none | 1 ✅ (SDK example) |
| wasteland_database | `database` | core, DB driver (see §6) | none | 2 ✅ |
| wasteland_players | `players` | core, database | none | 2 ✅ |
| wasteland_ui | `ui` | core | none | 3A (shell, character screens), 3B (inventory UI), 4 (HUD) |
| wasteland_appearance | `appearance` | core, players, ui | inventory (clothing items, 3B) | 3A |
| wasteland_inventory | `inventory` | core, database, players, ui | none | 3 |
| wasteland_survival | `survival` | core, database, inventory, ui | none | 4 |
| wasteland_zombies | `zombies` | core | world, survival, loot | 5 |
| wasteland_loot | `loot` | core, database, inventory | world | 6 |
| wasteland_world | `world` | core, database, inventory, ui | none | 7 |
| wasteland_crafting | `crafting` | core, inventory | world | 7 (see note) |
| wasteland_quests | `quests` | core, database, inventory, ui | zombies, loot, vehicles, world | 8 |
| wasteland_vehicles | `vehicles` | core, database, inventory, ui | crafting, quests | 9 |
| wasteland_admin | `admin` | core | every module | 10 |
| recipe/ (not a resource) | n/a | n/a | n/a | 11 |

**Note on crafting:** the required workflow lists no milestone for crafting, but vehicle parts (M9) must be craftable and camps (M7) have crafting stations. Crafting is therefore scheduled with Milestone 7.

**Start order** (server.cfg): `oxmysql` → `wasteland_config` → `wasteland_core` → `wasteland_database` → `wasteland_players` → `wasteland_ui` → `wasteland_inventory` → the rest. FiveM's `dependency` directive also enforces this, and the registry independently orders initialisation by declared module dependencies, so order mistakes in server.cfg cannot break initialisation.

## 3. Kernel (wasteland_core), implemented

| File | Responsibility |
|---|---|
| `shared/util.lua` | deep copy, sorted keys, inspect, path helpers |
| `shared/semver.lua` | versions and ranges (`^1.2.0`, `~1.2`, `>=1 <2`, `a \|\| b`) |
| `shared/schema.lua` | declarative config schemas: validation, defaults, precise errors, schema self-check |
| `shared/logger.lua` | levelled per-module logging; ring buffer of recent warnings and errors |
| `server/config_loader.lua` | sandboxed loading of `wasteland_config/config/*.lua`; core schemas |
| `server/registry.lua` | module registration, dependency resolution, init/shutdown, cascade on stop |
| `server/lifecycle.lua` | boot, config-error mode, startup window, readiness, ordered shutdown, status report |
| `server/security.lua` | counts net-event guard violations; optional kick (`framework.security`) |
| `server/commands.lua` | admin console command with ACE check and audit logging |
| `server/exports.lua` | the public server API (core api 1.0.0) |
| `server/main.lua` | wiring: boot, `onResourceStop`, txAdmin shutdown event |
| `client/main.lua` | prints admin command output in F8 for authorised players |
| `sdk/module.lua` | Module SDK included by module resources (`@wasteland_core/sdk/module.lua`), including the net-event guard (`M.netEvent`) |

### 3.1 Module lifecycle

```
register ──► waiting ──(deps running, config valid)──► initializing ──► running
   │            │  ▲                                        │   (async: until M.ready())
   │            │  └──── dependency stopped/failed ◄────────┘
   │            ├──► disabled   (modules.lua)
   │            └──► failed     (bad config, incompatible version, init error, cycle, timeout)
   └─ rejected (invalid definition, duplicate name) — never enters the registry
running ──(own resource stops)──► stopped ──(resource starts, re-registers)──► waiting
```

* **Dependencies** are `{ moduleName = 'semverRange' }` and are checked against the dependency's *api* version (interface version, defaults to the module version).
* **Optional dependencies** are waited for only if they are registered, and are ignored if they never register.
* **Cascade:** when a module stops or fails, every running module that hard-depends on it is shut down (deepest first) and returned to `waiting`. It re-initialises automatically, with config re-read, when the dependency comes back.
* **Shutdown** runs in reverse initialisation order and is idempotent. It is triggered by the core resource stopping (`core_stopped`) or by txAdmin's `txAdmin:events:serverShuttingDown` (`server_shutdown`). Errors in one module's shutdown are logged and do not prevent the others from stopping.
* **Core restart:** FiveM stops every resource that depends on `wasteland_core` when the core stops, and does not restart them (verified at runtime). The core records which module resources its own stop took down, in a process-lifetime server convar, and starts them again on boot (`framework.restartModulesAfterCoreRestart`).
* **Dependent restarts (any module):** the same FiveM behaviour applies to every module resource (`restart wasteland_database` stops `wasteland_players`). When a module resource stops, the core records the module resources that FiveM stopped just before it because their manifest depends on it, and starts them again when it returns. This uses the same setting.
* **Health:** a running module can report itself `degraded` with a detail (for example, database unreachable). Health is informational: it is shown in `status` and broadcast as `wasteland:core:moduleHealth`, but it does not change the module state or cascade.
* **Startup window** (`framework.startupTimeoutSeconds`): when it ends, async modules that never reported ready are failed, enabled-but-unregistered modules are reported as missing, still-waiting modules are listed with reasons, the status table is printed and `wasteland:core:ready` fires. Modules may still register afterwards.

### 3.2 Configuration

* Files live in a separate resource (`wasteland_config`) so framework updates never overwrite owner settings. You can rename it with the convar `wasteland_config_resource`.
* Files are Lua that `return { ... }`. They execute in a sandbox (no `os`, `io`, natives or `require`; only `math`, `string`, `table` and vector constructors).
* The core validates `framework.lua`, `modules.lua` and `logging.lua`. Each module declares `config = { file, schema, optional }`, and the core validates that file before calling the module's `init`.
* Errors look like `wasteland_config/config/logging.lua: setting 'level': expected one of "debug", "info", "warn", "error", "off", got "verbose" (string)`. Unknown keys produce a typo warning.
* If the core config is invalid, the framework enters `config_error` and initialises nothing. `wasteland config reload` resumes startup once the files are fixed.

## 4. Data contracts (core api 1.1.0)

**ModuleStatus** (`GetModuleStatus`, `GetModuleStatuses`):
`{ name, version, api, description, resource, state, reason, enabled, dependencies, optionalDependencies, configFile, configWarnings, initIndex, async, health, healthDetail }` (`health`/`healthDetail` since api 1.1)

**FrameworkInfo** (`GetFrameworkInfo`, init `ctx.framework`, events):
`{ name, shortName, version, api, state, resource, configResource }`

**Player identity (M2, implemented):** an **account** per Rockstar license (`wl_accounts`), a **session** per connected player keyed by `source`, and **characters** in numbered slots per account (`wl_characters`, soft-deleted). One character is loaded per session. `source` (session, server ID) is distinct from `characterId` (persistent): persistent APIs take `characterId`, session APIs take `source`. Module data per character is a JSON value per key in `wl_character_data`. See MODULE_API.md "Players".

**Planned contracts** (defined in the milestone that introduces them; listed so the design is visible now):

* **ItemStack (M3):** `{ name, count, metadata = { durability?, serial?, ... }, slot }`. Item definitions are registered by name, and the item `name` is the stable key.
* **Inventory ID (M3):** `'<type>:<id>'`, for example `player:42`, `vehicle:veh_9f2c`, `container:loot_123`, `stash:camp_a`.
* **Zone (M7):** `{ id, type, shape = circle|polygon, rules = {...} }`.
* **Vehicle record (M9):** `{ uid, model, coords, heading, components = { [componentId] = { installed, condition } }, fuel, ... }`.

## 5. Security model

* Client→server events are treated as untrusted input. Every net event goes through the core guard (`M.netEvent`, Milestone 2): source validation, module-running check, per-player token-bucket rate limiting, and argument count and schema validation (same schema DSL). Rejections are logged with throttling and counted by the core, which can kick repeat offenders (`framework.security.kickAfterViolations`). Checks that depend on game state (distance, ownership) stay in each handler.
* Database access only uses `?` placeholders. Player input is never concatenated into SQL. The database user has rights only on its own database.
* IP addresses are not stored.
* Admin actions require an ACE (`wasteland.admin` by default) and are always logged. The server console is always authorised.
* Inventory and transfer operations (M3) use per-inventory transaction locks and a single authoritative server state. The database is written transactionally.
* Config files are never sent to clients (they are not listed under `files`).

## 6. Database and persistence (Milestone 2, implemented)

FiveM has no built-in SQL client, so persistent storage needs a driver resource.

* **Driver:** **oxmysql** (LGPL-3.0, tested with v2.14.3) with MariaDB or MySQL. The owner approved it on 2026-10-10 as infrastructure. Only `wasteland_database/server/driver_oxmysql.lua` talks to it, so it can be replaced.
* **Adapter:** modules use `lib/db.lua` (`WDB.query/single/scalar/insert/update/transaction/migrate`), which waits on callback exports of `wasteland_database`. The request layer adds input checks, a per-query timeout (oxmysql waits forever without a connection), slow-query warnings, fail-fast while the database is down, and callbacks that survive a caller resource stopping.
* **Startup:** `database` is an async module. It waits for the driver connection up to `connectTimeoutSeconds`, then FAILS with a precise reason (driver not installed, not started, or no connection). Every module that depends on it stays `waiting` with that reason. There is no in-memory fallback.
* **Runtime outage:** health checks (`healthCheckSeconds`, and immediately after a timeout) mark the module `degraded`. Requests fail at once, `wasteland:database:health` is broadcast, and modules refuse database-backed actions and retry their saves when the connection returns.
* **Migrations:** per module, numbered, forward-only, checksummed, applied one at a time, recorded in `wl_migrations`. Downgrades and edited migrations are refused (see MODULE_API.md).
* **Save strategy (players):** write-through for create, select and delete and on module request (`SaveCharacter`); a periodic save of every loaded character in one transaction each (`saveIntervalSeconds`); a final save on unload, drop, switch, resource stop and txAdmin shutdown. An account stays locked until its last character's final save succeeds, so a reconnect cannot load stale data (no rollback or duplication by relogging). Failed final saves are retried.
* **Limits:** a killed process runs no shutdown, so changes since the last periodic save are lost (K-3). Writes that time out may still apply (K-9).
* Backups and restore: `docs/DATABASE.md`, `tools/backup_database.ps1`.

## 7. Known platform limitations relevant to the architecture

* Exports and function references cross resource boundaries via serialization. Tables are copied, and functions become callable reference objects. The registry handles this (see `KNOWN_ISSUES.md` K-1).
* Whether a module's `init` may yield (`Citizen.Wait`) across an export boundary is not relied on. Modules that need asynchronous setup declare `async = true` and call `M.ready()`.
* FiveM gives no guaranteed hook for an abrupt process kill. Graceful shutdown covers resource stops and txAdmin-announced restarts. Data safety relies on write-through persistence and periodic saves, not on shutdown alone.
* Module shutdown callbacks cannot wait. Final saves at shutdown are issued without waiting, and they complete in `wasteland_database` and oxmysql while the process is still alive. That is the case for resource restarts and for txAdmin restarts, which announce the shutdown before it happens.
* Cross-resource exports that wait (yield) are not relied on. Database calls use callback exports, and `lib/db.lua` waits inside the caller's own resource.
* Server-side player positions (`GetEntityCoords(GetPlayerPed(src))`) need OneSync.
