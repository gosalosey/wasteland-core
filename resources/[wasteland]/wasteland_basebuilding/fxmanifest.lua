fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_basebuilding'
author 'Wasteland Core contributors'
description 'Wasteland Core - base building (tool cupboards, snapping pieces, doors, storage, upkeep, raids). Ported from sbb-basebuilding.'
version '1.0.0'

-- The building props come from the "sinor-buildingProps-v2" asset pack,
-- which is NOT part of Wasteland Core (a licensed pack tied to the Cfx
-- account that owns it). Install it on the server and ensure it before this.
dependencies {
    'wasteland_core',
    'wasteland_database',
    'wasteland_players',
    'wasteland_inventory',
    'wasteland_ui',
}

shared_scripts {
    'shared/rules.lua',
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
    'html/build.js',
    'html/lockpick.js',
}
