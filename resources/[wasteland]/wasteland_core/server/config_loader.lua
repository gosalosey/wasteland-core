-- Wasteland Core :: server/config_loader.lua
-- Loads configuration files from the configuration resource
-- (default: wasteland_config/config/*.lua), executes them in a restricted
-- sandbox and validates them against declarative schemas.
--
-- Config files are plain Lua that `return { ... }`. They cannot access the
-- filesystem, OS, natives or other resources; only pure helpers are exposed.

WL = WL or {}
WL.Config = WL.Config or {}
local Config = WL.Config
local Util = WL.Util
local Schema = WL.Schema

Config.CONFIG_DIR = 'config/'
Config.FILE_PATTERN = '^[%w_%-]+%.lua$'

function Config.getConfigResource()
    local name = GetConvar('wasteland_config_resource', 'wasteland_config')
    if name == nil or name == '' then name = 'wasteland_config' end
    return name
end

local function sandboxEnv()
    local env = {
        math = math, string = string, table = table,
        pairs = pairs, ipairs = ipairs, next = next, select = select,
        type = type, tostring = tostring, tonumber = tonumber,
        error = error, assert = assert,
        unpack = table.unpack,
    }
    -- FiveM vector constructors, when available (used for coordinates).
    if vector3 then env.vector3 = vector3; env.vec3 = vector3 end
    if vector2 then env.vector2 = vector2; env.vec2 = vector2 end
    if vector4 then env.vector4 = vector4; env.vec4 = vector4 end
    return env
end

--- Read and execute a config file.
--- Returns: table | nil, errorMessage | nil, missing(boolean)
function Config.loadFile(fileName, resource)
    resource = resource or Config.getConfigResource()
    local label = string.format('%s/%s%s', resource, Config.CONFIG_DIR, tostring(fileName))
    if type(fileName) ~= 'string' or not fileName:match(Config.FILE_PATTERN) then
        return nil, string.format('%s: invalid config file name (expected letters, digits, "_" or "-" ending in .lua)', label), false
    end
    if GetResourceState(resource) == 'missing' then
        return nil, string.format('%s: configuration resource "%s" is not installed (set convar wasteland_config_resource or install it)', label, resource), true
    end
    local source = LoadResourceFile(resource, Config.CONFIG_DIR .. fileName)
    if source == nil then
        return nil, string.format('%s: file not found', label), true
    end
    local chunk, syntaxErr = load(source, '@' .. label, 't', sandboxEnv())
    if not chunk then
        return nil, string.format('%s: syntax error: %s', label, tostring(syntaxErr)), false
    end
    local ok, result = pcall(chunk)
    if not ok then
        return nil, string.format('%s: error while evaluating file: %s', label, tostring(result)), false
    end
    if type(result) ~= 'table' then
        return nil, string.format('%s: file must `return { ... }` (a table), but returned %s', label, type(result)), false
    end
    return result, nil, false
end

--- Load + validate. `opts.optional` = true allows a missing file (defaults used).
--- Returns a report:
---   { ok, file, label, config, errors = {string}, warnings = {string}, missing }
function Config.loadValidated(fileName, schema, opts)
    opts = opts or {}
    local resource = opts.resource or Config.getConfigResource()
    local label = string.format('%s/%s%s', resource, Config.CONFIG_DIR, tostring(fileName))
    local report = { ok = false, file = fileName, label = label, errors = {}, warnings = {}, missing = false }

    local raw, err, missing = Config.loadFile(fileName, resource)
    if not raw then
        report.missing = missing
        if missing and opts.optional then
            raw = {}
            report.warnings[#report.warnings + 1] = label .. ': file not found; using built-in defaults'
        else
            report.errors[#report.errors + 1] = err
            return report
        end
    end

    local value, errors, warnings = Schema.validate(schema, raw)
    for _, line in ipairs(Schema.formatIssues(errors, label)) do report.errors[#report.errors + 1] = line end
    for _, line in ipairs(Schema.formatIssues(warnings, label)) do report.warnings[#report.warnings + 1] = line end
    report.ok = #report.errors == 0
    if report.ok then report.config = value end
    return report
end

-------------------------------------------------------------------------------
-- Core configuration schemas
-------------------------------------------------------------------------------

Config.CORE_FILES = {
    framework = 'framework.lua',
    modules = 'modules.lua',
    logging = 'logging.lua',
}

local LEVEL_ENUM = { type = 'enum', values = { 'debug', 'info', 'warn', 'error', 'off' } }

Config.CORE_SCHEMAS = {
    framework = {
        type = 'table',
        fields = {
            name = { type = 'string', default = 'Wasteland Core', minLength = 1, maxLength = 64,
                description = 'Display name of the framework (shown in logs, UI and diagnostics).' },
            shortName = { type = 'string', default = 'wasteland', pattern = '^[a-z][a-z0-9_]*$', maxLength = 32,
                description = 'Lowercase identifier used for the admin command and ACE names.' },
            startupTimeoutSeconds = { type = 'integer', default = 30, min = 1, max = 600,
                description = 'Seconds to wait for enabled modules to register before reporting them as missing.' },
            adminAce = { type = 'string', default = 'wasteland.admin', minLength = 1,
                description = 'ACE permission required for administrative commands.' },
            shutdownOnTxAdminRestart = { type = 'boolean', default = true,
                description = 'Run the ordered module shutdown when txAdmin announces a server shutdown.' },
            restartModulesAfterCoreRestart = { type = 'boolean', default = true,
                description = 'Start module resources again after FiveM stopped them because a resource they depend on (the core or another module) restarted.' },
            updateCheck = {
                type = 'table',
                description = 'Checks GitHub for Wasteland Core updates and tells the console (and admins in chat).',
                fields = {
                    enabled = { type = 'boolean', default = true, description = 'Check for updates after start and every few hours.' },
                    repo = { type = 'string', default = 'gosalosey/wasteland-core', pattern = '^[%w%-_%.]+/[%w%-_%.]+$',
                        description = 'GitHub repository (owner/name).' },
                    branch = { type = 'string', default = 'main', pattern = '^[%w%-_%./]+$', description = 'Branch to compare with.' },
                    everyHours = { type = 'number', default = 6, min = 1, max = 168, description = 'Hours between checks.' },
                },
            },
            security = {
                type = 'table',
                description = 'Handling of rejected client requests (net-event guard).',
                fields = {
                    kickAfterViolations = { type = 'integer', default = 0, min = 0, max = 1000,
                        description = 'Kick a player after this many rejected requests within the window (0 = never kick, only log).' },
                    violationWindowSeconds = { type = 'integer', default = 60, min = 1, max = 3600,
                        description = 'Window for counting rejected requests.' },
                },
            },
        },
    },
    modules = {
        type = 'table',
        fields = {
            enabled = {
                type = 'map', default = {},
                keys = { type = 'string', pattern = '^[a-z][a-z0-9_]*$' },
                values = { type = 'boolean' },
                description = 'Per-module switches: moduleName = true|false.',
            },
            unlisted = { type = 'enum', values = { 'enable', 'disable' }, default = 'enable',
                description = 'What to do with a module that registers but is not listed in `enabled`.' },
        },
    },
    logging = {
        type = 'table',
        fields = {
            level = { type = 'enum', values = LEVEL_ENUM.values, default = 'info',
                description = 'Minimum level printed to the console.' },
            moduleLevels = { type = 'map', default = {}, values = LEVEL_ENUM,
                description = 'Per-module overrides, e.g. { registry = "debug" }.' },
            colors = { type = 'boolean', default = true, description = 'Use FiveM console colour codes.' },
            recentBufferSize = { type = 'integer', default = 200, min = 10, max = 5000,
                description = 'How many recent warnings/errors to keep for diagnostics.' },
        },
    },
}

--- Load all core config files. Returns { ok, configs = {framework=...}, reports = {...} }
function Config.loadCore()
    local result = { ok = true, configs = {}, reports = {} }
    for _, key in ipairs({ 'logging', 'framework', 'modules' }) do
        local report = Config.loadValidated(Config.CORE_FILES[key], Config.CORE_SCHEMAS[key], { optional = false })
        result.reports[key] = report
        if report.ok then
            result.configs[key] = report.config
        else
            result.ok = false
        end
    end
    return result
end

return Config
