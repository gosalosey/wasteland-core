-- Wasteland Core :: shared/schema.lua
-- Declarative configuration schemas. Schemas are plain data tables (no
-- functions) so they can cross resource boundaries through exports.
--
-- Node fields:
--   type        'any'|'string'|'number'|'integer'|'boolean'|'enum'|'table'|
--               'array'|'map'|'vector3'                       (required)
--   description human text shown in docs / error messages      (optional)
--   default     value used when the setting is absent         (optional)
--   required    true -> absent value is an error (unless default given)
--   nullable    for 'table': true -> an absent table stays nil instead of being
--               materialised as {} (use for optional sub-sections whose
--               children are required when the section IS present)
--   min, max    numeric bounds (number/integer)
--   minLength, maxLength, pattern   string constraints (Lua pattern)
--   values      list of allowed values for 'enum'
--   fields      table of child nodes for 'table'
--   allowUnknown  for 'table': true = unknown keys allowed silently,
--                 false/nil = unknown keys produce a warning
--   items, minItems, maxItems       for 'array'
--   keys, values(for map: node)     for 'map'  (keys defaults to string)

WL = WL or {}
WL.Schema = WL.Schema or {}
local Schema = WL.Schema
local Util = WL.Util

local KNOWN_TYPES = {
    any = true, string = true, number = true, integer = true, boolean = true,
    enum = true, table = true, array = true, map = true, vector3 = true,
}

local function joinPath(base, key)
    if base == nil or base == '' then return tostring(key) end
    if type(key) == 'number' then return base .. '[' .. key .. ']' end
    return base .. '.' .. tostring(key)
end

local function describeValue(v)
    local s = Util.inspect(v, 1)
    if #s > 60 then s = s:sub(1, 57) .. '...' end
    return s .. ' (' .. type(v) .. ')'
end

local function isVector3(v)
    local tv = type(v)
    if tv == 'vector3' then return true end
    if tv == 'table' then
        return type(v.x) == 'number' and type(v.y) == 'number' and type(v.z) == 'number'
    end
    return false
end

local function expectedText(node)
    local t = node.type
    if t == 'enum' then
        local vals = {}
        for i, v in ipairs(node.values or {}) do vals[i] = Util.inspect(v, 0) end
        return 'one of ' .. table.concat(vals, ', ')
    elseif t == 'integer' or t == 'number' then
        local s = t == 'integer' and 'an integer' or 'a number'
        if node.min and node.max then
            s = s .. string.format(' between %s and %s', node.min, node.max)
        elseif node.min then
            s = s .. ' >= ' .. node.min
        elseif node.max then
            s = s .. ' <= ' .. node.max
        end
        return s
    elseif t == 'vector3' then
        return 'a vector3 or { x = number, y = number, z = number }'
    elseif t == 'array' then
        return 'a list'
    elseif t == 'map' or t == 'table' then
        return 'a table'
    end
    return 'a ' .. t
end

local validateNode

