-- wasteland_supplydrops: the SDK example module (docs/SDK_GUIDE.md walks
-- through it). A real feature too: supply crates come down now and then.
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_supplydrops'
author 'Wasteland Core contributors'
description 'Wasteland Core - supply drops (the SDK example module)'
version '1.0.0'

-- Resources that must be started first (the module's own dependencies are
-- declared again, with versions, in DefineModule).
dependencies {
    'wasteland_core',
    'wasteland_database',
    'wasteland_players',
    'wasteland_inventory',
}

-- Loaded on server and client: pure rules with no game calls (unit-tested).
shared_scripts {
    'shared/rules.lua',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',      -- Wasteland.DefineModule
    '@wasteland_database/lib/db.lua',       -- WDB.query / insert / migrate ...
    'server/sql.lua',                       -- the table and statements
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}
