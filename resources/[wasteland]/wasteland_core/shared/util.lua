-- Wasteland Core :: shared/util.lua
-- Small, dependency-free helpers shared by every part of the core.
-- Loaded first; creates the resource-local WL namespace.

WL = WL or {}
WL.Util = WL.Util or {}
local Util = WL.Util

--- Deep copy a value. Functions and other non-table values are returned as-is.
--- Cycles are preserved.
function Util.deepCopy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[Util.deepCopy(k, seen)] = Util.deepCopy(v, seen)
    end
    return copy
end

--- Return a sorted array of a table's keys (string keys sort before numbers
--- are compared as strings so mixed tables still sort deterministically).
function Util.sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == 'number' or ta == 'string' then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

--- True when t is a sequence 1..n with no other keys. Empty tables count as arrays.
function Util.isArray(t)
    if type(t) ~= 'table' then return false end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

function Util.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Util.contains(array, value)
    for i = 1, #array do
        if array[i] == value then return true end
    end
    return false
end

--- Human-readable, deterministic, single-line representation used in
--- error messages and logs. Depth-limited so huge tables do not flood logs.
function Util.inspect(value, depth)
    depth = depth or 2
    local tv = type(value)
    if tv == 'string' then
        return string.format('%q', value)
    elseif tv ~= 'table' then
        return tostring(value)
    end
    if depth <= 0 then return '{...}' end
    local parts = {}
    if Util.isArray(value) then
        for i = 1, #value do parts[#parts + 1] = Util.inspect(value[i], depth - 1) end
    else
        for _, k in ipairs(Util.sortedKeys(value)) do
            local key = type(k) == 'string' and k:match('^[%a_][%w_]*$') and k or ('[' .. Util.inspect(k, 0) .. ']')
            parts[#parts + 1] = key .. ' = ' .. Util.inspect(value[k], depth - 1)
        end
    end
    return '{ ' .. table.concat(parts, ', ') .. ' }'
end

--- Split "a.b.c" into {"a","b","c"}.
function Util.splitPath(path)
    local out = {}
    for part in string.gmatch(path, '[^%.]+') do out[#out + 1] = part end
    return out
end

--- Safe nested lookup: Util.get(cfg, 'logging.level', 'info')
function Util.get(t, path, default)
    local node = t
    for _, key in ipairs(Util.splitPath(path)) do
        if type(node) ~= 'table' then return default end
        node = node[key]
        if node == nil then return default end
    end
    return node
end

function Util.trim(s)
    return (tostring(s):gsub('^%s+', ''):gsub('%s+$', ''))
end

return Util
