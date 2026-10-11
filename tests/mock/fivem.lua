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
--   * promises and Citizen.Await (a waiting thread is parked until settled)
--   * players: connecting (with deferrals), joining, dropping, identifiers,
--     player state bags (which survive resource restarts), ped coordinates
--   * client -> server net events (only events registered with
--     RegisterNetEvent are reachable; `source` is set for the handler)
--   * a `json` global (encode/decode)
--
-- What it does NOT model (must be verified on a real server): networking,
-- clients, natives other than those listed, real timing, msgpack edge cases.

local Mock = {}
Mock.__index = Mock
Mock.json = require('lib.json')

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
    self.players = {}       -- [serverId] = { id, name, identifiers, state, coords, heading }
    self.nextPlayerId = 1
    self.nextTempId = 65536
    self.dropped = {}       -- { id, reason }
    self.connections = {}   -- connection attempts (see connectPlayer)
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
--- `globals` (optional) are injected into the resource environment; tests
--- use this to hand a fake driver its backing store.
function Mock:addVirtualResource(name, meta, files, globals)
    self.resources[name] = {
        name = name, path = nil, meta = meta, state = 'stopped',
        handlers = {}, exports = {}, virtual = files or {}, globals = globals,
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
    local pseudo = ref.owner:sub(1, 1) == '<' -- harness / simulated client, always alive
    if not pseudo and (not owner or (owner.state ~= 'started' and owner.state ~= 'starting' and owner.state ~= 'stopping')) then
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
    return self:dispatchEvent(sender, nil, false, name, ...)
end

--- Dispatch an event. `src` becomes the handler's global `source`;
--- `netOnly` restricts delivery to resources that called RegisterNetEvent.
function Mock:dispatchEvent(sender, src, netOnly, name, ...)
    local args = table.pack(...)
    for _, resName in ipairs(self.order) do
        local r = self.resources[resName]
        if (r.state == 'started' or r.state == 'starting' or r.state == 'stopping')
            and (not netOnly or (r.netEvents and r.netEvents[name])) then
            local handlers = r.handlers[name]
            if handlers then
                for _, h in ipairs({ table.unpack(handlers) }) do
                    local copy = packMarshal(self, sender, table.unpack(args, 1, args.n))
                    local ok, err = pcall(function()
                        local env = r.env
                        local prevSource = env and env.source
                        if env then env.source = src end
                        local res = table.pack(pcall(self.withInvocation, self, sender, resName, h, table.unpack(copy, 1, copy.n)))
                        if env then env.source = prevSource end
                        if not res[1] then error(res[2], 0) end
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
        if nextT.owner == '<mock>' or (r and (r.state == 'started' or r.state == 'starting')) then
            if nextT.wake > self.clock then self.clock = nextT.wake end
            table.insert(self.invoking, { invoker = nil, current = nextT.owner })
            local ok, waitMs = coroutine.resume(nextT.co)
            table.remove(self.invoking)
            if not ok then
                local msg = string.format('SCRIPT ERROR in %s thread: %s', nextT.owner, tostring(waitMs))
                self.scriptErrors[#self.scriptErrors + 1] = msg
                self:log(nextT.owner, msg)
            elseif coroutine.status(nextT.co) ~= 'dead' then
                if type(waitMs) == 'table' and waitMs.__await then
                    -- Citizen.Await: park until the promise settles.
                    local p = waitMs.__await
                    if p.state ~= 'pending' then
                        nextT.wake = self.clock
                        self.threads[#self.threads + 1] = nextT
                    else
                        p.waiters[#p.waiters + 1] = nextT
                    end
                else
                    nextT.wake = self.clock + math.max(0, tonumber(waitMs) or 0)
                    self.threads[#self.threads + 1] = nextT
                end
            end
        end
    end
    self.clock = target
end

--- Run a function on the virtual clock outside any resource.
function Mock:schedule(ms, fn)
    self:createThread('<mock>', function()
        if ms and ms > 0 then coroutine.yield(ms) end
        fn()
    end)
end

-------------------------------------------------------------------------------
-- Promises (FiveM's `promise` global + Citizen.Await)
-------------------------------------------------------------------------------

function Mock:newPromise()
    local mock = self
    local p = { state = 'pending', waiters = {} }
    local function settle(state, value)
        if p.state ~= 'pending' then return end
        p.state, p.value = state, value
        for _, t in ipairs(p.waiters) do
            t.wake = mock.clock
            mock.threads[#mock.threads + 1] = t
        end
        p.waiters = {}
    end
    function p.resolve(_, value) settle('resolved', value) end
    function p.reject(_, value) settle('rejected', value) end
    return p
end

local function await(p)
    if p.state == 'pending' then
        if not coroutine.isyieldable() then error('Citizen.Await() called outside a thread', 2) end
        coroutine.yield({ __await = p })
    end
    if p.state == 'rejected' then error(p.value, 0) end
    return p.value
end

-------------------------------------------------------------------------------
-- Players
-------------------------------------------------------------------------------

local function playerKey(src) return tonumber(src) end

function Mock:getPlayer(src, includeConnecting)
    local p = self.players[playerKey(src) or -1]
    if p and (includeConnecting or not p.connecting) then return p end
    return nil
end

--- Start a connection. opts = { name, license, identifiers = {..} }.
--- Returns a connection record: { tempId, deferred, done, rejected, updates }.
--- Advance the clock until `done`, then call joinPlayer(conn).
function Mock:connectPlayer(opts)
    opts = opts or {}
    local tempId = self.nextTempId
    self.nextTempId = self.nextTempId + 1
    local identifiers = {}
    if opts.license ~= false then identifiers[#identifiers + 1] = 'license:' .. (opts.license or ('lic' .. tempId)) end
    for _, id in ipairs(opts.identifiers or {}) do identifiers[#identifiers + 1] = id end
    self.players[tempId] = {
        id = tempId, name = opts.name or ('Player' .. tempId), identifiers = identifiers,
        connecting = true, state = {}, coords = opts.coords, heading = opts.heading or 0.0,
    }
    local conn = { tempId = tempId, name = self.players[tempId].name, deferred = false, done = false, updates = {} }
    local deferrals = {
        defer = function() conn.deferred = true end,
        update = function(msg) conn.updates[#conn.updates + 1] = msg end,
        presentCard = function() end,
        handover = function() end,
        -- FiveM accepts only done() with NO argument. Any argument rejects;
        -- a non-string one (even an explicit nil) shows "Unknown error"
        -- (runtime finding R2.5, 2026-10-10).
        done = function(...)
            if conn.done then return end
            conn.done = true
            if select('#', ...) > 0 then
                local reason = ...
                conn.rejected = type(reason) == 'string' and reason or 'Unknown error'
            end
        end,
    }
    local kick = function(reason) conn.done = true; conn.rejected = reason end
    self.connections[#self.connections + 1] = conn
    self:dispatchEvent('<client>', tempId, false, 'playerConnecting', conn.name, kick, deferrals)
    if not conn.deferred and not conn.done then conn.done = true end
    return conn
end

--- Complete a successful connection: assigns the permanent server id and
--- fires playerJoining. Returns the new server id.
function Mock:joinPlayer(conn)
    assert(conn.done and not conn.rejected, 'connection was not accepted: ' .. tostring(conn.rejected))
    local rec = self.players[conn.tempId]
    self.players[conn.tempId] = nil
    local id = self.nextPlayerId
    self.nextPlayerId = self.nextPlayerId + 1
    rec.id, rec.connecting = id, false
    self.players[id] = rec
    conn.id = id
    self:dispatchEvent('<client>', id, false, 'playerJoining', tostring(conn.tempId))
    return id
end

--- Connect, wait (virtual time) for the deferral, and join.
--- Returns id or nil, rejection reason, conn.
function Mock:connectAndJoin(opts, maxWaitMs)
    local conn = self:connectPlayer(opts)
    local waited = 0
    while not conn.done and waited < (maxWaitMs or 60000) do
        self:advance(50)
        waited = waited + 50
    end
    if not conn.done then return nil, 'connection still pending', conn end
    if conn.rejected then
        self.players[conn.tempId] = nil
        return nil, conn.rejected, conn
    end
    return self:joinPlayer(conn), nil, conn
end

--- A player leaves (immediately fires playerDropped).
function Mock:dropPlayer(id, reason)
    local rec = self.players[id]
    if not rec then return false end
    self.players[id] = nil
    self.dropped[#self.dropped + 1] = { id = id, reason = reason }
    self:dispatchEvent('<client>', id, false, 'playerDropped', reason or 'Exiting')
    return true
end

--- A client sends a net event to the server.
function Mock:clientEvent(id, name, ...)
    self:dispatchEvent('<client>', id, true, name, ...)
end

--- Client events sent to a player (optionally filtered by name).
function Mock:clientEventsFor(id, name)
    local out = {}
    for _, e in ipairs(self.clientEvents) do
        if (e.target == id or e.target == -1) and (not name or e.name == name) then out[#out + 1] = e end
    end
    return out
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
    env.SetRoutingBucketPopulationEnabled = function(bucket, enabled)
        mock.population = mock.population or {}
        mock.population[bucket] = enabled
    end
    env.GetNumResourceMetadata = function(res, key)
        local rr = mock.resources[res]
        if not rr then return 0 end
        local list = rr.meta[SINGULAR[key] or key]
        return list and #list or 0
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
        r.netEvents = r.netEvents or {}
        r.netEvents[evName] = true
        if fn then return env.AddEventHandler(evName, fn) end
    end
    env.RegisterServerEvent = env.RegisterNetEvent
    env.json = mock.json
    env.promise = { new = function() return mock:newPromise() end }

    -- Players
    env.GetPlayers = function()
        local ids = {}
        for id, p in pairs(mock.players) do
            if not p.connecting then ids[#ids + 1] = id end
        end
        table.sort(ids)
        local out = {}
        for i, id in ipairs(ids) do out[i] = tostring(id) end
        return out
    end
    env.GetPlayerName = function(src)
        local p = mock:getPlayer(src, true)
        return p and p.name or nil
    end
    env.GetPlayerIdentifiers = function(src)
        local p = mock:getPlayer(src, true)
        if not p then return {} end
        local out = {}
        for i, v in ipairs(p.identifiers) do out[i] = v end
        return out
    end
    env.GetPlayerIdentifierByType = function(src, idType)
        local p = mock:getPlayer(src, true)
        if not p then return nil end
        for _, v in ipairs(p.identifiers) do
            if v:sub(1, #idType + 1) == idType .. ':' then return v end
        end
        return nil
    end
    env.GetPlayerPing = function(src) return mock:getPlayer(src) and 42 or 0 end
    env.DropPlayer = function(src, reason)
        local id = tonumber(src)
        mock:schedule(0, function() mock:dropPlayer(id, reason) end)
    end
    env.GetPlayerPed = function(src)
        local p = mock:getPlayer(src)
        if not p or not p.coords then return 0 end
        return p.id * 100
    end
    env.DoesEntityExist = function(ent)
        return mock:getPlayer(math.floor((tonumber(ent) or 0) / 100)) ~= nil
    end
    env.GetEntityCoords = function(ent)
        local p = mock:getPlayer(math.floor((tonumber(ent) or 0) / 100))
        local c = p and p.coords or { x = 0.0, y = 0.0, z = 0.0 }
        return { x = c.x, y = c.y, z = c.z }
    end
    env.GetEntityHeading = function(ent)
        local p = mock:getPlayer(math.floor((tonumber(ent) or 0) / 100))
        return p and p.heading or 0.0
    end
    env.Player = function(src)
        local p = mock:getPlayer(src, true)
        local bag = p and p.state or {}
        local state = setmetatable({}, {
            __index = function(_, k)
                if k == 'set' then
                    return function(_, key, value) bag[key] = value end
                end
                return bag[k]
            end,
            __newindex = function(_, k, v) bag[k] = v end,
        })
        return { state = state }
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
        Await = await,
    }
    for k, v in pairs(r.globals or {}) do env[k] = v end
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
    r.handlers, r.exports, r.netEvents = {}, {}, {}
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
    r.handlers, r.exports, r.netEvents = {}, {}, {}
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
