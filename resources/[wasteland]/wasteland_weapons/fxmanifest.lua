fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_weapons'
author 'Wasteland Core contributors'
description 'Wasteland Core - weapon items: hold, ammo from the inventory, durability, repairs'
version '0.1.0'

dependencies {
    'wasteland_core',
    'wasteland_players',
    'wasteland_inventory',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}
