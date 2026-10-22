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
    'shared/ai.lua',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
    'server/ai.lua',
    'server/hordes.lua',
}

client_scripts {
    'client/main.lua',
    'client/ai.lua',
    'client/sounds.lua',
    'client/noise.lua',
}

-- Zombie sounds: a hidden page plays the files of the sound pack resource.
ui_page 'html/sounds.html'

files {
    'html/sounds.html',
    'html/noise.js',
}
