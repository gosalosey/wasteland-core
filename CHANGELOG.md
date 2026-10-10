# Changelog

## Milestone 2: database and player persistence (2026-10-10)

### wasteland_core 0.2.0 (core api 1.1.0)
* **Added** module health: `ReportModuleHealth` export and `M.setHealth()` in the SDK. Running modules can report `degraded` with a detail, which shows as `DEGRADED: ...` in `wasteland status` and `wasteland module <name>`. New event `wasteland:core:moduleHealth`.
* **Added** the net-event guard `M.netEvent(name, { args, rateLimit }, handler)`. It checks the sender, that the module is running, a per-player and per-event rate limit, and validates each argument against a schema. Rejections are logged (throttled) and reported as `wasteland:core:netViolation`.
* **Added** `server/security.lua`: counts guard violations and kicks after `framework.security.kickAfterViolations` (default 0 = never) within `violationWindowSeconds`.
* **Changed** the dependent-restart fix from 0.1.1 now applies to every module resource, not only the core: restarting `wasteland_database` brings `wasteland_players` back.

### wasteland_database 0.1.0 (new)
* oxmysql driver (verified against oxmysql v2.14.3 source), request layer with timeouts, slow-query warnings, fail-fast while down, and safe callbacks.
* Startup fails with a precise reason when the driver is missing, not started or not connected. Runtime health checks mark it degraded and broadcast `wasteland:database:health`.
* Per-module, numbered, checksummed, forward-only migrations (`wl_migrations`).
* `lib/db.lua`: await-style `WDB.query/single/scalar/insert/update/transaction/migrate/isUp` for module resources.

### wasteland_players 0.1.0 (new)
* Accounts per Rockstar license (no IPs stored), sessions with admission checks (license, database, duplicate sessions: `kick_old` or `reject_new`).
* Multiple character slots (`maxCharacters`, default 3): create with validated names, select, switch, soft delete with name confirmation.
* Per-character module data (`Get/SetCharacterData`, JSON, size limit) and `SaveCharacter` for write-through.
* Saves: periodic, final save on unload/drop/switch/stop/txAdmin shutdown. The account stays locked until the final save succeeds, and failed saves are retried.
* Restores sessions and characters after `restart wasteland_players` (via player state bags), without moving the player.
* Interim chat command `/character list|create|select|delete` and guarded net events for the future UI.

### wasteland_config
* New `database.lua` and `players.lua`. `framework.lua` gains a `security` section.

### Tests and tools
* Mock: promises/`Citizen.Await`, players with connection deferrals, state bags, net events, JSON, a simulated oxmysql and an in-memory database.
* New suites: netguard, database, players, and the real-database suite (`tests/db/mariadb.lua`, runs the real SQL on MariaDB when `tests/db.env` is configured). 206 tests pass (192 simulated + 14 on MariaDB 11.6).
* `tools/backup_database.ps1`, `docs/DATABASE.md`, `.luarc.json` (FiveM globals for the Lua language server).

## 0.1.1 (core), runtime fix from in-game testing

### Fixed
* `restart wasteland_core` left every module resource stopped, because FiveM stops dependents but does not restart them (found in runtime test R1.7). The core now restarts exactly the module resources its own stop took down. Controlled by the new `framework.restartModulesAfterCoreRestart` setting (default `true`).

## 0.1.0 (Milestone 1: architecture and foundation)

### Added
* `wasteland_core` 0.1.0 (core api 1.0.0): module registry with semver dependency resolution, optional dependencies, cycle detection, async modules, cascade stop and re-init; sandboxed configuration loading with schema validation and precise errors; levelled logging with a recent-issues buffer; startup window and status report; ordered, idempotent shutdown (resource stop and txAdmin shutdown); `wasteland` admin command with ACE check and audit logging; Module SDK.
* `wasteland_config` 0.1.0: framework.lua, modules.lua, logging.lua, template.lua.
* `wasteland_template` 1.0.0: example and template module.
* Automated test suite (static, unit and simulated integration) with a multi-resource FiveM mock.
* Documentation: architecture, conventions, module API, testing, in-game test procedure, known issues, project status.
