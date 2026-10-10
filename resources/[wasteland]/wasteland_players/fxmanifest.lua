fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_players'
author 'Wasteland Core contributors'
description 'Wasteland Core - accounts, sessions and characters with persistence'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_database',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    '@wasteland_database/lib/db.lua',
    'server/state.lua',
    'server/sql.lua',
    'server/characters.lua',
    'server/sessions.lua',
    'server/interface.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}
