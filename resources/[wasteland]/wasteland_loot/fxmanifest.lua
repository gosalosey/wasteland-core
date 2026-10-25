fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_loot'
author 'Wasteland Core contributors'
description 'Wasteland Core - looting: searchable world props and zombie bodies, loot tables, refills'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_players',
    'wasteland_inventory',
}

shared_scripts {
    'shared/rules.lua',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

files {
    'html/progress.js',
    'html/gather.js',
}
