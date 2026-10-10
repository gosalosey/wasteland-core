-- tests/lib/json.lua
-- Minimal JSON encode/decode standing in for FiveM's `json` global in the
-- simulated runtime. Sequential tables encode as arrays (empty tables as []),
-- other tables as objects; null decodes to nil.

local json = {}

local ESCAPES = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function isArray(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do if t[i] == nil then return false end end
    return true
end

local encodeValue

local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
end

encodeValue = function(v, seen)
    local t = type(v)
    if v == nil then return 'null' end
    if t == 'boolean' then return tostring(v) end
    if t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then error('cannot encode non-finite number', 0) end
        if math.type(v) == 'integer' then return tostring(v) end
        if v == math.floor(v) and math.abs(v) < 2^53 then return string.format('%d', v) end
        return string.format('%.14g', v)
    end
    if t == 'string' then return encodeString(v) end
    if t == 'table' then
        seen = seen or {}
        if seen[v] then error('cannot encode a table with cycles', 0) end
        seen[v] = true
        local parts = {}
        if isArray(v) then
            for i = 1, #v do parts[i] = encodeValue(v[i], seen) end
            seen[v] = nil
            return '[' .. table.concat(parts, ',') .. ']'
        end
        local keys = {}
        for k in pairs(v) do
            if type(k) ~= 'string' and type(k) ~= 'number' then error('cannot encode key of type ' .. type(k), 0) end
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            parts[#parts + 1] = encodeString(tostring(k)) .. ':' .. encodeValue(v[k], seen)
        end
        seen[v] = nil
        return '{' .. table.concat(parts, ',') .. '}'
    end
    error('cannot encode value of type ' .. t, 0)
end

function json.encode(v)
    return encodeValue(v)
end

local function decodeError(str, pos, msg)
    error(string.format('json decode error at %d: %s', pos, msg), 0)
end

local decodeValue

local function skip(str, pos)
    return str:find('[^ \t\r\n]', pos) or #str + 1
end

local function decodeString(str, pos)
    local out, i = {}, pos + 1
    while true do
        local c = str:sub(i, i)
        if c == '' then decodeError(str, i, 'unterminated string') end
        if c == '"' then return table.concat(out), i + 1 end
        if c == '\\' then
            local e = str:sub(i + 1, i + 1)
            local map = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
            if map[e] then
                out[#out + 1] = map[e]; i = i + 2
            elseif e == 'u' then
                local hex = str:sub(i + 2, i + 5)
                out[#out + 1] = utf8.char(tonumber(hex, 16)); i = i + 6
            else
                decodeError(str, i, 'bad escape')
            end
        else
            out[#out + 1] = c; i = i + 1
        end
    end
end

decodeValue = function(str, pos)
    pos = skip(str, pos)
    local c = str:sub(pos, pos)
    if c == '{' then
        local obj = {}
        pos = skip(str, pos + 1)
        if str:sub(pos, pos) == '}' then return obj, pos + 1 end
        while true do
            if str:sub(pos, pos) ~= '"' then decodeError(str, pos, 'expected key') end
            local key
            key, pos = decodeString(str, pos)
            pos = skip(str, pos)
            if str:sub(pos, pos) ~= ':' then decodeError(str, pos, 'expected :') end
            local val
            val, pos = decodeValue(str, pos + 1)
            obj[key] = val
            pos = skip(str, pos)
            local d = str:sub(pos, pos)
            if d == '}' then return obj, pos + 1 end
            if d ~= ',' then decodeError(str, pos, 'expected , or }') end
            pos = skip(str, pos + 1)
        end
    elseif c == '[' then
        local arr, n = {}, 0
        pos = skip(str, pos + 1)
        if str:sub(pos, pos) == ']' then return arr, pos + 1 end
        while true do
            local val
            val, pos = decodeValue(str, pos)
            n = n + 1
            arr[n] = val
            pos = skip(str, pos)
            local d = str:sub(pos, pos)
            if d == ']' then return arr, pos + 1 end
            if d ~= ',' then decodeError(str, pos, 'expected , or ]') end
            pos = pos + 1
        end
    elseif c == '"' then
        return decodeString(str, pos)
    elseif str:sub(pos, pos + 3) == 'true' then
        return true, pos + 4
    elseif str:sub(pos, pos + 4) == 'false' then
        return false, pos + 5
    elseif str:sub(pos, pos + 3) == 'null' then
        return nil, pos + 4
    end
    local num = str:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
    if num and num ~= '' then
        return math.tointeger(tonumber(num)) or tonumber(num), pos + #num
    end
    decodeError(str, pos, 'unexpected character ' .. c)
end

function json.decode(str)
    if type(str) ~= 'string' then error('json.decode expects a string', 2) end
    local value, pos = decodeValue(str, 1)
    pos = skip(str, pos)
    if pos <= #str then decodeError(str, pos, 'trailing characters') end
    return value
end

return json
