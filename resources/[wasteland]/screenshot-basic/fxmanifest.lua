-- screenshot-basic by The CitizenFX Developers (MIT, see LICENSE),
-- https://github.com/citizenfx/screenshot-basic (commit 5e89d4a), shipped
-- already built (dist/) so the server does not need its yarn / webpack
-- builders. Wasteland uses it for the HUD's picture of your character.
fx_version 'bodacious'
game 'common'

client_script 'dist/client.js'
server_script 'dist/server.js'

files {
    'dist/ui.html'
}

ui_page 'dist/ui.html'
