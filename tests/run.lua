-- tests/run.lua — Wasteland Core automated test runner
-- Usage (from the repository root):   lua5.4 tests/run.lua [filter]
-- Requires a standalone Lua 5.4 interpreter. No FiveM server is needed:
-- tests use tests/mock/fivem.lua (a simulated server runtime). Passing here
-- is NOT the same as passing on a live server; see docs/TESTING.md.

local scriptPath = arg and arg[0] or 'tests/run.lua'
local ROOT = scriptPath:gsub('[/\\]?tests[/\\]run%.lua$', '')
if ROOT == '' or ROOT == scriptPath then ROOT = '.' end
package.path = ROOT .. '/tests/?.lua;' .. package.path

local H = require('lib.harness')
local Mock = require('mock.fivem')

_G.ROOT = ROOT
_G.RESOURCES = ROOT .. '/resources/[wasteland]'
_G.describe, _G.it, _G.expect, _G.skip = H.describe, H.it, H.expect, H.skip
_G.Mock = Mock

--- Load core shared/server files into an isolated environment (unit tests).
--- `stubs` adds/overrides globals (e.g. LoadResourceFile).
function _G.loadCoreFiles(files, stubs)
    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.WL = nil
    env.GetConvar = function(_, def) return def end
    env.GetGameTimer = function() return 0 end
    env.GetResourceState = function() return 'started' end
    env.TriggerEvent = function() end
    env.print = function() end
    for k, v in pairs(stubs or {}) do env[k] = v end
    for _, rel in ipairs(files) do
        local path = RESOURCES .. '/wasteland_core/' .. rel
        local chunk = assert(loadfile(path, 't', env))
        chunk()
    end
    return env
end

local MemoryDB = require('lib.memorydb')
_G.MemoryDB = MemoryDB
local FAKE_OXMYSQL = require('lib.fake_oxmysql')

--- Create a simulated server with the framework resources registered.
--- opts.fixtures = { 'name', ... } adds tests/fixtures/<name> resources.
--- A simulated `oxmysql` resource is always registered (not started);
--- server.db controls it (see tests/lib/fake_oxmysql.lua) and
--- server.db.backend is a MemoryDB unless opts.dbBackend is given.
function _G.newServer(opts)
    opts = opts or {}
    local server = Mock.new(opts)
    server:addResource('wasteland_config', RESOURCES .. '/wasteland_config')
    server:addResource('wasteland_core', RESOURCES .. '/wasteland_core')
    server:addResource('wasteland_template', RESOURCES .. '/wasteland_template')
    server:addResource('wasteland_database', RESOURCES .. '/wasteland_database')
    server:addResource('wasteland_players', RESOURCES .. '/wasteland_players')
    server:addResource('wasteland_ui', RESOURCES .. '/wasteland_ui')
    server:addResource('wasteland_appearance', RESOURCES .. '/wasteland_appearance')
    server:addResource('wasteland_inventory', RESOURCES .. '/wasteland_inventory')
    server:addResource('wasteland_survival', RESOURCES .. '/wasteland_survival')
    server:addResource('wasteland_world', RESOURCES .. '/wasteland_world')
    server:addResource('wasteland_admin', RESOURCES .. '/wasteland_admin')
    server:addResource('wasteland_weapons', RESOURCES .. '/wasteland_weapons')
    server:addResource('wasteland_images', RESOURCES .. '/wasteland_images')
    server:addResource('wasteland_zombies', RESOURCES .. '/wasteland_zombies')
    server:addResource('wasteland_loot', RESOURCES .. '/wasteland_loot')
    server:addResource('wasteland_camps', RESOURCES .. '/wasteland_camps')
    server:addResource('wasteland_crafting', RESOURCES .. '/wasteland_crafting')
    server:addResource('wasteland_quests', RESOURCES .. '/wasteland_quests')
    server:addResource('wasteland_vehicles', RESOURCES .. '/wasteland_vehicles')
    server:addResource('wasteland_tailor', RESOURCES .. '/wasteland_tailor')
    server:addResource('wasteland_supplydrops', RESOURCES .. '/wasteland_supplydrops')
    server:addResource('wasteland_events', RESOURCES .. '/wasteland_events')
    server:addResource('wasteland_groups', RESOURCES .. '/wasteland_groups')
    server:addResource('wasteland_trade', RESOURCES .. '/wasteland_trade')
    server:addResource('wasteland_bases', RESOURCES .. '/wasteland_bases')
    server.db = {
        backend = opts.dbBackend or MemoryDB.new(RESOURCES),
        connected = opts.dbConnected ~= false,
        hang = false,
        latencyMs = 5,
        calls = {},
    }
    server:addVirtualResource('oxmysql', {
        fx_version = { 'cerulean' }, game = { 'gta5' }, lua54 = { 'yes' },
        server_script = { 'server.lua' },
    }, { ['server.lua'] = FAKE_OXMYSQL }, { FAKEDB = server.db })
    for _, fx in ipairs(opts.fixtures or {}) do
        server:addResource(fx, ROOT .. '/tests/fixtures/' .. fx)
    end
    -- Older tests were written for fixed 6 x 4 pockets and the old backpack
    -- sizes; they keep them unless a test asks for the shipped ones
    -- (pockets that grow with what is worn).
    if not opts.shippedPockets and not (opts.config and opts.config['inventory.lua']) then
        local f = assert(io.open(RESOURCES .. '/wasteland_config/config/inventory.lua', 'r'))
        local text = f:read('a')
        f:close()
        local a = text:find('\n    pockets = {', 1, true)
        local b = a and text:find('\n    },\n', a, true)
        if a and b then
            text = text:sub(1, a) .. '    pockets = { width = 6, height = 4, maxWeight = 35.0 },\n' .. text:sub(b + 8)
            text = text:gsub('container = { width = 10, height = 10, maxWeight = 100 }', 'container = { width = 5, height = 4, maxWeight = 35 }')
            text = text:gsub('container = { width = 15, height = 15, maxWeight = 175 }', 'container = { width = 7, height = 6, maxWeight = 60 }')
            server:setFile('wasteland_config', 'config/inventory.lua', text)
        end
    end
    for file, contents in pairs(opts.config or {}) do
        server:setFile('wasteland_config', 'config/' .. file, contents)
    end
    return server
