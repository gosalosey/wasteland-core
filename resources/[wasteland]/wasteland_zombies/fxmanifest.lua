fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_zombies'
author 'Wasteland Core contributors'
description 'Wasteland Core - zombies: population around players, AI, hits, noise, loot'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_players',
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
