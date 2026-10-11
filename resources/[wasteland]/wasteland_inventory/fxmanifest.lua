fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_inventory'
author 'Wasteland Core contributors'
description 'Wasteland Core - grid inventories, equipment, hotbar, drops and stashes'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_database',
    'wasteland_players',
    'wasteland_ui',
}

shared_scripts {
    'shared/items.lua',
    'shared/grid.lua',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    '@wasteland_database/lib/db.lua',
    'server/sql.lua',
    'server/store.lua',
    'server/inventory.lua',
    'server/sync.lua',
    'server/drops.lua',
    'server/clothing.lua',
    'server/interface.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

-- Inventory screen, loaded by wasteland_ui.
files {
    'html/inventory.js',
}
