# Wasteland Core

An original, modular, standalone zombie-survival framework for FiveM, built without QBCore, Qbox, ESX, ox_* or any other gameplay framework.

> **Status: Milestone 2 of 12.** The kernel and persistence layer work: module registry, configuration, lifecycle, admin status, database adapter with migrations, accounts, sessions and multi-slot characters that are saved safely. There is **no gameplay yet**. See `PROJECT_STATUS.md`.

## Repository layout

```
resources/[wasteland]/
  wasteland_config/     your settings (config/*.lua), never overwritten by updates
  wasteland_core/       framework kernel + Module SDK (incl. net-event guard)
  wasteland_database/   database adapter, health checks, migrations (needs oxmysql)
  wasteland_players/    accounts, sessions, characters, character data
  wasteland_template/   example module; copy it to start a new one
docs/                   architecture, conventions, API, testing, in-game tests, known issues
tests/                  automated tests + simulated FiveM runtime
tools/                  test runners, database backup script
server.cfg.example      lines to add to your server.cfg
PROJECT_STATUS.md       milestone checklist and how to resume work
```

## Try it

1. Set up MariaDB and oxmysql: `docs/DATABASE.md` section 1.
2. Copy `resources/[wasteland]` into your FXServer `resources/` folder.
3. Add the lines from `server.cfg.example` to your server.cfg.
4. Start the server and run `wasteland status` in the console.
5. Join and use `/character create First Last`, then `/character select 1`.
6. Follow `docs/IN_GAME_TESTS.md` to verify it.

## Run the automated tests

`tools\run_tests.bat` on Windows, or `./tools/run_tests.sh` elsewhere. Both need Lua 5.4. A real-database suite runs too when `tests/db.env` is configured. See `docs/TESTING.md`.

## Documentation

* `docs/ARCHITECTURE.md`: design, resource map, lifecycle, contracts, security
* `docs/MODULE_API.md`: SDK, net-event guard, config schema DSL, exports, events, admin command, database and players APIs
* `docs/DATABASE.md`: database setup, how data is kept safe, backups, restore, upgrades
* `docs/CONVENTIONS.md`: naming, versioning, error handling
* `docs/TESTING.md` and `docs/IN_GAME_TESTS.md`
* `docs/KNOWN_ISSUES.md`
