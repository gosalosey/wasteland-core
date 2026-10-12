fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_events'
author 'Wasteland Core contributors'
description 'Wasteland Core - world events: helicopter crashes, ambushed convoys, bandit hideouts, hordes'
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
