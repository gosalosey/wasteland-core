fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_crafting'
author 'Wasteland Core contributors'
description 'Wasteland Core - crafting anywhere: recipes, blueprints, timed crafts'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_players',
    'wasteland_inventory',
}

shared_scripts {
    'shared/recipes.lua',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

files {
    'html/crafting.js',
    'html/progress.js',
}
