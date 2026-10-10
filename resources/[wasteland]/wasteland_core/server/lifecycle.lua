-- Wasteland Core :: server/lifecycle.lua
-- Framework startup, readiness reporting and ordered shutdown.
--
-- Framework states:
--   booting        core loaded, waiting for modules within the startup window
--   config_error   core configuration invalid; no module will be initialised
--   ready          startup window finished (modules may still register later)
--   shutting_down  ordered shutdown in progress
--   stopped        everything has been shut down

WL = WL or {}
WL.Lifecycle = WL.Lifecycle or {}
local Lifecycle = WL.Lifecycle
local Registry = WL.Registry
local Config = WL.Config
local Util = WL.Util
local log = WL.Logger.new('core')

WL.API_VERSION = '1.1.0'

Lifecycle.state = Lifecycle.state or 'booting'
Lifecycle.coreConfig = Lifecycle.coreConfig or nil
Lifecycle.lastConfigReport = Lifecycle.lastConfigReport or nil

local function setFrameworkState(state)
    local prev = Lifecycle.state
    Lifecycle.state = state
    if prev ~= state then
        log:debug('framework state %s -> %s', tostring(prev), state)
        TriggerEvent('wasteland:core:frameworkState', state, prev)
    end
end

function Lifecycle.getInfo()
    local fw = Lifecycle.coreConfig and Lifecycle.coreConfig.framework or {}
    return {
        name = fw.name or 'Wasteland Core',
        shortName = fw.shortName or 'wasteland',
        version = Lifecycle.version or '0.0.0',
        api = WL.API_VERSION,
        state = Lifecycle.state,
        resource = GetCurrentResourceName(),
        configResource = Config.getConfigResource(),
    }
end

local function printReport(result)
    for _, key in ipairs({ 'logging', 'framework', 'modules' }) do
        local report = result.reports[key]
        if report then
            for _, w in ipairs(report.warnings) do log:warn(w) end
            for _, e in ipairs(report.errors) do log:error(e) end
        end
    end
end

-- Apply a successfully loaded core config.
local function applyCoreConfig(configs)
    Lifecycle.coreConfig = configs
    WL.Logger.configure({
        level = configs.logging.level,
        moduleLevels = configs.logging.moduleLevels,
        colors = configs.logging.colors,
        recentBufferSize = configs.logging.recentBufferSize,
        prefix = configs.framework.name,
    })
    Registry.modulesConfig = configs.modules
    Registry.coreInfo = { name = configs.framework.name, version = Lifecycle.version, api = WL.API_VERSION }
    if Registry.modules.core then
        Registry.modules.core.description = configs.framework.name .. ' framework core'
    end
end

--- Load core config; on success allow module initialisation.
--- Returns true or false.
function Lifecycle.loadCoreConfig()
    local result = Config.loadCore()
    Lifecycle.lastConfigReport = result
    printReport(result)
    if not result.ok then
        Registry.bootAllowed = false
        Registry.blockedReason = 'framework configuration is invalid'
        setFrameworkState('config_error')
        log:error('Framework configuration is invalid. No modules will be initialised until it is fixed.')
        log:error('Fix the errors above, then run "%s config reload" in the server console (or restart the resource).',
            (Lifecycle.coreConfig and Lifecycle.coreConfig.framework.shortName) or 'wasteland')
        return false
    end
    applyCoreConfig(result.configs)
    return true
end

--- Boot the framework. Called once when the core resource starts.
function Lifecycle.boot()
    Lifecycle.version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '0.0.0'
    Lifecycle.bootedAt = GetGameTimer()
    setFrameworkState('booting')
    Registry.reset()
    Registry.registerCore(GetCurrentResourceName(), { name = 'Wasteland Core', version = Lifecycle.version, api = WL.API_VERSION })
    log:info('starting core v%s (api %s), config resource "%s"', Lifecycle.version, WL.API_VERSION, Config.getConfigResource())

    -- Resources can only be started once the core is fully started, i.e.
    -- after this script finishes loading, so defer to a thread.
    Citizen.CreateThread(function()
        Citizen.Wait(0)
        Lifecycle.restartCascadedResources()
    end)

    if not Lifecycle.loadCoreConfig() then
        TriggerEvent('wasteland:core:booting', Lifecycle.getInfo())
        return false
    end
    Lifecycle.startModules()
    return true
end

