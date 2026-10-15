# Installing Wasteland Core

Wasteland Core is a zombie survival framework for FiveM. It needs:

* a Windows or Linux machine that can run a FiveM server (FXServer with txAdmin),
* **MySQL or MariaDB** (MariaDB 10.6 or newer recommended),
* a **Cfx.re server license key** (free, from [portal.cfx.re](https://portal.cfx.re)).

## Option 1: txAdmin recipe (recommended)

1. Install the FiveM server (FXServer) and open txAdmin as usual
   ([guide](https://docs.fivem.net/docs/server-manual/setting-up-a-server-txadmin/)).
2. In the txAdmin setup, choose **Popular Recipes → Custom Template / Remote URL** and paste:

   ```
   https://raw.githubusercontent.com/gosalosey/wasteland-core/main/txadmin/recipe.yaml
   ```

3. Follow the steps. When txAdmin asks for the **database**, give it a MySQL/MariaDB user that may create a database (txAdmin creates it). Wasteland creates all of its tables itself on the first start.
4. Enter your **license key** and finish. txAdmin starts the server.

The recipe installs:

* FiveM's base resources (mapmanager, spawnmanager, ...),
* [oxmysql](https://github.com/overextended/oxmysql) (database driver, latest release),
* [pma-voice](https://github.com/AvarianKnight/pma-voice) v6.6.2 (voice chat) into `resources/[standalone]/pma-voice`,
* every Wasteland Core resource (`resources/[wasteland]`),
* a ready `server.cfg` (game build 3570, OneSync on, everything started in the right order, admins set up) and the server icon.

**Admins.** The txAdmin master account becomes an admin. Admins have the `wasteland.admin` permission: the admin panel (F10) and commands like `/give`, `/zombies`, `/event`, `/supplydrop`. Add more admins in `server.cfg`:

```
add_principal identifier.fivem:12345678 group.admin
```

## Option 2: by hand

1. Put `resources/[wasteland]` from this repository into your server's `resources` folder, and install [oxmysql](https://github.com/overextended/oxmysql/releases/latest) into `resources/[standalone]/oxmysql` and [pma-voice](https://github.com/AvarianKnight/pma-voice) into `resources/[standalone]/pma-voice` (copy the voice chat lines from `server.cfg.example`).
2. Create a database and a user for it (see [DATABASE.md](DATABASE.md)).
3. Use [`txadmin/server.cfg`](../txadmin/server.cfg) as your `server.cfg`, replacing the `{{...}}` parts: your server name, license key, `mysql://user:password@127.0.0.1/database?charset=utf8mb4`, the endpoints and your admins.
4. Start with OneSync on (`+set onesync on`, or the txAdmin setting).

## After installing

* **Settings** are all in `resources/[wasteland]/wasteland_config/config/` (zombies, loot, traders, events, ...). See [SDK_GUIDE.md](SDK_GUIDE.md).
* **Game build.** `sv_enforceGameBuild 3570` is set on purpose: newer builds were missing parts of the map with this framework.
* **Optional map fixes** (not included, third-party): some servers add interior maps such as a fixed Pillbox Medical Center. Put them in `resources/[defaultmaps]` and add `ensure [defaultmaps]` to `server.cfg`.
* **Checking it works:** the server console shows a module table after starting; every module should say `running`. `wasteland status` shows it again at any time.
* **Before opening to the public:** in `wasteland_config/config/players.lua`, `duplicateSession` must be `'kick_old'` (the default), not `'test_second_account'` (testing only).

## Updating

**With the updater (recommended).** Servers installed with the recipe have `update_wasteland.bat` in the server folder. On older installs, download [`tools/update.ps1`](../tools/update.ps1) (save it as `update_wasteland.ps1`) and [`tools/update_wasteland.bat`](../tools/update_wasteland.bat), both into the same folder: best the server folder (with `server.cfg`); anywhere near it works too (e.g. `txData	ools`), the updater finds the server and asks if there are several.

1. Stop the server (txAdmin: **Stop**).
2. Double-click `update_wasteland.bat`. It shows what is new, then:
   * backs up the database and the current `resources/[wasteland]` (into `backups/` in the server folder),
   * installs the new version but keeps your settings (`wasteland_config/config`) and your zombie models; where the new version's settings file differs from yours, it is saved next to it as `<name>.lua.new` so you can compare,
   * adds settings files that are new,
   * offers to add `ensure` lines that `server.cfg` is missing.
3. Start the server. Every Wasteland module should show `running` in the console.

**By hand.** Back up the database first ([DATABASE.md](DATABASE.md)), then replace `resources/[wasteland]` with the new version, keeping your own `wasteland_config/config/` files. Database changes are applied automatically on the next start.

## Base building props (optional)

`wasteland_basebuilding` shows its pieces with the **sinor-buildingProps-v2** props pack. It is not part of Wasteland Core: it is a licensed Cfx asset pack (escrow), which works only on servers whose licence key belongs to the account that owns it. To use base building:

1. Get the pack on your Cfx account (Keymaster) and download it.
2. Put the `sinor-buildingProps-v2` folder in your server's `resources` folder (for example `resources/[standalone]/`).
3. In `server.cfg`, `ensure sinor-buildingProps-v2` before `ensure wasteland_basebuilding` (the txAdmin server.cfg has the line ready, commented out).

Without the pack the module still runs, but the pieces cannot be seen; the console says so when it starts.

## Zombie sounds

The sound files are in `resources/[wasteland]/wasteland_zombiesounds` (installed and updated with everything else; `ensure wasteland_zombiesounds` before `ensure wasteland_zombies`). Which file plays for what (idle groans, chasing, attack, hurt, death, screamer calls) is listed in `wasteland_zombies/client/sounds.lua`; volume, range and how often they groan are in `zombies.lua` → `sounds`. To use your own sounds, put them in its `sounds` folder and list them in `zombies.lua` → `sounds.groups`. Without the resource zombies are silent and nothing else changes.

## Keys for players

Tab inventory · Left Alt (hold) interact · K crafting · F2 survivor's guide · F4 emotes · F6 group · F9 skills · F10 admin panel · X hands up · Caps Lock radio · 1-5 hotbar. Players can change them in GTA's Settings → Key Bindings → FiveM.
