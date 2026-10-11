fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_tailor'
author 'Wasteland Core contributors'
description 'Wasteland Core - tailors: restyle the clothes you wear for cash'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_players',
    'wasteland_inventory',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

files {
    'html/tailor.js',
}
