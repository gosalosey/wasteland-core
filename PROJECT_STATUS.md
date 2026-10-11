# Project status and development checklist

**Current milestone:** 5A (weapons) complete in automated tests; installed; runtime verification pending (R8.x). Next: 5B zombies.
**Next milestone:** 5, zombies (and weapons).
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
- [x] Installed on the owner's server; owner confirmed the creator works (camera framing adjusted)
Body (face, hair, features) is fixed after creation. Clothing is set only once (starter outfit) here;
from M3B clothes become wearable inventory items in equipment slots, found as loot and swapped in play.

## Milestone 3B: inventory and item API
Decisions (owner, 2026-10-10): Tetris grid with item sizes; backpacks add their own grid; 5-slot hotbar.
- [x] Item definition registry (config + RegisterItem) · [x] grid model, rotation, weight, stacks, metadata, durability
- [x] Containers: pockets, worn bag, stash, ground drops (vehicle containers come with M9) · [x] equipment slots, clothing items applied to the ped
- [x] Atomic operations (no yields) + ordered transactional write queue; move/rotate/merge/split/wear/take off/drop/pick up/use · [x] persistence
- [x] Inventory UI (drag and drop, preview, context menu, hotbar)
- [x] Tests: duplication, concurrency (two players, one item), disconnect mid-action, database failure, invalid client events; SQL on real MariaDB
- [x] Installed on the owner's server; owner confirmed it works after the drag fix (key changed to TAB)
Weapons as items are deferred to Milestone 5 (K-21).

## Milestone 4: survival and HUD
Decisions (owner, 2026-10-10): drop everything into a body bag with a map marker, except hotbar items; random respawn points; bleeding, infection and temperature; moderate pace.
- [x] Hunger, thirst, health (client ped, server-driven damage/heal); consumable effects · [x] bleeding, infection, temperature
- [x] Death/respawn rules, body bags (hotbar kept), respawn delay and points · [x] HUD (compact / only when it matters / off)
- [x] Tests: rules (unit), server flows, body bags, HUD logic, real MariaDB
- [x] Installed on the owner's server; owner confirmed it works (hand props added on request)
Stamina is shown, not changed (GTA's own). Weather/time sync for temperature: Milestone 7 (K-27).

## Owner requests (2026-10-10): empty silent world, admin panel
Brought forward: part of Milestone 7 (world) and Milestone 10 (admin).
- [x] wasteland_world: no ambient NPCs or traffic, ambient audio off, server clock and weather (also fixes K-27)
- [x] wasteland_admin: panel (players, items, bans, server & world, action log), bans checked on connect
- [x] Tests: world rules, admin permissions and every action, bans, real MariaDB
- [x] Installed on the owner's server; owner confirmed it works (fixes: plain look for given clothing, freeze when searching a drop)

## Milestone 5: weapons and zombies
Decisions (owner, 2026-10-10): mostly walkers, some runners; moderate numbers, gunshots attract from far; hits do damage with a chance of infection and bleeding; melee, pistols, shotguns, SMGs, rifles; durability and repairs. Split into 5A (weapons) and 5B (zombies).

### 5A: weapons
- [x] wasteland_weapons: weapon items held by using them (hotbar), ammo taken from the inventory per shot, durability per shot/hit, broken weapons, repair kits
- [x] Inventory: FindItem, SetItemMetadata, `wasteland:inventory:playerUpdated`; 14 weapons, 6 ammo types, repair kit
- [x] Tests: holding, ammo, wear, breaking, repairs, dropping, death, guarded events
- [~] Installed on the owner's server; runtime tests R8.1-R8.10 pending
Attachments: later (not chosen for 5A, K-34).

### 5B: zombies
- [ ] Archetypes (walkers, runners), spawning around players, population manager, ownership strategy
- [ ] AI states, detection (sight, sound: gunshots via `wasteland:weapons:used`)
- [ ] Attacks: damage, chance of infection and bleeding · [ ] multiplayer tests

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
