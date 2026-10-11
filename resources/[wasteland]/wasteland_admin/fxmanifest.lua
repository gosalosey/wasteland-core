fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_admin'
author 'Wasteland Core contributors'
description 'Wasteland Core - admin panel: players, items, bans, server and world tools, action log'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_database',
    'wasteland_players',
    'wasteland_ui',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    '@wasteland_database/lib/db.lua',
    'server/sql.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

-- Panel and announcement screens, loaded by wasteland_ui.
files {
    'html/admin.js',
    'html/announce.js',
}
