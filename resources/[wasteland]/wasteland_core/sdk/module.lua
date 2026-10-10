-- Wasteland Core :: sdk/module.lua  (Module SDK, core api 1.x)
--
-- Include in a module resource's fxmanifest.lua:
--     dependency 'wasteland_core'
--     server_script '@wasteland_core/sdk/module.lua'
--     server_script 'server/main.lua'
--
-- Then in server/main.lua:
--     local M = Wasteland.DefineModule({
--         name = 'mymodule', version = '1.0.0',
--         dependencies = { core = '^1.0.0' },
--         config = { file = 'mymodule.lua', schema = { type = 'table', fields = { ... } } },
--         onInit = function(M, ctx) ... end,        -- return false, 'why' to fail
--         onShutdown = function(M, reason) ... end,
--     })
--
-- The SDK handles registration (including re-registration after the core
-- restarts), symmetric init/shutdown, shutdown when the module's own resource
-- stops, and logging through the core.

Wasteland = Wasteland or {}
Wasteland.SDK_VERSION = '1.0.0'
Wasteland.CORE_RESOURCE = Wasteland.CORE_RESOURCE or 'wasteland_core'

local CORE = Wasteland.CORE_RESOURCE
local RESOURCE = GetCurrentResourceName()

local function coreStarted()
    return GetResourceState(CORE) == 'started'
end

--- Call a core export safely. Returns ok, results... ; never throws.
function Wasteland.CallCore(fnName, ...)
    if not coreStarted() then
        return false, string.format('%s is not started', CORE)
    end
    local args = table.pack(...)
    local res = table.pack(pcall(function()
        return exports[CORE][fnName](exports[CORE], table.unpack(args, 1, args.n))
    end))
    if not res[1] then
        return false, string.format('call to %s:%s failed: %s', CORE, fnName, tostring(res[2]))
    end
    return true, table.unpack(res, 2, res.n)
end

-------------------------------------------------------------------------------
-- Logger that forwards to the core (so central log levels apply)
-------------------------------------------------------------------------------

local LoggerMT = {}
LoggerMT.__index = LoggerMT

local function fmt(f, ...)
    if select('#', ...) == 0 then return tostring(f) end
    local ok, s = pcall(string.format, tostring(f), ...)
    if ok then return s end
    return tostring(f) .. ' [log format error: ' .. tostring(s) .. ']'
end

for _, level in ipairs({ 'debug', 'info', 'warn', 'error' }) do
    LoggerMT[level] = function(self, f, ...)
        local message = fmt(f, ...)
        local ok, logged = Wasteland.CallCore('Log', self.module, level, message)
        if not ok or not logged then
            -- Core unavailable: never drop the message.
            print(string.format('[Wasteland] [%s] [%s] %s', level:upper(), self.module, message))
        end
    end
end

function Wasteland.NewLogger(name)
    return setmetatable({ module = name }, LoggerMT)
end

-------------------------------------------------------------------------------
-- Module definition
-------------------------------------------------------------------------------

local FORWARDED_FIELDS = {
    'name', 'version', 'api', 'description', 'core', 'dependencies',
    'optionalDependencies', 'config', 'async',
}

--- Define and register a module. Returns the module handle `M`:
---   M.name, M.config (validated, set before onInit), M.framework,
---   M.active (true between init and shutdown), M.log,
---   M.ready() / M.fail(reason) for async modules,
---   M.registered, M.registerError
function Wasteland.DefineModule(spec)
    assert(type(spec) == 'table', 'DefineModule expects a table')
    assert(type(spec.name) == 'string', 'DefineModule: name is required')
    if Wasteland.Modules and Wasteland.Modules[spec.name] then
        error(string.format('DefineModule: module "%s" already defined in this resource', spec.name), 2)
    end
    Wasteland.Modules = Wasteland.Modules or {}

    local M = {
        name = spec.name,
        resource = RESOURCE,
        active = false,
        config = nil,
        framework = nil,
        log = Wasteland.NewLogger(spec.name),
        registered = false,
    }
    Wasteland.Modules[spec.name] = M

    local function runShutdown(reason)
        if not M.active then return end
        M.active = false
        if spec.onShutdown then
            spec.onShutdown(M, reason)
        end
    end

    local definition = {}
    for _, k in ipairs(FORWARDED_FIELDS) do definition[k] = spec[k] end
    if definition.core == nil then definition.core = '^1.0.0' end

    definition.init = function(ctx)
        M.config = ctx.config
        M.framework = ctx.framework
        M.active = true
        if not spec.onInit then return true end
        local ok, result, message = pcall(spec.onInit, M, ctx)
        if not ok or result == false then
            -- Undo partial initialisation, then let the core record the failure.
            local okShutdown, shutdownErr = pcall(runShutdown, 'init_failed')
            if not okShutdown then
                print(string.format('[Wasteland] [ERROR] [%s] cleanup after failed init raised: %s', M.name, tostring(shutdownErr)))
            end
            M.active = false
            if not ok then error(result, 0) end
            return false, message
        end
        return true
    end

    definition.shutdown = function(reason)
        runShutdown(reason)
        return true
    end

    function M.ready()
        local ok, done, err = Wasteland.CallCore('ReportModuleReady', M.name)
        if not ok then return false, done end
        return done, err
    end

    function M.fail(reason)
        local ok, done, err = Wasteland.CallCore('ReportModuleFailed', M.name, reason)
        if not ok then return false, done end
        return done, err
    end

    function M.register()
        local ok, registered, err = Wasteland.CallCore('RegisterModule', definition)
        if not ok then
            M.registered, M.registerError = false, registered
        else
            M.registered, M.registerError = registered == true, err
        end
        if not M.registered then
            print(string.format('^1[Wasteland] [ERROR] [%s] registration failed: %s^7', M.name, tostring(M.registerError)))
        end
        return M.registered, M.registerError
    end

    -- Our own resource is stopping: clean up locally (the core marks us stopped).
    AddEventHandler('onResourceStop', function(resourceName)
        if resourceName == RESOURCE then
            local ok, err = pcall(runShutdown, 'resource_stop')
            if not ok then
                print(string.format('^1[Wasteland] [ERROR] [%s] shutdown error: %s^7', M.name, tostring(err)))
            end
        elseif resourceName == CORE then
            -- Core went away without being able to call us.
            local ok, err = pcall(runShutdown, 'core_stopped')
            if not ok then
                print(string.format('^1[Wasteland] [ERROR] [%s] shutdown error: %s^7', M.name, tostring(err)))
            end
            M.registered = false
        end
    end)

    -- Core (re)started after us: register again.
    AddEventHandler('onResourceStart', function(resourceName)
        if resourceName == CORE then M.register() end
    end)

    if coreStarted() then M.register() end
    return M
end

return Wasteland
