fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_database'
author 'Wasteland Core contributors'
description 'Wasteland Core - database adapter, health checks and migrations'
version '0.1.0'

-- The driver resource (oxmysql) is deliberately NOT a `dependency`: if it is
-- missing or cannot connect, the module reports a precise reason instead of
-- FiveM refusing to start the resource. Start it before this resource.
dependency 'wasteland_core'

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/sql.lua',
    'server/driver_oxmysql.lua',
    'server/requests.lua',
    'server/migrations.lua',
    'server/main.lua',
}

-- Library for module resources:  server_script '@wasteland_database/lib/db.lua'
files {
    'lib/db.lua',
}
