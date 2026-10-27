fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_scrapweapons'
author 'Wasteland Core contributors'
description 'Wasteland Core - home-made scrap weapons (addon weapons with their own models)'
version '0.1.0'

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

-- Models (stream/) and weapon data (meta/) are added one weapon at a time.
-- Each weapon adds its meta files here, e.g.:
--   files { 'meta/weapon_wl_pipeshotgun.meta', ... }
--   data_file 'WEAPONINFO_FILE' 'meta/weapon_wl_pipeshotgun.meta'