--- Allow modules to initialise and arm the startup watchdog.
function Lifecycle.startModules()
    local info = Lifecycle.getInfo()
    log:info('%s v%s loaded configuration; initialising modules', info.name, info.version)
    Registry.bootAllowed = true
    Registry.blockedReason = nil
    setFrameworkState('booting')
    TriggerEvent('wasteland:core:booting', info)
    Registry.resolve()
    local timeout = Lifecycle.coreConfig.framework.startupTimeoutSeconds
    local bootToken = {}
    Lifecycle.bootToken = bootToken
    Citizen.CreateThread(function()
        Citizen.Wait(timeout * 1000)
        if Lifecycle.bootToken ~= bootToken or Lifecycle.state ~= 'booting' then return end
        Lifecycle.finishStartup()
    end)
end

--- End of the startup window: time out stuck async inits, report problems,
--- announce readiness.
function Lifecycle.finishStartup()
    for _, name in ipairs(Util.sortedKeys(Registry.modules)) do
        local mod = Registry.modules[name]
        if mod.state == 'initializing' then
            Registry.reportFailed(name, 'did not report ready within the startup timeout')
        end
    end
    for _, name in ipairs(Registry.missingModules()) do
        log:warn('module "%s" is enabled in modules config but never registered (is its resource installed and started after %s?)',
            name, GetCurrentResourceName())
    end
    for _, s in ipairs(Registry.list()) do
        if s.state == 'waiting' then
            log:warn('module "%s" is still waiting: %s', s.name, tostring(s.reason))
        end
    end
    setFrameworkState('ready')
    for _, line in ipairs(Lifecycle.statusLines()) do log:info(line) end
    TriggerEvent('wasteland:core:ready', Lifecycle.getInfo())
end

--- Re-read core config. While in config_error, a valid config resumes boot.
--- When running, changes are only validated (restart to apply).
function Lifecycle.reloadConfig()
    if Lifecycle.state == 'config_error' then
        if Lifecycle.loadCoreConfig() then
            log:info('configuration is now valid; resuming startup')
            Lifecycle.startModules()
            return true, 'configuration valid; startup resumed'
        end
        return false, 'configuration still invalid'
    end
    local report = Lifecycle.validateAll()
    return report.ok, report.ok and 'configuration valid (restart the framework to apply changes)'
        or 'configuration has errors (current settings remain active)'
end

