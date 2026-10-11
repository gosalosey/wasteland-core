# Wasteland Core: adding your own content

This guide is for server owners and developers who want to add to Wasteland Core: new items, loot, recipes, traders, jobs and zombies, or a whole new module. It is written as recipes. The exact API of every module is in [MODULE_API.md](MODULE_API.md); how the pieces fit together is in [ARCHITECTURE.md](ARCHITECTURE.md).

Most content needs **no code at all**. It lives in config files in `resources/[wasteland]/wasteland_config/config/`. After editing one, restart the resource it belongs to (for example `restart wasteland_loot` in the server console) or restart the server. A config mistake never crashes the server: the module refuses to start and the console names the file, the setting and what it expected.

Contents:

1. [Items](#1-items)
2. [Food, drink and medicine](#2-food-drink-and-medicine)
3. [Weapons](#3-weapons)
4. [Loot](#4-loot)
5. [Crafting recipes and blueprints](#5-crafting-recipes-and-blueprints)
6. [Camps, traders and shops](#6-camps-traders-and-shops)
7. [Jobs (quests)](#7-jobs-quests)
8. [Zombies](#8-zombies)
9. [Vehicles](#9-vehicles)
10. [Emotes, tailors, supply drops](#10-emotes-tailors-supply-drops)
11. [Writing your own module](#11-writing-your-own-module)
12. [Testing your work](#12-testing-your-work)

---

## 1. Items

File: `inventory.lua`, table `items`. Every item in the game is defined here, even ones that other modules give behaviour to (weapons, food, blueprints).

```lua
items = {
    -- name = { ... }   the name is what everything else uses (lower case, a-z 0-9 _)
    canned_tuna = {
        label = 'Canned tuna',          -- what players see
        image = 'canned_tuna',          -- picture in wasteland_images (file name without .webp); default: the item name
        category = 'food',              -- food drink medical material tool clothing armor container weapon ammo misc
        width = 1, height = 1,          -- grid cells
        weight = 0.3,                   -- kilograms per unit
        stack = 50,                     -- per stack (default 50; 1 = never stacks)
        description = 'Still good. Probably.',
    },
}
```

Other fields:

| Field | Use |
|---|---|
| `durability = 100` | the item wears out (weapons, tools, clothing, armor). Items with durability never stack. |
| `equip = 'torso'` | can be worn: `head eyes torso armor back legs feet` |
| `container = { width, height, maxWeight }` | worn in `back`: a backpack with its own grid |
| `warmth = 4` | degrees of insulation while worn (temperature) |
| `repairs = 'clothing'` | right-clicking a damaged item of that category offers "Repair with ..." (the module that registered the item as usable does the repair) |
| `color = '#5a4d6e'` | tile colour when there is no picture |

**Pictures.** `wasteland_images/html/images/` holds about 3,500 pictures; `wasteland_images/html/index.txt` lists their names. To use your own, put a PNG (transparent background, about 256 x 256) in `tools/images/` and run `python tools/import_images.py --custom-only`.

**Giving items.** Admins: `/give <server id> <item> [count]`, or the admin panel (F10, Players, Items).

**Making an item do something** when used needs a module: one module registers it with `exports.wasteland_inventory:RegisterUsable(name, handler)`. Food and medicine are already handled by survival (next section).

---

## 2. Food, drink and medicine

File: `survival.lua`, table `consumables`. The item must exist in `inventory.lua`.

```lua
consumables = {
    canned_tuna = { hunger = 30, thirst = -5, animation = 'eat', prop = 'prop_ecola_can' },
    morphine    = { health = 40, animation = 'treat', message = 'The pain is gone.' },
}
```

Fields: `hunger`, `thirst` (+/-), `health` (hit points), `stopBleeding` (levels, 1-3), `infection` (negative cures), `treatmentMinutes` (infection cannot grow meanwhile), `temperature` (degrees), `animation` (`eat`, `drink`, `treat`), `prop` (a GTA model held in the hand), `message`.

The health panel in the inventory lists these items automatically as the fix for bleeding, infection, hunger and so on.

Clothing and armor repair items are in the same file: `clothing.repairItems` and `armor.repairItems` (`{ item = { percent = 50 } }`).

---

## 3. Weapons

Two steps:

1. The item, in `inventory.lua` (category `weapon`, with `durability`):
   ```lua
   weapon_combatpistol = { label = 'Combat pistol', category = 'weapon', width = 2, height = 2, weight = 0.9, durability = 600 },
   ```
2. What it does, in `weapons.lua`:
   ```lua
   weapon_combatpistol = { hash = 'WEAPON_COMBATPISTOL', ammo = 'ammo_9mm', noise = 120 },
   ```
   `hash` is the GTA weapon name, `ammo` an ammo item (leave out for melee), `wear` durability lost per shot or hit (default 1), `noise` how far zombies hear it (metres).

---

## 4. Loot

File: `loot.lua`.

**Tables** say what can be found:

```lua
tables = {
    gun_locker = { emptyChance = 0.4, rolls = { 1, 2 }, items = {
        { name = 'ammo_9mm', min = 5, max = 15, weight = 10 },
        { name = 'weapon_pistol', min = 1, max = 1, weight = 1 },
    } },
}
```

`emptyChance` (0-1) is the chance the container is empty. `rolls` is how many picks. Each pick chooses one line by `weight` (10 against 1 means ten times as often) and gives between `min` and `max` of it.

**Containers** are the props that can be searched:

```lua
containers = {
    locker = { label = 'Gun locker', table = 'gun_locker', searchSeconds = 5, refillMinutes = 90,
        grid = { 4, 4 }, anim = 'search', models = { 'prop_gun_locker_01' } },
}
```

`models` are GTA prop names; every copy of that prop on the map becomes searchable. `anim` is `bin`, `search` or `kneel`. `reach` (metres) lets players search big props from further away (wrecks use 7).

**Without editing files.** Admins can do the same in the game:

* Hold Left Alt on any prop: "Admin: loot container…", pick a category, give it the name players see.
* Admin panel (F10), **Loot** tab: make whole new loot categories with their own item lists.

These are stored on the server and survive restarts. Props listed in `loot.lua` cannot be changed there.

Other modules can roll a table too: `exports.wasteland_loot:RollTable('gun_locker')` returns `{ { name, count } }` (the supply drop module does this).

---

## 5. Crafting recipes and blueprints

File: `crafting.lua`, table `recipes`.

```lua
recipes = {
    spear = { label = 'Spear', result = { name = 'weapon_spear', count = 1 },
        ingredients = { { name = 'scrap_metal', count = 2 }, { name = 'rag', count = 1 } },
        seconds = 6, blueprint = 'blueprint_spear' },
}
```

* No `blueprint`: everyone knows the recipe from the start.
* With `blueprint`: add that item to `inventory.lua` (category `misc`), put it in a loot table, and players learn the recipe by using it.

Every item named in a recipe must exist in `inventory.lua`; the module refuses to start otherwise and names the recipe and item.

---

## 6. Camps, traders and shops

File: `camps.lua`.

**Shops** are price lists:

```lua
shops = {
    mechanic = { label = 'Mechanic', items = {
        { name = 'car_battery', buy = 500, sell = 120, stock = 1, restock = 1 },
        { name = 'scrap_metal', sell = 4 },     -- they only buy this
    } },
}
```

`buy` is what the player pays, `sell` what the player gets. `stock` limits what the trader sells; it refills by `restock` every `restockMinutes` (top of the file).

**Camps** are safe zones (no zombies) with traders:

```lua
camps = {
    { id = 'docks', label = 'Docks Camp', coords = { x = 0.0, y = 0.0, z = 0.0 }, radius = 60,
        blip = { sprite = 40, color = 2 },
        traders = {
            { shop = 'mechanic', model = 's_m_y_xmech_01', coords = { x = 0.0, y = 0.0, z = 0.0, heading = 90.0 } },
        } },
}
```

Get coordinates in the game: admin panel (F10), **Coords** tab, "Copy vector4", and put the numbers in `coords` (x, y, z, heading).

---

## 7. Jobs (quests)

File: `quests.lua`, table `quests`. Traders offer them ("Jobs").

```lua
quests = {
    fuel_run = {
        label = 'Fuel run', cooldownMinutes = 60, camps = { 'sandy' },   -- leave out camps = every camp
        description = 'The generator is dry.',
        objectives = { { type = 'bring', item = 'jerry_can', count = 1 } },
        rewards = { cash = 75, items = { { name = 'bandage', count = 2 } } },
    },
}
```

Objective types:

| Type | Example |
|---|---|
| `bring` | `{ type = 'bring', item = 'scrap_metal', count = 6 }` (taken at hand-in) |
| `kill` | `{ type = 'kill', count = 10 }`, or with `near = { x, y, z, radius = 80 }, label = 'the hospital'` |
| `visit` | `{ type = 'visit', coords = { x, y, z }, radius = 40, label = 'the airfield' }` |
| `search` | `{ type = 'search', container = 'crate', count = 3 }` (a `loot.lua` container type) |
| `craft` | `{ type = 'craft', recipe = 'bandage', count = 2 }` |

A module can count its own events towards jobs with `exports.wasteland_quests:AddProgress(source, { type = ..., ... })`.

---

## 8. Zombies

File: `zombies.lua`.

* `population`: how many around each player, the most in the world, how far away they appear and disappear.
* `kinds`: each kind's `speed`, `damage = { min, max }`, `infectionChance`, `infection = { min, max }`, `bleedingChance`, and for kinds other than walkers `chance` / `nightChance` (percent of new zombies).
* `models`: what they look like (GTA ped models).
* `detection`: how far they see and hear players.
* `loot`: the chance a dead zombie leaves a bag, and what is in it (the `body` container in `loot.lua`).

To add a kind, add a line to `kinds` with a `chance`, for example a tough "brute":

```lua
brute = { speed = 1.2, chance = 5, nightChance = 8, damage = { 15, 22 }, infectionChance = 0.3, infection = { 8, 14 }, bleedingChance = 0.4 },
```

---

## 9. Vehicles

File: `vehicles.lua`.

* `models`: the GTA vehicle models wrecks are made from.
* `spawnPoints`: where wrecks appear (`{ x, y, z, heading }`); copy them from the Coords tab. Each spot is checked for props and walls the first time (`spotCheck`).
* `wreck`: how broken new wrecks are; `tankLitres`, `fuel`, `repair`, `seconds`, `lockpick`, `pump`: the rest of the rules.

---

## 10. Emotes, tailors, supply drops

* **Emotes:** `wasteland_emotes/shared/emotes.lua`, one line per emote: `{ name, label, cat, scenario = '...' }` or `{ name, label, cat, dict = '...', anim = '...', flag = 1 }` (flag 49 = upper body, you can walk).
* **Tailors:** `tailor.lua`: `price`, NPC `model`, `blip`, and `shops = { { label, coords = { x, y, z, heading } } }`.
* **Supply drops:** `supplydrops.lua`: how often, how long they last, what is inside (a loot table or an item list) and the `points` they can land on. Admins: `/supplydrop` or `/supplydrop here`.

---

## 11. Writing your own module

A module is a FiveM resource that registers with the core. The core starts modules in dependency order, gives them their checked config, restarts them when a dependency restarts, and reports their health (`/wasteland status` in the console).

The best way to learn is to read the example: **`resources/[wasteland]/wasteland_supplydrops`**. It is a complete, real feature (supply crates that come down, show on the map and hold loot), small enough to read in one sitting, and commented for this guide. Copy it to start your own.

### Files

```
wasteland_supplydrops/
  fxmanifest.lua          the resource: scripts and dependencies
  shared/rules.lua        pure rules (no game calls): easy to test
  server/sql.lua          the database table (migrations) and statements
  server/main.lua         the module: config, init/shutdown, network, exports
  client/main.lua         what players see: blips, the crate, the target option
wasteland_config/config/supplydrops.lua      its settings
tests/unit/supplydrop_rules.lua              tests of the rules
tests/integration/supplydrops.lua            tests of the module in a simulated server
```

### Step 1: the manifest

`fxmanifest.lua` loads the SDK and, if you use the database, the database library, before your own code:

```lua
server_scripts {
    '@wasteland_core/sdk/module.lua',      -- Wasteland.DefineModule
    '@wasteland_database/lib/db.lua',       -- WDB (only if you use the database)
    'server/sql.lua',
    'server/main.lua',
}
```

### Step 2: define the module

```lua
M = Wasteland.DefineModule({
    name = 'supplydrops',                     -- unique; also the config file name
    version = '1.0.0',
    core = '^1.1.0',
    dependencies = { database = '^0.1.0', players = '^0.1.0', inventory = '^0.1.0' },
    optionalDependencies = { loot = '^0.1.0' },   -- used if it runs
    async = true,                             -- init waits for the database: call M.ready()
    config = { file = 'supplydrops.lua', optional = true, schema = { ... } },
    onInit = function(mod) ... end,
    onShutdown = function() ... end,
})
```

* The **schema** describes every setting (type, default, limits). The core checks the file against it before `onInit`, so `M.config` is always valid. The schema language is in MODULE_API.md ("Configuration schema DSL").
* **`onInit`** sets things up. Return `false, 'reason'` to refuse to start (for example, an item in the config that does not exist).
* **`onShutdown`** undoes everything `onInit` did. Init can run again later (when a dependency restarts), so stop threads with a token:
  ```lua
  local token = {}
  runToken = token
  Citizen.CreateThread(function()
      while runToken == token do Citizen.Wait(5000) ... end
  end)
  -- onShutdown: runToken = nil
  ```
* **Async init:** never wait inside `onInit`. Start a thread, do the waiting work (the migration), then call `M.ready()`, or `M.fail('why')`.

### Step 3: the database

Put the table in a migration list and pass it to `WDB.migrate` on every start (it only applies what is new). Never change an applied migration; add the next number:

```lua
WLSD.MIGRATIONS = { { version = 1, name = 'create_supply_drops', up = [[CREATE TABLE IF NOT EXISTS wl_supply_drops (...)]] } }
local ok, err = WDB.migrate('supplydrops', WLSD.MIGRATIONS)
local id, err = WDB.insert(SQL.insert, { label, x, y, z, os.time() })
```

`WDB` calls wait for the database, so call them from a thread or a net event handler, never from `onInit` directly. Always use `?` placeholders.

### Step 4: talking to clients

Clients **ask**; the server **decides**. Every client-to-server event goes through `M.netEvent`, which checks the arguments and limits how often a player can send it:

```lua
M.netEvent('wasteland:supplydrops:server:open', {
    args = { { type = 'integer', required = true, min = 1 } },
    rateLimit = { burst = 4, perSecond = 1 },
}, function(src, id)
    -- still check the game state: does the drop exist, is the player next to it?
end)
```

Names are `wasteland:<module>:server:<action>` (to the server) and `wasteland:<module>:client:<action>` (to clients).

### Step 5: using other modules

Only through their exports and events, never their files:

```lua
exports.wasteland_inventory:EnsureStash('supply_' .. id, { label = 'Supply crate', width = 6, height = 5, coords = c, reach = 3.5 })
exports.wasteland_inventory:OpenStash(src, 'supply_' .. id, { open = true, ... })
exports.wasteland_loot:RollTable('crate')            -- optional dependency: check it runs first
exports.wasteland_players:GetCharacterId(src)
```

On the client: blips and props are normal GTA natives; interaction goes through the target system (`exports.wasteland_target:AddEntity(object, { { label = 'Open supply crate', onSelect = ... } })`); screens through `wasteland_ui` (see MODULE_API.md, "UI screens").

### Step 6: offering something back

Exports let other modules use yours; server events tell them what happened:

```lua
exports('GetActiveDrops', function() ... end)
TriggerEvent('wasteland:supplydrops:opened', src, id)    -- others: AddEventHandler('wasteland:supplydrops:opened', ...)
```

### Step 7: switch it on

1. Settings file: `wasteland_config/config/<name>.lua`.
2. `server.cfg`: `ensure wasteland_<name>` after the modules it needs.
3. Optional: `<name> = true` in `wasteland_config/config/modules.lua` (set it to `false` to switch the module off without removing it).
4. Start the server and check the console, or `wasteland status`.

### Checklist

* Every client event: `M.netEvent`, and the handler re-checks distance, ownership and what the player carries.
* Init and shutdown are symmetric; threads stop on shutdown.
* Settings in a schema, not hard-coded numbers.
* Database: migrations only ever added, `?` placeholders, writes from threads.
* Other modules: exports and events only; optional ones checked with `GetResourceState(...) == 'started'`.
* Tests for the rules and for the module (next section).

---

## 12. Testing your work

The test suite runs a simulated FiveM server (no game needed): `lua tests/run.lua` from the repository root, or `lua tests/run.lua supply` for tests whose file name contains "supply". See [TESTING.md](TESTING.md).

* **Rules** (`tests/unit/supplydrop_rules.lua`): pure functions with a fake random function.
* **The module** (`tests/integration/supplydrops.lua`): a small test config, the module's SQL taught to the in-memory database, a player with a character, then exports, client events and time (`server:advance(ms)`), and checks of what clients were told, the database and the log.
* **The real database** (`tests/db/mariadb.lua`): the same against MariaDB, so every SQL statement has run for real.

Add your test files to `tests/suites.lua`, and your resource to `tests/run.lua` (`server:addResource`) so the simulated server knows it.

Things only the game can check (props, animations, how a screen feels) go into [IN_GAME_TESTS.md](IN_GAME_TESTS.md) as numbered steps with what should happen.
