# Project status and development checklist

**Current milestone:** 1 complete (simulated), awaiting runtime verification and owner review.
**Next milestone:** 2, database and player persistence. Blocked on one decision: approval of oxmysql as the DB driver (see ARCHITECTURE §6).
**Last updated:** 2026-10-10

## How to resume work

1. Read this file, then `docs/ARCHITECTURE.md` and `docs/MODULE_API.md`.
2. Run `./tools/run_tests.sh`; all tests must pass before you change anything.
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
- [~] Acceptance test on a real server: R1.1 and R1.3 passed; R1.7 failed on 0.1.0, fixed in 0.1.1 (re-test); others pending

## Milestone 2: database and player persistence
- [ ] Owner approves the DB driver (oxmysql proposed)
- [ ] `wasteland_database`: adapter interface, oxmysql driver, health checks, failure reporting
- [ ] Migration runner (per-module, numbered, transactional, tracked)
- [ ] Core net-event guard: payload schema, rate limit, source validation
- [ ] Player identity (license-based), sessions, simultaneous-session handling
- [ ] Character data persistence, save strategy (write-through + periodic + shutdown)
- [ ] Backup/restore procedure documentation
- [ ] Tests: reconnect, simultaneous sessions, DB down/up, resource restart

## Milestone 3: inventory and item API
- [ ] Item definition registry (config + API) · [ ] grid inventory model, weight, stacks, metadata, durability
- [ ] Containers (player/stash/vehicle/container) · [ ] equipment slots
- [ ] Transactions with locking; split/merge/move/drop/pickup/use · [ ] persistence
- [ ] wasteland_ui: NUI shell, design system, inventory UI
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
