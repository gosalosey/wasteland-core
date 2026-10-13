fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_core'
author 'Wasteland Core contributors'
description 'Wasteland Core - framework kernel: module registry, configuration, lifecycle, logging'
version '0.2.0'

-- Shared code (loaded on server and client, order matters)
shared_scripts {
    'shared/util.lua',
    'shared/semver.lua',
    'shared/schema.lua',
    'shared/logger.lua',
}

server_scripts {
    'server/config_loader.lua',
    'server/registry.lua',
    'server/lifecycle.lua',
    'server/security.lua',
    'server/commands.lua',
    'server/exports.lua',
    'server/updates.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

-- The SDK is included by module resources with
--   server_script '@wasteland_core/sdk/module.lua'
-- It is also listed under `files` so future client-side modules can include it.
files {
    'sdk/module.lua',
}

dependency 'wasteland_config'
