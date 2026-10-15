# Changelog

## Zombie sounds included; Chiliad camp; respawn at the safe zones (owner)
* The zombie sound files are now part of Wasteland Core: `resources/[wasteland]/wasteland_zombiesounds` (Zombie Sound Pack, Free Version, by Catastic, plus a few extra clips). The recipe and the updater install them; `ensure wasteland_zombiesounds` is in the txAdmin server.cfg (the updater offers to add it). A server that had the folder outside `[wasteland]` should delete that copy.
* New camp: Chiliad Mountain Camp (general trader, medic, gunsmith).
* After dying you respawn at one of the safe zones: Sandy Shores, Paleto Bay, Pillbox, Chiliad.

## Survivor's guide (F2 or /guide)
* Progress: 22 milestones that tick off by themselves as you play (search a container, eat, first kill, craft, treat a wound, trade, blueprint, campfire, hunt, cook, group, vehicle, 25 kills, a camp job, tool cupboard, supply drop, a player trade, skill level 5, two hours without dying, a world event, 250 kills, a maxed skill). Counted milestones show progress (7 / 25). A message and a sound when one is done.
* "Try next": the next three unfinished milestones, each with a hint on how.
* Stats: time alive this life, longest life, best skill level, zombies killed, places searched, things crafted, animals harvested, meat cooked, wounds treated, trades, jobs, supply drops, blueprints, deaths.
* How to: pages on controls, staying alive, the dead, looting and crafting, camps and groups, vehicles, hunting, building, skills.
* guide.lua: the key, every milestone (label, hint, stat, count) and every page - edit them freely. Saved with the character; no tables of its own.
* New events other scripts can use: wasteland:basebuilding:cupboardPlaced, wasteland:hunting:fireLit, wasteland:hunting:cooked, wasteland:survival:consumed. Export AddStat(source, stat, amount) for your own milestones.
* Tests: the old zombie hit tests now use plain zombies (a random special infected made them fail now and then).

## Skills: level up by doing (/skills or F9)
* Six skills, levels 1 - 10, saved with the character: Scavenging (searching), Crafting, Medicine (bandages, medkits, antibiotics), Hunting (harvesting), Fitness (sprinting), Combat (zombie kills).
* Each level makes you a little better; level 1 has no bonus, level 10 the full one: searches 30 % faster and a 25 % chance of an extra find; crafting 30 % faster and a 20 % chance to get a material back; healing items heal 50 % more; 50 % more meat; stamina lasts longer; 20 % more melee damage and weapons wear 30 % slower.
* A level-up message and sound. The skills screen shows every skill, its XP bar and what it gives you now.
* Dying costs 10 % of the progress into each skill's current level - never a level (skills.lua `deathPenalty`: none / some / all).
* skills.lua: XP per action, the bonuses, the level curve, an XP multiplier (double XP weekends). Exports for other scripts: GetBonus, GetLevel, GetSkills, AddXP.
* Loot, crafting, hunting, survival and weapons ask for the bonus only when wasteland_skills is running; without it everything works as before.

## Zombie sounds
* Zombies groan (now and then when calm, more often when coming at you), make a sound when they swing, when they are hit (with a thud) and when they fall dead; screamers and howlers call (heard up to 90 m). Sleepers are quiet.
* Every player hears the zombies near them, louder when closer and from the side they are on.
* The sound files are a separate resource, `resources/wasteland_zombiesounds` (Zombie Sound Pack, Free Version, by Catastic, plus the zombey clips), kept on the server and not in the public repository: copy the folder to another server yourself and add `ensure wasteland_zombiesounds` to its server.cfg. Without it zombies are silent as before.
* zombies.lua `sounds`: on/off, volume, range, how often they groan (every file list: wasteland_zombies/client/sounds.lua).

## Zombies break through base walls, doors and gates
* A zombie whose target hides behind base walls (it stops getting closer), or inside a base's safe zone, attacks the nearest wall, doorway, window frame, half wall, door, gate or garage door in the way instead of giving up. When the piece breaks it goes after the player again; after 60 s it gives up.
* Damage per hit: wood 4, stone 2, metal 1 (basebuilding.lua `raid.zombies`; 0 = zombies cannot hurt that material). Open doors are left alone. Repairs work as usual.
* The owner gets "Zombies are attacking your base!" (at most every 3 minutes).
* Every hit is checked by the server like a player hit: the game reporting it runs the zombie, the zombie stands at the piece, not faster than its swing.
* Pieces inside the 12 m zombie-free zone round a tool cupboard stay out of reach (zombies cannot enter it); walls at its edge and outside it can be attacked.
* Off: zombies.lua `ai.barricades.enabled = false`, or basebuilding.lua `raid.zombies.enabled = false`.

