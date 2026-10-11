# Project status and development checklist

**Current milestone:** 3A complete in automated tests; installed on the owner's server; runtime verification pending (R2.x and R3.x in docs/IN_GAME_TESTS.md).
**Next milestone:** 3B, inventory and item API.
**Last updated:** 2026-10-10

## How to resume work

1. Read this file, then `docs/ARCHITECTURE.md` and `docs/MODULE_API.md`.
2. Run `tools\run_tests.bat` (Windows) or `./tools/run_tests.sh`; all tests must pass before you change anything. With `tests/db.env` configured, the real-database suite runs too (docs/TESTING.md).
3. Continue with the first unchecked item of the current milestone.
4. At the end of a milestone, write `docs/milestones/M<n>_REPORT.md` (the format follows spec §19) and update this file and CHANGELOG.md.

## Legend

`[x]` done and automated-tested · `[~]` done, simulated only, runtime check pending · `[ ]` not started

## Milestone 1: architecture and foundation
- [x] Inspect environment (no existing project; Lua 5.4 test environment set up)
- [x] Architecture and resource dependency map (docs/ARCHITECTURE.md)
- [x] Data contracts, event naming, exports, module interfaces (MODULE_API.md, CONVENTIONS.md)
- [x] Coding conventions, versioning, error handling (CONVENTIONS.md)
- [x] Repository structure
- [x] Startup and shutdown (lifecycle.lua)
- [x] Configuration loading and validation (config_loader.lua, schema.lua)
- [x] Module registry (registry.lua) and SDK (sdk/module.lua)
- [x] Automated test infrastructure: 107 tests passing
- [~] Acceptance test on a real server: R1.1 and R1.3 passed; R1.7 failed on 0.1.0, fixed in 0.1.1 (re-test); R1.11 (txAdmin restart shows `shutdown complete`) not yet confirmed: covered again by R2.20; others pending

## Milestone 2: database and player persistence
- [x] Owner approves the DB driver: oxmysql approved 2026-10-10 (multiple character slots chosen)
- [x] `wasteland_database`: adapter interface, oxmysql driver, timeouts, health checks, failure reporting (also run against real MariaDB 11.6)
- [x] Migration runner (per-module, numbered, checksummed, tracked; DDL caveat K-8)
- [x] Core net-event guard: payload schema, rate limit, source validation, violation counting/kick
- [x] Player identity (license-based), sessions, simultaneous-session handling (kick_old / reject_new, account lock until saved)
- [x] Character data persistence, save strategy (write-through + periodic + unload/shutdown, retries)
- [x] Backup/restore procedure documentation (docs/DATABASE.md, tools/backup_database.ps1)
- [x] Tests: reconnect, simultaneous sessions, DB down/up, resource restart (simulated); all SQL on real MariaDB
- [~] Installed on the owner's server (oxmysql 2.14.3, database + user, server.cfg); runtime tests R2.1-R2.21 pending

## Milestone 3A: UI shell, character select and character creator (added 2026-10-10)
Decision (owner asked for the better approach): appearance is not in the original spec but every
player sees it first. It needs the NUI shell, not the inventory, so the UI shell moves out of M3
and ships first, with the screens players hit on joining.
- [x] wasteland_ui: NUI shell, design system, focus/input handling, screens owned by modules
- [x] Character select screen (the `/character` chat command stays as a fallback)
- [x] wasteland_appearance: creator for new characters; freemode male/female, heritage, face features,
      hair + colours, overlays, starter clothing chosen in the creator (blocklist in config)
- [x] Appearance stored as character data, validated server-side, reapplied on load and after respawn;
      players held until a character is loaded (K-15)
- [x] Admin command to reopen the creator for a player
- [x] Tests: appearance validation, persistence, select/create flow, invalid payloads (Lua), UI logic (Node)
- [~] Installed on the owner's server; runtime tests R3.1-R3.15 pending
Body (face, hair, features) is fixed after creation. Clothing is set only once (starter outfit) here;
from M3B clothes become wearable inventory items in equipment slots, found as loot and swapped in play.

## Milestone 3B: inventory and item API
- [ ] Item definition registry (config + API) · [ ] grid inventory model, weight, stacks, metadata, durability
- [ ] Containers (player/stash/vehicle/container) · [ ] equipment slots, including clothing items applied to the ped
- [ ] Transactions with locking; split/merge/move/drop/pickup/use · [ ] persistence
- [ ] Inventory UI (on the M3A UI shell)
- [ ] Tests: duplication, concurrency, disconnect mid-action, invalid client events

## Milestone 4: survival and HUD
- [ ] Hunger, thirst, stamina, health; consumable effects · [ ] optional bleeding/infection/temperature
- [ ] Death/respawn rules, item loss options · [ ] HUD (configurable, compact/immersive modes)

## Milestone 5: zombies
- [ ] Archetypes, spawning, population manager, ownership strategy · [ ] AI states, detection (sight/sound)
- [ ] Combat, damage, infection hook, loot drops · [ ] ambient population control · [ ] multiplayer tests

## Milestone 6: looting
- [ ] Searchable containers, loot tables, rarity · [ ] durations, cooldowns, respawn · [ ] registration API · [ ] concurrency tests

## Milestone 7: zones, camps, NPCs, crafting
- [ ] Zones (circle/polygon) and rules · [ ] safe zones · [ ] camps, NPC registry, barter traders, reputation
- [ ] Crafting recipes and stations (scheduled here; see ARCHITECTURE)

## Milestone 8: quests
- [ ] Definitions, objective handler registry, chains, rewards, persistence, HUD tracking · [ ] duplicate-claim tests

## Milestone 9: persistent vehicles
- [ ] Registry and schema · [ ] discovery/spawning · [ ] components and parts · [ ] repair · [ ] fuel · [ ] entity lifecycle · [ ] restart tests

## Milestone 10: admin and SDK
- [ ] Diagnostics and admin tools · [ ] debug visualisation · [ ] example extension · [ ] SDK docs complete

## Milestone 11: txAdmin recipe
- [ ] Recipe (verify against current txAdmin docs) · [ ] clean-install test

## Milestone 12: integration and release
- [ ] Full integration, load tests, final docs, release notes, clean-install report
