# Changelog

## Target system, admin item list, zombie reach (owner requests)

### wasteland_target 0.1.0 (new)
* Hold Left Alt: an eye appears in the middle of the screen. Look at something with options: they appear beside the eye; scroll to choose, click or E to use. Rebindable in the GTA key settings (FiveM section).
* For other resources (client exports): `AddModel`, `AddEntity`, `AddNetId`, `AddGlobal('ped'|'vehicle'|'object'|'player')`, `AddSphere`, `AddBox`, `Remove`, `IsTargeting`. Options: `label`, `icon`, `distance` (default 2.5 m), `canInteract(entity, distance, coords)`, and `onSelect(data)`, `event` or `serverEvent`. Registrations disappear with the resource that made them.
* Bags on the ground and body bags are searched through the target ("Search ..."); without wasteland_target the "Press E" prompt still works.

### Other
* Admin panel: the item picker is a dropdown listing every item on the server by category, with pictures and a search box.
* Zombies reach further: attack range 2.6 m (was 1.7 m).
* Tests: 453 (new: target matching and screen, item grouping).


## Milestone 5B: zombies

### wasteland_zombies 0.1.0 (new)
* The server keeps zombies around every living player (8 by day, 12 at night; at most 60 in the world), 70-140 m away, topping up every 6 seconds. The player's game finds spots on the ground; the server checks every spot (ring around the player, not next to anyone) and creates the zombie itself.
* Walkers (drunk shuffle) and runners (15% by day, 30% at night). GTA ambient models (tramps, meth heads, GTA's own zombie) with blood and dirt; silent.
* AI runs on the client that owns each zombie: wander; notice players by sight (35 m by day, 18 m at night, needs a clear line) and sound (sprinting 25 m, walking 9 m, crouching 3 m; vehicles are loud); chase; attack; give up after 10 s without seeing or hearing them.
* Gunshots: every zombie within the weapon's noise radius (pistol 120 m, rifles 250 m...) walks to the shot.
* Hits are decided by the server (zombie owned by the reporting client, alive, close, cooldown): 6-10 damage (runners 5-8), a 25% chance of infection, a 15% chance of bleeding (survival).
* Dead zombies lie 90 seconds; 25% leave "Zombie remains" with a little loot (cash, ammo, bandage, food, scrap). Zombies far from everyone disappear.
* `/zombies count | clear | spawn <n>` (admin). Exports `GetZombieCount`, `SpawnZombie`, `ClearZombies`; events `wasteland:zombies:died`, `wasteland:zombies:hit`.

### Other
* wasteland_inventory: `CreateLootDrop(coords, items, opts)`. wasteland_survival: `Damage(source, amount)`.
* Tests: 441 simulated (new: zombie rules, population, hits, noise, loot, despawning, admin, abuse); the mock simulates server-created entities.


## Cash, HUD info line, stamina bar (owner request)
* Cash is an item (`cash`, weightless, stacks to 1,000,000, picture `cashroll`) and the only money: no bank. It is carried in pockets or a worn bag, can be dropped, handed over and looted, and goes into the body bag on death like other items (unless on the hotbar). Inventory exports `GetCash`, `AddCash`, `RemoveCash`; config `cashItem` in inventory.lua. Tiles show cash as `$1,250`. Inventory and admin limits for one action raised to 1,000,000 for cash.
* HUD: a line with the player's server id, character name and cash above the icons (moves with the HUD).
* Stamina: a small bar at the bottom middle of the screen, only while stamina is used; it fades out when full.
* GTA's green/blue health and armour bars under the minimap are hidden.

## HUD redesign (owner request)
* The survival HUD is now four green outlined icons in the bottom-right corner that drain like a liquid level: health (drop), food (tray with fork and knife), drink (bottle), temperature (thermometer, 33-39 °C). They turn amber at 35% or below (or cold/hot) and red and pulsing at 15% or below. Bleeding and infection show as small badges under the icons. Stamina is no longer shown (GTA shows its own).
* `/hud` opens edit mode: drag the HUD anywhere, choose Always / When it matters / Off, Row or Column, size S/M/L; Save keeps it on the player's PC (each player their own), Cancel or Esc keeps the old one, Reset returns to the bottom-right corner.

## Item pictures (owner request)

### wasteland_images 0.1.0 (new)
* All 3,474 pictures of the community MK-Items pack (3,485 files; same-name files kept with a folder suffix), converted to WebP and scaled down where oversized (187.7 MB of PNG -> 19.3 MB, empty borders trimmed so long items fill their tiles). `tools/import_images.py` re-imports a pack.
* Inventory: tiles show the item's picture (it turns with rotated items); items can pick a picture with `image = '...'`, otherwise the picture named like the item is used. 22 items mapped to pictures; most weapons, water and bandages match by name. Admin panel shows the chosen item's picture.


## Milestone 5A: weapons

### wasteland_weapons 0.1.0 (new)
* Weapon items: use (hotbar key) to draw, use again to put away. Knife, baseball bat, crowbar, hatchet, machete, pistol, heavy revolver, sawed-off and pump shotgun, micro SMG, SMG, carbine, assault rifle, hunting rifle.
* Ammo comes from the inventory: 9mm, .44, 12 gauge, 5.56, 7.62, .308. Every shot uses a round; picking up or dropping ammo updates the gun at once.
* Durability: every shot or melee hit wears the weapon; a broken weapon cannot be used until it is fixed with a weapon repair kit (40% per kit).
* GTA's own weapon switching (wheel, scroll, weapon-slot keys) is off; weapons come only from the inventory.
* Gunshots and hits announce their noise (`wasteland:weapons:used`) for the zombies in 5B.

### Other
* wasteland_inventory: `FindItem`, `SetItemMetadata`, server event `wasteland:inventory:playerUpdated`; the crowbar is now a melee weapon.
* Fixes: worn clothing that carries no look (given or looted) shows a plain outfit instead of nothing; searching a drop with E no longer freezes the game.
* Stacks (owner request): items stack to 50 by default; bandages, painkillers, rags, energy bars and scrap metal to 100; 9mm, 5.56 and 7.62 rounds to 250, other ammo to 100. Weapons, tools with durability, backpacks and clothing still never stack (each carries its own wear, contents or look). Weight limits still apply.
* Tests: 403 simulated (new: weapons, stack defaults).


## World and admin (owner requests, brought forward from Milestones 7 and 10)

### wasteland_world 0.1.0 (new)
* One server clock (48-minute day by default) and one weather for everyone (dynamic, weighted, transitions), with exports to control them.
* Empty world: no pedestrians, traffic, parked cars, police, trains or boats (OneSync population off for bucket 0, plus client density).
* Silence: no ambience, music or radio, police scanner, distant sirens or music emitters. Gameplay sounds are kept. Everything is switchable in `world.lua`.

### wasteland_admin 0.1.0 (new)
* Admin panel (F10 or `/admin`) with Players, Bans, Server & world, and Action log tabs. Every action is checked on the server and logged to `wl_admin_log`.
* Players: teleport to, bring, heal, revive, freeze, kick, ban, set survival stats, give items, open or clear inventory.
* Bans by player or license, timed or permanent, stored in `wl_bans`, checked on connect, can be lifted.
* Server: module status, recent warnings and errors, announcements, time and weather, noclip and invisibility.

### Other
* wasteland_players: `RegisterAdmissionCheck` (other modules can refuse connections; a broken check never locks players out).
* wasteland_survival: `Heal`, `Revive`. wasteland_inventory: `OpenForAdmin`, `ClearInventory`, `GetItemList`, and a client "open" event.
* Tests: 383 simulated + 22 on real MariaDB (bans, action log).

## Milestone 4: survival, HUD, death and respawn

### wasteland_survival 0.1.0 (new)
* Server-owned hunger, thirst, bleeding (3 levels, from hard hits, clotting), infection (grows, treatable, lethal at 100) and body temperature (weather, time, altitude, wet, clothing warmth). The rules are pure functions in `shared/model.lua`. Moderate pace by default: food 2 h, water 1.5 h.
* Consumables from config (food, drink, bandage, rag, painkillers, antibiotics), used through the inventory, with eat, drink and treat animations. Items that would do nothing are refused and kept.
* Death: everything except hotbar items goes into a body bag (map marker for the owner, 2 h lifetime). There is a "You died" screen with a countdown, and respawn happens at a random configured point with reset stats. spawnmanager autospawn is off.
* HUD (bottom left): compact, only when it matters, or off (`/hud`, remembered per player).
* Exports: GetStats, AddInfection, AddBleeding, ModifyStats, IsDead. Events: wasteland:survival:died and respawned.

### wasteland_inventory
* DeathDrop export (body bags), GetWornItems, the item field `warmth`, and migration 3 (drop owner, label and expiry). New survival items in config.

### Tests
* 341 passing: survival rules (unit), survival server (integration), body bags, HUD logic (Node), and body bags on real MariaDB.

## Milestone 3B: inventory and item API

### wasteland_inventory 0.1.0 (new)
* Tetris-style grids: items have a size and can be rotated; weights; stacks; durability; metadata.
* Pockets (6x4, 12 kg), worn items (head, eyes, torso, back, legs, feet), backpacks that add their own grid when worn (never nested).
* Operations: move, rotate, merge, split, wear (with swap), take off, drop, use, hotbar (keys 1-5). All decided by the server, atomic, saved as one transaction each in an ordered write queue; refused while the database is down.
* Items on the ground (stored, visible as bags, E to search, expire after 60 minutes) and stashes for modules (`OpenStash`).
* Clothing as items: the starting outfit from the creator becomes worn clothing; empty slots show configurable "naked" parts.
* Exports: AddItem/RemoveItem (all or nothing), GetItemCount, RegisterItem, RegisterUsable, OpenStash, GetInventory, GetItemDefinition, IsLoaded. Admin `/give`.
* Inventory screen (key TAB): drag and drop with placement preview, R to rotate, right-click menu, shift-click quick move.

### Other
* wasteland_appearance: fires `wasteland:appearance:saved` (server) and `wasteland:appearance:client:applied` (client); client export `IsEditing()`.
* Tests: 302 (grid unit tests, 30 inventory integration tests incl. duplication, races, forged requests, disconnects and database failures, 6 Node tests for the screen, inventory SQL on real MariaDB).

## Milestone 3A: UI shell, character select, character creator

### wasteland_ui 0.1.0 (new)
* NUI shell with a screen manager: modules open screens whose scripts live in their own resource; actions come back as `wasteland:ui:client:action`; NUI focus handled per screen; screens of stopped resources close automatically; screen errors are printed in F8.
* Design system (`style.css`) and DOM helpers (`h`, `button`, `slider`, `picker`, `tabs`).

### wasteland_players 0.2.0
* Character select screen (create, play, delete with name confirmation) using wasteland_ui; the chat command remains as a fallback.
* The player is held (frozen, invisible, no collision) until a character is loaded (K-15).
* A new character is played immediately after it is created.
* The character state bag is replicated to the player's own client; `requestCharacters` from the screen no longer sends chat lines; the create result includes the slot and character id; client export `IsReady()`.

### wasteland_appearance 0.1.0 (new)
* Character creator: male/female freemode, heritage, 20 face features, hair and colours, eye colour, 13 overlays (beard, eyebrows, makeup, ageing, ...), starter clothing (top, undershirt, arms, legs, shoes, hat, glasses), live preview, fixed camera with rotation.
* Opens automatically for characters without a look; admin command `/appearance <id>` reopens it (cancellable).
* Server-side validation (schema, allowed slots, `blockedClothing`), write-through save, applied on load and after every respawn.

### Tests
* `tests/integration/appearance.lua` (18) and `tests/js/ui.test.js` (14, Node) run from `tests/run.lua`. 248 tests pass.

## wasteland_players 0.1.1 (runtime fix, 2026-10-10)

### Fixed
* Every connection was refused with "Unknown error" (runtime test R2.5): the players module called `deferrals.done(nil)` to accept, which FiveM treats as a rejection. It now calls `done()` with no argument. The test mock reproduces FiveM's behaviour (K-16).

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
