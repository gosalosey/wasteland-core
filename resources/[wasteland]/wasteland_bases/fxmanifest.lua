fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_bases'
author 'Wasteland Core contributors'
description 'Wasteland Core - base building: claim with a flag, walls, doors, gates, storage, upkeep'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_database',
    'wasteland_players',
    'wasteland_inventory',
    'wasteland_ui',
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
    'html/base.js',
}
