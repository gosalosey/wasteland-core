# Wasteland Core

A standalone zombie-survival framework for FiveM. Everything is written from scratch: no QBCore, Qbox, ESX or ox_* gameplay resources. Each feature is its own module that can be switched on or off, and all settings live in one config folder that updates never overwrite.

**Install with txAdmin:** paste this recipe URL in the txAdmin setup (Popular Recipes → Remote URL):

```
https://raw.githubusercontent.com/gosalosey/wasteland-core/main/txadmin/recipe.yaml
```

Full steps, a manual install and updating: [docs/INSTALL.md](docs/INSTALL.md).

## Features

**The dead**
* Walkers and runners spawn around players, with more of them at night. The server controls the population and checks every hit.
* Six personalities: wanderers, stalkers that follow you from a distance, ambushers that wait still, sprinters, sleepers lying in the road, and pack hunters that surround you.
* They see and hear you. They can't see through walls, standing still is quiet and running is loud. They remember where they last saw you and search there.
* Special infected: screamers call the horde, brutes are tough and hit hard, howlers call from far away, spitters attack from range, and hunters go after lone players. Boss types are included but off by default.
* Horde behaviour: gunshots draw the nearest zombies, and repeated gunfire pulls them in from further away. Explosions and car crashes are loud too.
* They break through wooden walls, doors and gates to reach players hiding behind them.
* Zombie sounds (groans, attacks, pain, death), positioned around the player.

**Survival**
* Hunger, thirst, bleeding, infection, body temperature and the need to pee or poop (`/pee`, `/poop`).
* Death drops everything except your hotbar into a body bag where you fell.
* A HUD with three modes: compact, only when it matters, and off.

**Inventory and loot**
* A grid ("Tetris") inventory with item sizes, weight and durability, plus a hotbar and an auto-sort button.
* Pockets grow with the clothes you wear. Backpacks have their own grid and open with a right-click.
* Searchable containers all over the map, plus zombie bodies. Loot is scarce, containers are shared between players and refill over time.
* Supply drops by plane, and world events: helicopter crashes, convoys, bandit hideouts and hordes.

**Crafting, hunting and trading**
* Crafting: rags from old clothes, bandages, and blueprints for melee weapons, guns, gun parts and ammo.
* Hunting: deer and boar, harvesting with a blade, campfires and cooking.
* Safe camps with traders (who buy anything you loot), a medic and jobs.
* Trading face to face with other players.

**Progression**
* Skills that grow by doing (F9): scavenging, crafting, medicine, hunting, fitness and combat, each giving small bonuses.
* A survivor's guide (F2): milestones that tick off as you play, what to try next, your stats, and how-to pages.

**Vehicles, bases and groups**
* Wrecks you repair with batteries, wheels, engine parts and fuel. Big trunks, locks with keys, lockpicking.
* Base building (needs a separate props pack): tool cupboards claim the land, and walls, doors, gates and storage snap together. Pieces upgrade from wood to stone to metal, need upkeep, and can be raided. A small area around each cupboard is kept free of zombies.
* Groups: shared map markers and a group radio channel. Proximity voice chat via pma-voice.

**Server**
* An admin panel (F10): players, items, bans, world tools, a live view and debug overlays.
* A custom loading screen, emotes, a character creator and a tailor.
* An update notice in the console when GitHub has a newer version, and an updater that keeps your settings.

## Keys

| Key | What |
|---|---|
| Tab | Inventory |
| Left Alt (hold) | Look and interact: search, trade, repair, open |
| K | Crafting |
| F2 | Survivor's guide |
| F4 | Emotes |
| F6 | Group |
| F9 | Skills |
| F10 | Admin panel (admins) |
| X | Hands up |
| Caps Lock | Radio (voice) |
| 1 - 5 | Hotbar |

Chat commands: `/hud`, `/pee`, `/poop`, `/guide`, `/skills`.

## Requirements

