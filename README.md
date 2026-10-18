# Wasteland Core

**A complete zombie-survival server for FiveM.** Install it, start it, and you have smart zombie hordes, looting, crafting, hunting, base building, skills, trading and voice chat, all made from scratch. No QBCore, Qbox, ESX or ox_* gameplay scripts are needed.

* **For server owners:** one-click install with txAdmin, every setting in plain, commented files, and an updater that keeps your settings.
* **For players:** press **F2** in game for the Survivor's guide. It shows what to do next and explains everything.

---

## Quick start (about 10 minutes)

**You need:** a FiveM server with txAdmin, a MySQL or MariaDB database, and a free [Cfx.re licence key](https://portal.cfx.re).

1. In txAdmin's setup, choose **Popular Recipes → Remote URL** and paste:
   ```
   https://raw.githubusercontent.com/gosalosey/wasteland-core/main/txadmin/recipe.yaml
   ```
2. Follow the steps. Give it your database login and licence key when asked.
3. Start the server. In the console, every Wasteland module should say **running**.
4. Join, make a character, and press **F2**.

That's it. Wasteland creates its own database tables. The recipe also installs the database driver (oxmysql), voice chat (pma-voice), the zombie sounds and a ready `server.cfg`.

> **Base building needs a paid props pack.** The building pieces (walls, doors, gates, foundations and so on) come from **sinor-buildingProps-v2** by SinorSystem. It is **not free** and **not included**. Buy it from the [SinorSystem Tebex store](https://sinorsystem.tebex.io/), then install it on your server (see [docs/INSTALL.md](docs/INSTALL.md#base-building-props-optional)). Without it, everything else works, but base pieces are invisible. **Or use your own building props**, or GTA's: see [docs/INSTALL.md](docs/INSTALL.md#using-your-own-building-props-instead-of-the-paid-pack). To switch base building off, set `basebuilding = false` in `modules.lua`.

Installing by hand, adding admins, or updating: see **[docs/INSTALL.md](docs/INSTALL.md)**.

---

## What players can do

| | |
|---|---|
| **Survive** | Hunger, thirst, bleeding, infection, cold and heat, and the need to use the toilet. Die and everything except your hotbar drops in a body bag where you fell. |
| **Fight the dead** | Walkers, runners, stalkers that follow you, sleepers lying in the road, packs that surround you, screamers that call the horde, brutes, spitters and more. They hear gunshots (use a suppressor), see you in the open, and break through wooden walls. |
| **Loot** | Search dumpsters, fridges, cars, bodies and supply drops. Press **E** to take everything at once. |
| **Craft** | Rags from old clothes, bandages, and blueprints for weapons, gun parts and ammo. Weapon attachments: suppressor, scope, flashlight, grip, extended magazine. |
| **Hunt** | Deer and boar. Harvest them with a knife and cook the meat on a campfire. |
| **Trade** | Safe camps with traders (who buy anything), a medic and jobs. Trade face to face with other players. |
| **Drive** | Fix up wrecks with batteries, wheels, engine parts and fuel. New players start with a **Full vehicle repair** for a quick first car. |
| **Build** | Claim land with a tool cupboard. Build walls, doors, gates, window bars, storage, barbed wire, spike strips and sandbags. Or barricade an old building for the night without a cupboard. |
| **Team up** | Groups with a shared radio channel and map markers, proximity voice chat, and **/help** to call everyone for help. |
| **Grow** | Six skills that level up as you play (F9), and 22 milestones to tick off in the Survivor's guide (F2). |

### Keys

| Key | | Key | |
|---|---|---|---|
| **Tab** | Inventory | **F2** | Survivor's guide |
| **Left Alt** (hold) | Look at something and interact | **F4** | Emotes |
| **E** | Open doors and gates, take all when looting | **F6** | Group |
| **K** | Crafting | **F9** | Skills |
| **1 - 8** | Hotbar | **X** | Hands up |
| **Caps Lock** | Talk on the radio | **F10** | Admin panel (admins) |

Players can change any key in GTA's **Settings → Key Bindings → FiveM**.

### Chat commands

| Command | |
|---|---|
| `/help [what's wrong]` | Call every player for help. `/accepthelp` gets a GPS route to them, and `/cancelhelp` calls it off. |
| `/stuck` | Stuck somewhere? Stand still for 10 seconds and you're taken to the nearest safe camp (once every 30 minutes). |
| `/backpack` | Show or hide the backpack on your back (your bag still works either way). |
| `/hud` | Change the HUD: compact, only when it matters, or off |
| `/pee`, `/poop` | When you need to go |
| `/guide`, `/skills` | Same as F2 and F9 |

More detail for players: **[docs/PLAYER_GUIDE.md](docs/PLAYER_GUIDE.md)**.

---

## For server owners

### Changing things

Every setting is in **`resources/[wasteland]/wasteland_config/config/`**, one file per feature. Each file explains its settings in plain words. Change a value, save, and restart the server.

| I want to change... | File | Setting |
|---|---|---|
| How many zombies, how tough, how fast | `zombies.lua` | `population`, `kinds` |
| Zombie behaviour, special infected, hordes | `zombies.lua` | `ai` (`ai.enabled = false` turns the new AI off) |
| Zombie sounds (volume, range) | `zombies.lua` | `sounds` |
| Trader prices and what they sell | `camps.lua` | `shops` |
| Camps (safe zones) and trader positions | `camps.lua` | `camps` |
| What's in containers and supply drops | `loot.lua` | `tables` |
| Items: weight, size, what they do | `inventory.lua` | `items` |
| Pocket and backpack size | `inventory.lua` | `pockets`, `backpack_small`, `backpack_large` |
| What new players start with | `inventory.lua` | `startingItems` |
| Hunger, thirst, infection speed | `survival.lua` | `hunger`, `thirst`, `infection` |
| Respawn points after death | `survival.lua` | `respawn.points` |
| Crafting recipes | `crafting.lua` | `recipes` |
| Base safe-zone time, upkeep, building pieces | `basebuilding.lua` | `cupboard`, `upkeep`, `pieces` |
| Skill speed and bonuses, death penalty | `skills.lua` | `skills`, `deathPenalty`, `xpMultiplier` |
| Guide milestones and how-to pages | `guide.lua` | `milestones`, `pages` |
| `/stuck` and `/help` | `camps.lua` / `groups.lua` | `stuck` / `help` |
| Turn a whole feature off | `modules.lua` | set it to `false` |

### Admin tools

* **F10**: the admin panel, with players (spectate, give items, send to a camp), bans, world tools (time, weather), a live view and debug overlays.
* `/give <id> <item> [count]`, `/zombies count | clear | spawn <n> | sync`, `/survival <id> <stat> <value>`, `/event`, `/supplydrop [here]`, `/appearance <id>`.
* In the server console, `wasteland status` shows every module and whether it's running.
* Make someone an admin in `server.cfg`: `add_principal identifier.fivem:12345678 group.admin`

### Updating

Stop the server, double-click **`update_wasteland.bat`** in your server folder, then start the server.

The updater backs up your database and files first. It keeps your settings and your custom zombie models. When a new version changes a settings file you've edited, it saves the new version next to yours (`name.lua.new`) so you can compare. The server console tells admins when GitHub has a newer version.

### The map

Wasteland uses the **[Total Apocalypse](https://github.com/SparksScripts/Total-Apocalypse)** map pack by SparksScripts (free, GPL-3.0) as its standard world: wrecked roads, barricades and ruined towns. The txAdmin recipe downloads it for you (about 470 MB, so the first install takes longer). Installing by hand: put `pack1`, `pack2`, `pack3` and `postapo-interior` in `resources/[maps]` and add `ensure` lines for them after `pma-voice` (see `server.cfg.example`). To play on the normal GTA map, comment those four lines out.

### Optional extras

* **Base building props (paid, required for base building):** **sinor-buildingProps-v2** by SinorSystem. It is not free and not included. Get it from the [SinorSystem Tebex store](https://sinorsystem.tebex.io/). Install steps: [docs/INSTALL.md](docs/INSTALL.md#base-building-props-optional).
* **Your own zombie models:** put them in `resources/[wasteland]/wasteland_zombiemodels/stream` and list them in `zombies.lua`.

### Something not working?

See **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**. It covers common problems and fixes, such as the loading screen hanging on "Awaiting scripts", invisible base pieces, zombies not spawning and players not being able to connect.

---

## For developers

* **Add content without code:** items, loot, recipes, traders, jobs, zombie kinds and vehicles are all in the config files.
* **Write your own module:** copy `resources/[wasteland]/wasteland_template` and follow **[docs/SDK_GUIDE.md](docs/SDK_GUIDE.md)**, which walks through the supply drop module. The full API is in **[docs/MODULE_API.md](docs/MODULE_API.md)**, and the design is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
* **Tests:** about 900 automated tests run against a simulated FiveM server: `tools\run_tests.bat` (Windows) or `./tools/run_tests.sh` (needs Lua 5.4). Things only the game can show are listed as in-game checks in [docs/IN_GAME_TESTS.md](docs/IN_GAME_TESTS.md). See [docs/TESTING.md](docs/TESTING.md).
* **What changed:** [CHANGELOG.md](CHANGELOG.md) (newest first). Known limitations are in [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

<details>
<summary>Repository layout</summary>

```
resources/[wasteland]/
  wasteland_config/       your settings (config/*.lua)
  wasteland_core/         kernel: modules, config validation, lifecycle, SDK, net-event guard
  wasteland_database/     database adapter and migrations (oxmysql)
  wasteland_players/      accounts, sessions, characters, spawning
  wasteland_ui/           screens and design system      wasteland_target: Left Alt interaction
  wasteland_appearance/   character creator              wasteland_tailor: clothing shops
  wasteland_inventory/    grid inventory and item API    wasteland_images: item pictures
  wasteland_survival/     needs, health, death, HUD      wasteland_world: clock, weather, empty world
  wasteland_weapons/      weapons, ammo, attachments
  wasteland_zombies/      population, AI, horde, sounds  wasteland_zombiesounds: the sound files
  wasteland_zombiemodels/ your own zombie models         wasteland_loot: searchable containers
  wasteland_camps/        safe zones, traders, /stuck    wasteland_quests: camp jobs
  wasteland_crafting/     crafting and blueprints        wasteland_hunting: animals, campfires
  wasteland_vehicles/     wrecks, parts, fuel, locks     wasteland_events: world events
  wasteland_groups/       groups, radio, /help           wasteland_trade: player trading
  wasteland_basebuilding/ base building                  wasteland_supplydrops: supply drops
  wasteland_skills/       skills                         wasteland_guide: survivor's guide
  wasteland_admin/        admin panel                    wasteland_emotes: emotes, hands up
  wasteland_loadscreen/   loading screen                 wasteland_template: example module
docs/       install, player guide, troubleshooting, SDK, API, architecture, database, testing
tests/      automated tests and a simulated FiveM server
tools/      updater, test runners, database backup, image tools
txadmin/    txAdmin recipe and server.cfg
```
</details>

---

## Credits

**Item pictures** (`wasteland_images`) come from **MK-Items** by [McKleans-Scripts](https://mckleans-scripts.tebex.io/), a free community pack of FiveM item images, converted to WebP. All credit for those pictures goes to their authors, including, as credited by MK-Items: Jim and the [JixelPatterns](https://discord.gg/JixelPatterns) community, MrFurox from [Project Boosted](https://discord.gg/TrvAhGvDs3), [NatasWillDoIt](https://github.com/NatasWillDoIt), the [Project Sloth](https://github.com/Project-Sloth) community, [googleoblivion](https://github.com/googleoblivion), [oosayeroo](https://github.com/oosayeroo), and everyone who contributed images to MK-Items. The pictures `cap`, `jeans`, `sunglasses`, `siphon_hose` and `matches` were made for Wasteland Core.

**Zombie sounds** (`wasteland_zombiesounds`) are from the free **Zombie Sound Pack** by Catastic, plus a few extra zombie clips.

**Other software** used and not included: [FiveM / FXServer](https://fivem.net), [oxmysql](https://github.com/overextended/oxmysql) and [pma-voice](https://github.com/AvarianKnight/pma-voice) (MIT, by AvarianKnight). The standard map is [Total Apocalypse](https://github.com/SparksScripts/Total-Apocalypse) (GPL-3.0) by SparksScripts and the mappers credited in its README. Base building uses the **sinor-buildingProps-v2** props pack by SinorSystem, a paid pack you buy yourself from the [SinorSystem Tebex store](https://sinorsystem.tebex.io/).

If you are an author of any of these pictures or sounds and want them credited differently or removed, please open an issue.
