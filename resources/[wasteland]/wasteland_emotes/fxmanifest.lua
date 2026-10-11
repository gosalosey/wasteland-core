fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_emotes'
author 'Wasteland Core contributors'
description 'Wasteland Core - emotes (F4 menu, /e name, /e c) and hands up (X)'
version '0.1.0'

dependencies {
    'wasteland_ui',
}

shared_scripts {
    'shared/emotes.lua',
}

client_scripts {
    'client/main.lua',
}

files {
    'html/emotes.js',
}