* FXServer with **OneSync** on (game build 3570 is set on purpose, see [docs/INSTALL.md](docs/INSTALL.md)).
* **MySQL or MariaDB** with [oxmysql](https://github.com/overextended/oxmysql). Wasteland creates its own tables on first start.
* [pma-voice](https://github.com/AvarianKnight/pma-voice) for voice chat. The recipe installs it.
* Optional: the **sinor-buildingProps-v2** props pack for base building (licensed, not included).

## Configuration

Every setting is in `resources/[wasteland]/wasteland_config/config/`, one file per module: `zombies.lua`, `inventory.lua`, `loot.lua`, `camps.lua`, `skills.lua`, `guide.lua`, `basebuilding.lua` and so on. Each file explains its settings. `modules.lua` switches whole modules on or off. The updater keeps your files, and saves the new version of any file you've changed next to it as `<name>.lua.new`.

## Repository layout

```
resources/[wasteland]/
  wasteland_config/       your settings (config/*.lua)
  wasteland_core/         kernel: module registry, config validation, lifecycle, Module SDK, net-event guard
  wasteland_database/     database adapter, migrations, health checks (oxmysql)
  wasteland_players/      accounts, sessions, characters
  wasteland_ui/           NUI shell and design system   wasteland_target: Left Alt interaction
  wasteland_appearance/   character creator             wasteland_tailor: clothing shops
  wasteland_inventory/    grid inventory and item API   wasteland_images: item pictures
  wasteland_survival/     needs, health, death, HUD     wasteland_world: clock, weather, empty world
  wasteland_weapons/      weapons, ammo, durability
  wasteland_zombies/      population, AI, horde, sounds wasteland_zombiemodels: your own zombie models
  wasteland_zombiesounds/ the zombie sound files
  wasteland_loot/         searchable containers         wasteland_supplydrops: supply drops (SDK example)
  wasteland_camps/        safe zones and traders        wasteland_quests: camp jobs
  wasteland_crafting/     crafting and blueprints       wasteland_hunting: animals, campfires, cooking
  wasteland_vehicles/     wrecks, parts, fuel, locks    wasteland_events: world events
  wasteland_groups/       groups                        wasteland_trade: player trading
  wasteland_basebuilding/ base building                 wasteland_bases: older base building (off)
  wasteland_skills/       skills                        wasteland_guide: survivor's guide
  wasteland_admin/        admin panel                   wasteland_emotes: emotes and hands up
  wasteland_loadscreen/   loading screen                wasteland_template: example module to copy
docs/                     install, architecture, SDK guide, API, database, testing, in-game tests, known issues
tests/                    automated tests and a simulated FiveM server
tools/                    updater, test runners, database backup, image tools
txadmin/                  txAdmin recipe and server.cfg
```

## Making your own content

Items, loot, recipes, traders, jobs, zombie kinds and vehicles are all set in the config files. To write a whole new module, copy `wasteland_template` and follow [docs/SDK_GUIDE.md](docs/SDK_GUIDE.md), which walks through the supply drop module as an example. The full API is in [docs/MODULE_API.md](docs/MODULE_API.md).

## Tests

About 880 automated tests run against a simulated FiveM server: `tools\run_tests.bat` on Windows, `./tools/run_tests.sh` elsewhere (needs Lua 5.4). A suite against a real MariaDB database also runs when `tests/db.env` is set up. Anything only the game can show (animations, sounds, camera) is listed as a step-by-step check in [docs/IN_GAME_TESTS.md](docs/IN_GAME_TESTS.md). See [docs/TESTING.md](docs/TESTING.md).

## Documentation

* [docs/INSTALL.md](docs/INSTALL.md): install, admins, updating, optional packs
* [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): design, resource map, lifecycle, security
* [docs/SDK_GUIDE.md](docs/SDK_GUIDE.md): adding content and writing modules
* [docs/MODULE_API.md](docs/MODULE_API.md): SDK, config schema, exports and events
* [docs/DATABASE.md](docs/DATABASE.md): database setup, backups, restore
* [docs/CONVENTIONS.md](docs/CONVENTIONS.md), [docs/TESTING.md](docs/TESTING.md), [docs/IN_GAME_TESTS.md](docs/IN_GAME_TESTS.md), [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md)
* [CHANGELOG.md](CHANGELOG.md): what changed, newest first
* [PROJECT_STATUS.md](PROJECT_STATUS.md): milestones and what is checked

## Credits

**Item pictures** (`resources/[wasteland]/wasteland_images`) come from **MK-Items** by [McKleans-Scripts](https://mckleans-scripts.tebex.io/), a free community pack of FiveM item images, converted to WebP. All credit for those pictures goes to their authors, including, as credited by MK-Items:

* Jim and the [JixelPatterns](https://discord.gg/JixelPatterns) community
* MrFurox from [Project Boosted](https://discord.gg/TrvAhGvDs3)
* [NatasWillDoIt](https://github.com/NatasWillDoIt)
* the [Project Sloth](https://github.com/Project-Sloth) community
* [googleoblivion](https://github.com/googleoblivion) and [oosayeroo](https://github.com/oosayeroo)
* and everyone who contributed images to MK-Items

The pictures `cap`, `jeans`, `sunglasses`, `siphon_hose` (`tools/images`) and `matches` were made for Wasteland Core.

If you are an author of one of these pictures and want it credited differently or removed, please open an issue.

**Other software** used by Wasteland Core and not included here: [FiveM / FXServer](https://fivem.net), [oxmysql](https://github.com/overextended/oxmysql) (database driver) and [pma-voice](https://github.com/AvarianKnight/pma-voice) (voice chat, MIT licence, by AvarianKnight). Base building needs the **sinor-buildingProps-v2** props pack by sinorsystem, a licensed Cfx asset pack that you get and install yourself. **Zombie sounds** (`wasteland_zombiesounds`) are from the free **Zombie Sound Pack** by Catastic, plus a few extra zombie clips. If you are the author of one of these sounds and want it credited differently or removed, please open an issue.
