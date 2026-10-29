fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_survivors'
author 'Wasteland Core contributors'
description 'Wasteland Core - survivors: friendly people who fight zombies, reward help, trade, fight back'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_players',
    'wasteland_inventory',
    'wasteland_ui',
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
    'html/barter.js',
}
