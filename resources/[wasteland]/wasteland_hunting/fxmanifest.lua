fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_hunting'
author 'Wasteland Core contributors'
description 'Wasteland Core - animals, harvesting, campfires and cooking'
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
    'html/cook.js',
    'html/progress.js',
}
