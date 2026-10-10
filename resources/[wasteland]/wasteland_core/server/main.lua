-- Wasteland Core :: server/main.lua
-- Entry point: boots the framework when the resource starts and wires
-- platform events to the lifecycle.

local Lifecycle = WL.Lifecycle
local Registry = WL.Registry
local Commands = WL.Commands
local RESOURCE = GetCurrentResourceName()

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == RESOURCE then
        Lifecycle.shutdown('core_stopped')
    else
        Registry.onResourceStop(resourceName)
    end
end)

-- txAdmin announces scheduled restarts / shutdowns with this event.
AddEventHandler('txAdmin:events:serverShuttingDown', function()
    local cfg = Lifecycle.coreConfig
    if cfg == nil or cfg.framework.shutdownOnTxAdminRestart then
        Lifecycle.shutdown('server_shutdown')
    end
end)

Lifecycle.boot()
Commands.register(Lifecycle.getInfo().shortName)
