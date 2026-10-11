# Module API and SDK (core api 1.1.0)

This is the stable interface for writing Wasteland modules. Anything not documented here is internal and may change.

## Quick start: a new module

1. Copy `resources/[wasteland]/wasteland_template` to `resources/[wasteland]/wasteland_mymodule`.
2. In `server/main.lua`, set `name = 'mymodule'` and write your `onInit` and `onShutdown`.
3. If you need settings, create `wasteland_config/config/mymodule.lua` and declare a schema.
4. Add `ensure wasteland_mymodule` to server.cfg after `wasteland_core`.
5. Optionally list it in `wasteland_config/config/modules.lua` (`mymodule = true`).

fxmanifest.lua:

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'
version '1.0.0'
dependency 'wasteland_core'
server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}
```

server/main.lua:

```lua
local M = Wasteland.DefineModule({
    name = 'mymodule',            -- required, [a-z][a-z0-9_]*, unique
    version = '1.0.0',            -- required, semver
    api = '1.0.0',                -- optional interface version (defaults to version)
    description = 'What it does',
    core = '^1.0.0',              -- required core api range (SDK default ^1.0.0)
    dependencies = { inventory = '^1.0.0' },      -- must be running first
    optionalDependencies = { quests = '^1.0.0' }, -- waited for only if registered
    async = false,                -- true: call M.ready() when setup finishes
    config = {
        file = 'mymodule.lua',    -- in wasteland_config/config/
        optional = true,          -- missing file => defaults (+ warning)
        schema = { type = 'table', fields = {
            interval = { type = 'integer', default = 30, min = 1, max = 3600,
                         description = 'Seconds between ticks' },
        } },
    },
    onInit = function(M, ctx)
        -- M.config is the validated config (defaults applied).
        -- ctx.framework = FrameworkInfo
        -- Return false, 'reason' (or raise an error) to fail.
    end,
    onShutdown = function(M, reason)
        -- Undo everything onInit did. Must be safe to call once per init.
        -- reason: 'resource_stop' | 'core_stopped' | 'server_shutdown' |
        --         'dependency_unavailable:<name>' | 'init_failed'
    end,
})
```

### The module handle `M`

| Field / function | Meaning |
|---|---|
| `M.name` | module name |
| `M.config` | validated config table (set before `onInit`) |
| `M.framework` | FrameworkInfo at init time |
| `M.active` | `true` between init and shutdown |
| `M.log:debug/info/warn/error(fmt, ...)` | logging through the core (central levels apply) |
| `M.ready()` | async modules: report successful initialisation |
| `M.fail(reason)` | report failure (running modules are stopped and dependents cascaded) |
| `M.setHealth(status, detail)` | running modules: `'degraded'` with a reason, or `'ok'` (api 1.1) |
| `M.netEvent(name, opts, handler)` | register a guarded client → server event (api 1.1, see below) |
| `M.register()` | re-register manually (normally automatic) |
| `M.registered`, `M.registerError` | outcome of the last registration attempt |

### Rules for module authors

* `onInit` and `onShutdown` must be symmetric: init may run again after a shutdown (for example, when a dependency restarts). Use a token to stop threads, as the template shows.
* Do not `Citizen.Wait` inside `onInit`. Start a thread, set `async = true` and call `M.ready()`.
* Never read another module's files or globals. Use its exports and events.
* The SDK already handles your own resource stopping and core restarts (it re-registers automatically).

### Guarded net events (`M.netEvent`)

Client → server events are the only network entry points, and every one goes through the guard. Never use `RegisterNetEvent` directly in a module.

```lua
M.netEvent('wasteland:shop:server:buy', {
    args = {                                   -- one schema node per argument (config schema DSL)
        { type = 'string', required = true, pattern = '^[a-z_]+$', maxLength = 32 },
        { type = 'integer', required = true, min = 1, max = 10 },
    },
    rateLimit = { burst = 3, perSecond = 1 },  -- default { burst = 10, perSecond = 5 }
}, function(source, item, count)
    -- runs only for valid input from a connected player while the module is running
end)
```

The name must be `wasteland:<module>:server:<action>`. The guard checks these, in order:

1. The sender is a connected player.
2. The module is running. Events that arrive while it is down are dropped.
3. A token-bucket rate limit, per player and event.
4. No more arguments than declared, and each argument is valid against its schema. Defaults are applied, and unknown table keys are dropped.

Rejections are logged (at most once per 10 s per player, event and kind). They are reported to the core as `wasteland:core:netViolation`, which kicks a player after `framework.security.kickAfterViolations` rejections (0, the default, never kicks). A handler that raises an error is logged and does not affect other events. The handler still has to check anything that depends on game state, such as ownership and distance.

## Configuration schema DSL

Schemas are plain data (no functions). Node fields:

| Field | Applies to | Meaning |
|---|---|---|
| `type` | all | `any` `string` `number` `integer` `boolean` `enum` `table` `array` `map` `vector3` |
| `default` | all | value used when absent (deep-copied) |
| `required` | all | absent with no default → error |
| `description` | all | documentation |
| `min`, `max` | number, integer | inclusive bounds |
| `minLength`, `maxLength`, `pattern` | string | length and Lua pattern |
| `values` | enum | allowed values (list) |
| `fields`, `allowUnknown` | table | child nodes; unknown keys warn unless `allowUnknown` |
| `nullable` | table | an absent table stays `nil` instead of `{}` |
| `items`, `minItems`, `maxItems` | array | element node and size |
| `keys`, `values` | map | key node (default string) and value node |

Absent tables are materialised as `{}` so nested defaults apply. Schemas are checked when a module registers, so an invalid schema or invalid default is rejected with a precise message.

## Core exports (server)

Call as `exports.wasteland_core:Name(...)`. The caller's resource is identified by the platform (`GetInvokingResource`), not by arguments.

| Export | Returns | Notes |
|---|---|---|
| `RegisterModule(definition)` | `ok, err` | Normally called by the SDK |
| `ReportModuleReady(name)` | `ok, err` | Only the owning resource; only while `initializing` |
| `ReportModuleFailed(name, reason)` | `ok, err` | Only the owning resource |
| `ReportModuleHealth(name, status, detail)` | `ok, err` | api 1.1. `'ok'` or `'degraded'`; only the owning resource; shown in `status` |
| `GetModuleStatus(name)` | ModuleStatus or `nil` | |
| `GetModuleStatuses()` | ModuleStatus[] sorted by name | |
| `IsModuleRunning(name)` | boolean | |
| `GetModuleConfig(name)` | config copy or `nil` | Validated config of any module |
| `GetFrameworkInfo()` | FrameworkInfo | |
| `IsReady()` | boolean | Startup window finished |
| `Log(module, level, message)` | boolean | level: debug/info/warn/error |
| `GetRecentIssues(limit)` | records `{time, module, level, message, source}` | Recent warnings and errors |

## Core events (server-local, `AddEventHandler`)

| Event | Arguments | When |
|---|---|---|
| `wasteland:core:booting` | FrameworkInfo | Core loaded (also in config_error) |
| `wasteland:core:frameworkState` | state, previousState | Framework state change |
| `wasteland:core:moduleState` | name, state, previousState, reason | Any module state change |
| `wasteland:core:ready` | FrameworkInfo | Startup window finished |
| `wasteland:core:shutdown` | reason | Before modules are shut down |
| `wasteland:core:moduleHealth` | name, status, previousStatus, detail | A module reported a health change (api 1.1) |
| `wasteland:core:netViolation` | source, module, eventName, kind, detail | The guard rejected a client event; kind is `source`, `rate` or `payload` (api 1.1) |

States: framework `booting | config_error | ready | shutting_down | stopped`; module `waiting | initializing | running | failed | disabled | stopped`. A running module also has a health: `ok` or `degraded` (with a detail).

ModuleStatus (api 1.1) adds `health` and `healthDetail`.

## Admin command

`wasteland <subcommand>` (the name follows `framework.shortName`). Available from the server console or to players with the `wasteland.admin` ACE. Output for players appears in F8.

| Subcommand | Effect |
|---|---|
| `status` | framework and module table |
| `module <name>` | details, dependencies, config warnings |
| `config validate` | validate every config file without applying anything |
| `config reload` | in config_error: retry startup; otherwise validate only |
| `issues [n]` | recent warnings and errors |
| `version` | framework version |

To grant the ACE in server.cfg: `add_ace group.admin wasteland.admin allow`.

## Database (`wasteland_database`, database api 0.1)

Modules never call a database driver directly. They include the library and declare the dependency:

```lua
-- fxmanifest.lua
dependencies { 'wasteland_core', 'wasteland_database' }
server_scripts {
    '@wasteland_core/sdk/module.lua',
    '@wasteland_database/lib/db.lua',
    'server/main.lua',
}
-- module definition
dependencies = { database = '^0.1.0' },
```

Call these from a thread or an event handler, because they wait for the answer. Every function returns `value, err`. Check `err`, not the value: a query can legitimately return `nil`.

| Function | Returns |
|---|---|
| `WDB.query(sql, params)` | list of rows (`{ column = value }`) |
| `WDB.single(sql, params)` | first row or `nil` |
| `WDB.scalar(sql, params)` | first column of the first row or `nil` |
| `WDB.insert(sql, params)` | insert id |
| `WDB.update(sql, params)` | affected rows |
| `WDB.transaction({ { sql, params }, ... })` | `true`; all or nothing |
| `WDB.migrate(moduleName, migrations)` | `{ applied, version }` |
| `WDB.isUp()` | boolean, no waiting |

* Use `?` placeholders and pass values in `params`. Never build SQL from player input.
* Read timestamps with `UNIX_TIMESTAMP(col)` so you always get a number.
* While the database is down, every call fails at once with `database unavailable: ...`. A call that gets no answer fails after `database.queryTimeoutMs`. **A write that timed out may still have been applied**: design writes to be idempotent (upserts and absolute values, not increments).
* Server event `wasteland:database:health (up, detail)` fires when the connection is lost or restored.
* Exports (callback style, used by the library): `Execute(kind, sql, params, cb)`, `Transaction(statements, cb)`, `Migrate(module, list, cb)`, `IsUp()`, `GetHealth()`.

### Migrations

Pass the full list on every start. It is usually the first thing an async module does in `onInit`:

```lua
local MIGRATIONS = {
    { version = 1, name = 'create_things', up = [[CREATE TABLE IF NOT EXISTS wl_things (...)]] },
    { version = 2, name = 'add_owner', up = [[ALTER TABLE wl_things ADD COLUMN owner INT NULL]] },
}
-- in onInit (async = true):
Citizen.CreateThread(function()
    local result, err = WDB.migrate('mymodule', MIGRATIONS)
    if not result then return M.fail('migrations failed: ' .. err) end
    M.ready()
end)
```

* Versions are 1, 2, 3 ... with no gaps. They are applied in order, one module at a time, and each one is recorded in `wl_migrations` together with a checksum.
* **Never edit an applied migration.** The checksum check refuses to start the module. Add a new migration instead.
* A database with more migrations than the module knows (a downgrade) is refused.
* MySQL/MariaDB commit DDL implicitly, so a migration is only fully atomic for data statements. Use **one DDL statement per migration** and make it idempotent (`IF NOT EXISTS`).
* Prefix table names with `wl_`.

## Players (`wasteland_players`, players api 0.1)

Identity: an **account** per Rockstar license, a **session** per connected player (`source`), and up to `players.maxCharacters` **characters** per account. One character is loaded per session. Session APIs take `source`; persistent APIs take `characterId`.

Exports:

| Export | Returns |
|---|---|
| `GetSession(source)` | `{ source, accountId, license, name, state, characterId }` or `nil` |
| `GetCharacter(source)` | `{ id, slot, firstName, lastName, source }` or `nil` |
| `GetCharacterId(source)` / `GetSourceByCharacterId(id)` | id / source or `nil` |
| `GetOnlineCharacters()` | list of characters |
| `IsCharacterLoaded(source)` | boolean |
| `GetCharacterData(characterId, key)` | stored value (copy) or `nil, err` |
| `SetCharacterData(characterId, key, value)` | `ok, err`; JSON-serialisable values, `nil` deletes, size limit `players.maxCharacterDataBytes` |
| `SaveCharacter(characterId, cb)` | starts a save; `cb(ok, err)` after the write |

Character data is a per-character key-value store. Use your module name as the key (or `module.sub`). It is saved:

* every `players.saveIntervalSeconds`
* when the character unloads (player leaves, switches character, resource stops, txAdmin shutdown)
* immediately, when you call `SaveCharacter`. Do this after **valuable** changes, and only confirm the action to the player when `cb` reports `ok`.

Server events (`AddEventHandler`):

| Event | Arguments | When |
|---|---|---|
| `wasteland:players:sessionStarted` | source, accountId | A player joined and has a session |
| `wasteland:players:characterLoaded` | source, character, restored | A character is loaded (`restored` = after a resource restart) |
| `wasteland:players:characterUnloading` | source, character, reason | Before the final save. Write your last data **synchronously** here |
| `wasteland:players:characterUnloaded` | source, characterId, reason | The final save succeeded |
| `wasteland:players:sessionEnded` | source, accountId, reason | The player left |

Client events (for the UI): `wasteland:players:client:characters`, `wasteland:players:client:result`, `wasteland:players:client:characterLoaded`. Guarded server events: `wasteland:players:server:requestCharacters`, `createCharacter(first, last)`, `selectCharacter(slot)`, `deleteCharacter(slot, confirmFirstName)`.

## UI screens (`wasteland_ui`, ui api 0.1)

`wasteland_ui` owns the NUI page and the design system (`html/style.css`). Each module keeps its own screens: a JS file in the module's resource, listed under `files`, which the shell loads when the screen opens.

Client Lua (in the module's resource):

```lua
exports.wasteland_ui:Open('myScreen', {
    script = 'html/my_screen.js',   -- path inside YOUR resource (listed under `files`)
    data = { ... },                  -- passed to mount()
    focus = true, cursor = true,     -- NUI keyboard / mouse focus (default true)
})
exports.wasteland_ui:Update('myScreen', { ... })    -- calls update(data)
exports.wasteland_ui:Close('myScreen')              -- only the owning resource
exports.wasteland_ui:IsOpen('myScreen')
exports.wasteland_ui:SetFocus('myScreen', focus, cursor)

