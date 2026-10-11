fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_appearance'
author 'Wasteland Core contributors'
description 'Wasteland Core - character creator: face, hair, overlays and starter clothing'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_players',
    'wasteland_ui',
}

shared_scripts {
    'shared/defs.lua',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

-- Creator screen, loaded by wasteland_ui.
files {
    'html/creator.js',
}
