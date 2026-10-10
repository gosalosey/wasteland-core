-- Wasteland Core :: shared/semver.lua
-- Minimal semantic-version parsing and range matching used for module
-- versions, interface (API) versions and dependency declarations.
--
-- Supported range syntax:
--   *            any version
--   1.2.3        exactly 1.2.3 (also "=1.2.3")
--   ^1.2.3       >=1.2.3 <2.0.0   (for 0.x: ^0.2.3 => >=0.2.3 <0.3.0)
--   ~1.2.3       >=1.2.3 <1.3.0
--   >=1.2.3  >1.2.3  <=1.2.3  <1.2.3
--   ">=1.0.0 <1.5.0"   space-separated comparators are ANDed
--   "^1.0.0 || ^2.0.0" alternatives are ORed
-- Partial versions are allowed in ranges ("^1", ">=1.2") and are padded with 0.

WL = WL or {}
WL.Semver = WL.Semver or {}
local Semver = WL.Semver

--- Parse "1.2.3" or "1.2.3-beta.1". Returns table or nil, error.
--- When `partial` is true, "1" and "1.2" are accepted.
function Semver.parse(str, partial)
    if type(str) ~= 'string' then
        return nil, 'version must be a string, got ' .. type(str)
    end
    local core, pre = str:match('^v?([%d%.]+)%-([%w%.%-]+)$')
    if not core then core = str:match('^v?([%d%.]+)$') end
    if not core then
        return nil, string.format('invalid version "%s" (expected MAJOR.MINOR.PATCH)', str)
    end
    local parts = {}
    for n in core:gmatch('[^%.]+') do parts[#parts + 1] = n end
    if #parts < 1 or #parts > 3 or (not partial and #parts ~= 3) then
        return nil, string.format('invalid version "%s" (expected MAJOR.MINOR.PATCH)', str)
    end
    for i = 1, #parts do
        if not parts[i]:match('^%d+$') then
            return nil, string.format('invalid version "%s"', str)
        end
        parts[i] = tonumber(parts[i])
    end
    return {
        major = parts[1],
        minor = parts[2] or 0,
        patch = parts[3] or 0,
        pre = pre,
        given = #parts,
    }
end

function Semver.isValid(str)
    return Semver.parse(str) ~= nil
end

--- Compare two parsed or string versions. Returns -1, 0, 1.
function Semver.compare(a, b)
    if type(a) == 'string' then a = assert(Semver.parse(a, true)) end
    if type(b) == 'string' then b = assert(Semver.parse(b, true)) end
    for _, k in ipairs({ 'major', 'minor', 'patch' }) do
        if a[k] ~= b[k] then return a[k] < b[k] and -1 or 1 end
    end
    -- A pre-release sorts before its release.
    if a.pre == b.pre then return 0 end
    if a.pre == nil then return 1 end
    if b.pre == nil then return -1 end
    return a.pre < b.pre and -1 or 1
end

local function comparatorSatisfied(v, op, target)
    local c = Semver.compare(v, target)
    if op == '=' then return c == 0
    elseif op == '>' then return c > 0
    elseif op == '>=' then return c >= 0
    elseif op == '<' then return c < 0
    elseif op == '<=' then return c <= 0
    end
    return false
end

-- Expand one token ("^1.2.3", ">=1.0") into a list of {op, version}.
local function expandToken(token)
    if token == '*' or token == 'x' or token == '' then return {} end
    local op, ver = token:match('^([%^~><=]*)(.+)$')
    local parsed, err = Semver.parse(ver, true)
    if not parsed then return nil, err end
    if op == '^' then
        local upper
        if parsed.major > 0 or parsed.given == 1 then
            upper = { major = parsed.major + 1, minor = 0, patch = 0 }
        elseif parsed.minor > 0 or parsed.given == 2 then
            upper = { major = 0, minor = parsed.minor + 1, patch = 0 }
        else
            upper = { major = 0, minor = 0, patch = parsed.patch + 1 }
        end
        return { { '>=', parsed }, { '<', upper } }
    elseif op == '~' then
        local upper
        if parsed.given == 1 then
            upper = { major = parsed.major + 1, minor = 0, patch = 0 }
        else
            upper = { major = parsed.major, minor = parsed.minor + 1, patch = 0 }
        end
        return { { '>=', parsed }, { '<', upper } }
    elseif op == '' or op == '=' then
        if parsed.given < 3 then
            -- "1.2" means any 1.2.x
            local upper = parsed.given == 1
                and { major = parsed.major + 1, minor = 0, patch = 0 }
                or { major = parsed.major, minor = parsed.minor + 1, patch = 0 }
            return { { '>=', parsed }, { '<', upper } }
        end
        return { { '=', parsed } }
    elseif op == '>' or op == '>=' or op == '<' or op == '<=' then
        return { { op, parsed } }
    end
    return nil, string.format('invalid range operator "%s"', op)
end

--- Validate a range string without testing a version.
function Semver.isValidRange(range)
    if type(range) ~= 'string' then return false, 'range must be a string' end
    for alt in (range .. '||'):gmatch('(.-)||') do
        for token in alt:gmatch('%S+') do
            local comps, err = expandToken(token)
            if not comps then return false, err end
        end
    end
    return true
end

--- Does `version` satisfy `range`? Returns boolean, or false, error for bad input.
function Semver.satisfies(version, range)
    local v, verr = Semver.parse(version)
    if not v then return false, verr end
    if type(range) ~= 'string' then return false, 'range must be a string' end
    local anyAlt = false
    for alt in (range .. '||'):gmatch('(.-)||') do
        anyAlt = true
        local ok = true
        for token in alt:gmatch('%S+') do
            local comps, err = expandToken(token)
            if not comps then return false, err end
            for _, c in ipairs(comps) do
                if not comparatorSatisfied(v, c[1], c[2]) then ok = false end
            end
        end
        if ok then return true end
    end
    if not anyAlt then return false, 'empty range' end
    return false
end

return Semver
