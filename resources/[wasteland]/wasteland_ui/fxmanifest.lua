fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_ui'
author 'Wasteland Core contributors'
description 'Wasteland Core - NUI shell, design system and screen manager'
version '0.1.0'

dependency 'wasteland_core'

server_scripts {
    '@wasteland_core/sdk/module.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/shell.js',
}
