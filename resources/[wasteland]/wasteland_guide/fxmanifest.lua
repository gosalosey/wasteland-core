fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_guide'
author 'Wasteland Core contributors'
description "Wasteland Core - survivor's guide: milestones, stats, what to try next, how-to pages (F2)"
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_players',
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
    'html/guide.js',
}
