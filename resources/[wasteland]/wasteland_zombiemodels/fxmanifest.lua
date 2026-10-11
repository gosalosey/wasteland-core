-- wasteland_zombiemodels: your own zombie models.
-- Put the model files in stream/ and, for add-on peds, their entries in
-- peds.meta. Then name the models in wasteland_config/config/zombies.lua
-- (`models`, or a kind's `models`). See README.md.
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_zombiemodels'
author 'Wasteland Core contributors'
description 'Wasteland Core - custom zombie models (streamed)'
version '1.0.0'

files {
    'peds.meta',
}

-- Add-on peds need their model info (peds.meta). Replacements of GTA peds
-- do not, but an empty list here does no harm.
data_file 'PED_METADATA_FILE' 'peds.meta'
