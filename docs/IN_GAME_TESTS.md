# In-game (runtime) test procedures

These steps need a real FXServer. Record the date, server build (artifact number) and result for each step in the milestone report. A step only counts as **passed** if someone actually ran it.

## Milestone 1: framework foundation

**Setup**

1. Copy `resources/[wasteland]` into your server's `resources/` folder.
2. Add these lines to server.cfg, after the default resources:
   ```
   ensure wasteland_config
   ensure wasteland_core
   ensure wasteland_template
   add_ace group.admin wasteland.admin allow
   ```
3. Make sure no other framework is started for this test (no qb-core, es_extended, ox_* and so on).

| # | Step | Expected result |
|---|---|---|
| R1.1 | Start the server and watch the console | `starting core v0.2.0 (api 1.1.0)`, then `module "template" ... -> running` and `Template module is running (framework Wasteland Core v0.2.0)`. No red SCRIPT ERROR lines. |
| R1.2 | Wait 30 s | A status table ending in `summary: running=2` (`running=4` once Milestone 2 is installed: core, database, players, template) |
| R1.3 | In the server console: `wasteland status` | The same table; `core` and `template` are running |
| R1.4 | `wasteland config validate` | `[ OK ]` for framework.lua, modules.lua, logging.lua and template.lua; then `All configuration files are valid.` |
| R1.5 | Edit `wasteland_config/config/template.lua` to `heartbeatSeconds = -5`, then run `wasteland config validate` | An error naming the file, `heartbeatSeconds` and the range 0–3600. The template keeps running. Revert the edit. |
| R1.6 | `restart wasteland_template` | `template module stopped (resource_stop)`, then it registers and runs again |
| R1.7 | `restart wasteland_core`, then `wasteland status` | `will restart 1 module resource(s)... wasteland_template`, `shutdown complete`, then `restarting module resource "wasteland_template"`. The status shows the template `running`. |
| R1.7b | `stop wasteland_template`, wait 5 s, `restart wasteland_core`, `wasteland status` | The template is **not** restarted (you stopped it on purpose). Run `ensure wasteland_template` afterwards. |
| R1.8 | Set `level = 'verbose'` in `logging.lua`, then `restart wasteland_core` | A precise error for `logging.lua`, `level`; the framework reports config_error and no module initialises. Fix the file, run `wasteland config reload`, and confirm `OK: configuration valid; startup resumed` and that the template is running. |
| R1.9 | Join the server as a player **without** the ACE and type `wasteland status` in F8 | `You are not authorised...` in F8; the server console logs `denied admin command` |
| R1.10 | Join **with** the ACE (or `add_ace identifier.license:<yours> wasteland.admin allow`) and run `wasteland status` in F8 | The status table is printed in F8 |
| R1.11 | Use txAdmin to schedule a restart (or "Restart server") | Before exit, `shutting down (server_shutdown)` and `shutdown complete` appear in the console |

## Milestone 2: database and player persistence