end

--- Add an in-memory module resource that uses the real SDK.
--- `body` is Lua source run after a preamble providing:
---   track(x)     append x to the resource's CALLS list
---   exports Calls() -> CALLS   (read from tests with server:export(name, 'Calls'))
--- `extraScripts` are inserted after the SDK (e.g. '@wasteland_database/lib/db.lua').
function _G.addModule(server, resName, body, extraDeps, extraScripts)
    local deps = { 'wasteland_core' }
    for _, d in ipairs(extraDeps or {}) do deps[#deps + 1] = d end
    local preamble = 'CALLS = {}\n'
        .. 'function track(x) CALLS[#CALLS + 1] = x end\n'
        .. "exports('Calls', function() return CALLS end)\n"
    local scripts = { '@wasteland_core/sdk/module.lua' }
    for _, s in ipairs(extraScripts or {}) do scripts[#scripts + 1] = s end
    scripts[#scripts + 1] = 'main.lua'
    server:addVirtualResource(resName, {
        fx_version = { 'cerulean' }, game = { 'gta5' }, lua54 = { 'yes' },
        dependency = deps,
        server_script = scripts,
    }, { ['main.lua'] = preamble .. body })
end

--- Start the simulated driver and the given resources, then let them boot.
function _G.boot(server, resources, ms)
    server:start('oxmysql')
    for _, r in ipairs(resources) do server:start(r) end
    server:advance(ms or 3000)
end

--- Map of module name -> state from the live core.
function _G.states(server)
    local out = {}
    for _, s in ipairs(server:export('wasteland_core', 'GetModuleStatuses')) do out[s.name] = s.state end
    return out
end

local suites = dofile(ROOT .. '/tests/suites.lua')
local filter = arg and arg[1]

print('Wasteland Core test suite (' .. _VERSION .. ')')
for _, suite in ipairs(suites) do
    if not filter or suite:find(filter, 1, true) then
        print('')
        print('== ' .. suite)
        local chunk, err = loadfile(ROOT .. '/tests/' .. suite)
        if not chunk then
            H.it('load ' .. suite, function() error(err) end)
        else
            local ok, runErr = pcall(chunk)
            if not ok then H.it('run ' .. suite, function() error(runErr) end) end
        end
    end
end

local ok = H.summary()
os.exit(ok and 0 or 1)
