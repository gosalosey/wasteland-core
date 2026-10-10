# Milestone 2 report: database and player persistence

Date: 2026-10-10 · Core 0.2.0 (api 1.1.0) · Database 0.1.0 · Players 0.1.0

## Acceptance test

> Players connect with a persistent identity, create and select characters, and their data survives disconnects, reconnects, resource restarts and server restarts. Database failures are reported clearly and never cause silent data loss.

| Part | Simulated | Real MariaDB 11.6 | Runtime (real FXServer) |
|---|---|---|---|
| Database connection, failure reporting | **Pass** (driver missing, not started, no connection, timeout, down/up) | **Pass** (connect, migrations) | Not run: R2.1, R2.2, R2.17, R2.18 |
| Migrations | **Pass** (order, no-op rerun, checksum change, downgrade, failure stops, malformed list, several modules) | **Pass** (real DDL, rerun) | Not run: R2.3, R2.4 |
| Identity and sessions | **Pass** (license required, DB down refused, returning account, IPs not stored) | **Pass** | Not run: R2.5 |
| Characters | **Pass** (create/validate/limit/list/select/switch/delete) | **Pass** (unique slot key, soft delete) | Not run: R2.6-R2.14 |
| Persistence: reconnect | **Pass** | **Pass** | Not run: R2.10, R2.11 |
| Simultaneous sessions | **Pass** (kick_old, reject_new, account locked while a save fails) | n/a | Not run: R2.19 |
| Resource restarts | **Pass** (players, database) | **Pass** (players) | Not run: R2.15, R2.16 |
| Server shutdown | **Pass** (txAdmin event) | n/a | Not run: R2.20 |
| Net-event guard | **Pass** (types, ranges, patterns, extra args, rate limit, source, inactive module, handler errors, kick) | n/a | Indirect (character UI events arrive in M3) |

**Verdict:** passed in simulation and against a real MariaDB. Runtime acceptance is pending. Nothing in this report was checked in-game: no client joined during development, and the live server has not been restarted since installation.

## 1. Files created or changed

```
resources/[wasteland]/wasteland_core/     fxmanifest.lua (0.2.0), sdk/module.lua (health, net-event guard),
                                          server/{registry,exports,lifecycle,commands,config_loader,main}.lua,
                                          server/security.lua (new)
resources/[wasteland]/wasteland_database/ fxmanifest.lua, server/{sql,driver_oxmysql,requests,migrations,main}.lua, lib/db.lua   (new)
resources/[wasteland]/wasteland_players/  fxmanifest.lua, server/{state,sql,characters,sessions,interface,main}.lua, client/main.lua (new)
resources/[wasteland]/wasteland_config/   config/{database,players}.lua (new), config/{framework,modules}.lua
docs/DATABASE.md (new), docs/milestones/M2_REPORT.md (new), docs/{ARCHITECTURE,MODULE_API,CONVENTIONS,TESTING,IN_GAME_TESTS,KNOWN_ISSUES}.md
tools/backup_database.ps1 (new), .luarc.json, .gitattributes
tests/mock/fivem.lua (promises, players, deferrals, state bags, net events, JSON)
tests/lib/{json,memorydb,fake_oxmysql,mariadbcli}.lua (new), tests/lib/harness.lua (skip)
tests/integration/{netguard,database,players}.lua (new), tests/db/mariadb.lua (new)
```

## 2. Features implemented

* **Database adapter:** oxmysql driver behind an adapter. Per-query timeout (oxmysql waits forever without a connection), fail-fast while down, slow-query warnings, safe callbacks, health checks with `degraded` status and a health event, and precise startup failures.
* **Migrations:** per module, numbered, checksummed, forward-only and serialised. Edited migrations and downgrades are refused.
* **Net-event guard** in the SDK, with violation counting and an optional kick in the core.
* **Module health** in the core (api 1.1).
* **Players:** license accounts, admission (license, database up, duplicate sessions), multi-slot characters (default 3), per-character module data with size limits, write-through, periodic and final saves, an account lock until the final save succeeds, retries, restore after a resource restart, and an interim `/character` command.
* **Dependent restarts** for every module resource (generalises the R1.7 fix).
* **Operations:** database setup guide, backup script with rotation, restore and upgrade procedures.

## 3. Automated tests: 206 passed, 0 failed

Command: `lua tests/run.lua` (Lua 5.4.6, Windows 11). The real-database suite used MariaDB 11.6 on the owner's PC (database `wasteland_test`).

| Suite | Kind | Tests |
|---|---|---|
| static/manifests | static | 25 |
| unit/* | unit | 34 |
| integration/boot, registry, lifecycle, commands | simulated | 58 |
| integration/netguard | simulated | 16 |
| integration/database | simulated | 26 |
| integration/players | simulated | 33 |
| db/mariadb | real MariaDB | 14 |

**Defects found and fixed during this milestone:**
1. A health probe waited on its own request, while the same thread was the only one expiring timed-out requests. With a hung database it would never time out. Split into a separate watchdog thread (found in review, before tests).
2. `restart wasteland_database` left `wasteland_players` stopped (same platform behaviour as R1.7). The core now restarts dependents of any module resource.
3. The `characterUnloading` event lost the player id after a drop. It now carries the character's last source.
4. A stale session (player gone, no drop event) blocked reconnects until timeout. It is now closed on the next connection attempt.
5. A failed final save while the database was "up" (SQL error) was not visible in `status`. It is now reported as degraded health.
6. After a resource restart the client would have teleported players back to an older saved position. Restored characters are no longer moved.
7. The real-database backend could not read results: the MariaDB client prints column types only in table mode, so it now uses an XML data run plus a metadata run.

## 4. Installation on the owner's server (2026-10-10)

* MariaDB 11.6 (already running): database `wasteland` with user `wasteland@127.0.0.1` (rights only on `wasteland`), and database `wasteland_test` with user `wasteland_test@127.0.0.1` for the test suite. The passwords were generated randomly; the root password was used once and not stored.
* oxmysql v2.14.3 in `resources/[standalone]/oxmysql` (identical to the release zip).
* `server.cfg`: connection string and `ensure` lines added (backup: `server.cfg.before-m2`).
* `resources/[wasteland]`: identical to the repository (hash-checked).
* The game server was running and **was not restarted**. The new code loads on the next txAdmin restart.

## 5. Known issues and unresolved items

See `docs/KNOWN_ISSUES.md` K-8 to K-15. The most important ones to check at runtime:

* K-11: positions need OneSync.
* K-10: restore timing after `restart wasteland_players`.
* The real oxmysql type handling (K-14).
* R1.11 (`shutdown complete` on a txAdmin restart) is still unconfirmed. It is covered again by R2.20.

## 6. Reproducing remaining failures

No automated failures remain. For runtime issues, follow `docs/IN_GAME_TESTS.md` (R2.1-R2.21) and record the console output around any mismatch.

## 7. Regression

All 107 Milestone 1 tests still pass. Their version assertions were updated to 0.2.0 / api 1.1.0, and `wasteland status` now also counts degraded modules.
