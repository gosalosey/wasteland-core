fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_props'
author 'Wasteland Core contributors'
description 'Wasteland Core - prop placer: admins place, move and delete saved props anywhere (/propplacer)'
version '1.0.0'

dependencies {
    'wasteland_core',
    'wasteland_database',
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

files {
    'html/props.js',
}
