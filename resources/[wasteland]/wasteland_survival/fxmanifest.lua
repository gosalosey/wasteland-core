fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_survival'
author 'Wasteland Core contributors'
description 'Wasteland Core - hunger, thirst, bleeding, infection, temperature, death, respawn and HUD'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_players',
    'wasteland_ui',
}

shared_scripts {
    'shared/model.lua',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}

client_scripts {
    'client/portrait.lua',   -- the HUD picture of your character (screenshot-basic)
    'client/main.lua',
}

-- HUD and death screens, loaded by wasteland_ui.
files {
    'html/hud.js',
    'html/death.js',
}
