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
| 0 | Foundation (resource, registration exports) | - | approved (tested on the server) |
| 1 | Spiked Baseball Bat | `scrap_spiked_bat` | approved (tested on the server) |
| 2 | Pipe Shotgun | `scrap_pipe_shotgun` | approved (tested on the server) |
| 3 | Scrap-Made Axe | `scrap_axe` | **awaiting your test** |
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

## 1. Spiked Baseball Bat

![spiked bat](images/scrapweapons/spiked_bat_view3.jpg)

| | |
|---|---|
| Item | `scrap_spiked_bat` (1 x 4, 0.7 kg, 300 hits durability) |
| Game weapon | `WEAPON_WL_SPIKEDBAT`, model `wl_w_me_spikedbat` |
| Based on | `WEAPON_BAT`: same two-handed swings, blocking, first person |
| Damage | 1.35 x the bat (client `SetWeaponDamageModifier`) |
| Noise | 10 m (zombies) |
| Recipe | Baseball bat + 10 nails + 1 scrap metal + 1 duct tape, 8 s, no blueprint |
| Model | 4,596 triangles, one 1024 texture (embedded), the bat's bones and collision |

Build (needs the game's `w_me_bat.ydr`, exported with CodeWalker, and the
ambientCG textures Wood049 and Rust004):

```
blender -b --python tools/scrapweapons/build_spiked_bat.py -- <tex> <out>
python tools/scrapweapons/dds_mips.py <out>/spiked_bat_d.png <out>/spiked_bat_d.dds
blender -b --python tools/scrapweapons/export_weapon.py -- <w_me_bat.ydr> <out> spiked_bat wl_w_me_spikedbat
python tools/scrapweapons/make_meta.py <game data> WEAPON_BAT WEAPON_WL_SPIKEDBAT wl_w_me_spikedbat WT_WL_SPKBAT <meta out>
```

## 2. Pipe Shotgun

![pipe shotgun](images/scrapweapons/pipe_shotgun_view1.jpg)

| | |
|---|---|
| Item | `scrap_pipe_shotgun` (4 x 2, 1.4 kg, 120 shots durability, wear 2 per shot) |
| Game weapon | `WEAPON_WL_PIPESHOTGUN`, model `wl_w_sg_pipeshotgun` |
| Based on | `WEAPON_DBSHOTGUN` (sawed-off): its handling, damage, sound and break-open reload; clip 1 shell |
| Ammo | `ammo_12g` from the inventory |
| Noise | 180 m (zombies) |
| Recipe | 6 scrap metal + 1 wood planks + 4 nails + 2 duct tape, 12 s, no blueprint |
| Model | 3,484 triangles (v2: long rusty barrel with clamp rings, taped rifle stock, after the first look was rejected); the barrel is on the hinge bone (opens on reload), trigger on the trigger bone |

Build (game files: `w_sg_doublebarrel.ydr`; the DLC data `weapondbshotgun.meta`,
`weaponanimations.meta`, `weaponarchetypes.meta` from mplowrider2, as weapons.meta etc.):

```
blender -b --python tools/scrapweapons/build_pipe_shotgun.py -- <tex> <out>
python tools/scrapweapons/dds_mips.py <out>/pipe_shotgun_d.png <out>/pipe_shotgun_d.dds
blender -b --python tools/scrapweapons/export_weapon.py -- <w_sg_doublebarrel.ydr> <out> pipe_shotgun wl_w_sg_pipeshotgun
python tools/scrapweapons/make_meta.py <dlc data> WEAPON_DBSHOTGUN WEAPON_WL_PIPESHOTGUN wl_w_sg_pipeshotgun WT_WL_PIPESG <meta out> ClipSize=1
```

## 3. Scrap-Made Axe

![scrap axe](images/scrapweapons/scrap_axe_view3.jpg)

| | |
|---|---|
| Item | `scrap_axe` (1 x 3, 0.9 kg, 350 hits durability) |
| Game weapon | `WEAPON_WL_SCRAPAXE`, model `wl_w_me_scrapaxe` |
| Based on | `WEAPON_HATCHET`: same one-handed swings |
| Damage | 1.2 x the hatchet |
| Recipe | 4 scrap metal + 1 log + 2 nails + 1 rag + 1 duct tape, 10 s |
| Model | 2,952 triangles |

Build: `build_scrap_axe.py`, then `export_weapon.py -- <w_me_hatchet.ydr> <out> scrap_axe wl_w_me_scrapaxe`,
`make_meta.py <spupgrade data> WEAPON_HATCHET WEAPON_WL_SCRAPAXE wl_w_me_scrapaxe WT_WL_SCRAPAXE <meta>`
(game data: weaponhatchet.meta as weapons.meta, and the spupgrade weaponanimations / weaponarchetypes).

## Licensing

* Models: made for this project in Blender. Each keeps the skeleton (bone
  names and positions) and the simple collision box of the game weapon it is
  based on, which the game needs to hold it; no game mesh or texture is used.
* Textures: ambientCG (CC0).
* Weapon data (`meta/`): the game's own values for the base weapon, renamed;
  standard for any add-on weapon.
* Game files (the original models and data) are never committed; they are
  read from your own GTA V install with CodeWalker.
