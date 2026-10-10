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
        local owned = Registry.onResourceStop(resourceName)
        if owned > 0 then Lifecycle.rememberDependents(resourceName) end
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE and Lifecycle.dependentsToRestart[resourceName] then
        -- Let the restarted resource finish starting first.
        Citizen.CreateThread(function()
            Citizen.Wait(0)
            Lifecycle.restartDependents(resourceName)
        end)
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
