-- Wasteland Core :: server/commands.lua
-- Administrative console command: `<shortName> <subcommand>` (default: wasteland).
-- The server console is always authorised; players need the configured ACE
-- (default "wasteland.admin"). Every invocation is logged.

WL = WL or {}
WL.Commands = WL.Commands or {}
local Commands = WL.Commands
local Lifecycle = WL.Lifecycle
local Registry = WL.Registry
local Logger = WL.Logger
local Util = WL.Util
local log = WL.Logger.new('admin')

local function adminAce()
    local cfg = Lifecycle.coreConfig
    return cfg and cfg.framework.adminAce or 'wasteland.admin'
end

function Commands.isAuthorized(source)
    if source == 0 then return true end
    local allowed = IsPlayerAceAllowed(tostring(source), adminAce())
    return allowed == true or allowed == 1
end

local function reply(source, lines)
    if type(lines) == 'string' then lines = { lines } end
    if source == 0 then
        for _, l in ipairs(lines) do print(l) end
    else
        TriggerClientEvent('wasteland:core:client:consoleOutput', source, lines)
    end
end

local function describeModule(name)
    local s = Registry.getStatus(name)
    if not s then return { string.format('No module named "%s".', tostring(name)) } end
    local lines = {
        string.format('module:      %s', s.name),
        string.format('version:     %s (api %s)', s.version, s.api),
        string.format('resource:    %s', tostring(s.resource)),
        string.format('state:       %s%s', s.state, s.reason and (' - ' .. s.reason) or ''),
        string.format('enabled:     %s', tostring(s.enabled)),
        string.format('config file: %s', s.configFile or '(none)'),
    }
    local deps = {}
    for _, k in ipairs(Util.sortedKeys(s.dependencies)) do deps[#deps + 1] = k .. ' ' .. s.dependencies[k] end
    lines[#lines + 1] = 'requires:    ' .. (#deps > 0 and table.concat(deps, ', ') or '(nothing)')
    local opt = {}
    for _, k in ipairs(Util.sortedKeys(s.optionalDependencies)) do opt[#opt + 1] = k .. ' ' .. s.optionalDependencies[k] end
    if #opt > 0 then lines[#lines + 1] = 'optional:    ' .. table.concat(opt, ', ') end
    for _, w in ipairs(s.configWarnings) do lines[#lines + 1] = 'config warning: ' .. w end
    return lines
end

local function validationLines(report)
    local lines = {}
    for _, f in ipairs(report.files) do
        lines[#lines + 1] = string.format('[%s] %s', f.ok and ' OK ' or 'FAIL', f.label)
        for _, e in ipairs(f.errors) do lines[#lines + 1] = '    error: ' .. e end
        for _, w in ipairs(f.warnings) do lines[#lines + 1] = '    warning: ' .. w end
    end
    lines[#lines + 1] = report.ok and 'All configuration files are valid.' or 'Configuration has errors.'
    return lines
end

local HELP = {
    'usage: %s <subcommand>',
    '  status                 framework and module status',
    '  module <name>          details for one module',
    '  config validate        validate all config files (does not apply)',
    '  config reload          retry startup after fixing config errors',
    '  issues [count]         recent warnings and errors',
    '  version                framework version',
}

--- Execute a subcommand. Returns the reply lines (also used by tests).
function Commands.execute(source, args)
    local cmdName = Lifecycle.getInfo().shortName
    if not Commands.isAuthorized(source) then
        log:warn('denied admin command "%s %s" for player %s (missing ACE %s)',
            cmdName, table.concat(args, ' '), tostring(source), adminAce())
        return { 'You are not authorised to use this command.' }
    end
    log:info('admin command "%s %s" by %s', cmdName, table.concat(args, ' '),
        source == 0 and 'console' or ('player ' .. tostring(source)))
    local sub = args[1] and args[1]:lower() or 'help'
    if sub == 'status' or sub == 'modules' then
        return Lifecycle.statusLines()
    elseif sub == 'module' then
        return describeModule(args[2])
    elseif sub == 'config' then
        local action = args[2] and args[2]:lower()
        if action == 'validate' then
            return validationLines(Lifecycle.validateAll())
        elseif action == 'reload' then
            local ok, msg = Lifecycle.reloadConfig()
            return { (ok and 'OK: ' or 'FAILED: ') .. msg }
        end
        return { 'usage: ' .. cmdName .. ' config <validate|reload>' }
    elseif sub == 'issues' then
        local recent = Logger.getRecent(tonumber(args[2]) or 20)
        if #recent == 0 then return { 'No warnings or errors recorded.' } end
        local lines = {}
        for _, r in ipairs(recent) do
            lines[#lines + 1] = string.format('%s %-5s [%s]%s %s', r.time, r.level:upper(), r.module,
                r.source and (' (' .. r.source .. ')') or '', r.message)
        end
        return lines
    elseif sub == 'version' then
        local info = Lifecycle.getInfo()
        return { string.format('%s v%s (api %s)', info.name, info.version, info.api) }
    end
    local lines = {}
    for i, l in ipairs(HELP) do lines[i] = i == 1 and string.format(l, cmdName) or l end
    return lines
end

function Commands.register(name)
    Commands.name = name
    -- restricted = false: we perform our own ACE check so the console and
    -- the configured ACE both work, and denied attempts are logged.
    RegisterCommand(name, function(source, args)
        reply(source, Commands.execute(source, args))
    end, false)
end

return Commands
