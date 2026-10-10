fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_config'
description 'Wasteland Core - server owner configuration (edit files in config/)'
version '0.1.0'

-- This resource contains no scripts. wasteland_core reads config/*.lua with
-- LoadResourceFile. Keeping configuration in its own resource means framework
-- updates never overwrite your settings.
-- Config files are server-only: they are NOT listed under `files`, so they are
-- never sent to clients.
