fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_vehicles'
author 'Wasteland Core contributors'
description 'Wasteland Core - persistent vehicles: wrecks to repair, fuel, parts, trunks, locks and keys'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_database',
    'wasteland_players',
    'wasteland_inventory',
}

shared_scripts {
    'shared/rules.lua',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    '@wasteland_database/lib/db.lua',
    'server/sql.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

files {
    'html/progress.js',
    'html/lockpick.js',
    'html/hud.js',
}