AddEventHandler('wasteland:ui:client:action', function(screen, action, payload)
    if screen ~= 'myScreen' then return end
    -- NUI input is untrusted: send anything that matters to the server
    -- through a guarded net event (M.netEvent).
end)
```

Screen script:

```js
(function () {
    const UI = window.WastelandUI;          // h, button, slider, picker, tabs, registerScreen, post
    UI.registerScreen('myScreen', {
        mount(el, data, api) { el.appendChild(UI.h('div', { class: 'wl-panel', text: 'Hello' })); },
        update(data) {},
        unmount() {},
    });
    // api.post(action, payload) -> arrives as wasteland:ui:client:action
})();
```

Screens of a stopped resource are closed automatically. Use the design-system classes (`wl-panel`, `wl-title`, `wl-btn`, `wl-btn--primary`, `wl-input`, `wl-field`, `wl-tabs`, `wl-message`) and CSS variables (`--wl-accent`, ...) so the game stays consistent. Keep logic that can be tested out of the DOM code and export it for Node (see `characters.js`).

## Appearance (`wasteland_appearance`, appearance api 0.1)

* The creator opens automatically when a character without a look is loaded (it cannot be cancelled). An admin can reopen it with `/appearance <server id>` (ACE `appearance.adminAce`); that one can be cancelled.
* The look is stored as character data key `appearance` (format in `shared/defs.lua`), validated on the server (schema, allowed clothing slots, `blockedClothing`), saved write-through, and applied on every load and after every respawn.
* Export: `GetAppearance(characterId)`. Client events: `wasteland:appearance:client:openCreator|apply|saved|saveFailed`. Guarded server events: `wasteland:appearance:server:save(appearance)`, `request`, `cancel`.
* Players module (client export): `exports.wasteland_players:IsReady()` is true once a character is loaded and the player is placed in the world.

## Inventory (`wasteland_inventory`, inventory api 0.1)

**Model.** Items are defined by name (config `inventory.lua` → `items`, or the `RegisterItem` export) with a size in grid cells, weight, stack size, optional durability, an optional `equip` slot and, for bags, a `container` grid. Players have **pockets** (`player:<characterId>`), **worn items** (`equip:<characterId>`, slots `head eyes torso back legs feet`) and, while wearing a bag, its grid (`item:<uid>`). Items on the ground are `drop:<id>` and stashes `stash:<name>`.

**ItemStack contract:** `{ uid, name, count, x, y, rotated, slot, metadata }`. `x`/`y` are 0-based cells (grid stacks) and `slot` is set for worn items. `metadata.durability` is set for items with durability. Clothing metadata is `{ model, <part> = { drawable, texture } }`.

Server exports:

| Export | Returns |
|---|---|
| `AddItem(target, name, count, metadata?)` | `ok, err`. `target` is a player server id (pockets, then worn bag) or an inventory id. **All or nothing**: tops up stacks, then free space; fails without changes if it does not all fit. |
| `RemoveItem(target, name, count)` | `ok, err`. All or nothing. |
| `GetItemCount(target, name)` | number |
| `GetItemDefinition(name)` | definition copy or `nil` |
| `RegisterItem(name, definition)` | `ok, err`. Add a module's own item (same fields as the config). |
| `RegisterUsable(name, handler)` | `ok, err`. `handler(source, stack, inventoryId)` returns the number of units to consume (0 for none), or `false, message` to refuse. A message returned after a successful use is shown to the player. |
| `OpenStash(source, name, opts)` | `true` (loading starts) or `false, err`. `opts`: `label, width, height, maxWeight, coords` (with coords the player must be within `reachDistance`). |
| `GetInventory(id)` | snapshot or `nil` |
| `IsLoaded(source)` | boolean |

Rules the server enforces on every request: the player must be able to reach both inventories (own pockets, worn items and worn bag, or a drop or stash the server opened for them, within reach). The item must still be there. The target cells must be free and inside the grid. Weight limits apply. Bags never go inside bags, and worn items must match their slot and the character's body. Every operation runs without yielding and is saved as one transaction in an ordered queue. While the database is down, operations are refused.

## Survival (`wasteland_survival`, survival api 0.1)

The server owns each character's **hunger, thirst** (0-100, 100 = full), **infection** (0-100, 100 = lethal), **bleeding** (0-3) and **body temperature** (°C). They are stored as character data `survival` and updated every `tickSeconds`. The rules are pure functions in `shared/model.lua`. Health stays on the client's ped: the server sends damage and healing, and the client applies them. Consumables are set in `survival.lua` → `consumables` and registered as usable items with the inventory.

Exports:

| Export | Returns |
|---|---|
| `GetStats(source)` | `{ hunger, thirst, infection, bleeding, temperature, dead }` or `nil` |
| `AddInfection(source, amount)` | ok (Milestone 5: zombie hits) |
| `AddBleeding(source, levels)` | ok |
| `ModifyStats(source, { hunger, thirst, infection, temperature })` | ok (changes, not absolute values) |
| `IsDead(source)` | boolean |

Server events: `wasteland:survival:died (source, characterId, cause)` and `wasteland:survival:respawned (source, characterId)`. On death, the inventory's `DeathDrop` puts everything except hotbar items into a body bag (see Inventory), and the respawn point is random from `respawn.points`.

Inventory additions: `DeathDrop(source, label)`, `GetWornItems(source)`, an item field `warmth` (insulation in °C while worn), and drops carry `owner` and `label` (body bags show as a map marker for their owner).

## World (`wasteland_world`, world api 0.1)

One game clock and one weather for everyone, decided by the server. Ambient population is off: OneSync population is disabled for routing bucket 0, and clients set density to 0 and turn off dispatch, police, trains and boats. Ambient audio is off: ambience, music and radio, the police scanner, distant sirens and music emitters. Everything is switchable in `world.lua`. Scripted peds and vehicles are not affected.

Exports: `GetTime() -> hour, minute, frozen`, `SetTime(hour, minute)`, `FreezeTime(bool)`, `GetWeather() -> name, dynamic`, `SetWeather(name, keepDynamic?)` (stops the cycle unless `keepDynamic`), `SetWeatherDynamic(bool)`, `GetWeatherNames()`.

## Admin (`wasteland_admin`, admin api 0.1)

The panel opens with F10 or `/admin`. Every action goes through one guarded event and is checked against `admin.adminAce` on the server. Changes are written to `wl_admin_log` and the console (teleporting and viewing inventories are not logged).

Actions: teleport to and bring a player, heal, revive, freeze, kick, ban (by player or by license, with a duration or permanent), lift a ban, set survival stats, give items, open a player's inventory (pockets and bag, in the admin's own inventory screen), clear an inventory, announcements, time and weather, noclip and invisibility for the admin.

World tools (10A): `zombieSpawn{count}`, `zombieClear`, `vehicleWreck`, `vehicleWorking`, `vehicleFix{netId}` (the client fills in the vehicle), `refillPumps`, `tpWaypoint`. Debug overlays: `overlay{overlay = zombies|vehicles|camps|loot, enabled}` sends `wasteland:admin:client:overlay(name, on, data)` and the admin's client draws them. Player tools: `spectate{target, enabled}`, `giveCash`/`takeCash{target, count}`, `dropQuest{target, quest}`, `resetCooldowns{target}`, `teachRecipe`/`forgetRecipe{target, recipe}`, `sendToCamp{target}`. The panel data carries `live = { players, uptimeMinutes, zombies = { total, alive }, vehicles = { total, out, pumpsUsed }, loot = { containers, searches } }` and, per player with a character, `cash`, `quests` and `recipes`. Modules that are not running are skipped (their actions answer "... module is not running").

Bans are stored in `wl_bans`, cached in memory and checked when a player connects (players `RegisterAdmissionCheck`).

Exports: `IsAdmin(source)`, `IsBanned(license)`.

New exports used by the panel: players `RegisterAdmissionCheck(name, fn)`. Survival `Heal(source)` and `Revive(source)`. Inventory `OpenForAdmin(admin, target)`, `ClearInventory(source)` and `GetItemList()`.

## Weapons (`wasteland_weapons`, weapons api 0.1)

Weapon, ammo and repair items are defined in `inventory.lua` like every other item; `weapons.lua` says what each weapon item does (`hash`, `ammo`, `wear`, `noise`) and which items repair (`repairItems`). Using a weapon item (hotbar key or Use) holds it; using it again puts it away. Only items the player carries can be held. GTA weapon selection is switched off; the client only has the weapon the server handed it.

Guns take their ammo straight from the inventory (pockets and worn bag). The client reports shots and melee hits once a second; the server removes that many rounds (never more than the player has), wears the weapon (`wear` per shot or hit; durability is the item's `durability`) and sends the new state. A weapon at 0 durability can be held but not used. A repair item restores `percent` of full durability to the weapon in hand. The held weapon is put away when it leaves the player's inventory or the player dies.

Server events: `wasteland:weapons:used(source, item, count, noise, coords)` after every report (zombies listen for noise), `wasteland:weapons:held(source, item)`, `wasteland:weapons:holstered(source)`.

Exports: `GetHeldWeapon(source) -> { uid, item } | nil`, `GetWeaponConfig(item) -> { hash, ammo, wear, noise } | nil`.

New inventory exports: `FindItem(source, uid) -> stack, inventoryId | nil` (only items the player carries), `SetItemMetadata(source, uid, patch) -> ok, err`. New server event: `wasteland:inventory:playerUpdated(source)` after every change to what a player carries or sees.

## Item pictures (`wasteland_images`)

`wasteland_images` holds item pictures (`html/images/<name>.webp`, listed in `html/index.txt`). An item definition may name one with `image = '<name>'`; without it the picture named like the item is used, if there is one; otherwise the screen shows the item's colour. Definitions sent to clients carry `image` as a full NUI URL (or nil), and `GetItemList()` entries include `image` too. Items registered with `RegisterItem` work the same way. The inventory re-sends definitions when `wasteland_images` starts.

## Money (cash item)

Cash is the item named by `cashItem` in `inventory.lua` (default `cash`); there is no bank. Inventory exports: `GetCash(source) -> amount` (pockets and worn bag), `AddCash(source, amount) -> ok, err` (needs room), `RemoveCash(source, amount) -> ok, err` (all or nothing; `false, 'not enough items'` when short). `AddItem`/`RemoveItem`/`GetItemCount` with the cash item work the same. Definitions sent to clients include `cashItem`.

## Zombies (`wasteland_zombies`, zombies api 0.1)

The server keeps a population around living players (`zombies.lua` → `population`), asks each player's client for ground spots in a ring around them (`wasteland:zombies:client:findSpawns`), checks every spot and creates the ped itself (OneSync). A zombie is a networked ped with entity state `wlZombie = { kind = 'walker' | 'runner' }`. The client that owns the ped (OneSync) runs its AI; on ownership change the new owner takes over.

Noise: on `wasteland:weapons:used(source, item, count, noise, coords)` every zombie within `noise` metres gets entity state `wlInvestigate = { x, y, z, untilMs, at }` and its owner walks it there.

Hits: the owning client reports `wasteland:zombies:server:hit(netId, victim)`; the server checks ownership, life, distance and cooldown, then applies `kinds.<kind>` damage/infection/bleeding through survival (`Damage`, `AddInfection`, `AddBleeding`). Deaths: reported by the owner (`...:server:died`, only accepted for a hurt zombie) or seen by the server (health 0); corpses are removed after `corpseSeconds`; `loot` may create a drop with `CreateLootDrop`.

Server events: `wasteland:zombies:died(netId, kind, cause)`, `wasteland:zombies:hit(victim, netId, { damage, infection, bleeding })`.

Exports: `GetZombieCount() -> total, alive`, `SpawnZombie(coords, kind?) -> netId | nil`, `ClearZombies() -> removed`, `SpawnNear(source, n)` (asks that client for spots 15-35 m away). Client export: `GetZombieMode(ped) -> mode | nil`.

Admin command: `/zombies count | clear | spawn <n>` (ACE `wasteland.admin`).

New exports elsewhere: inventory `CreateLootDrop(coords, items, opts) -> dropId | nil, err` (items: list of { name, count }; opts: label, lifetimeMinutes, grid); survival `Damage(source, amount) -> ok`.

## Target (`wasteland_target`, client)

Hold Left Alt to target. Client exports (call from client scripts):

* `AddModel(models, options) -> id` (models: name, hash or a list)
* `AddEntity(entity, options) -> id` (a local entity handle)
* `AddNetId(netId, options) -> id` (a networked entity)
* `AddGlobal(kind, options) -> id` (kind: `'ped'`, `'vehicle'`, `'object'`, `'player'`)
* `AddSphere(coords, radius, options) -> id`, `AddBox(coords, size, heading, options) -> id` (the point looked at must be inside)
* `Remove(id) -> ok`, `IsTargeting() -> boolean`

Options: a list of `{ label, icon?, name?, distance? (2.5), canInteract?(entity, distance, coords), onSelect?(data) | event? | serverEvent?, args? }`. `onSelect` gets `{ entity, netId, coords, distance, model, args, name, zone }`; `event` is triggered on the client with the same table; `serverEvent` is sent to the server with `{ netId, coords, args }` (check everything there). Registrations are removed when the resource that made them stops. The target is off while dead, in a vehicle, in the pause menu or while a screen has focus.

## Loot (`wasteland_loot`, loot api 0.1)

`loot.lua`: `containers` (type → `label`, `table`, `searchSeconds`, `refillMinutes`, `grid`, `anim` = `bin`|`search`|`kneel`, `models`) and `tables` (name → `emptyChance`, `rolls = { min, max }`, `items = { { name, min, max, weight } }`). The container type `body` (no models) is used for dead zombies.

A world container is identified by its type and its position rounded to a metre; it is an inventory stash `loot_<type>_<x>_<y>_<z>` shared by everyone. The client asks to search (`wasteland:loot:server:start(model, coords)` or `...:body(netId)`); the server checks the model, the distance and whether anything is left, times the search, fills the stash when it is new or empty and due for a refill, and opens it (`OpenStash` with `open`). Bodies use the stash `loot_body_<uid>`, deleted when the zombie is removed.

Exports: `RollTable(name) -> list of { name, count } | nil`, `GetLootStats() -> { containers, searches }`, `GetContainerModels() -> { [type] = { label, models } }`. Server event: `wasteland:loot:searched(source, type, stashName)`.

## Camps (`wasteland_camps`, camps api 0.1)

`camps.lua`: `shops` (name → `label`, `items = { { name, buy?, sell?, stock?, restock? } }`; `buy` = the player pays, `sell` = the player is paid, `stock` limits what the trader sells and refills by `restock` every `restockMinutes`), and `camps` (list of `{ id, label, coords, radius, safe = true, blip = { sprite, color }, traders = { { shop, model, coords = { x, y, z, heading } } } }`).

Traders are local peds on each client (created within 80 m) with a "Trade" target. Net events `wasteland:camps:server:open|buy|sell(campId, traderIndex, item?, count?)`; the server checks the distance (`tradeDistance`), stock, cash and inventory room and answers with the screen data. Stock is kept in memory.

Exports (server): `IsInSafeZone(coords) -> boolean`, `GetCampAt(coords) -> { id, label } | nil`, `GetCamps()`. Client export: `IsInSafeZone(coords?)`. Server event: `wasteland:camps:traded(source, 'buy'|'sell', item, count, cash, campId)`.

Zombies use `IsInSafeZone`: no spawning inside, removal inside, no chasing a player inside, no hits on a player inside.

## Crafting (`wasteland_crafting`, crafting api 0.1)

`crafting.lua`: `recipes` (name → `label`, `result = { name, count }`, `ingredients = { { name, count } }`, `seconds`, `blueprint?`). A recipe with a `blueprint` is learned by using that item (registered as usable by this module; it is used up); others are known from the start. Known recipes are character data `crafting = { known = { [recipe] = true } }`.

Net events: `wasteland:crafting:server:open`, `...:craft(recipe)`, `...:finish`, `...:cancel`. The server checks the recipe is known and the materials are carried, times the craft, then removes every ingredient and adds the result (all given back on failure).

Exports: `KnowsRecipe(source, recipe) -> boolean`, `TeachRecipe(source, recipe) -> ok`, `ForgetRecipe(source, recipe) -> ok`, `GetRecipeSummary(source) -> list of { name, label, known, blueprint }`. Server events: `wasteland:crafting:learned(source, recipes)`, `wasteland:crafting:crafted(source, recipe)`. Client event `wasteland:crafting:client:open` opens the screen (the inventory's Crafting button uses it).

## Quests (`wasteland_quests`, quests api 0.1)

`quests.lua`: `maxActive`, `quests` (id → `label`, `description`, `camps?`, `cooldownMinutes`, `objectives`, `rewards = { cash, items }`). Objective types: `bring { item, count }`, `kill { count, near?, label? }`, `visit { coords, radius, label }`, `search { container?, count, near?, label? }`, `craft { recipe, count }`.

Progress comes from `wasteland:zombies:died` (killer), `wasteland:loot:searched`, `wasteland:crafting:crafted`, the server's own position checks (visit, every 2 s) and the live inventory (bring). State is character data `quests = { active = { [id] = { progress } }, done = { [id] = unixTime } }`.

Net events: `wasteland:quests:server:board|accept|abandon|handIn(campId, questId?)`, `...:givers`, `...:tracker`; the player must stand at one of that camp's traders. Hand-in gives the reward first (refused if it does not fit), then takes the items, then pays the cash.

Exports: `GetActiveQuests(source) -> ids`, `AddProgress(source, { type, ... }) -> ok` (custom events from other modules), `GetQuestSummary(source) -> { active = { { id, label, ready, objectives } }, cooldowns = { { id, label, minutes } } }`, `DropQuest(source, id) -> ok`, `ResetCooldowns(source) -> count`. Server event: `wasteland:quests:completed(source, questId)`.

## Vehicles (`wasteland_vehicles`, vehicles api 0.1)

Records in `wl_vehicles` (id, model, position, fuel, engine, body, parts `{"battery","engine","wheels"}`, lock_code, lock_owner, locked). The server creates the entity (`CreateVehicleServerSetter`) when a player is within `spawnDistance` and removes it (saving first) when nobody is within `despawnDistance` for `despawnAfterSeconds`. Entity state `wlVeh = { id, fuel, tank, engine, body, parts, locked, hasLock, seq, acked }`; the owning client applies damage and missing wheels once per `seq` and confirms (`wasteland:vehicles:server:applied`); until then the server does not read damage from the entity.

Actions (`wasteland:vehicles:server:act(netId, action)`, then `...:finish`): battery, engine, wheel, refuel, siphon (hose + a jerry can with room; tank into the can), repair, fitLock, toggleLock, removeLock, trunk (no wait). `removeLock` only for the character that fitted the lock (`lock_owner`; `wlVeh.lockBy`). `pickLock` sends `wasteland:vehicles:client:lockpick({ pins, zone, speed, speedStep })` instead of a progress bar; the client plays the minigame (`html/lockpick.js`) and answers `...:server:lockpick(success)`, accepted once, not faster than `pins * minSecondsPerPin`. Pumps: `...:fillCan(coords)`. Fuel: the driver reports litres (`...:fuel`), accepted only from the driver seat and only going down. A car lock creates a `vehicle_key` item with metadata `{ code }`; the key fits when its code matches. Trunks are stashes `veh_<id>`.

Gas pumps (`pump` in vehicles.lua) have limited, shared fuel keyed by their position (rounded to a metre); a pump is full again `refillMinutes` after fuel was first taken from it. `...:pumpInfo(coords)` answers `wasteland:vehicles:client:pump(key, { litres, max, minutes })` (players within 10 m; the client shows it above the pump). `...:pumpRefuel(netId, pumpCoords)` fills a vehicle parked within `vehicleDistance`; `...:fillCan(pumpCoords)` fills a jerry can; both take only what the pump has.

Exports: `GetVehicleCount()`, `SpawnWreck(coords, model?) -> id`, `SpawnWorking(coords, model?) -> id`, `GetVehicleState(id)`, `GetVehicleStats() -> { total, out, pumpsUsed }`, `FixVehicle(netId) -> ok, err`, `RefillPumps() -> count`, `GetSpawnPoints()`, `GetPumpFuel(coords) -> litres`. Server events: `wasteland:vehicles:action(source, action, id)`, `wasteland:noise(coords, radius)` (lock picking). New inventory export: `FindItems(source, name) -> list of { uid, count, metadata, inventoryId }`.
