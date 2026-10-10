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
