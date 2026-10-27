# Scrap weapons (wasteland_scrapweapons)

Home-made weapons with their own models, added **one weapon at a time**. Each
one is tested in-game and approved before the next is started.

## How it fits in

The resource only brings the weapons; everything else is the framework's:

| What | Who does it |
|---|---|
| Model (`stream/*.ydr`, `*.ytd`) and weapon data (`meta/*.meta`) | `wasteland_scrapweapons` |
| The item (size, weight, durability, icon) | registered with `wasteland_inventory` (`RegisterItem`) |
| Holding, ammo from the inventory, wear, repairs, zombie noise | registered with `wasteland_weapons` (`RegisterWeapon`) |
| Recipe | registered with `wasteland_crafting` (`RegisterRecipe`) |
| Saving, dropping, trading, death drops | the inventory, like any item |
| Icon pictures | `wasteland_images/html/images/<item>.webp` (+ `index.txt`) |

Nothing is added to your config files, so updates never need merging. A
weapon or recipe of the same name in `weapons.lua` / `crafting.lua` wins over
the one registered here.

Item names start with `scrap_`; weapon names with `WEAPON_WL_`.

## Limits of the game (no custom animation files)

* Animations are GTA's own: each weapon borrows those of a GTA weapon.
  Pump shotgun: real pump. Double-barrel: real break-open reload. Bolt and
  lever rifles: rifle handling; the cycle between shots is fire rate + sound,
  the hands do not work a bolt or lever. The maul swings like the bat.
* Sounds are GTA's own sound sets for now (custom audio is a later step).
* Concept art and icons are renders of the actual model.

## Status

| # | Weapon | Item | Status |
|---|---|---|---|
| 0 | Foundation (resource, registration exports) | - | awaiting your test |
| 1 | Spiked Baseball Bat | `scrap_spiked_bat` | not started |
| 2 | Pipe Shotgun | `scrap_pipe_shotgun` | not started |
| 3 | Scrap-Made Axe | `scrap_axe` | not started |
| 4 | Scrap Pump Shotgun | `scrap_pump_shotgun` | not started |
| 5 | Scrap Bolt Rifle | `scrap_bolt_rifle` | not started |
| 6 | Pipe Club | `scrap_pipe_club` | not started |
| 7 | Scrap Machete | `scrap_machete` | not started |
| 8 | Scrap Lever Rifle | `scrap_lever_rifle` | not started |
| 9 | Heavy Scrap Maul | `scrap_maul` | not started |
| 10 | Improvised Double-Barrel | `scrap_double_barrel` | not started |

Order note: the Spiked Bat is first because a melee weapon has no muzzle,
ammo or reload, so it proves the whole addon-weapon chain with the fewest
moving parts.
