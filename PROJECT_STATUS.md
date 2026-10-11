# Project status and development checklist

**Current milestone:** 8 (quests) complete in automated tests; installed; runtime verification pending (R18.x). Next: Milestone 9 persistent vehicles.
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
- [x] Walkers and runners, spawning around players (client finds ground, server checks and creates), population manager (per player, night, world cap, despawn), ownership: OneSync owner runs the AI
- [x] AI states (wander, chase, attack, investigate), detection by sight and sound; gunshots via `wasteland:weapons:used`
- [x] Attacks decided by the server: damage, chance of infection and bleeding; deaths, corpses, loot drops
- [x] Tests: rules, population, hits and their checks, noise, loot, despawn, admin, abuse (simulated server-side; AI is runtime only)
- [~] Installed on the owner's server; runtime tests R12.1-R12.12 pending (also the 5A weapons R8.x, confirmed working by the owner)

## Milestone 6: looting
Decisions (owner, 2026-10-11): world props everywhere and zombie bodies; shared containers that refill on a timer; short search bar, then the container opens; scarce loot.
- [x] Searchable containers (world props by model, zombie bodies) through wasteland_target; loot tables with rarity and empty chance
- [x] Search duration, cancel, refill only when empty after a timer; shared between players (inventory stashes)
- [x] Registration: containers and tables in loot.lua; `RollTable` export
- [x] Tests: rules, searching, sharing, refills, bodies, abuse (early finish, distance, cancel)
- [~] Installed on the owner's server; runtime tests R14.1-R14.10 pending
Refill state is kept in memory (after a restart emptied containers can be filled again).

## Milestone 7: zones, camps, NPCs, crafting
Decisions (owner, 2026-10-11): safe zones keep zombies out, with map blips and entry messages; traders buy and sell for cash; limited stock that restocks, no reputation; three starter camps picked by me. Split into 7A (camps) and 7B (crafting).

### 7A: camps
- [x] Camp zones (circles), safe zones (zombies: no spawn, removed inside, no chasing or hits inside), blips, entry/leave messages
- [x] Traders as NPCs with the target; cash buy/sell, stock and restock; server-checked trades
- [x] Tests: zone and trade rules, trading, safe zones with zombies, screen
- [~] Installed on the owner's server; runtime tests R16.1-R16.9 pending
Not chosen: barter, reputation, no-weapons zones, faster healing in camps.

### 7B: crafting
Decisions (owner, 2026-10-11): craft anywhere; recipes learned from blueprints found as loot; short progress bar; medical items, repair kits and melee weapons.
- [x] Recipes (crafting.lua), blueprints (use to learn, stored per character), starter recipes (rags, bandages)
- [x] Timed crafts with cancel; atomic exchange (materials back if the result does not fit)
- [x] Tests: rules, learning, crafting, abuse (unknown recipe, early finish), persistence
- [~] Installed on the owner's server; runtime tests R17.1-R17.7 pending
Splints not added: there are no broken bones yet (a fracture system would come first).

## Milestone 8: quests
Decisions (owner, 2026-10-11): camp traders give jobs; bring, kill, visit/search, craft; repeatable with cooldowns; tracker on screen + map markers.
- [x] Definitions (quests.lua), objectives bring/kill/visit/search/craft, rewards, cooldowns, per-character persistence
- [x] Board at traders, tracker on screen, map markers with route
- [x] Tests: rules, every objective, hand-in (rewards first, then items), duplicate claims (cooldown, one active copy), limits, persistence
- [~] Installed on the owner's server; runtime tests R18.1-R18.9 pending
Not done: quest chains (one-time story lines) - not chosen.

## Milestone 9: persistent vehicles
- [ ] Registry and schema · [ ] discovery/spawning · [ ] components and parts · [ ] repair · [ ] fuel · [ ] entity lifecycle · [ ] restart tests

## Milestone 10: admin and SDK
- [ ] Diagnostics and admin tools · [ ] debug visualisation · [ ] example extension · [ ] SDK docs complete

## Milestone 11: txAdmin recipe
- [ ] Recipe (verify against current txAdmin docs) · [ ] clean-install test

## Milestone 12: integration and release
- [ ] Full integration, load tests, final docs, release notes, clean-install report