## Zombie AI upgrade (zombies.lua `ai`; `ai.enabled = false` restores the old zombies)
* Personalities (share by day / night, configurable): wanderers, stalkers (follow from a distance, circle round, charge later, may back off and come again), ambushers (wait still, jump anyone close; optional `ambushPoints`), sprinters (slow until alerted, then sprint bursts with cooldowns), sleepers (lie down until you come close or make noise), pack hunters (surround you from different sides, no stacking).
* Senses: a view cone (less to the sides), still players are harder to see and runners easier, nothing through walls, engines heard (idling less), a short reaction time per personality. Memory: zombies go to where they last saw you and search around, then go back to what they were doing; a chase ends after 2 minutes or 160 m.
* Special infected (they keep their normal model): screamer, brute, howler, spitter (telegraphed, checked by the server), hunter (goes for players on their own), crawler (off). Bosses juggernaut, alpha, butcher and night terror are off until given a chance.
* Horde layer: the nearest zombies answer a noise (max 15), each to its own spot around it; repeated gunfire in one place brings more from further out; explosions and car crashes are noises; a cooldown per sound and spot; optional building `entryPoints`. Only existing zombies: nothing new spawns.
* Day / night: dawn, day, dusk and night change sight, chase speed, horde size and the personality mix; zombies change gradually, only when calm.
* Nothing else changed: spawning, population, models, loot, safe zones and every other system are as they were; no database change. In-game checks: docs/IN_GAME_TESTS.md R43.

## Smaller backpacks (they covered most of the screen)
* Small backpack: 8 x 8 (was 10 x 10). Hiking backpack: 12 x 10 (was 15 x 15). Weight limits unchanged (100 and 175 kg).
* A bag that holds more than fits in its new size keeps everything: stacks move into the smaller grid, and a bag that really cannot fit them stays just big enough until it is emptied a bit.

## Inventory: Sort button
* Every grid (pockets, the open backpack, storage, trunks, the ground) has a Sort button.
* Part stacks of the same item merge (same condition and metadata only); then everything is packed from the top left, grouped by category (weapons, ammo, medical, food, drinks, tools, materials, clothing, armor, bags, other), biggest first.
* Hotbar slots follow a stack that was merged into another. One saved step; if it would not all fit, nothing changes.

## A small zombie-free zone around every tool cupboard
* Within 12 m of a tool cupboard, zombies act as they do in camps: none spawn there, they stop chasing players inside, they cannot hit them, and ones that wander in are removed. You can build in peace.
* basebuilding.lua `cupboard.safeRadius` (0 turns it off). Exports: `IsInBaseZone(coords)` on the server and on the client.

## Fix: the garage door swung sideways like a normal door (owner report)
* Garage doors now roll up into their frame when opened (about a second) and back down when closed, and they stay up or down after a restart and for players who come near later.
* How far they go up: the door's own height less 0.3 m, or the piece's `openLift` in basebuilding.lua.

## Fix: gaps at wall corners; ramp distance when turned round (owner report)
* Walls, doorways, window frames and half walls snapped to the outside of the foundation edge, so two walls on neighbouring edges left a gap the thickness of a wall at the corner.
  * They now stand on the edge, their outer face flush with it; at a corner they overlap instead.
  * basebuilding.lua `placement.wallsInset = true` (false: the old way).
  * Pieces already built stay where they are.
* Ramps:
  * Turned round (R), the distance was measured from the wrong end of the ramp; fixed.
  * "On top of the foundation" (Q) now lies on the foundation, flush with its edge, instead of hanging off the outside.

## Base building: ramp up/down, gap tuning that is kept (owner report)
* Ramps snap four ways:
  * R turns them up or down.
  * Q puts them beside the foundation (top level with it: walk up onto it) or on top of the foundation.
  * The help line shows which.
* Gaps between snapped pieces: Ctrl+wheel while placing (Ctrl+Shift+wheel for big steps) is now remembered per piece on that computer, not only for one placement.
* /bbsnap lists the values (and prints a line to paste into basebuilding.lua `placement.overlap` for everyone); /bbsnap reset clears them.

