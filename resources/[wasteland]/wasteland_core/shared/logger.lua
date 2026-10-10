-- Wasteland Core :: shared/logger.lua
-- Levelled, per-module logging. Warnings and errors are kept in a bounded
-- in-memory ring buffer so diagnostics can show recent problems.
-- Nothing is ever swallowed: callers that catch errors must log them.

WL = WL or {}
WL.Logger = WL.Logger or {}
local Logger = WL.Logger

Logger.LEVELS = { debug = 10, info = 20, warn = 30, error = 40, off = 100 }
Logger.LEVEL_NAMES = { 'debug', 'info', 'warn', 'error' }

local COLORS = { debug = '^6', info = '^7', warn = '^3', error = '^1' }
local LABELS = { debug = 'DEBUG', info = 'INFO ', warn = 'WARN ', error = 'ERROR' }

-- Settings are replaced by Logger.configure() once config is loaded. The
-- defaults apply to messages emitted before configuration (early boot).
Logger.settings = Logger.settings or {
    level = 'info',
    moduleLevels = {},
    colors = true,
    recentBufferSize = 200,
    prefix = 'Wasteland',
}
Logger.recent = Logger.recent or {}
Logger.listeners = Logger.listeners or {}
Logger.sink = Logger.sink or function(line) print(line) end

function Logger.configure(settings)
    for k, v in pairs(settings or {}) do Logger.settings[k] = v end
    Logger.trimRecent()
end

function Logger.trimRecent()
    local max = Logger.settings.recentBufferSize or 200
    while #Logger.recent > max do table.remove(Logger.recent, 1) end
end

function Logger.isEnabled(module, level)
    local threshold = Logger.settings.moduleLevels and Logger.settings.moduleLevels[module]
        or Logger.settings.level or 'info'
    return (Logger.LEVELS[level] or 0) >= (Logger.LEVELS[threshold] or 20)
end

local function now()
    if type(os) == 'table' and os.date then
        local ok, s = pcall(os.date, '%H:%M:%S')
        if ok then return s end
    end
    return ''
end

local function render(fmt, ...)
    if select('#', ...) == 0 then return tostring(fmt) end
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    if ok then return msg end
    -- A bad format string is a programming error; still show everything.
    local parts = { tostring(fmt) }
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    return table.concat(parts, ' ') .. ' [log format error: ' .. tostring(msg) .. ']'
end

--- Emit a record. `source` is an optional resource name for forwarded logs.
function Logger.write(module, level, message, source)
    if not Logger.LEVELS[level] or level == 'off' then level = 'info' end
    local record = {
        time = now(),
        module = module,
        level = level,
        message = message,
        source = source,
    }
    if Logger.LEVELS[level] >= Logger.LEVELS.warn then
        Logger.recent[#Logger.recent + 1] = record
        Logger.trimRecent()
    end
    for _, listener in ipairs(Logger.listeners) do
        local ok, err = pcall(listener, record)
        if not ok then
            Logger.sink('[Wasteland] [ERROR] [logger] log listener failed: ' .. tostring(err))
        end
    end
    if not Logger.isEnabled(module, level) then return record end
    local s = Logger.settings
    local line = string.format('[%s] [%s] [%s] %s', s.prefix or 'Wasteland', LABELS[level], module, message)
    if s.colors then line = COLORS[level] .. line .. '^7' end
    Logger.sink(line)
    return record
end

function Logger.addListener(fn)
    Logger.listeners[#Logger.listeners + 1] = fn
end

--- Returns a copy of recent warning/error records (oldest first).
function Logger.getRecent(limit)
    local out = {}
    local start = 1
    if limit and #Logger.recent > limit then start = #Logger.recent - limit + 1 end
    for i = start, #Logger.recent do
        local r = Logger.recent[i]
        out[#out + 1] = { time = r.time, module = r.module, level = r.level, message = r.message, source = r.source }
    end
    return out
end

local LoggerMT = {}
LoggerMT.__index = LoggerMT

for _, level in ipairs(Logger.LEVEL_NAMES) do
    LoggerMT[level] = function(self, fmt, ...)
        if level == 'debug' and not Logger.isEnabled(self.module, 'debug') then return end
        return Logger.write(self.module, level, render(fmt, ...))
    end
end

--- Create a logger bound to a module/subsystem name.
function Logger.new(module)
    return setmetatable({ module = module }, LoggerMT)
end

return Logger
