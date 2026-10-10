fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_template'
description 'Wasteland Core - module template. Copy this resource to start a new module.'
version '1.0.0'

dependency 'wasteland_core'

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}
