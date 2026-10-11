fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_world'
author 'Wasteland Core contributors'
description 'Wasteland Core - game clock and weather, empty world (no ambient NPCs or traffic), ambient audio off'
version '0.1.0'

dependency 'wasteland_core'

shared_scripts {
    'shared/clock.lua',
    'shared/emitters.lua',
}

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}
