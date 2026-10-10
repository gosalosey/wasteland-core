-- Wasteland Core :: server/registry.lua
-- The module registry: accepts module definitions, checks versions and
-- dependencies, loads and validates each module's configuration, initialises
-- modules in dependency order and shuts them down in reverse order.
--
-- Module states:
--   disabled      turned off in config/modules.lua
--   waiting       registered, blocked on the framework or on dependencies
--   initializing  init() running, or async module that has not reported ready
--   running       initialised and operational
--   failed        rejected or crashed; `reason` explains why
--   stopped       its resource stopped (or the framework shut it down)

WL = WL or {}
WL.Registry = WL.Registry or {}
local Registry = WL.Registry
local Util = WL.Util
local Semver = WL.Semver
local Schema = WL.Schema
local log = WL.Logger.new('registry')

Registry.STATES = {
    disabled = true, waiting = true, initializing = true,
    running = true, failed = true, stopped = true,
}

local NAME_PATTERN = '^[a-z][a-z0-9_]*$'

-- Data part of a module definition (functions are checked separately because
-- across resources they arrive as callable function-reference tables).
local DEFINITION_SCHEMA = {
    type = 'table',
    fields = {
        name = { type = 'string', required = true, pattern = NAME_PATTERN, maxLength = 32 },
        version = { type = 'string', required = true },
        api = { type = 'string' },
        description = { type = 'string', default = '' },
        resource = { type = 'string' },
        core = { type = 'string', default = '*' },
        dependencies = { type = 'map', default = {}, keys = { type = 'string', pattern = NAME_PATTERN }, values = { type = 'string' } },
        optionalDependencies = { type = 'map', default = {}, keys = { type = 'string', pattern = NAME_PATTERN }, values = { type = 'string' } },
        config = {
            type = 'table', nullable = true,
            fields = {
                file = { type = 'string', required = true, pattern = '^[%w_%-]+%.lua$' },
                optional = { type = 'boolean', default = true },
                schema = { type = 'any', required = true },
            },
        },
        async = { type = 'boolean', default = false },
        init = { type = 'any' },
        shutdown = { type = 'any' },
    },
}

--- True for Lua functions and for FiveM cross-resource function references
--- (tables with a __call metamethod).
function Registry.isCallable(f)
    if type(f) == 'function' then return true end
    if type(f) == 'table' then
        local mt = getmetatable(f)
        return type(mt) == 'table' and mt.__call ~= nil
    end
    return false
end

function Registry.reset()
    Registry.modules = {}
    Registry.order = {}          -- names in the order they reached `running`
    Registry.bootAllowed = false -- set by lifecycle when core config is valid
    Registry.blockedReason = 'framework is starting'
    Registry.modulesConfig = { enabled = {}, unlisted = 'enable' }
    Registry.coreInfo = { version = '0.0.0', api = '0.0.0', name = 'Wasteland Core' }
    Registry.initCounter = 0
end

if not Registry.modules then Registry.reset() end

-------------------------------------------------------------------------------
-- State helpers
-------------------------------------------------------------------------------

local function now()
    return GetGameTimer and GetGameTimer() or 0
end

local function setState(mod, state, reason)
    local prev = mod.state
    mod.state = state
    mod.reason = reason
    mod.stateSince = now()
    if state == 'running' then
        Registry.initCounter = Registry.initCounter + 1
        mod.initIndex = Registry.initCounter
    end
    if prev ~= state then
        local lvl = (state == 'failed') and 'error' or ((state == 'waiting' or state == 'stopped') and 'info' or 'info')
        if state == 'failed' then
            log:error('module "%s" %s -> failed: %s', mod.name, tostring(prev), tostring(reason))
        else
            log[lvl](log, 'module "%s" %s -> %s%s', mod.name, tostring(prev), state, reason and (' (' .. reason .. ')') or '')
        end
        if TriggerEvent then
            TriggerEvent('wasteland:core:moduleState', mod.name, state, prev, reason)
        end
    end
end

function Registry.isEnabled(name)
    local enabled = Registry.modulesConfig.enabled or {}
    if enabled[name] ~= nil then return enabled[name] end
    if name == 'core' then return true end
    return Registry.modulesConfig.unlisted ~= 'disable'
end

function Registry.get(name)
    return Registry.modules[name]
end

function Registry.isRunning(name)
    local m = Registry.modules[name]
    return m ~= nil and m.state == 'running'
end

