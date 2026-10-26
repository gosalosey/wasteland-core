fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_story'
author 'Wasteland Core contributors'
description 'Wasteland Core - story quest chain: characters, dialogue with choices, steps, endings, a journal'
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
    'html/dialogue.js',
    'html/note.js',
    'html/journal.js',
    'html/tracker.js',
    'html/banner.js',
}
