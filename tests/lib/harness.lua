-- tests/lib/harness.lua
-- Tiny dependency-free test framework: describe / it / expect.

local H = { results = {}, current = {}, passed = 0, failed = 0, failures = {} }

local function fullName(name)
    local parts = {}
    for _, d in ipairs(H.current) do parts[#parts + 1] = d end
    parts[#parts + 1] = name
    return table.concat(parts, ' > ')
end

function H.describe(name, fn)
    table.insert(H.current, name)
    fn()
    table.remove(H.current)
end

function H.it(name, fn)
    local label = fullName(name)
    local ok, err = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end)
    if ok then
        H.passed = H.passed + 1
        print('  ok   ' .. label)
    else
        H.failed = H.failed + 1
        H.failures[#H.failures + 1] = { name = label, err = err }
        print('  FAIL ' .. label)
        print('       ' .. tostring(err):gsub('\n', '\n       '))
    end
end

local function show(v)
    if type(v) == 'string' then return string.format('%q', v) end
    if type(v) ~= 'table' then return tostring(v) end
    local parts = {}
    for k, val in pairs(v) do parts[#parts + 1] = tostring(k) .. '=' .. show(val) end
    table.sort(parts)
    return '{' .. table.concat(parts, ', ') .. '}'
end

local function deepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function H.expect(actual)
    local e = {}
    function e.toBe(expected)
        if actual ~= expected then error(string.format('expected %s, got %s', show(expected), show(actual)), 2) end
    end
    function e.toEqual(expected)
        if not deepEqual(actual, expected) then error(string.format('expected %s, got %s', show(expected), show(actual)), 2) end
    end
    function e.toBeTruthy()
        if not actual then error('expected truthy value, got ' .. show(actual), 2) end
    end
    function e.toBeFalsy()
        if actual then error('expected falsy value, got ' .. show(actual), 2) end
    end
    function e.toContain(needle)
        if type(actual) == 'string' then
            if not actual:find(needle, 1, true) then error(string.format('expected %q to contain %q', actual, needle), 2) end
        elseif type(actual) == 'table' then
            for _, v in ipairs(actual) do
                if v == needle then return end
                if type(v) == 'string' and type(needle) == 'string' and v:find(needle, 1, true) then return end
            end
            error(string.format('expected list to contain %s; list = %s', show(needle), show(actual)), 2)
        else
            error('toContain needs a string or table, got ' .. type(actual), 2)
        end
    end
    function e.notToContain(needle)
        if type(actual) == 'string' then
            if actual:find(needle, 1, true) then error(string.format('expected %q not to contain %q', actual, needle), 2) end
        else
            for _, v in ipairs(actual) do
                if v == needle or (type(v) == 'string' and type(needle) == 'string' and v:find(needle, 1, true)) then
                    error(string.format('expected list not to contain %s (found %s)', show(needle), show(v)), 2)
                end
            end
        end
    end
    function e.toHaveLength(n)
        if #actual ~= n then error(string.format('expected length %d, got %d (%s)', n, #actual, show(actual)), 2) end
    end
    return e
end

function H.summary()
    print('')
    print(string.format('%d passed, %d failed', H.passed, H.failed))
    if H.failed > 0 then
        print('Failures:')
        for _, f in ipairs(H.failures) do print('  - ' .. f.name) end
    end
    return H.failed == 0
end

return H