local function snapshot(mod)
    local deps = {}
    for k, v in pairs(mod.dependencies or {}) do deps[k] = v end
    local opt = {}
    for k, v in pairs(mod.optionalDependencies or {}) do opt[k] = v end
    return {
        name = mod.name,
        version = mod.version,
        api = mod.api,
        description = mod.description,
        resource = mod.resource,
        state = mod.state,
        reason = mod.reason,
        enabled = Registry.isEnabled(mod.name),
        dependencies = deps,
        optionalDependencies = opt,
        configFile = mod.configSpec and mod.configSpec.file or nil,
        configWarnings = mod.configWarnings and Util.deepCopy(mod.configWarnings) or {},
        initIndex = mod.initIndex,
        async = mod.async,
    }
end

function Registry.getStatus(name)
    local m = Registry.modules[name]
    return m and snapshot(m) or nil
end

--- All module statuses sorted by name.
function Registry.list()
    local out = {}
    for _, name in ipairs(Util.sortedKeys(Registry.modules)) do
        out[#out + 1] = snapshot(Registry.modules[name])
    end
    return out
end

--- Enabled modules listed in modules.lua that never registered.
function Registry.missingModules()
    local out = {}
    for _, name in ipairs(Util.sortedKeys(Registry.modulesConfig.enabled or {})) do
        if Registry.modulesConfig.enabled[name] and not Registry.modules[name] then
            out[#out + 1] = name
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- Registration
-------------------------------------------------------------------------------

--- Register a module definition. `resource` is the owning resource name.
--- Returns true or false, error message.
function Registry.register(def, resource)
    if type(def) ~= 'table' then
        return false, 'module definition must be a table'
    end
    local value, errors, warnings = Schema.validate(DEFINITION_SCHEMA, def)
    if #errors > 0 then
        local lines = Schema.formatIssues(errors, 'module definition' .. (type(def.name) == 'string' and (' "' .. def.name .. '"') or ''))
        local msg = table.concat(lines, '; ')
        log:error('rejected registration from resource "%s": %s', tostring(resource), msg)
        return false, msg
    end
    local name = value.name

    -- Versions and ranges
    if not Semver.isValid(value.version) then
        local msg = string.format('module "%s": invalid version "%s" (expected MAJOR.MINOR.PATCH)', name, value.version)
        log:error(msg); return false, msg
    end
    value.api = value.api or value.version
    if not Semver.isValid(value.api) then
        local msg = string.format('module "%s": invalid api version "%s"', name, value.api)
        log:error(msg); return false, msg
    end
    local okRange, rangeErr = Semver.isValidRange(value.core)
    if not okRange then
        local msg = string.format('module "%s": invalid core range "%s": %s', name, value.core, tostring(rangeErr))
        log:error(msg); return false, msg
    end
    for _, field in ipairs({ 'dependencies', 'optionalDependencies' }) do
        for depName, range in pairs(value[field]) do
            local ok, err = Semver.isValidRange(range)
            if not ok then
                local msg = string.format('module "%s": %s.%s has invalid version range "%s": %s', name, field, depName, range, tostring(err))
                log:error(msg); return false, msg
            end
            if depName == name then
                local msg = string.format('module "%s" cannot depend on itself', name)
                log:error(msg); return false, msg
            end
        end
    end
    -- Check the ORIGINAL callables: schema validation deep-copies values, which
    -- would strip the metatable from FiveM function-reference tables.
    if def.init ~= nil and not Registry.isCallable(def.init) then
        local msg = string.format('module "%s": init must be a function', name)
        log:error(msg); return false, msg
    end
    if def.shutdown ~= nil and not Registry.isCallable(def.shutdown) then
        local msg = string.format('module "%s": shutdown must be a function', name)
        log:error(msg); return false, msg
    end
    if value.config then
        local okSchema, schemaErrors = Schema.check(value.config.schema)
        if not okSchema then
            local msg = string.format('module "%s": invalid config schema: %s', name, table.concat(schemaErrors, '; '))
            log:error(msg); return false, msg
        end
    end
    for _, w in ipairs(warnings) do
        log:warn('module "%s" definition: %s: %s', name, w.path, w.message)
    end

    -- Ownership / duplicates
    local existing = Registry.modules[name]
    if existing then
        if existing.resource ~= resource then
            local msg = string.format('module name "%s" is already registered by resource "%s" (attempted by "%s")',
                name, tostring(existing.resource), tostring(resource))
            log:error(msg); return false, msg
        end
        if existing.state == 'running' or existing.state == 'initializing' then
            local msg = string.format('module "%s" is already %s; it must stop before re-registering', name, existing.state)
            log:warn(msg); return false, msg
        end
    end

    local mod = {
        name = name,
        version = value.version,
        api = value.api,
        description = value.description,
        resource = resource,
        coreRange = value.core,
        dependencies = value.dependencies,
        optionalDependencies = value.optionalDependencies,
        configSpec = value.config,
        async = value.async,
        -- keep the original callables (deep copies would break function refs)
        init = def.init,
        shutdown = def.shutdown,
        state = nil,
        registeredAt = now(),
    }
    Registry.modules[name] = mod
    log:info('registered module "%s" v%s (api %s) from resource "%s"', name, mod.version, mod.api, tostring(resource))
    setState(mod, 'waiting', 'queued for initialisation')
    Registry.resolve()
    return true
end

--- Register the core itself as module "core" so other modules can declare
--- `dependencies = { core = '^1.0.0' }` uniformly.
function Registry.registerCore(resource, info)
    Registry.coreInfo = info
    Registry.modules.core = {
        name = 'core', version = info.version, api = info.api,
        description = info.name .. ' framework core', resource = resource,
        coreRange = '*', dependencies = {}, optionalDependencies = {},
        async = false, state = nil, registeredAt = now(),
    }
    setState(Registry.modules.core, 'running')
end

-------------------------------------------------------------------------------
-- Resolution
-------------------------------------------------------------------------------

local function configureModule(mod)
    mod.config = {}
    mod.configWarnings = {}
    if not mod.configSpec then return true end
    local report = WL.Config.loadValidated(mod.configSpec.file, mod.configSpec.schema, { optional = mod.configSpec.optional })
    for _, w in ipairs(report.warnings) do
        mod.configWarnings[#mod.configWarnings + 1] = w
        log:warn('[%s] %s', mod.name, w)
    end
    if not report.ok then
        for _, e in ipairs(report.errors) do log:error('[%s] %s', mod.name, e) end
        return false, 'invalid configuration: ' .. table.concat(report.errors, '; ')
    end
    mod.config = report.config
    return true
end

-- Returns 'ready' | 'wait', reason | 'fail', reason
local function checkDependencies(mod)
    for _, depName in ipairs(Util.sortedKeys(mod.dependencies)) do
        local range = mod.dependencies[depName]
        local dep = Registry.modules[depName]
        if not dep then
            if not Registry.isEnabled(depName) then
                return 'fail', string.format('required dependency "%s" is disabled in modules config', depName)
            end
            return 'wait', string.format('waiting for dependency "%s" to register', depName)
        end
        if dep.state == 'disabled' then
            return 'fail', string.format('required dependency "%s" is disabled', depName)
        end
        if not Semver.satisfies(dep.api, range) then
            return 'fail', string.format('dependency "%s" api %s does not satisfy required range %s', depName, dep.api, range)
        end
        if dep.state == 'failed' then
            return 'wait', string.format('dependency "%s" failed (%s)', depName, tostring(dep.reason))
        end
        if dep.state ~= 'running' then
            return 'wait', string.format('waiting for dependency "%s" (%s)', depName, dep.state)
        end
    end
    for _, depName in ipairs(Util.sortedKeys(mod.optionalDependencies)) do
        local range = mod.optionalDependencies[depName]
        local dep = Registry.modules[depName]
        if dep and Registry.isEnabled(depName) then
            if dep.state == 'running' and not Semver.satisfies(dep.api, range) then
                log:warn('module "%s": optional dependency "%s" api %s does not satisfy %s; it will be ignored',
                    mod.name, depName, dep.api, range)
            elseif dep.state == 'waiting' or dep.state == 'initializing' then
                return 'wait', string.format('waiting for optional dependency "%s" (%s)', depName, dep.state)
            end
        end
    end
    return 'ready'
end

local function initModule(mod)
    local ok, err = configureModule(mod)
    if not ok then
        setState(mod, 'failed', err)
        return
    end
    setState(mod, 'initializing')
    if not mod.init then
        setState(mod, 'running')
        return
    end
    local ctx = {
        name = mod.name,
        config = Util.deepCopy(mod.config),
        framework = Util.deepCopy(Registry.coreInfo),
    }
    local okCall, result, message = pcall(mod.init, ctx)
    if mod.state ~= 'initializing' then
        -- The module reported ready/failed synchronously from inside init.
        return
    end
    if not okCall then
        setState(mod, 'failed', 'init error: ' .. tostring(result))
        return
    end
    if result == false then
        setState(mod, 'failed', 'init returned false: ' .. tostring(message or 'no reason given'))
        return
    end
    if mod.async then
        log:info('module "%s" initialising asynchronously; waiting for it to report ready', mod.name)
        return
    end
    setState(mod, 'running')
end

-- Detect dependency cycles among waiting modules; mark members failed.
local function failCycles()
    local visiting, visited, failedAny = {}, {}, false
    local function visit(name, stack)
        if visiting[name] then
            local cycle = {}
            local started = false
            for _, n in ipairs(stack) do
                if n == name then started = true end
                if started then cycle[#cycle + 1] = n end
            end
            cycle[#cycle + 1] = name
            return cycle
        end
        if visited[name] then return nil end
        local mod = Registry.modules[name]
        if not mod or mod.state ~= 'waiting' then return nil end
        visiting[name] = true
        stack[#stack + 1] = name
        for _, dep in ipairs(Util.sortedKeys(mod.dependencies)) do
            local c = visit(dep, stack)
            if c then return c end
        end
        stack[#stack] = nil
        visiting[name] = nil
        visited[name] = true
        return nil
    end
    for _, name in ipairs(Util.sortedKeys(Registry.modules)) do
        visiting = {}
        local cycle = visit(name, {})
        if cycle then
            local text = table.concat(cycle, ' -> ')
            for i = 1, #cycle - 1 do
                local m = Registry.modules[cycle[i]]
                if m and m.state == 'waiting' then
                    setState(m, 'failed', 'dependency cycle: ' .. text)
                    failedAny = true
                end
            end
        end
    end
    return failedAny
end

--- Advance every module whose prerequisites are satisfied. Safe to call
--- repeatedly; runs until no further progress is possible.
function Registry.resolve()
    if Registry.resolving then
        Registry.resolveAgain = true
        return
    end
    Registry.resolving = true
    repeat
        Registry.resolveAgain = false
        local progressed = true
        while progressed do
            progressed = false
            for _, name in ipairs(Util.sortedKeys(Registry.modules)) do
                local mod = Registry.modules[name]
                if mod.state == 'waiting' or mod.state == 'disabled' then
                    if not Registry.isEnabled(name) then
                        if mod.state ~= 'disabled' then
                            setState(mod, 'disabled', 'disabled in modules config')
                            progressed = true
                        end
                    elseif mod.state == 'disabled' then
                        setState(mod, 'waiting', 'enabled')
                        progressed = true
                    elseif not Registry.bootAllowed then
                        if mod.reason ~= Registry.blockedReason then
                            mod.reason = Registry.blockedReason
                        end
                    elseif not Semver.satisfies(Registry.coreInfo.api, mod.coreRange) then
                        setState(mod, 'failed', string.format('requires core api %s but this core provides %s',
                            mod.coreRange, Registry.coreInfo.api))
                        progressed = true
                    else
                        local status, reason = checkDependencies(mod)
                        if status == 'ready' then
                            initModule(mod)
                            progressed = true
                        elseif status == 'fail' then
                            setState(mod, 'failed', reason)
                            progressed = true
                        elseif mod.reason ~= reason then
                            mod.reason = reason
                        end
                    end
                end
            end
            if not progressed and Registry.bootAllowed then
                progressed = failCycles()
            end
        end
    until not Registry.resolveAgain
    Registry.resolving = false
end

--- Called by an async module (through the export) when it finishes init.
function Registry.reportReady(name, resource)
    local mod = Registry.modules[name]
    if not mod then return false, 'unknown module "' .. tostring(name) .. '"' end
    if resource and mod.resource ~= resource then
        return false, string.format('resource "%s" does not own module "%s"', tostring(resource), name)
    end
    if mod.state ~= 'initializing' then
        return false, string.format('module "%s" is %s, not initializing', name, tostring(mod.state))
    end
    setState(mod, 'running')
    Registry.resolve()
    return true
end

function Registry.reportFailed(name, reason, resource)
    local mod = Registry.modules[name]
    if not mod then return false, 'unknown module "' .. tostring(name) .. '"' end
    if resource and mod.resource ~= resource then
        return false, string.format('resource "%s" does not own module "%s"', tostring(resource), name)
    end
    if mod.state ~= 'initializing' and mod.state ~= 'running' then
        return false, string.format('module "%s" is %s', name, tostring(mod.state))
    end
    local wasRunning = mod.state == 'running'
    setState(mod, 'failed', tostring(reason or 'module reported failure'))
    if wasRunning then Registry.cascadeUnavailable(name) end
    Registry.resolve()
    return true
end

-------------------------------------------------------------------------------
-- Shutdown
-------------------------------------------------------------------------------

local function ownerAlive(mod)
    if not mod.resource then return false end
    if not GetResourceState then return true end
    local st = GetResourceState(mod.resource)
    return st == 'started' or st == 'starting'
end

-- Call a module's shutdown handler (if its resource is still alive).
local function callShutdown(mod, reason)
    if not mod.shutdown then return true end
    if not ownerAlive(mod) then
        log:debug('module "%s": owner resource not running; skipping shutdown callback', mod.name)
        return true
    end
    local ok, err = pcall(mod.shutdown, reason)
    if not ok then
        log:error('module "%s" shutdown error (%s): %s', mod.name, reason, tostring(err))
        return false, err
    end
    return true
end

--- A module became unavailable: stop every running module that hard-depends
--- on it (deepest dependents first) and put them back in `waiting`.
function Registry.cascadeUnavailable(name, visited)
    visited = visited or {}
    if visited[name] then return end
    visited[name] = true
    -- Sort dependents by reverse init order so the latest started stop first.
    local dependents = {}
    for _, mod in pairs(Registry.modules) do
        if mod.dependencies and mod.dependencies[name] and (mod.state == 'running' or mod.state == 'initializing') then
            dependents[#dependents + 1] = mod
        end
    end
    table.sort(dependents, function(a, b) return (a.initIndex or 0) > (b.initIndex or 0) end)
    for _, dep in ipairs(dependents) do
        Registry.cascadeUnavailable(dep.name, visited)
        if dep.state == 'running' or dep.state == 'initializing' then
            callShutdown(dep, 'dependency_unavailable:' .. name)
            setState(dep, 'waiting', string.format('dependency "%s" became unavailable', name))
        end
    end
end

--- A resource stopped. Modules it owns are marked stopped (their own SDK
--- runs their shutdown inside that resource); dependents are cascaded.
function Registry.onResourceStop(resource)
    local affected = {}
    for _, name in ipairs(Util.sortedKeys(Registry.modules)) do
        local mod = Registry.modules[name]
        if mod.resource == resource and name ~= 'core' then
            affected[#affected + 1] = mod
        end
    end
    for _, mod in ipairs(affected) do
        local wasActive = mod.state == 'running' or mod.state == 'initializing'
        mod.resourceStoppedAt = now()
        mod.wasActiveAtStop = wasActive
        if mod.state ~= 'stopped' then
            setState(mod, 'stopped', string.format('resource "%s" stopped', resource))
        end
        if wasActive then Registry.cascadeUnavailable(mod.name) end
    end
    if #affected > 0 then Registry.resolve() end
    return #affected
end

--- Resources whose modules were active and whose resource stopped at or
--- after `since` (game timer ms). Used to find modules that FiveM stopped
--- because the core itself was stopping.
function Registry.resourcesStoppedSince(since)
    local seen, out = {}, {}
    for _, name in ipairs(Util.sortedKeys(Registry.modules)) do
        local mod = Registry.modules[name]
        if name ~= 'core' and mod.wasActiveAtStop and mod.resourceStoppedAt
            and mod.resourceStoppedAt >= since and not seen[mod.resource] then
            seen[mod.resource] = true
            out[#out + 1] = mod.resource
        end
    end
    return out
end

--- Ordered shutdown of every active module (reverse initialisation order).
--- Returns a summary { stopped = n, errors = n, order = {names} }.
function Registry.shutdownAll(reason)
    reason = reason or 'shutdown'
    Registry.bootAllowed = false
    Registry.blockedReason = 'framework is shutting down'
    local active = {}
    for _, mod in pairs(Registry.modules) do
        if mod.name ~= 'core' and (mod.state == 'running' or mod.state == 'initializing') then
            active[#active + 1] = mod
        end
    end
    table.sort(active, function(a, b) return (a.initIndex or math.huge) > (b.initIndex or math.huge) end)
    local summary = { stopped = 0, errors = 0, order = {} }
    for _, mod in ipairs(active) do
        local ok = callShutdown(mod, reason)
        if not ok then summary.errors = summary.errors + 1 end
        setState(mod, 'stopped', reason)
        summary.stopped = summary.stopped + 1
        summary.order[#summary.order + 1] = mod.name
    end
    if Registry.modules.core then setState(Registry.modules.core, 'stopped', reason) end
    return summary
end

return Registry
