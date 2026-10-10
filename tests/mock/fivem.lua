-- tests/mock/fivem.lua
-- A multi-resource simulation of the parts of the FiveM *server* runtime
-- that Wasteland Core uses. It exists so the framework's real resource files
-- (fxmanifest.lua + scripts) can be loaded and exercised outside the game.
--
-- What it models faithfully enough for the tests:
--   * one isolated Lua environment (globals) per resource
--   * fxmanifest parsing, script load order (shared -> server), @resource/ includes
--   * dependency auto-start and stop-dependents-first behaviour
--   * exports: arguments/results are deep-copied between resources and Lua
--     functions become *callable tables* (like FiveM function references);
--     calling a reference whose owner stopped raises an error
--   * GetInvokingResource() during export and function-reference calls
--   * events (onResourceStart / onResourceStop / custom), handler errors are
--     reported and do not stop other handlers
--   * Citizen.CreateThread / Citizen.Wait on a virtual clock
--   * commands, ACE checks, convars, LoadResourceFile, GetResourceMetadata
--
-- What it does NOT model (must be verified on a real server): networking,
-- clients, natives other than those listed, real timing, msgpack edge cases.

local Mock = {}
Mock.__index = Mock

local function readFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('a')
    f:close()
    return data
end

-------------------------------------------------------------------------------
-- Manifest parsing
-------------------------------------------------------------------------------

local SINGULAR = {
    shared_scripts = 'shared_script', server_scripts = 'server_script',
    client_scripts = 'client_script', dependencies = 'dependency', files = 'file',
}

function Mock.parseManifest(path)
    local src = readFile(path)
    if not src then return nil, 'fxmanifest.lua not found at ' .. path end
    local meta = {}
    local function add(key, value)
        key = SINGULAR[key] or key
        meta[key] = meta[key] or {}
        if type(value) == 'table' then
            for _, v in ipairs(value) do table.insert(meta[key], v) end
        else
            table.insert(meta[key], value)
        end
    end
    local env = setmetatable({}, {
        __index = function(_, key)
            local function collector(value)
                add(key, value)
                return collector
            end
            return collector
        end,
    })
    local chunk, err = load(src, '@' .. path, 't', env)
    if not chunk then return nil, 'manifest syntax error: ' .. err end
    local ok, runErr = pcall(chunk)
    if not ok then return nil, 'manifest error: ' .. tostring(runErr) end
    return meta
end

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------

function Mock.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Mock)
    self.resources = {}
    self.order = {}
    self.clock = 0
    self.threads = {}
    self.convars = opts.convars or {}
    self.aces = {}
    self.commands = {}
    self.output = {}       -- { resource, line }
    self.scriptErrors = {} -- errors raised in event handlers / threads
    self.clientEvents = {}
    self.invoking = {}     -- stack of invoking resources
    self.funcrefs = {}
    self.nextRef = 0
    self.echo = opts.echo or os.getenv('WL_TEST_ECHO') == '1'
    -- FiveM stops dependents when a dependency stops; set false to simulate
    -- the opposite (used to prove the SDK copes either way).
    self.cascadeStop = opts.cascadeStop ~= false
    return self
end

