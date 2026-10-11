# Changelog

## Tailors (owner request)
* New resource wasteland_tailor (module "tailor", config tailor.lua; added to server.cfg). Tailor NPCs at Paleto Bay, Sandy Shores and Legion Square, with map blips. Left Alt on one: "Restyle my clothes ($25 a piece)".
* The screen lists only the pieces you wear (hat, glasses, top with undershirt and arms, pants, shoes): style and colour arrows per part, every change shown on your character at once (a camera looks at you; "Turn around"), "Undo all", "Pay $X (N pieces)". Nothing can be added or removed: only what is worn gets a new look. The server checks you stand at the tailor, that each piece is worn clothing, sane values, and takes the cash first.
* Inventory: worn clothes are put on again when an item's look changes (not only when items change); client exports `ApplyClothing()`, `GetClothingInfo()`; server export `GetClothingParts()`.
* Tests: 656.


## Fahrenheit, craft several at once (owner request)
* Inventory health panel: body temperature in °F with how it feels: Freezing / Cold / Comfortable / Hot / Overheating (coloured). The Cold/Hot advice shows °F too.
* Crafting: choose how many (−, number, +, Max; "can make N"), then "Craft xN". They are made one after another (each one timed, "Making bandage (2 of 5)"); moving or X cancels the rest; it stops early if the materials run out ("Made 2 of 3 x Bandage: out of materials."). Up to 50 at once.
* Tests: 646.


