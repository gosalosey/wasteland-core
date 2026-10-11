fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_target'
author 'Wasteland Core contributors'
description 'Wasteland Core - target system: hold Left Alt, look at something, choose what to do'
version '0.1.0'

-- Client-only: no module, nothing stored. Uses wasteland_ui for the eye
-- and the option list.
dependencies {
    'wasteland_ui',
}

shared_scripts {
    'shared/match.lua',
}

client_scripts {
    'client/main.lua',
}

files {
    'html/target.js',
}