## Base building (new module wasteland_basebuilding, ported from sbb-basebuilding)
* **Ported from sbb-basebuilding** (QBCore / ox) to Wasteland Core:
  * Wasteland characters, inventory (items and stash grids), target (Left Alt), UI screens, the lockpick minigame and the database (migrations).
  * Nothing from QBCore or ox is needed.
* **Needs the "sinor-buildingProps-v2" props pack.** It is NOT part of Wasteland Core: it is a Cfx escrow asset pack, licensed to the account that owns it. Install it on the server and `ensure` it before wasteland_basebuilding; the module warns if it is missing.
* **Tool cupboards** claim 40 m.
  * The owner, players they authorize (by player id), and the owner's group (/group) may build, open doors and storage, repair and remove there.
  * The cupboard screen shows upkeep per material, who has access, Supplies, Repair all and Remove.
* **Building:** use a Building plan (craft: rag + duct tape, or buy one) to open the build menu.
  * Pieces: foundation, wall, doorway, window frame, half wall, ceiling, frame, ramp, gate frame, doors, gate door, garage door, storage (3 sizes).
  * Pieces snap to foundations and to each other.
  * Controls: E place, wheel turn, arrows turn freely, Shift+wheel height, Tab snapping, Backspace cancel.
* **Upgrades** wood → stone → metal, repairs, and doors with E.
* **Raids:** explosives damage pieces, wood also takes melee hits.
  * Doors and storage can be lockpicked (the minigame; a failed try breaks the pick).
  * Owners are told when their base is lockpicked, also later if they were offline.
* **Upkeep** comes from the cupboard's supplies (wood planks, stone, metal sheets): 1 a day per piece of each material. Short of a material, its pieces decay.
  * Fix from the original: the cost was rounded up on every 5-minute tick (about 288 a day per piece); the fraction now carries over.
* **Items and recipes:**
  * New items: building plan, stone.
  * Wood planks are back in loot and at the trader and weigh 0.5 kg.
  * Metal sheets can be crafted again (no station).
* Tables `wl_bb_cupboards`, `wl_bb_auth`, `wl_bb_props`, `wl_bb_notices`. Config: basebuilding.lua.

## Update notice: the console says when GitHub has a newer Wasteland Core
* 15 s after the server starts, and every 6 hours, the core compares the installed version with GitHub. The installed version is `wasteland_core/VERSION.txt`, written by the updater (a resource may only read its own files); a fresh install records the newest version on its first start.
* If there are updates, a yellow banner in the console shows how many, the installed and newest versions, the titles of up to 10 changes, and how to update (run update_wasteland.bat).
* Admins (wasteland.admin) get a line in chat when they join while updates wait.
* framework.lua: `updateCheck = { enabled, repo, branch, everyHours }`.

## Bigger vehicle trunks
* Trunks are now 15 x 12 cells and hold 300 kg (were 6 x 5, 80 kg). Pickups and vans (Bison, Sadler, Rebel, Rat-Loader, Bodhi, Duneloader, Surfer, Rumpo, Youga) are 18 x 14 and hold 450 kg.
* vehicles.lua: `trunk = { width, height, maxWeight, models = { <model> = { width, height, maxWeight } } }`.
* A stash that is already loaded takes a new size from the settings straight away (never smaller than what is in it), so existing trunks grow without a restart.

## Inventory: the backpack opens on demand
* Opening the inventory shows the pockets only. To use the worn backpack, right-click it in the Back slot and choose Open backpack (or double-click it). Its grid then shows next to the pockets, with a Close button.
* With the backpack open and nothing else open, double-click (or Shift+click) moves items between the pockets and the backpack. Dragging works as before.
* Each time the inventory opens, the backpack starts closed. Items you buy, loot through Take all, or harvest still go into the backpack when the pockets are full.

## Fix: armor plates wore down every login or server restart (owner report)
* While a plate is worn, the game keeps GTA's armour full and reports what it loses as hits on the plate. A new ped (logging in, a server restart, respawning, a new look) starts with 0 armour, and that was counted as a 100-point hit: about 25% of the plate each time.
* Now only armour lost after it was full on the same ped counts, and not while the screen is faded out (teleports). The server also ignores armour reports for 15 s after a character loads.
* Clothing: only zombie hits wear it, and not while a player is protected (creating a character, choosing where to wake up).

## Fix: "Last known position" put you on the roof; no more idle camera (owner reports)
* After spawning, the ground was looked for from 5 m above the point, and inside a building the first thing found is the roof.
  * "Last known position" now puts you exactly where you were, after the building's interior has loaded.
  * Camp spawns look for the ground from just above the point.