**Setup** (already done on the owner's server on 2026-10-10; see `docs/DATABASE.md` for a fresh install)

* oxmysql 2.14.3 in `resources/[standalone]/oxmysql`
* `server.cfg`: `set mysql_connection_string ...`, then `ensure oxmysql`, `wasteland_config`, `wasteland_core`, `wasteland_database`, `wasteland_players`, `wasteland_template`
* A MariaDB database `wasteland` and a user `wasteland@127.0.0.1` that has rights only on that database

Open the database to check results, using HeidiSQL (installed with MariaDB) or `mariadb.exe` logged in as `wasteland`.

| # | Step | Expected result |
|---|---|---|
| R2.1 | Restart the server from txAdmin and watch the console | oxmysql prints `Database server connection established!`. Then `[database] connected through oxmysql`, `applied migration players #1 create_accounts`, `#2`, `#3`, and `module "players" ... -> running`. No red SCRIPT ERROR lines. |
| R2.2 | Wait 30 s, then `wasteland status` | `core`, `database`, `players` and `template` are `running`, with no `DEGRADED` note. `summary: running=4`. |
| R2.3 | In the database: `SELECT * FROM wl_migrations;` | 3 rows for `players`, each with an 8-character checksum |
| R2.4 | Restart again (txAdmin) | No `applied migration` lines this time. Everything is running. |
| R2.5 | Join the server | You connect normally. Chat shows `You have no characters. Create one with: /character create <first name> <last name>`. The `wl_accounts` table has your license and name, and the identifiers do not include `ip:`. |
| R2.6 | `/character create John Doe` | `Created John Doe in slot 1. Play it with: /character select 1` |
| R2.7 | `/character create J0hn Doe`, then `/character create X Y` | `...contains characters that are not allowed`, then `...must be 2 to 20 characters long` |
| R2.8 | `/character select 1` | `You are now playing John Doe.` The screen fades and you are placed at the Sandy Shores airfield (the default spawn). |
| R2.9 | Walk or drive somewhere memorable. Wait 70 s. In the database: `SELECT pos_x, pos_y, pos_z, play_seconds FROM wl_characters;` | The position matches where you are (within about 10 s of movement), and `play_seconds` is above 0. **If the position never changes, OneSync is off** (server-side position needs it). Record this. |
| R2.10 | Quit the game (F8 → `quit`). In the database, check the position again. | It is where you quit. Console: `character 1 "John Doe" unloaded (dropped: ...)` and `session ended`. |
| R2.11 | Rejoin, then `/character select 1` | You are placed where you quit, not at the airfield. |
| R2.12 | `/character create Mary Jane`, `/character select 2`, then `/character select 1` | Each switch says `You are now playing ...`. The console shows the previous character unloading and saving first. |
| R2.13 | `/character delete 2` | Asks you to confirm with `/character delete 2 Mary` |
| R2.14 | `/character delete 2 Mary`, then `/character list` | `Deleted Mary Jane.` The list shows only John Doe. In the database, Mary's row still exists, with `deleted_at` set and `slot` NULL. |
| R2.15 | While playing, run `restart wasteland_players` in the server console | `issued final saves for 1 character(s) (resource_stop)`. A moment later: `restored 1 session(s) (1 character(s)) after a restart`. You stay connected and are still John Doe (`/character list` shows `(playing)`). |
| R2.16 | While playing, run `restart wasteland_database` | `will restart ... wasteland_players` / `restarting module resource "wasteland_players"`. Then players and database are both `running` and your character is restored. |
| R2.17 | **Database outage:** while playing, stop MariaDB (Windows Services → MariaDB → Stop). Wait 30 s, then `wasteland status`. | `database` and `players` show `DEGRADED: ...unreachable`. `/character create Test Guy` fails with a message. A second player trying to join is refused with `The server database is unavailable...`. |
| R2.18 | Start MariaDB again. Wait 30 s. | `database connection restored`. `wasteland status` shows no DEGRADED. Your character keeps saving (repeat the R2.9 check). |
| R2.19 | **Simultaneous session:** while connected, connect again with the same Rockstar account (for example from a second PC with the same account, or reconnect right after a crash). | The first session is dropped with `You connected to this server from another session.`. The new one joins after the old session is saved. |
| R2.20 | txAdmin → Restart server, while you are playing | Before exit: `shutting down (server_shutdown)`, `issued final saves for 1 character(s) (server_shutdown)`, `shutdown complete` (this also covers R1.11). After the restart, your position is where you were. |
| R2.21 | `tools\backup_database.ps1` (needs `tools\backup.cnf`, see DATABASE.md §3) | A `wasteland-<date>.sql.zip` file appears in the output folder |

Report anything that does not match, with the console lines around it.

## Milestone 3A: UI shell, character select and character creator

**Setup:** `server.cfg` also has `ensure wasteland_ui` and `ensure wasteland_appearance` after `ensure wasteland_players` (already done on the owner's server). Restart the server. Open F8 if anything looks wrong: screen errors are printed there as `[wasteland_ui] error: ...`.

| # | Step | Expected result |
|---|---|---|
| R3.1 | Restart the server, then `wasteland status` | `ui` and `appearance` are `running` |
| R3.2 | Join | Instead of walking around, you see a dark screen titled **SURVIVORS** with your slots (Gosa Row in slot 1, empty slots after it). You cannot move, and you are invisible. The mouse cursor works. |
| R3.3 | Click **Create character** on an empty slot, type `Test Person`, press **Create** | The screen closes. You are placed at the airfield, then the **New survivor** creator opens on the right with a camera on your character. |
| R3.4 | In the creator: Body tab → **Female**, then **Male** | The character switches model each time and stays in view |
| R3.5 | Change mother/father, the resemblance and skin sliders, then go through the Face, Hair, Details and Clothing tabs and change several values | Every change shows on the character immediately. The camera moves closer for Face, Hair and Details, and further away for Body and Clothing. |
| R3.6 | Press the rotate buttons | The character turns. The camera stays still. |
| R3.7 | Press **Done** | The creator closes, the camera returns to normal and you can move. Console: `player N saved the appearance of character N (new)`. |
| R3.8 | Quit and rejoin, select the new character | The **creator does not open again**, and you look exactly as you saved |
| R3.9 | Die (e.g. jump from a height) and respawn | After the respawn you still have your look, not a random skater model |
| R3.10 | Select **Gosa Row** (created before 3A) | The creator opens for Gosa Row, because it never had a look. Finish it. |
| R3.11 | Server console: `appearance <your server id>` | The creator opens titled **Appearance**, with a **Cancel** button. Cancel puts your saved look back. Run it again, change something and press **Done**: the new look is kept. |
| R3.12 | Second account or a friend: try `/appearance 1` without admin rights | Nothing happens. Console: `tried "appearance" without the wasteland.admin ACE` |
| R3.13 | On the select screen, **Delete** an extra character: type the wrong name, then the right one | Wrong name: an error message. Right name: the character disappears from the list. |
| R3.14 | `restart wasteland_appearance` while playing | You keep your look (after your next death you still have it) |
| R3.15 | `stop wasteland_ui`, rejoin | Without the UI you are still held until you pick a character with the chat command (`/character select 1`). Afterwards: `start wasteland_ui`. |

Report anything that does not match, and include any F8 lines starting with `[wasteland_ui]`.

## Milestone 3B: inventory

**Setup:** `server.cfg` has `ensure wasteland_inventory` after `ensure wasteland_appearance` (done on the owner's server). Restart the server. Keys can be changed in Settings → Key Bindings → FiveM.

| # | Step | Expected result |
|---|---|---|
| R4.1 | `wasteland status` | `inventory` is `running` |
| R4.2 | Join with a **new** character (finish the creator), press **TAB** | The inventory opens. The pockets (6x4) hold a water bottle, 2 canned beans and 2 bandages. Under **Worn**, Torso, Legs and Feet hold the clothes chosen in the creator. |
| R4.3 | Join with **Gosa Row** (or any character that already had a look) and press **TAB** | The clothes from its look are now worn items |
| R4.4 | Drag the water bottle to another cell. Start dragging again and press **R** | A green preview shows where it lands (red if it cannot). It moves. R turns it sideways. |
| R4.5 | Close (TAB or Esc), reopen, then rejoin | Everything is where you left it |
| R4.6 | Console: `give <your id> backpack_small` then right-click the backpack → **Wear** | A **Small backpack** grid appears in the middle column, with its weight. |
| R4.7 | Move items into the backpack. Console: `give <id> scrap_metal 30` | Scrap fills the pockets and bag up to their weight limits. Whatever does not fit is **not** given: "Could not give: not enough room". |
| R4.8 | Right-click the canned beans → **Split…** 1, then drag one stack onto the other | Two stacks, then one again |
| R4.9 | Drag the **Top** from Worn into the pockets | Your character's top comes off (bare torso). Drag it back onto Torso: it is on again. |
| R4.10 | Drag an item onto **Drop here...** | A bag appears on the ground at your feet. Close the inventory and walk up to it: "Press E to search". E opens it on the right. Drag the item back. When the pile is empty the bag disappears. |
| R4.11 | Drop something, then restart the server | The bag on the ground is still there with the item (until `dropLifetimeMinutes`, 60 by default) |
| R4.12 | Right-click a bandage → **Hotbar 1**. Close the inventory and press **1** | A message that it cannot be used. Nothing uses bandages yet: survival (Milestone 4) adds that. Right-click the hotbar slot in the inventory to clear it. |
| R4.13 | Two players: one drops an item, both search the pile, both drag the same item at once | Only one gets it, and the other sees "that item is no longer there" |
| R4.14 | Die and respawn | You keep your worn clothes (not the skater model) |
| R4.15 | Watch F8 while doing all of the above | No `[wasteland_ui] error` lines and no SCRIPT ERROR |

If an empty clothing slot looks wrong (for example underwear that does not match), the `naked` values in `wasteland_config/config/inventory.lua` need adjusting for your game build; tell me what you see.

## Milestone 4: survival, HUD, death and respawn

**Setup:** `server.cfg` has `ensure wasteland_survival` after `ensure wasteland_inventory` (done on the owner's server). Restart the server. To test quickly, set values with the admin command `survival <id> <hunger|thirst|infection|bleeding|temperature> <value>` (for example `survival 1 hunger 5`).

| # | Step | Expected result |
|---|---|---|
| R5.1 | `wasteland status` | `survival` is `running`; the inventory applied migration 3 (`drops_owner_label_expiry`) |
| R5.2 | Join and select a character | The HUD at the bottom left shows Health, Food and Water (and Stamina while you sprint), plus the body temperature |
| R5.3 | `/hud` three times | Only when it matters: bars appear only when low. Then off. Then compact again. The choice is kept after you rejoin. |
| R5.4 | Wait a few minutes (or use fast test rates) | Food and Water drop. With fast rates they reach 0 and you lose health slowly. |
| R5.5 | TAB, right-click canned beans → **Use** | An eating animation, Food goes up, one can is used. With a full stomach: "You do not need that right now." and nothing is used. |
| R5.6 | Fall from a height or get hit hard (several times if needed) | Sometimes a **Bleeding** chip appears and health drops slowly. **Use** a bandage: the bleeding stops, you heal a little and see "You bandage your wounds." |
| R5.7 | Console: `give <id> antibiotics 1`, then `survival <id> infection 70` (Milestone 5 does this through zombies) | An **Infection** bar appears. Above 60 the screen effect starts and you lose health. Antibiotics lower it and say it is treated. |
| R5.8 | Swim in cold weather or at night, or stand in the rain without a top | The temperature chip falls. Below 35.5 °C it turns blue and the camera shakes, and below 35 you lose health. Wearing clothes slows this. |
| R5.9 | Put a bandage on hotbar 1, then die (fall from a roof) | The **You died** screen with a 15 s countdown. GTA's own respawn does **not** happen. |
| R5.10 | After the countdown, **Respawn** | You appear at one of the respawn points with your own face. Your clothes are in the body bag, so you are in underwear. Food and Water are at 70; bleeding and infection are gone. Only the bandage (hotbar) is still in your pockets. |
| R5.11 | Open the map | A red marker **Your body** where you died. Go there and press E: the bag is labelled **Body of First Last** and holds everything else. Empty it: the marker disappears. |
| R5.12 | Die, then quit before respawning. Rejoin. | The death screen shows **Respawn** straight away. Nothing is dropped twice. |
| R5.13 | A second player loots your body bag | They can. Body bags never merge with other piles. |
| R5.14 | Watch F8 throughout | No `[wasteland_ui] error` and no SCRIPT ERROR |

Tell me what does not match, especially the temperatures (they are estimated from your game's weather) and whether the animations play.

## World: empty, silent, one clock and weather

**Setup:** `server.cfg` has `ensure wasteland_world` and `ensure wasteland_admin` after `ensure wasteland_survival` (done on the owner's server). Restart the server.

| # | Step | Expected result |
|---|---|---|
| R6.1 | Join and look around a busy area (for example downtown Los Santos) | No pedestrians, no traffic, no parked cars, no police. Players' own vehicles still work. |
| R6.2 | Listen | No city hum, birds, music from buildings, radio or police scanner. Gunshots, footsteps, doors and your own car still make sound. Tell me any sound that is still there (for example a specific building's music). |
| R6.3 | Get in a vehicle | The radio stays off and cannot be switched on |
| R6.4 | Two players compare the time and weather (the sky) | They are the same. One game day lasts 48 real minutes, and the weather changes every 30 minutes. |
| R6.5 | Commit a crime in front of where police would be | No wanted level |

## Admin panel

| # | Step | Expected result |
|---|---|---|
| R7.1 | As a player **without** admin rights, press F10 | "You are not an admin." The console logs the attempt. |
| R7.2 | As an admin (`add_ace group.admin wasteland.admin allow` and your principal), press F10 | The panel opens with Players, Bans, Server & world and Action log |
| R7.3 | Players: select someone, then **Teleport to** and **Bring** | You go to them; they come to you |
| R7.4 | **Freeze**, then **Unfreeze** | They cannot move, then they can |
| R7.5 | Survival: set Food to 10, then **Heal** | Their HUD shows 10, then full. Bleeding and infection are cleared. |
| R7.6 | Kill a test character, then **Revive** | They stand up where they fell. Their body bag stays where it is. |
| R7.7 | Items: search "bandage", give 3, then **Open inventory** | They get 3 bandages. Your inventory screen opens with their pockets on the right, and you can drag items out. |
| R7.8 | **Clear inventory** (click twice) | Everything they carried and wore is gone |
| R7.9 | **Kick** with a reason | They are disconnected with "Kicked: <reason>" |
| R7.10 | **Ban** for 1 hour with a reason, then they try to reconnect | They are kicked, and on reconnect they see "You are banned from this server until … Reason: …". Bans tab: the ban is active; **Lift** it and they can join again. |
| R7.11 | Bans: ban a license that is not online (from `wl_accounts` or a friend) | It is listed, and that account cannot join |
| R7.12 | Server & world: set the time to 22:00, freeze time, set the weather to THUNDER, then let the weather change by itself again | Everyone's sky follows each change |
| R7.13 | Send an announcement | Every player sees a banner at the top for 10 seconds and a chat line |
| R7.14 | Noclip on: fly with W A S D, Space and Ctrl (Shift is faster). Invisible on. | You fly through walls; others cannot see you. Turning them off puts you back to normal. |
| R7.15 | Modules and recent warnings, then the Action log tab | All modules are running. Every change you made above is listed with your name. |

## Weapons (5A)

**Setup:** `server.cfg` has `ensure wasteland_weapons` after `ensure wasteland_admin` (done on the owner's server). Restart the server. Give items with the admin panel (Players, Items) or `/give <id> <item> <count>`: `weapon_pistol`, `ammo_9mm` 30, `weapon_bat`, `weapon_pumpshotgun`, `ammo_12g` 10, `weapon_repair_kit` 2.

| # | Step | Expected result |
|---|---|---|
| R8.1 | Put the pistol on hotbar key 1, press 1 | You draw the pistol with 30 rounds (GTA ammo counter). The pistol stays in your inventory. |
| R8.2 | Press 1 again | You put it away (unarmed) |
| R8.3 | Draw it, fire 5 shots, open the inventory (TAB) | 9mm rounds: 25. The pistol's durability bar is slightly lower. |
| R8.4 | Fire until empty; then give yourself 12 more rounds | At 0 you cannot shoot. After the 12 rounds arrive you can reload and shoot without drawing again. |
| R8.5 | Mouse wheel, GTA weapon-slot keys, TAB (weapon wheel) | None of them gives you a weapon or switches weapons |
| R8.6 | Draw the bat and hit another player (or a car) a few times | Durability goes down a little per hit |
| R8.7 | Keep using the bat until it breaks (or ask for a low-durability test item) | "Your Baseball bat broke." You can hold it but not attack. A repair kit used while holding it fixes 40% and is used up. |
| R8.8 | Drop the pistol you are holding (inventory, drop) | It leaves your hands |
| R8.9 | Hold a weapon and die | After respawn you are unarmed. Weapons on the hotbar are still in your inventory; others are in the body bag. |
| R8.10 | Shotgun with 10 shells: fire 3 times | 12 gauge shells: 7 |

## Item pictures

**Setup:** `server.cfg` has `ensure wasteland_images` before `ensure wasteland_inventory` (done on the owner's server). Restart the server. The first join downloads the pictures once (about the size given in the CHANGELOG).

| # | Step | Expected result |
|---|---|---|
| R9.1 | Open the inventory (TAB) | Items show pictures: water bottle, bandages, beans (a can), backpack (a bag), weapons, ammo |
| R9.2 | Rotate a long item while dragging (R), e.g. a rifle or the bat | The picture turns with the item and fits the tile |
| R9.3 | Look at pants, hat and glasses | Drawn pictures: blue jeans, a green cap, sunglasses |
| R9.4 | Admin panel, Players, Items: pick different items in the list | A small picture of the chosen item is shown next to the list |

## HUD (icons)

| # | Step | Expected result |
|---|---|---|
| R10.1 | Join with full stats | Bottom right: four green icons (drop, food tray, bottle, thermometer), full; the thermometer about two-thirds |
| R10.2 | Admin panel: set Food to 30, then 10 | The tray drains to a third and turns amber; at 10 it is red and pulses |
| R10.3 | Get hurt | The drop drains with health |
| R10.4 | Start bleeding / get infected (admin panel stats) | Badges under the icons: "Bleeding", "Infection 40%" |
| R10.5 | `/hud` | Mouse appears, the HUD has a dashed outline and a toolbar shows at the top |
| R10.6 | Drag the HUD to the left side, choose Column and size L, Save | It stays there; after reconnecting it is still there |
| R10.7 | `/hud`, drag it somewhere else, press Esc (or Cancel) | It goes back to where it was |
| R10.8 | `/hud`, Show: When it matters, Save | Icons disappear while everything is fine; low food brings the tray back |
| R10.9 | `/hud`, Reset, Save | Back in the bottom-right corner, as a row, size M |

## Cash, HUD info, stamina, minimap bars

| # | Step | Expected result |
|---|---|---|
| R11.1 | Look under the minimap | No green health or blue armour bar |
| R11.2 | Look at the HUD | Above the icons: `#<your id>  <character name>  $0` |
| R11.3 | Admin panel: give yourself `cash` 1500 | The HUD shows $1,500; the inventory has one Cash stack showing `$1,500` |
| R11.4 | Drop 500 of it (split, then drop) and pick it up again | HUD goes to $1,000, then back to $1,500 |
| R11.5 | Sprint | A thin bar appears at the bottom middle and shrinks; it turns yellow when almost empty and fades out once stamina is full again |
| R11.6 | Die with cash not on the hotbar | The cash is in the body bag |

## Zombies (5B)

**Setup:** `server.cfg` has `ensure wasteland_zombies` after `ensure wasteland_weapons` (done on the owner's server). Restart the server. Two players make R12.9 possible.

| # | Step | Expected result |
|---|---|---|
| R12.1 | Join and wait 10-20 seconds outside | Zombies appear in the distance (never right next to you), shuffling or wandering. `/zombies count` (admin) shows them. |
| R12.2 | Walk normally towards one | It notices you at about 30 m in daylight when it can see you, and comes at you. Walkers shuffle; runners run. |
| R12.3 | Crouch (Ctrl) and sneak behind one | It does not notice you until very close |
| R12.4 | Let it reach you | An attack animation; you lose health; sometimes "Bleeding" or "Infection" appears under the HUD |
| R12.5 | Kill it with a melee weapon, then with a gun | It dies; the weapon wears (5A). After about 90 s the body is gone. Sometimes a "Zombie remains" bag with loot lies there (press E). |
| R12.6 | Fire a gun with zombies 50-100 m away that have not seen you | They walk towards where you fired |
| R12.7 | Run away far (or drive) | Zombies give up after about 10 s; ones left far behind disappear |
| R12.8 | Wait until night (or set 22:00 in the admin panel) | More zombies, more runners; they see you less far |
| R12.9 | Two players near each other | Both see the same zombies doing the same things; both can be attacked |
| R12.10 | `/zombies spawn 5` (admin) | Up to 5 zombies 15-35 m around you |
| R12.11 | `/zombies clear` | All zombies disappear |
| R12.12 | Watch the F8 console and the server console while playing | No errors from wasteland_zombies |

Tell me how they feel: too many, too few, too slow, too fast, too weak, too strong. Every number is in `zombies.lua`.

## Target, admin item list, zombie reach

**Setup:** `server.cfg` has `ensure wasteland_target` after `ensure wasteland_ui` (done on the owner's server). Restart the server.

| # | Step | Expected result |
|---|---|---|
| R13.1 | Hold Left Alt | A small eye in the middle of the screen; letting go hides it |
| R13.2 | Drop an item, hold Left Alt and look at the bag on the ground (within about 2.5 m) | The eye turns green and "Search" appears beside it |
| R13.3 | Click (or press E) | The bag opens next to your inventory |
| R13.4 | Die, respawn, go to your body bag, Left Alt and look at it | "Search Body of <name>"; it opens |
| R13.5 | Left Alt while in a vehicle, dead, or with the inventory open | No eye |
| R13.6 | Admin panel, a player, Items: click the item box | A list of every item by category with pictures; typing filters it; clicking one picks it; Give works |
| R13.7 | Let a zombie attack you | It swings from about 2.5 m instead of walking into you |

## Looting (6)

**Setup:** `server.cfg` has `ensure wasteland_loot` after `ensure wasteland_zombies` (done on the owner's server). Restart the server.

| # | Step | Expected result |
|---|---|---|
| R14.1 | Find a dumpster or trash can, hold Left Alt and look at it | "Search dumpster" / "Search trash can" |
| R14.2 | Choose it | You lean in (animation); "Searching dumpster" with a bar fills in 3-5 seconds |
| R14.3 | Search another one and walk away (or press X) before it is done | "Search cancelled."; nothing opens |
| R14.4 | Let a search finish | Either "You found nothing." or the container opens next to your inventory with a few items (mostly junk) |
| R14.5 | Take everything, search it again | "Already searched. Nothing left (check back in about N min)." |
| R14.6 | Leave an item in a container; a second player searches it | They find what you left |
| R14.7 | Try a fridge, a vending machine, a tool chest, a wooden crate, a mailbox | Each can be searched and gives fitting loot (drinks, snacks, tools, mail money...) |
| R14.8 | Kill a zombie, Left Alt on the body | "Search body"; a short search (kneeling); sometimes loot; no loot bag on the ground |
| R14.9 | Wait until the body disappears (90 s) | Its loot is gone with it |
| R14.10 | Tell me any prop that should be searchable but is not (model name from a tool, or a screenshot) | It can be added to `loot.lua` |

## Inventory: weight, double-click

| # | Step | Expected result |
|---|---|---|
| R15.1 | Open the inventory | Pockets show `/ 35.0 kg`; a small backpack `/ 35.0 kg`, a hiking backpack `/ 60.0 kg` |
| R15.2 | Search a container that has items; double-click one | It jumps into your pockets (or your backpack if the pockets are full) |
| R15.3 | Double-click ammo in a container while you carry the same ammo | It joins your stack |
| R15.4 | Double-click one of your items while a container is open | It goes into the container |
| R15.5 | Fill up until too heavy, double-click something heavy | "Too heavy to carry." |

## Camps and traders (7A)

**Setup:** `server.cfg` has `ensure wasteland_camps` after `ensure wasteland_loot` (done on the owner's server). Restart the server.

| # | Step | Expected result |
|---|---|---|
| R16.1 | Open the map | Three green camp markers with circles: Sandy Shores Camp, Paleto Bay Camp, Legion Square Camp |
| R16.2 | Walk into a camp, then out | "Sandy Shores Camp - safe zone", then "Leaving Sandy Shores Camp" |
| R16.3 | Look around in the camp | Traders standing there (general trader, medic; gunsmith in Sandy Shores). Tell me if one stands inside a wall or floats: its coords are in camps.lua. |
| R16.4 | Hold Left Alt on a trader, "Trade" | The trade screen: Buy (prices, stock) and Sell (what you carry that they buy), your cash |
| R16.5 | Buy something you can afford, then something you cannot | Cash goes down, the item is in your inventory; "You need $..." |
| R16.6 | Sell something (or All) | Items gone, cash up |
| R16.7 | Buy out an item, wait 10 minutes | "Sold out", later some back in stock |
| R16.8 | Lead zombies to a camp | They stop following at the edge; any that walk in disappear; none appear inside |
| R16.9 | Walk away from the trader with the screen open | The screen closes |

## Crafting (7B)

**Setup:** `server.cfg` has `ensure wasteland_crafting` after `ensure wasteland_camps` (done on the owner's server). Restart the server.

| # | Step | Expected result |
|---|---|---|
| R17.1 | Press K (or the "Crafting (K)" button in the inventory) | The crafting screen: Rags and Bandage, "5 more recipes to learn" |
| R17.2 | With a top in your inventory, craft Rags | You crouch and work; a bar fills in 3 s; "Made 3 x Clean rag." |
| R17.3 | Craft a Bandage from 2 rags | 2 rags gone, 1 bandage more |
| R17.4 | Start a craft and walk away (or press X) | "Crafting cancelled."; nothing used up |
| R17.5 | Give yourself `blueprint_machete` (admin panel), use it from the inventory | "You learned how to make: Machete. Press K to craft." The blueprint is gone; the Machete recipe is in the list |
| R17.6 | With 4 scrap metal, 2 duct tape and 1 rag, craft the Machete | A machete with a full durability bar |
| R17.7 | Reconnect | You still know the machete recipe |

## Quests (8)

**Setup:** `server.cfg` has `ensure wasteland_quests` after `ensure wasteland_crafting` (done on the owner's server). Restart the server.

| # | Step | Expected result |
|---|---|---|
| R18.1 | Hold Left Alt on a camp trader | "Trade" and "Jobs" |
| R18.2 | Jobs | The board: jobs with what to do, reward, status; "0 of 3 jobs taken" |
| R18.3 | Accept "Scrap run" | A tracker on the right: "Scrap run - Bring Scrap metal 0/6"; picking up scrap updates it |
| R18.4 | Accept "Thin the herd", kill zombies | "Kill zombies 1/10, 2/10, ..."; kills by another player do not count for you |
| R18.5 | Accept a "Check the ..." job | A yellow marker on the map with a route; arriving shows "(done)" |
| R18.6 | Hand in a finished job at a trader of that camp | Items taken, reward given, the job shows "Done", "Again in N min" |
| R18.7 | Try to take a 4th job | "You can only have 3 jobs at once." |
| R18.8 | Reconnect with a job half done | The tracker shows the same progress |
| R18.9 | Accept "Field dressings", craft 3 bandages (K), hand in 3 bandages | It counts the crafts, then takes the bandages |

## Vehicles (9)

**Setup:** `server.cfg` has `ensure wasteland_vehicles` after `ensure wasteland_quests` (done on the owner's server). Restart the server (the database table is created on start). Give yourself parts with the admin panel: `car_battery`, `engine_parts`, `car_wheel`, `jerry_can`, `vehicle_repair_kit`, `vehicle_lock`, `lockpick`.

| # | Step | Expected result |
|---|---|---|
| R19.1 | Go to Sandy Shores (by the 24/7) or a Los Santos car park | A rusty wreck stands there. Tell me if one floats, sinks or stands in a wall. |
| R19.2 | Left Alt on it, "Check vehicle" | e.g. "Fuel 4/50 L · Engine 45% · Body 60% · Battery: missing · Engine parts: OK · Wheels 3/4" |
| R19.3 | Get in and try to drive | "There is no battery." (or what is missing); the engine does not start |
| R19.4 | Install the battery / engine parts / a wheel | A short animation and bar; the part is used up; a missing wheel shows as a bare rim until mounted |
| R19.5 | Fill a jerry can at a gas pump (Left Alt on the pump), then "Refuel" the car | The can is full (20 L), then empty; the fuel gauge rises |
| R19.6 | Drive | It runs; fuel goes down while driving; at 0 the engine stops |
| R19.7 | Crash it, then "Repair (toolkit)" | Engine and body get better |
| R19.8 | Put things in the trunk, drive far away, come back later (or after a restart) | The car is where you left it, with its damage, fuel and trunk |
| R19.9 | "Fit a lock" | Locked; you get a "Car key"; doors stay shut for others |
| R19.10 | Another player (without the key): "Pick the lock" with lockpicks | Usually fails ("The lock holds." / "The lockpick snaps."); sometimes "The lock breaks open."; nearby zombies come to look |
| R19.11 | Give the key to someone else | They can unlock it and open the trunk |
| R19.12 | Blow a car up | It burns out and disappears after a while; later another wreck appears somewhere else |
| R19.13 | Get in a vehicle | Bottom middle: speed (mph), fuel gauge (litres), engine and body %, lock; a red line saying why it will not run, if it will not |
| R19.14 | Park a car next to a gas pump, Left Alt on the pump, "Refuel vehicle" | A bar ("Refuelling at the pump (30 L, pump has 80 L)"); the tank fills; "the pump has 50 L left" |
| R19.15 | Stand next to a pump, take some fuel, then keep taking until it is empty | Above the pump: "Fuel: 80 / 80 L", "Full"; then e.g. "Fuel: 35 / 80 L", "Full again in 1 h 59 min"; when empty: "This pump is dry. It is full again in 1 h 50 min." Two hours after the first fuel was taken it is full |

## R20: admin tools (Milestone 10A)

Open the panel with F10 (you need the `wasteland.admin` ACE).

| # | Do | Expect |
|---|---|---|
| R20.1 | Open the "Live" tab and leave it open | Cards for players, zombies alive, vehicles, pumps, containers searched and uptime; the numbers change every 5 seconds |
| R20.2 | Server & world: set zombies to 5, "Spawn around me" | Up to 5 zombies appear 15-35 m away. "Clear all zombies" (click twice) removes them |
| R20.3 | "Spawn a wreck", then "Spawn a working car" | A wreck, then a car you can drive, 6 m in front of you |
| R20.4 | Sit in a broken car, "Fix the car I am in / next to" | All parts, full tank, no damage |
| R20.5 | Empty a gas pump, then "Refill all gas pumps" (click twice) | The pump shows full again |
| R20.6 | Put a waypoint on the map, "Teleport to my map waypoint" | You land on the ground there |
| R20.7 | Switch each debug overlay on | Zombie AI: a label over every zombie (walker/runner and what it is doing). Vehicles: info over each car, markers at wreck spawn points. Camp borders: a circle on the ground. Loot: a marker over searchable props near you. "off" removes it |
| R20.8 | Players: pick another player, "Spectate", then "Stop spectating" | You watch them (you are hidden); stopping brings you back where you were |
| R20.9 | Give $100 cash, then take $50 | Their cash goes up 100, then down 50; taking more than they have says so |
| R20.10 | Jobs: with a job taken, "Drop"; with a job on cooldown, "Reset cooldowns" | The job is gone from their tracker; they can take the job again |
| R20.11 | Recipes: "Teach" a blueprint recipe, then "Forget" | It shows in / disappears from their crafting screen (K) |
| R20.12 | "Send to nearest camp" (click twice) | They are teleported into the closest camp |
| R20.13 | Admin panel, "Coords" tab; walk around with the panel closed, open it again; press each Copy and paste into Notepad | Live X/Y/Z/heading; pasted text is e.g. `vector3(1853.42, 3686.06, 34.27)`, `vector4(..., 211.55)`, `211.55` |

## R21: car locks and lock picking

| # | Do | Expect |
|---|---|---|
| R21.1 | Fit a lock on a car, then Left Alt on it: "Take the lock off" | A short bar; "You took the lock off..."; the car lock is back in your pockets; the car opens for everyone |
| R21.2 | Second player (even holding your key): Left Alt on your locked car | No "Take the lock off" option for them |
| R21.3 | Second player without a lockpick: "Pick the lock" | "You need a lockpick."; no minigame |
| R21.4 | With a lockpick: "Pick the lock" | The minigame opens (your character works on the door); zombies nearby come to look |
| R21.5 | Press E when the pick is in the green, 4 times | Each pin lights up, the pick turns back faster; after the 4th: "The lock turns!", then "The lock breaks open." and the car is open |
| R21.6 | Press E outside the green | Red shake, "The pick slips."; then "The lockpick snaps." or "The pick slips. The lock holds." |
| R21.7 | Press Esc during the minigame / get hit by a zombie during it | "You stop picking the lock." / "You were interrupted."; you can move again |

## R22: siphoning fuel

| # | Do | Expect |
|---|---|---|
| R22.1 | Left Alt on a car with fuel, "Siphon fuel (hose)" without a hose / without a jerry can with room | "You need a siphon hose." / "You need a jerry can that is not full." |
| R22.2 | With a hose and an empty jerry can | A 10 s bar; "Siphoned 12 L. Jerry can: 12 of 20 L. The tank has 0 L left."; the car will not start ("The tank is empty.") |
| R22.3 | Use that can on another car ("Refuel (jerry can)") | The fuel goes in |
| R22.4 | The general trader | Sells siphon hoses; the item shows the hose picture |

## R23: moving the vehicle HUD

| # | Do | Expect |
|---|---|---|
| R23.1 | Type /hud (in or out of a vehicle) | The vehicle HUD shows with a dashed outline and a "VEHICLE HUD  -  100%  +  Reset" bar above it (example values when on foot) |
| R23.2 | Drag it somewhere; scroll the mouse wheel over it; press - and + | It follows the mouse; it gets smaller/bigger (60%-180%) |
| R23.3 | Save the HUD, get in a car; reconnect | The vehicle HUD is where you put it, at that size, after reconnecting too |
| R23.4 | /hud, move it, then cancel (Esc) | It goes back to where it was |
| R23.5 | /hud, Reset, save | Bottom middle, normal size again |

## R24: clothing durability

| # | Do | Expect |
|---|---|---|
| R24.1 | Open the inventory (TAB) | Worn clothes have a green condition bar; hovering shows "Condition 100%" |
| R24.2 | Let zombies hit you a few times | The bars of your clothes go down (one piece per hit) |
| R24.3 | Keep getting hit until a piece is ruined | "Your top is ruined. Mend it with a sewing kit."; the tile is grey with RUINED; in the cold you get colder faster |
| R24.4 | Get a sewing kit (general trader / craft from 2 rags + scrap); right-click the ruined piece | "Repair with Sewing kit"; "You mend your top (0% -> 50%)."; one kit is gone; a short animation |
| R24.5 | Use a sewing kit from its own menu ("Use") | It mends the most worn piece you wear |

## R25: armor plates

| # | Do | Expect |
|---|---|---|
| R25.1 | Buy an armor plate (gunsmith), open the inventory | A new "Armor" slot under Worn; drag the plate in (or right-click, Wear) |
| R25.2 | Look at the HUD | A shield icon next to Health, full |
| R25.3 | Let zombies hit you | Health does not go down, no bleeding; the shield goes down a little each hit |
| R25.4 | Have another player shoot / punch you | Health does not go down; the shield goes down |
| R25.5 | Keep taking hits until it breaks | "Your armor plate broke. Repair it with an armor repair kit."; now you take damage |
| R25.6 | Right-click the plate, "Repair with Armor repair kit" | "You repair your armor plate (0% -> 40%)."; protected again |
| R25.7 | Take the plate off | The shield icon goes; you take damage normally |

## R26: wrecked vehicles

| # | Do | Expect |
|---|---|---|
| R26.1 | Go to rusted car wrecks (e.g. around Sandy Shores / Grand Senora), Left Alt on one | "Search wrecked vehicle"; a 6 s search; it opens (or "You found nothing.") |
| R26.2 | Try from the side of a long wreck (bus, van) | Works anywhere along its side |
| R26.3 | A wreck shows no "Search" option | Admin panel (F10), Coords tab, look at it: send me the "Looking at" model number so I can add it |
| R26.4 | Admin panel, Server & world, overlay "Loot containers" | Markers over the wrecks that can be searched |

## R27: make props lootable from the admin panel

| # | Do | Expect |
|---|---|---|
| R27.1 | F10, Coords tab; stand so the camera faces a prop that cannot be searched (a barrel, a box) | "Looking at: object model ..."; under "Make it lootable" a dropdown and "Add to loot" |
| R27.2 | Pick "Crate (crate loot)", Add to loot; close the panel; Left Alt on the prop | "Search crate"; it opens with crate loot. Other copies of the same prop elsewhere too |
| R27.3 | Restart the server | Still searchable; listed under "Props added here" |
| R27.4 | Look at it again: "Change" to another type / "Remove" (click twice) | The search changes / is gone for everyone |
| R27.5 | Look at a dumpster | "Already searchable: Dumpster (trash loot) (set in loot.lua)" |

## R28: prop names and own loot categories

| # | Do | Expect |
|---|---|---|
| R28.1 | Coords tab, look at a car / a dumpster / some other prop | "vehicle Rebel (rebel) · model ..." / "object prop_dumpster_01a · ..." / "object (name unknown) · ..." |
| R28.2 | Loot tab, "+ New loot category": name "Gun safe", add ammo and a pistol, Save | It is listed; "Loot category saved" |
| R28.3 | Coords tab, look at a prop, "Loot as" Gun safe, type a prop name, Add to loot | The prop can be searched and gives only the items you chose; the name shows from then on |
| R28.4 | Edit the category (change items), Save; restart the server | The changes stay |
| R28.5 | Delete the category (click twice) | Its props can no longer be searched |

## R29: admin loot target and health panel

| # | Do | Expect |
|---|---|---|
| R29.1 | As admin, Left Alt on a barrel / box | "Admin: loot container…" (not shown to normal players) |
| R29.2 | Pick it, choose a category, Make lootable | "Every prop of this model ... can now be searched"; the window closes; "Search ..." works on it |
| R29.3 | Do it again on the same prop | The window shows the current category with Change / Remove |
| R29.4 | Open the inventory (TAB) when healthy | Health panel: body outline, bars, "You are in good shape." |
| R29.5 | Get hit by zombies until bleeding / infected, get hungry | Blood drops / green tint on the body; "Bleeding ... Stop it with: Bandage, Rag." and the others, updating every second |

## R30: wrecks on clear ground

| # | Do | Expect |
|---|---|---|
| R30.1 | Restart, drive/walk to the wreck spawn points | Wrecks stand on open ground, not inside props, walls, fences or other cars; the server console may say "moved x m to a clear spot" |
| R30.2 | Leave and come back | They stay where they were placed (checked once) |

## R31: hotbar, hands up, emotes

| # | Do | Expect |
|---|---|---|
| R31.1 | Put items on the hotbar (inventory, right-click, Hotbar 1-5) | They show bottom middle with pictures and counts |
| R31.2 | /hotbar, then /hotbar again; reconnect | Hidden, shown; the choice is kept |
| R31.3 | Press X, try to shoot; X again | Hands up (others see it), no shooting; hands down |
| R31.4 | F4 | Emote menu; search "sit", click it; you sit; walk: you get up |
| R31.5 | /e wave while walking; /e smoke; /e c | Wave while walking; smoking; stops |
| R31.6 | /e nothing | "No emote ... Press F4 or type /e for the list." |
| R31.7 | Try every emote once | Tell me any that do nothing (wrong animation name) |

## R32: tailors

| # | Do | Expect |
|---|---|---|
| R32.1 | Map | Three "Tailor" blips: Paleto Bay, Sandy Shores, Legion Square |
| R32.2 | Go to one; Left Alt on the shopkeeper | "Restyle my clothes ($25 a piece)"; the screen opens, the camera looks at you |
| R32.3 | Click the style / colour arrows | Your clothes change at once; changed parts are outlined; Pay shows the price |
| R32.4 | Cancel | Your old clothes come back, nothing paid |
| R32.5 | Change pants and shoes, Pay $50 (with the cash) | "The tailor restyled 2 pieces for $50."; the look stays after relog |
| R32.6 | Without enough cash | "That costs $X. You do not have enough cash." |

## R33: supply drops

| # | Do | Expect |
|---|---|---|
| R33.1 | As admin: /supplydrop | Everyone: "Supply drop coming down near ..."; a red area and a crate blip on the map |
| R33.2 | Go there | A military crate with red smoke on the ground (tell me if it floats or sinks) |
| R33.3 | Left Alt on it: "Open supply crate" | It opens next to your inventory with loot; everyone gets "Someone opened the supply crate at ..." |
| R33.4 | Another player opens it | Same contents, minus what was taken |
| R33.5 | Wait 20 minutes | The crate and the blips are gone |
| R33.6 | /supplydrop here | A crate a few metres from you |

## R34: aggressive zombies, custom models

| # | Do | Expect |
|---|---|---|
| R34.1 | Walk in the open by day | Zombies notice you from about 70 m (40 m at night) and come; several come together |
| R34.2 | Break line of sight and hide | They keep looking for about 25 s |
| R34.3 | (Optional) put a ped model in wasteland_zombiemodels/stream, add it to zombies.lua `models`, restart | Some zombies use it; with a wrong name the console says it is not in the game and no invisible zombies appear |

## R35: zombie sync (needs two players)

| # | Do | Expect |
|---|---|---|
| R35.1 | Two players stand near each other with zombies around; one types /zombies sync and opens F8 | Each player: "sees N of the N zombies near them"; "Sync check: OK" |
| R35.2 | Both look at the same zombie | Both see it bloody and staggering, in the same place |
| R35.3 | One player drives 500 m away and comes back; /zombies sync again | OK again |

## R36: world events

| # | Do | Expect |
|---|---|---|
| R36.1 | /event helicrash here | "A helicopter went down near an admin..."; a red area and a helicopter marker 25 m away |
| R36.2 | Look there | A crashed helicopter (fire), a crate; tell me if anything floats or sinks |
| R36.3 | Stay within 150 m | 4 bandits with pistols attack you; zombies come |
| R36.4 | Left Alt on the wreck before they are dead | "Too dangerous: N bandits and M zombies are still here." |
| R36.5 | Kill a bandit | A "Bandit" bag where he fell (ammo, cash) |
| R36.6 | Kill them all | Everyone: "The bandits at the crash ... are dead"; the marker turns green; "Search: Helicopter wreckage" opens good loot |
| R36.7 | /event convoy here, /event hideout here, /event horde here | Each looks right; tell me any prop that is missing |
| R36.8 | /event end | Everything is gone |

## R37: new players

| # | Do | Expect |
|---|---|---|
| R37.1 | Make a new character near zombies; stay in the creator a while | Zombies do not come for you; you take no damage |
| R37.2 | Finish the creator | "Where do you start?" with the camps; pick one; the screen fades and you are there; "Welcome to ..." |
| R37.3 | Open the inventory | $50 cash, water, beans, bandages |

## R38: groups
Needs two players (or a second client).

| # | Do | Expect |
|---|---|---|
| R38.1 | Press F6 (or /group), type a name, Create | "Group ... created"; you are listed as LEADER |
| R38.2 | Invite player B by id, or with the "Near you" button | B gets a notice; B opens /group and sees the invitation; Join |
| R38.3 | Open the map on both | Each sees the other: yellow for the leader, blue for a member, named "Name (Group)" |
| R38.4 | B dies (or goes down) | B's marker turns red for A |
| R38.5 | Leader: Make leader on B (click twice) | B is now LEADER |
| R38.6 | New leader renames the group | The new name shows for both, also on the markers |
| R38.7 | Restart the server, both log back in | The group is still there with both members |
| R38.8 | Leader: Remove a member, then Disband (click twice) | The member is told; after disband both have no group and the markers go |
