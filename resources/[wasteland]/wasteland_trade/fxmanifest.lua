fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_trade'
author 'Wasteland Core contributors'
description 'Wasteland Core - player to player trading'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_players',
    'wasteland_inventory',
    'wasteland_ui',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

files {
    'html/trade.js',
}
