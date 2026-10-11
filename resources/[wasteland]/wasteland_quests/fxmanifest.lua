fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_quests'
author 'Wasteland Core contributors'
description 'Wasteland Core - jobs from camp traders: bring, kill, visit, search, craft; repeatable with cooldowns'
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
    'html/board.js',
    'html/tracker.js',
}
