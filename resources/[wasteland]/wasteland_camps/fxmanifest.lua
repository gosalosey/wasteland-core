fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_camps'
author 'Wasteland Core contributors'
description 'Wasteland Core - camps: safe zones, map blips, traders (cash, limited stock)'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_players',
    'wasteland_inventory',
}

shared_scripts {
    'shared/zones.lua',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

files {
    'html/trader.js',
}
