fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_skills'
author 'Wasteland Core contributors'
description 'Wasteland Core - skills: scavenging, crafting, medicine, hunting, fitness, combat (level up by doing)'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_players',
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
    'html/skills.js',
}