local function addError(ctx, path, message)
    ctx.errors[#ctx.errors + 1] = { path = path, message = message }
end

local function addWarning(ctx, path, message)
    ctx.warnings[#ctx.warnings + 1] = { path = path, message = message }
end

local function validateTable(node, value, path, ctx)
    local out = {}
    local fields = node.fields or {}
    for _, key in ipairs(Util.sortedKeys(fields)) do
        local child = validateNode(fields[key], value[key], joinPath(path, key), ctx)
        out[key] = child
    end
    for _, key in ipairs(Util.sortedKeys(value)) do
        if fields[key] == nil then
            if node.allowUnknown then
                out[key] = Util.deepCopy(value[key])
            else
                addWarning(ctx, joinPath(path, key), 'unknown setting (ignored); check for a typo')
            end
        end
    end
    return out
end

local function validateArray(node, value, path, ctx)
    if not Util.isArray(value) then
        addError(ctx, path, 'expected a list (sequential table), got a table with non-sequential keys')
        return nil
    end
    if node.minItems and #value < node.minItems then
        addError(ctx, path, string.format('expected at least %d item(s), got %d', node.minItems, #value))
    end
    if node.maxItems and #value > node.maxItems then
        addError(ctx, path, string.format('expected at most %d item(s), got %d', node.maxItems, #value))
    end
    local out = {}
    for i = 1, #value do
        if node.items then
            out[i] = validateNode(node.items, value[i], joinPath(path, i), ctx)
        else
            out[i] = Util.deepCopy(value[i])
        end
    end
    return out
end

local function validateMap(node, value, path, ctx)
    local out = {}
    local keyNode = node.keys or { type = 'string' }
    for _, k in ipairs(Util.sortedKeys(value)) do
        local keyCtx = { errors = {}, warnings = {} }
        validateNode(keyNode, k, joinPath(path, k), keyCtx)
        for _, e in ipairs(keyCtx.errors) do
            addError(ctx, e.path, 'invalid key: ' .. e.message)
        end
        if #keyCtx.errors == 0 then
            if type(node.values) == 'table' and node.values.type then
                out[k] = validateNode(node.values, value[k], joinPath(path, k), ctx)
            else
                out[k] = Util.deepCopy(value[k])
            end
        end
    end
    return out
end

validateNode = function(node, value, path, ctx)
    if value == nil then
        if node.default ~= nil then
            value = Util.deepCopy(node.default)
        elseif node.type == 'table' and not node.required and not node.nullable then
            -- Absent optional tables are materialised so nested defaults apply.
            value = {}
        elseif node.required then
            addError(ctx, path, 'missing required setting; expected ' .. expectedText(node))
            return nil
        else
            return nil
        end
    end

    local t = node.type
    if t == 'any' then
        return Util.deepCopy(value)
    elseif t == 'string' then
        if type(value) ~= 'string' then
            addError(ctx, path, 'expected a string, got ' .. describeValue(value)); return nil
        end
        if node.minLength and #value < node.minLength then
            addError(ctx, path, string.format('expected at least %d character(s), got %d', node.minLength, #value))
        end
        if node.maxLength and #value > node.maxLength then
            addError(ctx, path, string.format('expected at most %d character(s), got %d', node.maxLength, #value))
        end
        if node.pattern and not value:match(node.pattern) then
            addError(ctx, path, string.format('value %q does not match the required format %s', value, node.pattern))
        end
        return value
    elseif t == 'number' or t == 'integer' then
        if type(value) ~= 'number' or value ~= value then
            addError(ctx, path, 'expected ' .. expectedText(node) .. ', got ' .. describeValue(value)); return nil
        end
        if t == 'integer' and math.type(value) ~= 'integer' and value ~= math.floor(value) then
            addError(ctx, path, 'expected ' .. expectedText(node) .. ', got ' .. describeValue(value)); return nil
        end
        if (node.min and value < node.min) or (node.max and value > node.max) then
            addError(ctx, path, 'expected ' .. expectedText(node) .. ', got ' .. tostring(value)); return nil
        end
        if t == 'integer' then return math.tointeger(value) or value end
        return value
    elseif t == 'boolean' then
        if type(value) ~= 'boolean' then
            addError(ctx, path, 'expected true or false, got ' .. describeValue(value)); return nil
        end
        return value
    elseif t == 'enum' then
        if not Util.contains(node.values or {}, value) then
            addError(ctx, path, 'expected ' .. expectedText(node) .. ', got ' .. describeValue(value)); return nil
        end
        return value
    elseif t == 'vector3' then
        if not isVector3(value) then
            addError(ctx, path, 'expected ' .. expectedText(node) .. ', got ' .. describeValue(value)); return nil
        end
        return value
    elseif t == 'table' or t == 'array' or t == 'map' then
        if type(value) ~= 'table' then
            addError(ctx, path, 'expected ' .. expectedText(node) .. ', got ' .. describeValue(value)); return nil
        end
        if t == 'table' then return validateTable(node, value, path, ctx) end
        if t == 'array' then return validateArray(node, value, path, ctx) end
        return validateMap(node, value, path, ctx)
    end
    addError(ctx, path, 'schema error: unknown type ' .. tostring(t))
    return nil
end

--- Validate `value` against `schema`.
--- Returns: result (value with defaults applied), errors[], warnings[]
--- Each error/warning is { path = 'a.b', message = '...' }.
function Schema.validate(schema, value)
    local ctx = { errors = {}, warnings = {} }
    local result = validateNode(schema, value, '', ctx)
    return result, ctx.errors, ctx.warnings
end

--- Check that a schema itself is well formed (catches module author mistakes
--- early with a precise message). Returns true or false, errors[].
function Schema.check(schema)
    local errors = {}
    local function walk(node, path)
        if type(node) ~= 'table' then
            errors[#errors + 1] = path .. ': schema node must be a table'
            return
        end
        if not KNOWN_TYPES[node.type] then
            errors[#errors + 1] = string.format('%s: unknown schema type %s', path, Util.inspect(node.type, 0))
            return
        end
        if node.type == 'enum' and (type(node.values) ~= 'table' or #node.values == 0) then
            errors[#errors + 1] = path .. ': enum requires a non-empty `values` list'
        end
        if node.type == 'table' and node.fields ~= nil then
            if type(node.fields) ~= 'table' then
                errors[#errors + 1] = path .. ': `fields` must be a table'
            else
                for _, k in ipairs(Util.sortedKeys(node.fields)) do
                    walk(node.fields[k], joinPath(path, k))
                end
            end
        end
        if node.type == 'array' and node.items ~= nil then walk(node.items, path .. '[]') end
        if node.type == 'map' then
            if node.keys ~= nil then walk(node.keys, path .. '<key>') end
            if node.values ~= nil then walk(node.values, path .. '<value>') end
        end
        if node.default ~= nil then
            local ctx = { errors = {}, warnings = {} }
            local copy = Util.deepCopy(node)
            copy.default = nil
            copy.required = true
            validateNode(copy, node.default, path, ctx)
            for _, e in ipairs(ctx.errors) do
                errors[#errors + 1] = string.format('%s: default value is invalid: %s', e.path ~= '' and e.path or path, e.message)
            end
        end
    end
    walk(schema, '<root>')
    return #errors == 0, errors
end

--- Format a list of errors/warnings as lines: "<file>: '<path>' <message>"
function Schema.formatIssues(issues, file)
    local lines = {}
    for _, e in ipairs(issues) do
        local where = (e.path and e.path ~= '') and string.format("setting '%s'", e.path) or 'file root'
        lines[#lines + 1] = string.format('%s: %s: %s', file or '<config>', where, e.message)
    end
    return lines
end

return Schema
