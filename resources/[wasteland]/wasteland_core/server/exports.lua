-- Wasteland Core :: server/exports.lua
-- Public, versioned server API (core api 1.x). Everything another resource
-- may rely on is listed here and documented in docs/MODULE_API.md.
-- Values returned are copies; callers cannot mutate core state.

local Registry = WL.Registry
local Lifecycle = WL.Lifecycle
local Logger = WL.Logger
local Util = WL.Util

local function caller()
    return GetInvokingResource() or GetCurrentResourceName()
end

--- RegisterModule(definition) -> ok, err
exports('RegisterModule', function(def)
    local res = caller()
    if type(def) == 'table' then def.resource = res end
    return Registry.register(def, res)
end)

--- ReportModuleReady(name) -> ok, err   (async modules only)
exports('ReportModuleReady', function(name)
    return Registry.reportReady(name, caller())
end)

--- ReportModuleFailed(name, reason) -> ok, err
exports('ReportModuleFailed', function(name, reason)
    return Registry.reportFailed(name, reason, caller())
end)

--- ReportModuleHealth(name, status, detail) -> ok, err   (api 1.1)
--- status: 'ok' | 'degraded'. Only the owning resource.
exports('ReportModuleHealth', function(name, status, detail)
    return Registry.reportHealth(name, status, detail, caller())
end)

--- GetModuleStatus(name) -> status table | nil
exports('GetModuleStatus', function(name)
    return Registry.getStatus(name)
end)

--- GetModuleStatuses() -> array of status tables sorted by name
exports('GetModuleStatuses', function()
    return Registry.list()
end)

--- IsModuleRunning(name) -> boolean
exports('IsModuleRunning', function(name)
    return Registry.isRunning(name)
end)

--- GetModuleConfig(name) -> validated config copy | nil
exports('GetModuleConfig', function(name)
    local mod = Registry.get(name)
    if not mod or mod.config == nil then return nil end
    return Util.deepCopy(mod.config)
end)

--- GetFrameworkInfo() -> { name, shortName, version, api, state, resource, configResource }
exports('GetFrameworkInfo', function()
    return Lifecycle.getInfo()
end)

--- IsReady() -> boolean  (startup window finished)
exports('IsReady', function()
    return Lifecycle.state == 'ready'
end)

--- Log(module, level, message) — central logging for module resources.
exports('Log', function(module, level, message)
    if type(module) ~= 'string' or type(message) ~= 'string' then return false end
    if not Logger.LEVELS[level] or level == 'off' then level = 'info' end
    Logger.write(module, level, message, caller())
    return true
end)

--- GetRecentIssues(limit) -> recent warnings/errors (oldest first)
exports('GetRecentIssues', function(limit)
    return Logger.getRecent(tonumber(limit))
end)