* GTA's idle camera (it starts slowly panning when you stand still) is switched off: world.lua `idleCamera = false`.

## Fix: the cooking window fell back to the list after the first piece (owner report)
* The server sent "pieces done" as `done`, and the window read any number above 0 as "finished". After the first piece, the window showed the list again while the server was still cooking, and Cook did nothing.
* The end of cooking is now its own flag (`finished`). The window keeps showing "Cooking 3 of 5" until the last piece, and Cook works again right after.

## Fix: campfires stopped working after a while (owner report)
* The game deletes server-made props it thinks nobody needs, and the fire was one: the server then no longer knew the fire, so Cook did nothing. Fires are now kept (orphan mode 2), and a lost fire prop is made again in the same place.
* A fire now burns as long as anyone is within 30 m. Left alone for 15 minutes (`idleMinutes` in hunting.lua; it replaces `burnMinutes`), it goes out and goes back to its owner.
* If a fire cannot be placed, the match and firewood are given back too.

## Fix: supply crates landing on roofs, and "too far away" when you reach them (owner report)
* The crate looked for the ground from 50 m above its point, so it could land on a roof over the point. It now looks just above the point, so it lands on the ground there.
* Opening checks the distance along the ground (3.5 m) and allows 4 m up or down, for slopes and steps. Someone on a roof high above still cannot open it.

## Hunting, campfires and cooking (new module wasteland_hunting)
* **Animals:** deer, boars, rabbits and coyotes wander near every player.
  * Three per player, 40 on the map at most.
  * They spawn 90-200 m away, not on roads, in water or in camps.
  * They are removed when nobody is within 350 m; a carcass lasts 10 minutes.
* **Harvesting:** hold Left Alt on a dead animal and choose Harvest. It needs a blade: knife, switchblade, machete, hatchet or battle axe.
  * It takes 6 seconds of kneeling; moving or X cancels.
  * Yield: raw meat (deer 2-4, boar 2-3, coyote 1-2, rabbit 1, any other animal 1-2), and an animal pelt from deer, boars and coyotes (traders pay 15).
  * Any animal can be harvested, also ones this module did not spawn.
* **Campfire:**
  * Craft it from 3 scrap metal, or buy it.
  * Use it from the inventory: it is placed in front of you. Lighting it takes 1 match and 2 firewood.
  * It burns 30 minutes and warms you within 5 m.
  * Anyone can cook on it. The player who made it can put it out and pick it up again. When it burns out, it goes back to its owner.
* **Cooking:** Left Alt on the fire and choose Cook. Pick how many raw meat (up to what you carry, with - / + / All).
  * Each piece takes 5 seconds; the window shows "Cooking 2 of 5" and has a Stop button.
  * Walking away stops it.
* **Eating:**
  * Cooked meat: food +45 and a little health.
  * Raw meat: food +10, but infection +5.
* **New items:** raw meat, cooked meat, animal pelt, matches, firewood, campfire.
  * Matches and firewood are found in trash, tool sheds and crates, and sold by the general trader.
* Config: hunting.lua.

## Trading between players (new module wasteland_trade)
* Hold Left Alt on another player: **Trade**. They get a popup (Trade / No thanks); the request lasts 30 seconds.
* One window with three lists side by side:
  * your items (Offer);
  * your offer (change the amount, remove);
  * their offer.
* Each list scrolls on its own, so any number of items fits without overlapping. Up to 40 different stacks per side.
* Both press Accept. Any change to either offer takes both accepts back, so nobody can swap something at the last second.
* The swap is all or nothing:
  * whole stacks keep their condition (and a bag keeps its contents);
  * part of a stack splits off;
  * cash trades like any item;
  * if anything does not fit (room or weight), nothing changes and the trade stays open.
* Moving more than 8 m apart, dying or leaving cancels the trade. Traded items leave the giver's hotbar.
* Inventory exports: `GetTradeable(source)` and `Trade(a, offerA, b, offerB)`. Config: trade.lua.

## Inventory: a hover box with the item's name and amount
* Hovering over an item shows a box to the bottom right of the cursor, in large text (18 and 16 px):
  * the item's name;
  * the amount in the stack (dollars for cash) and its condition if it wears;
  * its description.
* The box stays on screen near the edges and hides while dragging. It replaces the browser's small, slow tooltip.

