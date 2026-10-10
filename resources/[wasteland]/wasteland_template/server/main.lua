-- wasteland_template :: server/main.lua
-- A minimal, complete module. Copy the resource, rename it, change `name`,
-- and replace the body of onInit/onShutdown.

local heartbeatToken = nil

local M = Wasteland.DefineModule({
    name = 'template',
    version = '1.0.0',
    description = 'Example module demonstrating the module SDK',
    core = '^1.0.0',
    dependencies = {},

    -- Config file: wasteland_config/config/template.lua (optional; defaults apply)
    config = {
        file = 'template.lua',
        optional = true,
        schema = {
            type = 'table',
            fields = {
                greeting = { type = 'string', default = 'Template module is running', maxLength = 200 },
                heartbeatSeconds = { type = 'integer', default = 60, min = 0, max = 3600 },
            },
        },
    },

    onInit = function(M, ctx)
        M.log:info('%s (framework %s v%s)', M.config.greeting, ctx.framework.name, ctx.framework.version)
        if M.config.heartbeatSeconds > 0 then
            local token = {}
            heartbeatToken = token
            Citizen.CreateThread(function()
                while heartbeatToken == token do
                    Citizen.Wait(M.config.heartbeatSeconds * 1000)
                    if heartbeatToken == token then M.log:debug('heartbeat') end
                end
            end)
        end
        return true
    end,

    onShutdown = function(M, reason)
        heartbeatToken = nil -- stops the heartbeat thread
        M.log:info('template module stopped (%s)', reason)
    end,
})
