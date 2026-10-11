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