## Traders buy anything you carry
* Every trader buys every item except cash, not only what is on its list. The sell list shows whatever you carry.
* Price:
  * A shop's own `sell` price wins.
  * Otherwise: the item's price in `buyAnything.prices` (guns 60 to 220, gun parts, car parts, kits...), `blueprints` (25) for blueprints, or the item's category (food 4, drink 3, medical 6, material 2, tool 10, clothing 4, armor 30, bags 40, melee weapons 15, ammo 1 a round, other 3).
* What a trader pays is capped at half the lowest price any trader sells the item for, so nobody can buy at one trader and sell dearer at another.
* camps.lua: `buyAnything = { enabled, default, blueprints, categories, prices, except }`.

## Voice chat (pma-voice) and group radio
* Proximity voice with [pma-voice](https://github.com/AvarianKnight/pma-voice) v6.6.2: players near you hear you.
  * F11 cycles whisper, normal and shout.
  * Push-to-talk is the FiveM voice key, N by default.
* Group radio: everyone in your group (/group) is on the group's own radio channel. Hold Caps Lock to talk to them anywhere on the map. You join it when you join, log in, or the group is made; you leave it when you leave, are removed, or the group is disbanded.
* The radio key is Caps Lock, not pma-voice's default Left Alt, which is the interaction key.
* Installing it:
  * The txAdmin recipe downloads pma-voice.
  * The updater offers to install it and add its server.cfg lines.
  * server.cfg.example and the txAdmin server.cfg have the lines: `setr voice_*` and `ensure pma-voice` after oxmysql.
* groups.lua: `radio = { enabled, channelBase, keyName }`.

## Fix: hands up (X and the emote menu) did nothing (owner report)
* The animation dictionary was misspelled (`missminuteman_1ink` instead of `missminuteman_1ig_2`), so the game never found the animation.

## Fix: an "invisible block" when hitting zombies in melee (owner report)
* Zombies were in a relationship group the game treats as neutral toward players. That means no melee lock-on or hit assist, and running or swinging into one plays the bystander "bump", which felt like an invisible wall.
* Zombies and players are now enemies (as bandits already were), set on every player's game. Zombies also no longer block or dodge melee (combat ability 0).
* Not confirmed in-game yet.

## Fix: inventory grid lines did not match the items (owner report)
* The grid lines were always drawn 50 px apart, while the cells now shrink to fit big grids, so they drifted away from the items. The lines now use the same size as the cells, and the border no longer eats into the last row and column.
* The health panel no longer gets pushed off the right edge: the grids leave room for it and it takes the space that is left.

## Choose where you wake up (owner report: random spawn after waiting at character select)
* Returning characters now choose on login: their last known position, or one of the safe camps. The screen stays dark and they stay protected until they arrive. The choice puts them exactly there, whatever happened while they waited at the character screen.
* New characters still pick a camp after the creator. Not after a resource restart, and not while dead (the respawn screen handles that).
* spawnmanager's auto-spawn is now switched off as soon as the client starts, not only after a character is loaded. That was what moved players who waited at the character screen.
* camps.lua: `chooseSpawnOnLogin = true`. Players export `GetSavedPosition(source)`.

## Pockets grow with clothing; bigger backpacks
* Pockets start at 3x3. A worn top adds 2x2, pants 2x2 and an armor plate 2x2: 5x5, then 7x7, then 9x9. The most is 10x10.
* The pockets hold 55 kg. This is set in `inventory.lua` → `pockets` (`bonus` per worn slot, `maxWidth` and `maxHeight`).
* Taking something off is refused while the smaller pockets could not hold what is in them ("make room in them first"). Otherwise stacks outside the smaller grid move inside.
* Nothing is ever lost:
  * Old characters whose items do not fit keep pockets just big enough for them, until they make room.
  * On death, the clothes go into the body bag, and kept hotbar items that no longer fit go in with them.
* Backpacks:
  * Small backpack: 10x10, 100 kg.
  * Hiking backpack: 15x15, 175 kg.
* The inventory screen shows the pockets and backpack side by side, and makes the cells smaller when big grids would not fit on the screen.

## Crafting: rags from any clothing, weapon and ammo blueprints
* Tear up pants (3 rags), shoes (2) or a hat (1), as well as tops. These are known from the start.
* New melee weapons: hammer, pipe wrench, battle axe, brass knuckles and switchblade. Each has its own blueprint, and so does the baseball bat.
* Gun blueprints: pistol, heavy revolver, sawed-off shotgun, pump shotgun, micro SMG, SMG, hunting rifle, carbine and assault rifle.
* Ammo blueprints:
  * Pistol ammo (9mm and .44).
  * Shotgun shells.
  * Rifle ammo (5.56, 7.62 and .308).
* New materials:
  * Gun parts: crates, tool sheds, wrecks, crash sites, military and bandit loot.
  * Gunpowder: crates, crash sites, military and bandit loot, survivor caches.
* The best blueprints are the rarest: rifles at crash sites and military events, the SMG at crash sites.
* Change any of it in crafting.lua, loot.lua and inventory.lua.

## Base building switched off (owner decision)
* The props did not look good enough. `bases = false` in modules.lua, and `ensure wasteland_bases` is removed from the server.cfg templates.
* The code stays in `wasteland_bases`, along with the unit tests for its grid math.
* The building materials are out of loot, crafting and the trader: wood planks, nails, metal sheets and the base flag.
* The item definitions stay, so items players already have remain valid.
* The survival and crafting hooks stay; they are general: warmth sources, respawn points, crafting stations.

## Base building (new module wasteland_bases)
* **Claim:** craft a Base flag (4 wood planks, 2 rags, 2 scrap metal) and use it from the inventory. A preview shows where it goes (E / Q turn, left click place). You claim a 30 m circle.
  * Not within 150 m of a camp's edge or another base.
  * One base per group, or per player who is not in a group. Everyone in the owner's group builds and uses it.
* **Build:** /base or F7 opens the base screen: the pieces, what they cost and what you have. Pick one and place it.
  * The preview stays on so you can keep placing; right click stops.
  * Walls, doors and gates snap to a 3 m grid laid out from the flag.
  * The other pieces go anywhere in the claim.
* **Pieces:**
  * Scrap, metal and fortified walls. Build a better wall over an old one to upgrade it in place.
  * Scrap and metal doors, and a gate wide enough for vehicles. They open and close for the group only.
  * Storage crate and metal locker (shared storage).
  * Workbench: crafting recipes can need a station; metal sheets are made at a workbench.
  * Campfire: warms you within 6 m.
  * Sleeping bag: your group respawns there after dying, with a 5 minute cooldown.
  * Rain collector: makes a bottle of water every 30 minutes, up to 4.
* **Interacting:** hold Left Alt on a piece to open, use or demolish it. Demolishing asks twice and gives back half the materials. Storage must be empty first.
* **Upkeep:** keep scrap metal in the flag's upkeep box.
  * The cost is 1 a day plus 1 per started 10 pieces. A new base is paid for 3 days.
  * Unpaid, the base lasts 72 more hours, then it is removed with everything in it (the owner is warned).
* **How walls are made:** each wall is built from game props for the scavenged look, plus hidden solid panels that fill it exactly, so it blocks players whatever the props look like.
  * Admins: `/baseadmin preview` shows every piece in a row, named, so the props can be tuned in bases.lua.
  * `/baseadmin remove` removes the nearest base.
* **New items:**
  * Wood planks: trash, sheds, crates, the trader.
  * Nails: craft 20 from 1 scrap metal, or buy them.
  * Metal sheet: workbench.
  * Base flag.
* **Other modules:**
  * Survival: `RegisterWarmthSource(name, fn)` and `RegisterRespawnPoint(name, fn)`.
  * Crafting: recipes take `station`, plus `RegisterStation(name, label, fn)`.
* Tables `wl_bases` and `wl_base_pieces`. Config: `bases.lua`.

## More food and drink
* 18 new items, each with its own picture:
  * Food: canned tuna, canned salmon, chicken soup, country stew, MREs (beef and chicken), chips, peanut butter, bread, apple, banana, orange.
  * Drinks: Sprunk, coffee, milk, grape juice, beer, whiskey.
* They differ in what they do. Soup, stew, coffee and whiskey warm you up. Fruit gives a bit of water as well as food. Salty food (chips, tuna, peanut butter) makes you thirstier. MREs are a full meal. Whiskey warms you but dries you out.
* Found in fridges, vending machines, trash and crates. Most of them are also sold by the general trader.
* Change the effects in survival.lua (consumables), the items in inventory.lua, where they drop in loot.lua and prices in camps.lua.

## Groups (new module wasteland_groups)
* /group or F6: make a named group (3-24 characters, unique), invite players by id or from a "near you" list, accept or decline invites (they expire after 2 minutes).
* Members see each other on the map: blue for members, yellow for the leader, red when down. Updated every 2 seconds.
* The leader can remove members, make someone else leader, rename the group, and disband it. Members can leave; a leader must hand over first (if they are the only member, leaving disbands the group).
* Groups are saved in the database (wl_groups, wl_group_members) and last across restarts until the leader disbands them.
* Config: groups.lua (maxMembers 8, name length, invite time, marker update rate, command). Exports for other modules: GetGroupOf(characterId), SameGroup(a, b).
* Tests: 726.

## Updater: works wherever it is saved (owner report)
* update_wasteland.bat finds update_wasteland.ps1 or update.ps1 next to it (and says where to get it if neither is there).
* The updater finds the server folder itself when it is not in it: it looks in its own folder, its parent folders and their sub-folders (e.g. txData\MyServer.base) and asks which one if there are several.


## Fix: zombies only hurt you when the swing lands (owner report)
* Before, damage was sent the moment a zombie within 2.6 m started its attack animation, so being near one hurt even when it never touched you.
* Now a zombie within 2.2 m starts a swing; 0.45 s later it lands and hits only if you are still within 1.7 m, in front of it (about 60 degrees either side), with nothing in between and not in a vehicle. Step back or sideways in time and it misses. The server refuses hit reports from further than reach + 1 m. zombies.lua `attack = { range, hitReach, windupMs, cooldownMs }`.
* Tests: 709.


## Updater for other servers
* tools/update.ps1 (+ update_wasteland.bat): stop the server, double-click, start it. Shows what is new since the installed version (VERSION.txt), backs up the database (mysqldump / mariadb-dump, from the server.cfg connection string) and the old resources, installs the newest version from GitHub keeping the server's settings and zombie models (differing settings files get a .lua.new next to them), adds new settings files, offers to add missing ensure lines to server.cfg, updates itself.
* The txAdmin recipe (1.0.3) puts the updater into the server folder.
* Tested on an outdated server folder: settings kept, new settings file added, missing ensure lines added, database and files backed up, custom zombie models kept.


## New players: protected, $50, choose where to start (owner request)
* Protection: while choosing or making a character and until a new character has arrived at their camp, a player is protected (player state `wlProtected`): no damage from the server (survival Damage refuses), zombies do not notice or hit them, bandits ignore them. (Before, a zombie could kill you in the character creator.)
* New characters start with $50 cash (inventory.lua startingItems).
* Choose where to start: after making a new character, a "Where do you start?" screen lists the safe camps (traders shown); the character is taken there, protected for a few more seconds. camps.lua: optional `spawn = { x, y, z, heading }` per camp (default: its centre). Server event wasteland:camps:spawnChosen(source, campId).
* Tests: 707.


## Milestone 11: txAdmin recipe
* The repository is on GitHub: https://github.com/gosalosey/wasteland-core (credits for the item pictures in the README).
* txAdmin recipe (txadmin/recipe.yaml): installs FiveM's base resources, oxmysql (latest release), Wasteland Core, a ready server.cfg (build 3570, OneSync, start order, admins, server icon) and creates the database. Recipe URL: https://raw.githubusercontent.com/gosalosey/wasteland-core/main/txadmin/recipe.yaml
* Clean-install test: the published recipe was run into an empty folder and an FXServer started from it: all modules running, the database tables created.
* docs/INSTALL.md.


## World events (owner request)
* New resource wasteland_events (module "events", config events.lua; added to server.cfg). Every 35 minutes (with players online) an event starts at one of 10 points (never in a camp): a message for everyone and a red marker.
  * Helicopter crash: a burning crashed helicopter, 16 zombies and 4 bandits with pistols; the wreckage holds military loot.
  * Ambushed convoy: wrecked trucks and crates, 6 bandits with pistols and micro SMGs, 8 zombies; convoy cargo.
  * Bandit hideout: tents, a campfire, 7 bandits with pistols and sawed-offs; their stash.
  * Horde: 32 zombies at a wrecked car; a survivor cache.
* The danger appears when a player comes within 150 m. Bandits shoot players, take cover, stay near their spot and leave zombies alone; each drops a small bag (pistol ammo, cash, sometimes medicine). The loot stays locked ("Too dangerous: 2 bandits and 5 zombies are still here.") until every bandit and event zombie is dead; then everyone is told, the marker turns green and the loot (shared) opens. The event ends 15 minutes later.
* New loot tables: helicrash, military, bandit_stash, survivor_cache.
* Admins: /event (list), /event <type>, /event <type> here, /event end.
* Exports GetEvents, StartEvent, EndEvent; server events wasteland:events:started / cleared / looted / banditKilled.
* camps.lua: the owner's move of the Legion Square camp to Pillbox Hospital taken into the repository.
* Tests: 704.


## Testing with two games on one PC
* players.lua `duplicateSession = 'test_second_account'` (testing only): a second FiveM game on the same Rockstar account (started with -cl2) joins as a separate account ("...:test2") with its own characters, instead of kicking the first. Switched on in the owner's live config while the server is private; the shipped default stays 'kick_old'.
* Tests: 688.


## Zombie sync: same zombies for everyone, and a check (owner request)
* Audit: zombies and vehicles are networked entities created by the server (OneSync sends them to every player near them); ground bags, supply crates, traders, tailors and loot containers are drawn by every player's game from what the server sends to everyone. Nothing deletes zombies on one player's side.
* Fixed: a zombie's blood and stagger were only applied by the game that runs it, so other players could see a clean zombie walking normally. Every game now applies them to every zombie it shows.
* New: /zombies sync (admins, or the server console). Every player's game lists the zombies it shows within 150 m and the server compares that with the zombies it has there: "sees 4 of the 4 zombies near them", or MISSING / shown but not on the server / no answer. Output in F8 (or the console).
* Tests: 687.


## Zombies: more aggressive, custom kinds and models (owner request)
* More aggressive: they see 70 m by day / 40 m at night (was 35 / 18), hear running 45 m, walking 18 m, crouching 6 m, keep chasing 25 s without seeing you (was 10), hit every 1.1 s (was 1.5), walkers a little faster, more runners (25 % by day, 45 % at night). New: a zombie that spots a player brings the others within 25 m (`detection.alertRadius`).
* Any number of zombie kinds (zombies.lua `kinds`; walker required): each with its chance, speed, damage, infection, bleeding, `shamble` and its own `models`. A commented "brute" example is in the config.
* Custom models: new resource wasteland_zombiemodels (put files in its stream folder; add-on peds also in its peds.meta; added to server.cfg). Players' games report models they do not have; those are skipped with a console warning, so a bad model never makes invisible zombies.
* Tests: 684.


## Repair kits ask what to repair (owner request)
* Using a sewing kit or an armor repair kit ("Use (choose what to repair)…" in its right-click menu, or its hotbar key) opens a list of the damaged pieces it can fix, worn and carried, most worn first ("Pants · 42% (worn)"); pick one, or Cancel. Nothing is used until you pick. From the hotbar the inventory opens with the list.
* Right-clicking a damaged piece still offers "Repair with ..." directly.
* Tests: 674.


## Milestone 10B: SDK guide and example module
* docs/SDK_GUIDE.md: recipes for adding items, food and medicine, weapons, loot (files and in-game), recipes and blueprints, camps, traders and shops, jobs, zombie kinds, vehicles, emotes, tailors and supply drops; a step-by-step walk-through of writing a module; how to test it.
* New resource wasteland_supplydrops (module "supplydrops", config supplydrops.lua; added to server.cfg): the SDK example and a real feature. Every 45 minutes (with players online) a military crate comes down at one of 8 points: map blip and area, a message for everyone, red smoke. The first player to open it fills it (loot table "crate", or its own item list); everyone shares what is inside; gone after 20 minutes. Drops are recorded in `wl_supply_drops`. Admins: /supplydrop, /supplydrop here.
* It shows every part of the SDK: config schema, async init with a migration, a token-stopped thread, guarded net events with server-side checks, optional dependencies, inventory stashes, target, blips and props, an admin command, exports and server events, unit, integration and real-MariaDB tests.
* Tests: 672 (including the real MariaDB suite).


## Fix: sometimes spawning at a random spot after choosing a character
* Cause: the base server's spawnmanager (with the default map spawn points) could spawn the player after we placed them at their saved spot, and the server could sample the position before the move arrived, saving that spawn point.
* Now: the server only records positions after the client reports the character was placed (or after a minute if a client never does); autospawn is turned off as soon as a character loads; if spawnmanager still spawns the player in the first minute, they are put back at their saved spot.
* Tests: 658.


## Tailor camera controls (owner request)
* At the tailor: drag anywhere outside the panel to look around (left/right circles your character, up/down raises or lowers the camera), scroll to zoom in and out, and quick views: Full body, Face, Top, Pants, Shoes. "Turn around" now swings the camera to your back instead of turning the character.
* Turn the character too: "⟲ Left" / "Right ⟳" (45°), "Half turn", or Q / E (15°); the camera stays put. The character faces the way it did when you leave.


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