--- Register a resource directory. `path` is the folder containing fxmanifest.lua.
function Mock:addResource(name, path)
    local meta, err = Mock.parseManifest(path .. '/fxmanifest.lua')
    if not meta then error(err, 2) end
    self.resources[name] = {
        name = name, path = path, meta = meta, state = 'stopped',
        handlers = {}, exports = {},
    }
    self.order[#self.order + 1] = name
    return self.resources[name]
end

--- Register an in-memory resource (used for test fixtures).
--- meta = parsed-manifest-like table, files = { ['path'] = 'source' }
function Mock:addVirtualResource(name, meta, files)
    self.resources[name] = {
        name = name, path = nil, meta = meta, state = 'stopped',
        handlers = {}, exports = {}, virtual = files or {},
    }
    self.order[#self.order + 1] = name
    return self.resources[name]
end

--- Override a file's contents for a resource (e.g. to inject a bad config).
function Mock:setFile(resource, relPath, contents)
    local r = assert(self.resources[resource], 'unknown resource ' .. resource)
    r.overrides = r.overrides or {}
    r.overrides[relPath] = contents
end

function Mock:readResourceFile(resource, relPath)
    local r = self.resources[resource]
    if not r then return nil end
    if r.overrides and r.overrides[relPath] ~= nil then
        if r.overrides[relPath] == false then return nil end
        return r.overrides[relPath]
    end
    if r.virtual then return r.virtual[relPath] end
    return readFile(r.path .. '/' .. relPath)
end

function Mock:log(resource, line)
    self.output[#self.output + 1] = { resource = resource, line = line }
    if self.echo then print(string.format('  | %-20s %s', resource, line)) end
end

--- All output lines (optionally only those containing `needle`).
function Mock:lines(needle)
    local out = {}
    for _, o in ipairs(self.output) do
        if not needle or o.line:find(needle, 1, true) then out[#out + 1] = o.line end
    end
    return out
end

function Mock:clearOutput() self.output = {} end

-------------------------------------------------------------------------------
-- Marshalling between resources (models msgpack + function references)
-------------------------------------------------------------------------------

function Mock:makeFuncRef(fn, owner)
    self.nextRef = self.nextRef + 1
    local id = self.nextRef
    self.funcrefs[id] = { fn = fn, owner = owner }
    local mock = self
    return setmetatable({ __cfx_functionReference = owner .. ':' .. id }, {
        __call = function(_, ...)
            return mock:callFuncRef(id, ...)
        end,
    })
end

function Mock:marshal(value, owner, seen)
    local tv = type(value)
    if tv == 'function' then return self:makeFuncRef(value, owner) end
    if tv ~= 'table' then return value end
    if rawget(value, '__cfx_functionReference') then return value end
    seen = seen or {}
    if seen[value] then error('cannot serialise a table with cycles', 0) end
    seen[value] = true
    local out = {}
    for k, v in pairs(value) do out[self:marshal(k, owner, seen)] = self:marshal(v, owner, seen) end
    seen[value] = nil
    return out
end

local function packMarshal(mock, owner, ...)
    local n = select('#', ...)
    local t = { n = n }
    for i = 1, n do t[i] = mock:marshal((select(i, ...)), owner) end
    return t
end

function Mock:currentCaller()
    return self.invoking[#self.invoking] and self.invoking[#self.invoking].current or nil
end

function Mock:withInvocation(caller, target, fn, ...)
    table.insert(self.invoking, { invoker = caller, current = target })
    local res = table.pack(pcall(fn, ...))
    table.remove(self.invoking)
    if not res[1] then error(res[2], 0) end
    return table.unpack(res, 2, res.n)
end

function Mock:callFuncRef(id, ...)
    local ref = self.funcrefs[id]
    if not ref then error('invalid function reference', 2) end
    local owner = self.resources[ref.owner]
    if not owner or (owner.state ~= 'started' and owner.state ~= 'starting' and owner.state ~= 'stopping') then
        error(string.format('function reference to stopped resource %s', ref.owner), 2)
    end
    local caller = self:currentCaller() or '<harness>'
    local args = packMarshal(self, caller, ...)
    local results = table.pack(self:withInvocation(caller, ref.owner, ref.fn, table.unpack(args, 1, args.n)))
    local back = packMarshal(self, ref.owner, table.unpack(results, 1, results.n))
    return table.unpack(back, 1, back.n)
end

function Mock:callExport(caller, target, fnName, ...)
    local r = self.resources[target]
    if not r or (r.state ~= 'started' and r.state ~= 'starting') or not r.exports[fnName] then
        error(string.format('No such export %s in resource %s', fnName, target), 2)
    end
    local args = packMarshal(self, caller, ...)
    local results = table.pack(self:withInvocation(caller, target, r.exports[fnName], table.unpack(args, 1, args.n)))
    local back = packMarshal(self, target, table.unpack(results, 1, results.n))
    return table.unpack(back, 1, back.n)
end

--- Call an export from the test harness: mock:export('wasteland_core', 'GetModuleStatuses')
function Mock:export(target, fnName, ...)
    return self:callExport('<harness>', target, fnName, ...)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

function Mock:triggerEvent(sender, name, ...)
    local args = table.pack(...)
    for _, resName in ipairs(self.order) do
        local r = self.resources[resName]
        if r.state == 'started' or r.state == 'starting' or r.state == 'stopping' then
            local handlers = r.handlers[name]
            if handlers then
                for _, h in ipairs({ table.unpack(handlers) }) do
                    local copy = packMarshal(self, sender, table.unpack(args, 1, args.n))
                    local ok, err = pcall(function()
                        self:withInvocation(sender, resName, h, table.unpack(copy, 1, copy.n))
                    end)
                    if not ok then
                        local msg = string.format('SCRIPT ERROR in %s handler for "%s": %s', resName, name, tostring(err))
                        self.scriptErrors[#self.scriptErrors + 1] = msg
                        self:log(resName, msg)
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Threads (virtual clock)
-------------------------------------------------------------------------------

function Mock:createThread(owner, fn)
    local co = coroutine.create(fn)
    self.threads[#self.threads + 1] = { co = co, owner = owner, wake = self.clock }
end

--- Advance the virtual clock by `ms`, running due threads in time order.
function Mock:advance(ms)
    local target = self.clock + (ms or 0)
    while true do
        local nextT, idx = nil, nil
        for i, t in ipairs(self.threads) do
            if t.wake <= target and (nextT == nil or t.wake < nextT.wake) then nextT, idx = t, i end
        end
        if not nextT then break end
        table.remove(self.threads, idx)
        local r = self.resources[nextT.owner]
        if r and (r.state == 'started' or r.state == 'starting') then
            if nextT.wake > self.clock then self.clock = nextT.wake end
            table.insert(self.invoking, { invoker = nil, current = nextT.owner })
            local ok, waitMs = coroutine.resume(nextT.co)
            table.remove(self.invoking)
            if not ok then
                local msg = string.format('SCRIPT ERROR in %s thread: %s', nextT.owner, tostring(waitMs))
                self.scriptErrors[#self.scriptErrors + 1] = msg
                self:log(nextT.owner, msg)
            elseif coroutine.status(nextT.co) ~= 'dead' then
                nextT.wake = self.clock + math.max(0, tonumber(waitMs) or 0)
                self.threads[#self.threads + 1] = nextT
            end
        end
    end
    self.clock = target
end

-------------------------------------------------------------------------------
-- Resource environments
-------------------------------------------------------------------------------

local STD = {
    'assert', 'error', 'ipairs', 'next', 'pairs', 'pcall', 'print', 'rawequal', 'rawget', 'rawlen', 'rawset',
    'select', 'setmetatable', 'getmetatable', 'tonumber', 'tostring', 'type', 'xpcall', 'load',
    'math', 'string', 'table', 'coroutine', 'utf8', 'os', '_VERSION',
}

function Mock:buildEnv(r)
    local mock = self
    local env = {}
    for _, k in ipairs(STD) do env[k] = _G[k] end
    env._G = env
    local name = r.name

    env.print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        mock:log(name, table.concat(parts, '\t'))
    end
    env.GetCurrentResourceName = function() return name end
    env.GetInvokingResource = function()
        local top = mock.invoking[#mock.invoking]
        if top and top.invoker and top.invoker ~= name and top.invoker ~= '<harness>' then return top.invoker end
        return nil
    end
    env.GetResourceState = function(res)
        local rr = mock.resources[res]
        return rr and rr.state or 'missing'
    end
    env.GetResourceMetadata = function(res, key, idx)
        local rr = mock.resources[res]
        if not rr then return nil end
        local list = rr.meta[SINGULAR[key] or key]
        return list and list[(idx or 0) + 1] or nil
    end
    env.LoadResourceFile = function(res, path) return mock:readResourceFile(res, path) end
    env.GetConvar = function(k, def)
        local v = mock.convars[k]
        if v == nil then return def end
        return v
    end
    env.SetConvar = function(k, v) mock.convars[k] = tostring(v) end
    env.StartResource = function(res)
        local ok = mock:start(res)
        return ok == true
    end
    env.GetGameTimer = function() return mock.clock end
    env.AddEventHandler = function(evName, fn)
        r.handlers[evName] = r.handlers[evName] or {}
        table.insert(r.handlers[evName], fn)
        return { name = evName, fn = fn }
    end
    env.RegisterNetEvent = function(evName, fn)
        if fn then return env.AddEventHandler(evName, fn) end
    end
    env.TriggerEvent = function(evName, ...) mock:triggerEvent(name, evName, ...) end
    env.TriggerClientEvent = function(evName, target, ...)
        mock.clientEvents[#mock.clientEvents + 1] = { name = evName, target = target, args = packMarshal(mock, name, ...) }
    end
    env.RegisterCommand = function(cmd, fn, restricted)
        mock.commands[cmd] = { fn = fn, owner = name, restricted = restricted }
    end
    env.IsPlayerAceAllowed = function(src, ace)
        return mock.aces[tostring(src) .. '|' .. ace] == true
    end
    env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
    env.Citizen = {
        CreateThread = function(fn) mock:createThread(name, fn) end,
        Wait = function(ms)
            if not coroutine.isyieldable() then error('Wait() called outside a thread', 2) end
            coroutine.yield(ms)
        end,
        SetTimeout = function(ms, fn)
            mock:createThread(name, function() coroutine.yield(ms); fn() end)
        end,
    }
    env.CreateThread = env.Citizen.CreateThread
    env.Wait = env.Citizen.Wait
    env.SetTimeout = env.Citizen.SetTimeout
    env.exports = setmetatable({}, {
        __call = function(_, exportName, fn) r.exports[exportName] = fn end,
        __index = function(_, target)
            return setmetatable({}, {
                __index = function(_, fnName)
                    return function(_, ...) return mock:callExport(name, target, fnName, ...) end
                end,
            })
        end,
    })
    return env
end

local function resolveScript(mock, r, entry)
    if entry:find('*', 1, true) then error('glob script paths are not supported by the mock: ' .. entry) end
    local other, rel = entry:match('^@([^/]+)/(.+)$')
    if other then
        local rr = mock.resources[other]
        if not rr then error(string.format('%s: included resource "%s" is not registered', r.name, other)) end
        return other, rel
    end
    return r.name, entry
end

-------------------------------------------------------------------------------
-- Start / stop
-------------------------------------------------------------------------------

function Mock:start(name)
    local r = self.resources[name]
    if not r then return false, 'resource ' .. name .. ' not found' end
    if r.state == 'started' then return true end
    for _, dep in ipairs(r.meta.dependency or {}) do
        local ok, err = self:start(dep)
        if not ok then return false, string.format('could not start dependency %s of %s: %s', dep, name, err) end
    end
    r.state = 'starting'
    r.handlers, r.exports = {}, {}
    r.env = self:buildEnv(r)
    local scripts = {}
    for _, s in ipairs(r.meta.shared_script or {}) do scripts[#scripts + 1] = s end
    for _, s in ipairs(r.meta.server_script or {}) do scripts[#scripts + 1] = s end
    for _, entry in ipairs(scripts) do
        local owner, rel = resolveScript(self, r, entry)
        local label = owner .. '/' .. rel
        local src = self:readResourceFile(owner, rel)
        if not src then
            r.state = 'stopped'
            return false, 'script not found: ' .. label
        end
        local chunk, err = load(src, '@' .. label, 't', r.env)
        if not chunk then
            r.state = 'stopped'
            return false, 'syntax error: ' .. err
        end
        table.insert(self.invoking, { invoker = nil, current = name })
        local ok, runErr = pcall(chunk)
        table.remove(self.invoking)
        if not ok then
            local msg = string.format('SCRIPT ERROR while loading %s: %s', label, tostring(runErr))
            self.scriptErrors[#self.scriptErrors + 1] = msg
            self:log(name, msg)
        end
    end
    r.state = 'started'
    self:triggerEvent(name, 'onResourceStart', name)
    self:triggerEvent(name, 'onServerResourceStart', name)
    return true
end

function Mock:stop(name)
    local r = self.resources[name]
    if not r or r.state ~= 'started' then return false end
    -- Stop resources that depend on this one first.
    for _, other in ipairs(self.cascadeStop and self.order or {}) do
        local o = self.resources[other]
        if o.state == 'started' then
            for _, dep in ipairs(o.meta.dependency or {}) do
                if dep == name then self:stop(other) end
            end
        end
    end
    r.state = 'stopping'
    self:triggerEvent(name, 'onResourceStop', name)
    self:triggerEvent(name, 'onServerResourceStop', name)
    r.state = 'stopped'
    r.handlers, r.exports = {}, {}
    for cmd, c in pairs(self.commands) do
        if c.owner == name then self.commands[cmd] = nil end
    end
    for i = #self.threads, 1, -1 do
        if self.threads[i].owner == name then table.remove(self.threads, i) end
    end
    return true
end

function Mock:restart(name)
    self:stop(name)
    return self:start(name)
end

--- Execute a console/player command line. Returns true if handled.
function Mock:command(source, line)
    local args = {}
    for word in line:gmatch('%S+') do args[#args + 1] = word end
    local cmdName = table.remove(args, 1)
    local cmd = self.commands[cmdName]
    if not cmd then return false end
    if cmd.restricted and source ~= 0 then return false end
    table.insert(self.invoking, { invoker = nil, current = cmd.owner })
    local ok, err = pcall(cmd.fn, source, args, line)
    table.remove(self.invoking)
    if not ok then
        local msg = string.format('SCRIPT ERROR in command %s: %s', cmdName, tostring(err))
        self.scriptErrors[#self.scriptErrors + 1] = msg
        self:log(cmd.owner, msg)
    end
    return true
end

--- Simulate txAdmin's scheduled-shutdown announcement.
function Mock:txAdminShutdown()
    self:triggerEvent('monitor', 'txAdmin:events:serverShuttingDown', { delay = 5000, author = 'test', message = 'test' })
end

return Mock