## Hotbar on screen, hands up, emotes (owner request)
* Hotbar on screen (bottom middle): the five hotbar slots with picture, key, count and condition. /hotbar shows or hides it (remembered on the player's computer). Hidden in vehicles, while the inventory is open and while dead.
* New resource wasteland_emotes (ensure it after wasteland_ui; added to server.cfg):
  * X: hands up, X again: down. No shooting or punching with your hands up. Ignored while a progress bar or the lockpick game is open (X cancels those).
  * F4: emote menu (search, categories: Gestures, Survival, Sit & lie, Work, Moods, Fitness); 46 emotes. /e <name> plays one, /e c stops, /e alone opens the menu. Whole-body emotes stop when you walk; upper-body ones (wave, salute...) keep playing while you walk. No emotes in vehicles, while dead, swimming or falling.
  * The list is wasteland_emotes/shared/emotes.lua (name, label, category, scenario or animation).
* Tests: 643.


## Named loot props (owner request)
* A prop an admin made lootable and named shows that name to players: the target says "Search Old barrel", the bar "Searching Old barrel", and the container opens as "Old barrel". Names can now have spaces (letters, digits, space, _ - . ' ( ), up to 40); the field is called "Name players see". Unnamed props still show their category.
* Tests: 635.


## Wrecks spawn on clear ground (owner request)
* Before a vehicle first appears, the nearest player's game checks its spot: no prop within 3.2 m, no other vehicle within 4.5 m, nothing solid across a car-sized box (walls, poles, fences, props), no steep ground. If blocked it is moved to the nearest clear spot within 12 m; a new wreck with no room at all goes to another spawn point. Checked once per vehicle (new column `wl_vehicles.spot_checked`, migration 3); vehicles players parked are only ever nudged, never sent elsewhere. If no player answers within 8 s, it appears where it is.
* vehicles.lua: `spotCheck = { enabled, radius, clearance }`. Vehicles admins spawn are placed as they are.
* Tests: 633.


## Admin loot target, health panel in the inventory (owner request)
* Admins: Left Alt on any prop, "Admin: loot container…": a small window to make that prop (every copy of its model) a loot container of a chosen category, with an optional prop name; Change / Remove for props added before. Only admins see the option (the client asks the server once a minute); the server still checks every request.
* Inventory: a Health panel (right column, under anything being looted) with a body outline (colour by health, green tint when infected, blood drops when bleeding, blue/orange edge when cold/hot, a plate when wearing armor), bars for health, food, water and armor, body temperature, and a list of what is wrong with how to fix it (the items that help come from survival.lua consumables).
* Survival client export `GetVitals()`; survival stats carry `cures` and `limits`.
* Tests: 630.


## Admin: prop names, own loot categories (owner request)
* "Looking at" shows a name where one is known: vehicles (their game name), props listed in loot.lua, and props you named when adding them (new optional "Prop name" box). GTA cannot turn a prop's model number back into its name, so other props show "(name unknown)".
* New Loot tab: make your own loot categories. Name, search time, refill time, size, chance it is empty, how many items per search, and the items it can hold (item, least, most, chance weight). Edit and delete them; deleting one stops its props being searchable. They show up in the Coords tab's "Loot as" list. Kept in wasteland_loot's KVP (loot.lua is not changed).
* Loot exports: `SaveLootCategory(id, def)`, `DeleteLootCategory(id)`; `AddContainerModel(hash, type, name?)`. Admin actions `lootTypeSave`, `lootTypeDelete`.
* Tests: 627.


## Admin: make any prop lootable (owner request)
* Admin panel, Coords tab, "Make it lootable": look at a prop, pick a loot container type (Dumpster / Trash can / Fridge / Vending machine / Tool chest / Crate / Mailbox / Wrecked vehicle, each with its loot table) and press "Add to loot". Every prop of that model on the map can then be searched by everyone, right away (no restart). "Change" and "Remove" for props added this way; a list of all of them. Props loot.lua already lists show "Already searchable".
* Kept in wasteland_loot's server KVP (survives restarts; loot.lua is not changed). Loot exports: `GetLootAdminData()`, `AddContainerModel(hash, type)`, `RemoveContainerModel(hash)`. Admin actions `lootAdd`, `lootRemove` (in the action log).
* Model hashes are handled signed and unsigned (target matching, loot lookup).
* Tests: 621.


## Loot in wrecked vehicles (owner request)
* New loot container "Wrecked vehicle": the rusted car, van, truck and bus wreck props on the map (prop_rub_carwreck_*, prop_rub_buswreck_*, prop_rub_trukwreck_*, ...). Left Alt on one: "Search wrecked vehicle" (6 s), shared, refills after 60 min. Loot table `wreck`: mostly scrap metal; rags, duct tape, wheels, jerry cans, engine parts, batteries, siphon hoses, lockpicks, a little cash and ammo.
* Containers can set `reach` (metres from the prop's middle; wrecks: 7) because big props are searched from their side. Stashes take the same `reach` option (inventory OpenStash).
* Admin panel, Coords tab: "Looking at" shows the model hash of the prop or vehicle in front of the camera (to find props that should be lootable).
* Tests: 615.


## Armor plates (owner request)
* New Armor slot in the inventory (Worn) and new items: Armor plate, Armor repair kit, Blueprint: armor plate.
* While a worn plate holds, all incoming damage is stopped: zombie hits (and they cannot cause bleeding; infection still can) and gunshots/blows from players (the client keeps GTA armour full and reports what the game took). The plate loses 0.25 durability per point of damage it stops (`survival.lua` armor.wearPerDamage): a new plate stops about 400 damage. At 0 it breaks ("Your armor plate broke...") and stops nothing until repaired. Falls and other damage the game does not put on armour still hurt.
* HUD: a shield icon shows the plate's condition while one is worn.
* Repair: Armor repair kit (+40%, used up): right-click the plate, "Repair with Armor repair kit", or use the kit (repairs the worn plate first). Sewing kits do not repair plates.
* Get them: crates (plate, kit, blueprint), tool loot (kit); gunsmith sells plates ($750) and kits ($150); craft plates with the blueprint (6 scrap metal, 2 duct tape, 2 rags), kits from the start (2 scrap metal, 1 duct tape).
* New item category `armor`; survival `Damage` export returns `ok, absorbed`.
* Tests: 613.


## Clothing durability and mending (owner request)
* Tops, pants, shoes, hats and glasses have durability (100). Every zombie hit wears out one worn piece (4-10, `survival.lua` clothing.hitWear). The inventory shows a condition bar (red at 25% or less), "Condition 64%" on hover and in the right-click menu; a ruined piece is greyed out and marked RUINED.
* Worn-out clothing keeps you less warm: full warmth when new, at least half while worn, none when ruined (until mended).
* New item: Sewing kit. Right-click a damaged piece: "Repair with Sewing kit" (or just use the kit: it mends the most worn piece you wear, then what you carry). One kit mends 50% (`clothing.repairItems`) and is used up. Found in trash and crates, sold by the general trader ($70), craftable from the start (2 rags + 1 scrap metal).
* Clothing from before this update counts as new.
* Inventory (for every module): item setting `repairs = '<category>'` makes the screen offer "Repair with ..." on damaged items of that category; usable handlers get the chosen item as a 4th argument (`targetUid`). `GetWornItems` now also returns uid, label, category and max durability.
* Tests: 606.


## Vehicle HUD: move and resize (owner request)
* /hud now also edits the vehicle HUD (shown with example values when you are not in a vehicle): drag it anywhere; resize it with the mouse wheel or the - / + buttons above it (60% to 180%); Reset puts it back at the bottom middle, normal size. Saving the HUD keeps it (stored on the player's computer, like the main HUD); Esc / cancel puts it back.
* survival sends the local event `wasteland:hud:editing(on, saved)` so other HUD pieces can join the edit mode.
* Tests: 599.


## Siphoning fuel (owner request)
* New item: Siphon hose (own picture). Left Alt on any vehicle with fuel: "Siphon fuel (hose)" drains the tank into a jerry can that is not full (up to the can's 20 L) in 10 seconds (`seconds.siphon`). The hose is kept. Works on locked cars too (the fuel cap has no lock).
* Found in garage/vehicle loot, sold by the general trader ($60, sells for $15).
* A driver sitting in a siphoned car sees the lower level at once.
* Trader positions at Sandy Shores taken from the live server config (moved by the owner).
* Tests: 598.


## Admin coords, removing your own car lock, lockpick minigame (owner request)
* Admin panel, new "Coords" tab: your position live (X, Y, Z, heading) with Copy buttons for `vector3(x, y, z)`, `vector4(x, y, z, heading)` and the heading alone; the last copied lines stay listed to copy again.
* Car locks: "Take the lock off" (Left Alt on the car) for the survivor who fitted it, and only them (stored per character, new column `wl_vehicles.lock_owner`, migration 2). The lock goes back into your pockets; the old key fits nothing any more. Locks fitted before this update: whoever holds the key can take them off.
* Picking a lock needs a lockpick and a minigame: a pick turns around the lock; press E, Space or click while it is in the green zone to set a pin. Set all 4 pins to open the car; one miss fails the try (the pick may snap, 50%). Each pin: a new zone, the other direction, faster. Esc gives up. Settings in vehicles.lua `lockpick` (`pins`, `zoneDegrees`, `speed`, `speedStep`, `breakChance`, `noise`); the old `chance` setting is gone. The server times the game (results faster than `minSecondsPerPin` per pin are rejected) and checks distance, lockpick and lock again.
* Tests: 595.


## Milestone 10A: admin tools
* New "Live" tab: players online, zombies alive, vehicles (in the world / out right now), gas pumps refilling, containers searched, uptime, module health and the latest warnings and errors; refreshes every 5 seconds while open.
* Server & world tab, world tools: spawn 1-20 zombies around you, clear all zombies, spawn a wreck or a working car in front of you, fix the car you sit in (or the nearest within 8 m), refill every gas pump, teleport to your map waypoint.
* Debug overlays (only for the admin who turns them on): zombie AI (kind and what it is doing), vehicles and wreck spawn points, camp borders, loot containers around you.
* Player tools: spectate, give and take cash, the player's jobs (drop one, reset cooldowns), recipes (teach or forget a blueprint recipe), send to the nearest camp.
* New exports: zombies `SpawnNear`, `GetZombieMode` (client); vehicles `GetVehicleStats`, `FixVehicle`, `SpawnWorking`, `RefillPumps`, `GetSpawnPoints`; loot `GetLootStats`, `GetContainerModels`; quests `GetQuestSummary`, `DropQuest`, `ResetCooldowns`; crafting `GetRecipeSummary`, `ForgetRecipe`.
* Tests: 587.


## Loading screen (owner request)
* wasteland_loadscreen 0.1.0: WASTELAND title and tagline, what the server offers (the dead, survival, scavenging, crafting, weapons, camps, vehicles, jobs), rotating survival tips, a typed-out survivor's log, outbreak counters, and an animated scene (ruined skyline, moon, fog, falling ash, zombies shambling along the bottom). The loading bar follows FiveM's real progress. One self-contained page: nothing to download, works offline.


## Gas pumps: level shown, full again after 2 hours (owner request)
* Standing next to a gas pump shows above it: "Fuel: 35 / 80 L" and "Full again in 1 h 24 min" (or "Full").
* Refill rule changed: a pump is full again 2 hours (real time) after fuel was first taken from it; taking more meanwhile does not restart the clock (`pump.refillMinutes = 120`; the 20 L every 15 minutes rule is gone).
* Tests: 571.


## Gas pumps: refuel at the pump, limited fuel (owner request)
* Park within 8 m of a gas pump, hold Left Alt on the pump: "Refuel vehicle" fills the nearest vehicle straight from the pump (4 L a second; no jerry can needed). "Fill jerry can" is still there.
* Every pump holds 80 L, shared by everyone (vehicles and jerry cans), and gets 20 L back every 15 minutes up to full. A dry pump says when it refills; a pump with little left gives what it has. All numbers in vehicles.lua (`pump`). Pump levels are kept in memory (full again after a restart).
* Fix: vehicle database writes after an action (parts, refuelling, locks, repairs) waited for the database inside a network event and failed; they only reached the database with the next 30-second save. Every vehicle write now runs in its own thread, and the tests fail on any handler error.
* Tests: 570 (new: pump refuel, dry pumps, refills, distance checks, pump rules).


## Vehicle HUD (owner request)
* While in a vehicle (any seat), bottom middle: speed in mph, fuel gauge with litres, engine and body condition (green, yellow at 35% or less, red at 15% or less), Locked / Unlocked for vehicles with a lock, and the reason a car will not run ("There is no battery.", "The tank is empty.").
* Tests: 566.


## Vehicles: never lose a car on relog or restart (owner request)
* Players already come back where they left (their position is checked every 10 s, saved every 60 s and when they leave). Vehicles are now saved as reliably:
  * when the driver gets out (position, damage, the last fuel used), right away;
  * when a player leaves the server (every vehicle that is out);
  * on a server stop or txAdmin restart: one final save that the database finishes on its own (before, the final save waited for the database, which a stopping resource cannot do, so it could be lost; then only the 30-second save counted).
* Tests: 564.


## Milestone 9: persistent vehicles

### wasteland_vehicles 0.1.0 (new)
* 30 abandoned wrecks at 22 spots around the map (Sandy Shores, Grapeseed, Route 68, Paleto Bay, Los Santos, Senora). Nobody owns a vehicle. Each is stored in the database (wl_vehicles) and stays where it was left; the car appears when a player is within 250 m.
* A vehicle needs engine parts, a battery, four wheels, fuel and an engine that is not wrecked. Wrecks miss parts by chance and have little fuel.
* Hold Left Alt on a vehicle: Check vehicle, Open trunk, Install battery, Fit engine parts, Mount a wheel, Refuel (jerry can), Repair (toolkit), Fit a lock, Lock / unlock (key), Pick the lock. Each takes a few seconds (moving cancels); the server checks and does it.
* Fuel: 50 L tank, used while driving (idle and per km); jerry cans (20 L) are filled at gas pumps (Left Alt, "Fill jerry can").
* Trunk: every vehicle has a 6x5 trunk that stays with it.
* Locks (owner request): a car lock locks the vehicle and makes the only key; whoever carries the key can lock, unlock and open the trunk. Without it, a lockpick opens the lock 30% of the time (and breaks it off), snaps half of the times it fails, and the noise draws zombies.
* Destroyed vehicles are gone (record and trunk); new wrecks appear over time.

### Other
* Items: car battery, engine parts, wheel, jerry can, toolkit, car lock, car key, lockpick (pictures from the pack). Sold by the general traders, found in tool chests, crates and trash; lockpicks can be crafted from scrap (known from the start).
* Inventory: `FindItems(source, name)`; stashes that move (trunks) take their current position when opened.
* Zombies: react to any `wasteland:noise(coords, radius)` (lock picking), not only weapons.
* Tests: 560 simulated + 24 on real MariaDB (new: vehicle rules, wrecks, spawning, saving, parts, fuel, repairs, locks, keys, lock picking, trunks, destruction, restarts).


## Milestone 8: quests

### wasteland_quests 0.1.0 (new)
* Jobs from camp traders: hold Left Alt on a trader, "Jobs". The board shows the camp's jobs: what to do, the reward, and New / In progress / Ready to hand in / Done (again in N min).
* Objectives: bring items (counted live, taken at hand-in), kill zombies (anywhere or near a place; only your own kills), go to a place (checked by the server), search loot containers of a type, craft something.
* Up to 3 jobs at once; repeatable after a cooldown. Hand-in at a camp that offers the job: the reward must fit first, then the items are taken; cash and items as rewards.
* Tracker on the right of the screen with each job's progress; job places are marked on the map with a route to the first one.
* 8 jobs: Scrap run, Food drive, Thin the herd, Field dressings, Crate scavenger (every camp); Check the airfield (Sandy Shores), Check the sawmill (Paleto Bay), Clear Pillbox Hospital (Legion Square).
* Exports `GetActiveQuests`, `AddProgress`; event `wasteland:quests:completed`.

### Other
* Zombies: the client reports who killed a zombie (checked: a player near the body); `wasteland:zombies:died` now also passes the killer and the position.
* Camps: `GetCamps` includes the traders' positions.
* Tests: 535 (new: quest rules, every objective type, hand-in, rewards, cooldowns, limits, persistence, board; a test that boots every module with the shipped config files).


## Milestone 7B: crafting

### wasteland_crafting 0.1.0 (new)
* Craft anywhere: key K (or /craft, or the "Crafting (K)" button in the inventory). The screen lists every recipe you know, what it needs (red when you lack it) and how many recipes are left to learn.
* Crafting takes a few seconds with an animation and a progress bar; moving, getting hurt, dying or X cancels. The server takes the materials and gives the result in one go (everything back if the result does not fit).
* Known from the start: rags (tear a top) and bandages (from rags). Learned from blueprints found while looting (rare): weapon repair kit, knife, hatchet, machete, crowbar. Use a blueprint in the inventory to learn its recipe for good (stored with the character).
* Exports `KnowsRecipe`, `TeachRecipe`; events `wasteland:crafting:learned`, `wasteland:crafting:crafted`.

### Other
* Inventory: 5 blueprint items (pictures from the pack); blueprints added to the trash, tools, crate and zombie loot tables; Crafting button in the inventory screen.
* Tests: 514 (new: recipe rules, learning, crafting, materials, timing, no room, persistence, screen).


## Milestone 7A: camps, safe zones, traders

### wasteland_camps 0.1.0 (new)
* Three camps: Sandy Shores, Paleto Bay, Legion Square. Each is a safe zone shown on the map (green circle + marker); entering shows "<camp> - safe zone", leaving "Leaving <camp>".
* Zombies never spawn inside a camp, ones that wander in are removed, they stop chasing players who are inside, and cannot hurt them there.
* Traders (NPCs, hold Left Alt, "Trade"): general trader and medic in every camp, a gunsmith in Sandy Shores. Buy and sell for cash; each item has a stock that refills every 10 minutes; selling to a trader raises its stock. Every trade is checked by the server (at the trader, stock, cash, room in the inventory; money back when the items do not fit).
* Exports `IsInSafeZone`, `GetCampAt`, `GetCamps` (server; `IsInSafeZone` also on the client); event `wasteland:camps:traded`.

### Fixes
* Zombies: `/zombies spawn` checked the spots against the normal 70-140 m ring and refused them all; it now uses the 15-35 m ring it asked for.
* Tests: 497 (new: camp zones and trade rules, trading, safe zones with zombies, trade screen).


## Inventory: carry more, double-click to take (owner request)
* Weight limits raised: pockets 35 kg (was 12), small backpack 35 kg (was 15), hiking backpack 60 kg (was 30).
* Double-click an item in a searched container (or a bag on the ground, a stash) to take it into your inventory: it tops up a matching stack first (ammo onto ammo), then uses free space in your pockets, then your backpack. Double-click one of yours to put it back into the open container. Shift-click still works.


## Milestone 6: looting

### wasteland_loot 0.1.0 (new)
* Every dumpster, trash can, recycling bin, fridge, vending machine, tool chest, wooden crate and mailbox on the map can be searched (hold Left Alt, "Search ..."). Dead zombies are searched the same way ("Search body"), instead of dropping a loot bag.
* Searching takes 3-5 seconds with an animation and a progress bar; moving, getting hurt, dying or X cancels. Then the container opens next to the inventory and you take what you want.
* Containers are shared: what one player takes is gone for everyone. A container refills only once it is empty and its time has passed (40-90 minutes). A body's loot is gone with the body.
* Scarce loot: many containers are empty; mostly junk; food and medicine uncommon; guns rare (crates, bodies). Every table, chance and time is in `loot.lua`.
* Export `RollTable(name)` for other modules (quests, rewards); event `wasteland:loot:searched(source, type, stash)`.

### Other
* wasteland_inventory: `EnsureStash`, `DeleteStash`, `OpenStash` option `open` (shows the screen).
* wasteland_zombies: zombies have a unique id (`wlZombie.uid`), export `GetZombieInfo`, event `wasteland:zombies:removed`; no loot bag while wasteland_loot runs.
* Tests: 475 (new: loot rules, searching, sharing, refills, bodies, abuse).


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
