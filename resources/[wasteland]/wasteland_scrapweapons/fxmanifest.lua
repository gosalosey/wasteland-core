fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_scrapweapons'
author 'Wasteland Core contributors'
description 'Wasteland Core - home-made scrap weapons (addon weapons with their own models)'
version '0.2.0'

-- Only needs the core to log; it registers its items, weapons and recipes
-- with wasteland_inventory, wasteland_weapons and wasteland_crafting
-- whenever those are running (in any start order).
dependencies {
    'wasteland_core',
}

shared_scripts {
    'shared/catalog.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

-- Models are in stream/ (streamed automatically). Each weapon has three data
-- files, made by tools/scrapweapons/make_meta.py from the game weapon it is
-- based on.
files {
    'meta/weapon_wl_spikedbat_weaponarchetypes.meta',
    'meta/weapon_wl_spikedbat_weaponanimations.meta',
    'meta/weapon_wl_spikedbat_weapons.meta',
    'meta/weapon_wl_pipeshotgun_weaponarchetypes.meta',
    'meta/weapon_wl_pipeshotgun_weaponanimations.meta',
    'meta/weapon_wl_pipeshotgun_weapons.meta',
    'meta/weapon_wl_scrapaxe_weaponarchetypes.meta',
    'meta/weapon_wl_scrapaxe_weaponanimations.meta',
    'meta/weapon_wl_scrapaxe_weapons.meta',
    'meta/weapon_wl_scrappump_weaponarchetypes.meta',
    'meta/weapon_wl_scrappump_weaponanimations.meta',
    'meta/weapon_wl_scrappump_weapons.meta',
    'meta/weapon_wl_scrapbolt_weaponarchetypes.meta',
    'meta/weapon_wl_scrapbolt_weaponanimations.meta',
    'meta/weapon_wl_scrapbolt_weapons.meta',
    'meta/weapon_wl_pipeclub_weaponarchetypes.meta',
    'meta/weapon_wl_pipeclub_weaponanimations.meta',
    'meta/weapon_wl_pipeclub_weapons.meta',
    'meta/weapon_wl_scrapmachete_weaponarchetypes.meta',
    'meta/weapon_wl_scrapmachete_weaponanimations.meta',
    'meta/weapon_wl_scrapmachete_weapons.meta',
    'meta/weapon_wl_scraplever_weaponarchetypes.meta',
    'meta/weapon_wl_scraplever_weaponanimations.meta',
    'meta/weapon_wl_scraplever_weapons.meta',
}

-- Spiked baseball bat (based on WEAPON_BAT)
data_file 'WEAPON_METADATA_FILE' 'meta/weapon_wl_spikedbat_weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'meta/weapon_wl_spikedbat_weaponanimations.meta'
data_file 'WEAPONINFO_FILE' 'meta/weapon_wl_spikedbat_weapons.meta'

-- Pipe shotgun (based on WEAPON_DBSHOTGUN, the sawed-off; ClipSize 1)
data_file 'WEAPON_METADATA_FILE' 'meta/weapon_wl_pipeshotgun_weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'meta/weapon_wl_pipeshotgun_weaponanimations.meta'
data_file 'WEAPONINFO_FILE' 'meta/weapon_wl_pipeshotgun_weapons.meta'

-- Scrap-made axe (based on WEAPON_HATCHET)
data_file 'WEAPON_METADATA_FILE' 'meta/weapon_wl_scrapaxe_weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'meta/weapon_wl_scrapaxe_weaponanimations.meta'
data_file 'WEAPONINFO_FILE' 'meta/weapon_wl_scrapaxe_weapons.meta'

-- Scrap pump shotgun (based on WEAPON_PUMPSHOTGUN; ClipSize 4)
data_file 'WEAPON_METADATA_FILE' 'meta/weapon_wl_scrappump_weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'meta/weapon_wl_scrappump_weaponanimations.meta'
data_file 'WEAPONINFO_FILE' 'meta/weapon_wl_scrappump_weapons.meta'

-- Scrap bolt rifle (based on WEAPON_PRECISIONRIFLE, needs game build 2699+; ClipSize 5)
data_file 'WEAPON_METADATA_FILE' 'meta/weapon_wl_scrapbolt_weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'meta/weapon_wl_scrapbolt_weaponanimations.meta'
data_file 'WEAPONINFO_FILE' 'meta/weapon_wl_scrapbolt_weapons.meta'

-- Pipe club (based on WEAPON_CROWBAR)
data_file 'WEAPON_METADATA_FILE' 'meta/weapon_wl_pipeclub_weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'meta/weapon_wl_pipeclub_weaponanimations.meta'
data_file 'WEAPONINFO_FILE' 'meta/weapon_wl_pipeclub_weapons.meta'

-- Scrap machete (based on WEAPON_MACHETE)
data_file 'WEAPON_METADATA_FILE' 'meta/weapon_wl_scrapmachete_weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'meta/weapon_wl_scrapmachete_weaponanimations.meta'
data_file 'WEAPONINFO_FILE' 'meta/weapon_wl_scrapmachete_weapons.meta'

-- Scrap lever rifle (based on WEAPON_PRECISIONRIFLE; ClipSize 7, Damage 65, TimeBetweenShots 1.0)
data_file 'WEAPON_METADATA_FILE' 'meta/weapon_wl_scraplever_weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'meta/weapon_wl_scraplever_weaponanimations.meta'
data_file 'WEAPONINFO_FILE' 'meta/weapon_wl_scraplever_weapons.meta'
