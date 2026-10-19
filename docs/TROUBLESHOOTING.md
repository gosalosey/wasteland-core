# Troubleshooting

Start with the **server console**. After startup it prints a table of every Wasteland module; each should say **running**. Type `wasteland status` to see it again. A module that says something else gives the reason on the same line.

Players can press **F8** in game to see their own console. Lines starting with `[wasteland]` explain what went wrong on their side.

## The server

**A module is not running / "config_error".**
A settings file has a mistake. The console names the file, the setting and what it expected. Fix that line, or compare with the `.lua.new` copy the updater saved, then restart.

**"Database is down" / modules waiting.**
Check the database is running and the `mysql_connection_string` in `server.cfg` is right (user, password, database name). Wasteland makes its own tables; it doesn't need anything imported.

**Players can't connect / "Connection failed".**
* Open port **30120** (TCP and UDP) in Windows Firewall and forward it on your router to the server PC.
* Two servers on one PC need different ports: change `endpoint_add_tcp` / `endpoint_add_udp` in the second server's `server.cfg` (for example 30121) and open that too. txAdmin's own web port (40120) must be different for each server too.

**The update notice says there's a newer version.**
Stop the server, run `update_wasteland.bat`, start the server.

## Joining and spawning

**Stuck on the loading screen at "Awaiting scripts", or the world looks hazy and unfinished.**
Make sure `wasteland_players` is up to date: Wasteland does the first spawn itself and closes the loading screen. Old versions blocked the base server's spawn without doing that. Restart the server after updating.

**Spawned somewhere random, in the air, or in the ground.**
Update `wasteland_players`. The current version loads the world at your last position first, puts your feet on the ground, and sends you to a safe camp if that fails. Players can always use `/stuck`.

**The character creator or select screen doesn't show.**
`wasteland_ui` must be started. As a fallback, players can type `/character` in chat.

## Zombies

**No zombies.**
Check `wasteland_zombies` is running. Zombies never spawn in camps or near a fresh tool cupboard, and `zombies.lua` → `population.perPlayer` must be above 0. Admins: `/zombies spawn 5`.

**Zombies don't make sounds.**
`wasteland_zombiesounds` must be started (`ensure wasteland_zombiesounds` in `server.cfg`) and `zombies.lua` → `sounds.enabled = true`.

**Zombies act oddly after an update.**
`zombies.lua` → `ai = { enabled = false }` puts every zombie back to the original simple behaviour, so you can tell whether the new AI is the cause.

**Kills don't count (guide, skills, jobs).**
Update `wasteland_zombies`; older versions threw away kill reports. Kills made before the fix can't be counted back.

## Base building

**Pieces are invisible, or "model ... is not in the game: is the props pack running?" in F8.**
* For the normal building pieces: install the **sinor-buildingProps-v2** pack (paid, from the [SinorSystem Tebex store](https://sinorsystem.tebex.io/)), keep its folder name exactly like that, and put `ensure sinor-buildingProps-v2` before `ensure wasteland_basebuilding`. It only works on a server whose licence key belongs to the account that owns the pack. Using your own props instead? Check `propsResource` and every piece's `model` in `basebuilding.lua` ([docs/INSTALL.md](INSTALL.md#using-your-own-building-props-instead-of-the-paid-pack)).
* For a defence piece: its GTA model can't be spawned. Change its `model` in `basebuilding.lua`. Only models whose names start with `prop_` or `p_` can reliably be placed.

**"Place a Tool Cupboard first".**
Storage always needs a cupboard. Walls, doors and defences can go up without one (they last 12 hours), unless `freeBuild.enabled = false`.

## Items and inventory

**An item has no picture.**
Set `image = 'name'` on the item in `inventory.lua` to a picture that exists in `wasteland_images/html/images`, or add your own PNG to `tools/images` and run `python tools/import_images.py --custom-only`.

**A new item is missing from the admin panel.**
Restart `wasteland_inventory` (and the admin panel) after adding items to `inventory.lua`.

## Still stuck?

Note what you did, what you expected and what happened, plus any red lines from the server console or F8, and open an issue on GitHub.
