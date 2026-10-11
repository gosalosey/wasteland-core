-- Runs the JavaScript unit tests (tests/js/*.test.js) with Node's built-in
-- test runner and reports each one here. Skipped when Node is not installed.

local IS_WINDOWS = package.config:sub(1, 1) == '\\'
local FILES = { 'ui.test.js', 'inventory.test.js', 'survival.test.js', 'admin.test.js' }

local function nodeAvailable()
    local p = io.popen(IS_WINDOWS and 'node --version 2>nul' or 'node --version 2>/dev/null')
    if not p then return false end
    local out = p:read('a') or ''
    p:close()
    return out:match('^v%d+') ~= nil
end

if not nodeAvailable() then
    skip('JavaScript tests', 'Node.js not found on PATH (https://nodejs.org); the NUI logic is not tested')
    return
end

for _, file in ipairs(FILES) do
    local path = ROOT .. '/tests/js/' .. file
    local cmd = 'node --test --test-reporter=tap "' .. path .. '" 2>&1'
    if IS_WINDOWS then cmd = '"' .. cmd .. '"' end
    local p = assert(io.popen(cmd))
    local out = p:read('a')
    p:close()
    describe(file, function()
        local count = 0
        for status, name in out:gmatch('\n%s*(n?o?t? ?ok) %d+ %- ([^\n]+)') do
            -- only top-level results (TAP subtests are indented; ours are flat)
            count = count + 1
            local passed = status == 'ok'
            it(name, function()
                if not passed then error('failed in node; run: node --test tests/js/' .. file, 0) end
            end)
        end
        if count == 0 then
            it('produced results', function() error('no test results parsed; output:\n' .. out, 0) end)
        end
    end)
end
