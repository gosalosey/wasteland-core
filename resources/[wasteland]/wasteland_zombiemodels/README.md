# wasteland_zombiemodels: your own zombie models

1. **Get the models.** Ped models for FiveM come as files named after the model
   (`.ydd`, `.yft`, `.ytd`, and for add-on peds a `.ymt` and a `peds.meta` entry).
   Only use models you are allowed to use.
2. **Put the files in `stream/`** (sub-folders are fine).
3. **Add-on peds** (a new name, not replacing a GTA ped): copy their
   `<Item type="CPedModelInfo__InitData">` entries from the `peds.meta` that came
   with them into this resource's `peds.meta`, between `<InitDatas>` and `</InitDatas>`.
4. **Use them** in `wasteland_config/config/zombies.lua`:
   * every zombie: add the names to `models = { ... }`
   * one kind only: give the kind its own list, for example
     ```lua
     brute = { speed = 1.3, chance = 5, damage = { 15, 22 }, models = { 'my_zombie' } },
     ```
5. **Restart the server** (players download the new files when they join).

If a model is missing or misspelled, players' games report it and the server
stops using that model (the console says
`zombie model "..." is not in the game of player ...`); the other models keep
working, and GTA's own zombie (`u_m_y_zombie_01`) is always there as a fallback.

`server.cfg` needs `ensure wasteland_zombiemodels` (any place before players join).