--- Validate every core and module config file without applying anything.
--- Returns { ok, files = { {label, ok, errors, warnings} } }
function Lifecycle.validateAll()
    local out = { ok = true, files = {} }
    local core = Config.loadCore()
    for _, key in ipairs({ 'logging', 'framework', 'modules' }) do
        local r = core.reports[key]
        out.files[#out.files + 1] = { label = r.label, ok = r.ok, errors = r.errors, warnings = r.warnings }
        if not r.ok then out.ok = false end
    end
    for _, name in ipairs(Util.sortedKeys(Registry.modules)) do
        local mod = Registry.modules[name]
        if mod.configSpec then
            local r = Config.loadValidated(mod.configSpec.file, mod.configSpec.schema, { optional = mod.configSpec.optional })
            out.files[#out.files + 1] = { label = r.label .. ' (' .. name .. ')', ok = r.ok, errors = r.errors, warnings = r.warnings }
            if not r.ok then out.ok = false end
        end
    end
    return out
end

-- FiveM stops resources that depend on wasteland_core when the core stops,
-- but does not start them again when the core restarts. The core records
-- which module resources were stopped *by its own stop* in a server convar
-- (lives for the server process, not written to disk) and starts them again
-- on the next boot.
Lifecycle.RESTART_CONVAR = 'wasteland_core_restart_resources'
Lifecycle.CASCADE_WINDOW_MS = 1000

function Lifecycle.rememberCascadedResources()
    local cfg = Lifecycle.coreConfig
    if cfg and cfg.framework.restartModulesAfterCoreRestart == false then return {} end
    local list = Registry.resourcesStoppedSince(GetGameTimer() - Lifecycle.CASCADE_WINDOW_MS)
    SetConvar(Lifecycle.RESTART_CONVAR, table.concat(list, ','))
    if #list > 0 then
        log:info('will restart %d module resource(s) when the core starts again: %s', #list, table.concat(list, ', '))
    end
    return list
end

function Lifecycle.restartCascadedResources()
    local raw = GetConvar(Lifecycle.RESTART_CONVAR, '')
    if raw == nil or raw == '' then return {} end
    SetConvar(Lifecycle.RESTART_CONVAR, '')
    local cfg = Lifecycle.coreConfig
    if cfg and cfg.framework.restartModulesAfterCoreRestart == false then return {} end
    local started = {}
    for res in raw:gmatch('[^,]+') do
        local state = GetResourceState(res)
        if state == 'stopped' then
            log:info('restarting module resource "%s" (stopped by the previous core restart)', res)
            if StartResource(res) then
                started[#started + 1] = res
            else
                log:error('could not restart resource "%s"; start it manually with: ensure %s', res, res)
            end
        elseif state == 'missing' then
            log:warn('resource "%s" was running before the core restart but no longer exists', res)
        end
    end
    return started
end

-- The same FiveM behaviour applies to every module resource: restarting
-- wasteland_database stops wasteland_players (it declares the dependency)
-- and leaves it stopped. When a module resource stops, the core remembers
-- the module resources FiveM stopped just before it because they depend on
-- it, and starts them again when it comes back (same setting).
Lifecycle.dependentsToRestart = Lifecycle.dependentsToRestart or {}

--- True when `res` lists `target` as a dependency in its fxmanifest.
function Lifecycle.manifestDependsOn(res, target)
    local n = GetNumResourceMetadata(res, 'dependency') or 0
    for i = 0, n - 1 do
        if GetResourceMetadata(res, 'dependency', i) == target then return true end
    end
    return false
end

function Lifecycle.rememberDependents(resource)
    local cfg = Lifecycle.coreConfig
    if cfg and cfg.framework.restartModulesAfterCoreRestart == false then return {} end
    local list = {}
    for _, res in ipairs(Registry.resourcesStoppedSince(GetGameTimer() - Lifecycle.CASCADE_WINDOW_MS)) do
        if res ~= resource and Lifecycle.manifestDependsOn(res, resource) then list[#list + 1] = res end
    end
    if #list > 0 then
        Lifecycle.dependentsToRestart[resource] = list
        log:info('"%s" stopped; will restart %d dependent module resource(s) when it starts again: %s',
            resource, #list, table.concat(list, ', '))
    end
    return list
end

function Lifecycle.restartDependents(resource)
    local list = Lifecycle.dependentsToRestart[resource]
    if not list then return {} end
    Lifecycle.dependentsToRestart[resource] = nil
    local started = {}
    for _, res in ipairs(list) do
        if GetResourceState(res) == 'stopped' then
            log:info('restarting module resource "%s" (stopped because "%s" restarted)', res, resource)
            if StartResource(res) then
                started[#started + 1] = res
            else
                log:error('could not restart resource "%s"; start it manually with: ensure %s', res, res)
            end
        end
    end
    return started
end

--- Ordered, idempotent shutdown.
function Lifecycle.shutdown(reason)
    if Lifecycle.state == 'shutting_down' or Lifecycle.state == 'stopped' then
        return nil
    end
    reason = reason or 'shutdown'
    if reason == 'core_stopped' then Lifecycle.rememberCascadedResources() end
    Lifecycle.bootToken = nil
    setFrameworkState('shutting_down')
    log:info('shutting down (%s)', reason)
    TriggerEvent('wasteland:core:shutdown', reason)
    local summary = Registry.shutdownAll(reason)
    if summary.stopped > 0 then
        log:info('stopped %d module(s) in order: %s', summary.stopped, table.concat(summary.order, ', '))
    end
    if summary.errors > 0 then
        log:error('shutdown finished with %d module error(s); see messages above', summary.errors)
    else
        log:info('shutdown complete')
    end
    setFrameworkState('stopped')
    return summary
end

--- Human-readable status table (used at boot and by the admin command).
function Lifecycle.statusLines()
    local info = Lifecycle.getInfo()
    local lines = {}
    lines[#lines + 1] = string.format('%s v%s | api %s | state: %s | config: %s',
        info.name, info.version, info.api, info.state, info.configResource)
    local counts = {}
    local list = Registry.list()
    lines[#lines + 1] = string.format('%-14s %-9s %-13s %-22s %s', 'MODULE', 'VERSION', 'STATE', 'RESOURCE', 'DETAILS')
    for _, s in ipairs(list) do
        counts[s.state] = (counts[s.state] or 0) + 1
        local details = s.reason or ''
        if s.health == 'degraded' then
            counts.degraded = (counts.degraded or 0) + 1
            details = 'DEGRADED: ' .. tostring(s.healthDetail or 'no detail given')
        end
        lines[#lines + 1] = string.format('%-14s %-9s %-13s %-22s %s',
            s.name, s.version, s.state, tostring(s.resource), details)
    end
    for _, name in ipairs(Registry.missingModules()) do
        counts.missing = (counts.missing or 0) + 1
        lines[#lines + 1] = string.format('%-14s %-9s %-13s %-22s %s', name, '-', 'missing', '-',
            'enabled in modules config but not registered')
    end
    local parts = {}
    for _, st in ipairs({ 'running', 'degraded', 'initializing', 'waiting', 'failed', 'disabled', 'stopped', 'missing' }) do
        if counts[st] then parts[#parts + 1] = st .. '=' .. counts[st] end
    end
    lines[#lines + 1] = 'summary: ' .. table.concat(parts, ' ')
    return lines
end

return Lifecycle
