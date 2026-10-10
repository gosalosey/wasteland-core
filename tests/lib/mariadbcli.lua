-- tests/lib/mariadbcli.lua
-- Test backend that runs statements on a REAL MariaDB/MySQL server through
-- the command-line client, shaping results the way oxmysql does. Used by
-- the db/ suite to prove the framework's SQL works on the real database.
--
-- Configure with environment variables or the same KEY=VALUE lines in
-- tests/db.env (gitignored); the suite is skipped without them:
--   WL_TEST_DB_CLIENT    path to mariadb.exe / mysql (default: mariadb)
--   WL_TEST_DB_HOST      default 127.0.0.1
--   WL_TEST_DB_PORT      default 3306
--   WL_TEST_DB_USER      user with rights on the test database
--   WL_TEST_DB_PASSWORD  password
--   WL_TEST_DB_NAME      test database (default wasteland_test); it is
--                        DROPPED AND RECREATED by the suite
-- Each statement starts a client process, so this is slow (tens of ms per
-- statement) but exact.

local CLI = {}
CLI.__index = CLI

local IS_WINDOWS = package.config:sub(1, 1) == '\\'

--- Settings from the environment, falling back to KEY=VALUE lines in
--- `envFile` (tests/db.env, which is gitignored). Returns nil when no user
--- is configured.
function CLI.configFromEnv(envFile)
    local file = {}
    local f = envFile and io.open(envFile, 'rb')
    if f then
        for line in f:read('a'):gmatch('[^\r\n]+') do
            local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
            if k then file[k] = v end
        end
        f:close()
    end
    local function get(k, def)
        local v = os.getenv(k)
        if v == nil or v == '' then v = file[k] end
        if v == nil or v == '' then return def end
        return v
    end
    local user = get('WL_TEST_DB_USER')
    if not user then return nil end
    return {
        client = get('WL_TEST_DB_CLIENT', 'mariadb'),
        host = get('WL_TEST_DB_HOST', '127.0.0.1'),
        port = get('WL_TEST_DB_PORT', '3306'),
        user = user,
        password = get('WL_TEST_DB_PASSWORD', ''),
        database = get('WL_TEST_DB_NAME', 'wasteland_test'),
    }
end

local function writeFile(path, data)
    local f = assert(io.open(path, 'wb'))
    f:write(data)
    f:close()
end

function CLI.new(cfg, tmpDir)
    local self = setmetatable({ cfg = cfg, tmpDir = tmpDir, log = {}, failPattern = nil }, CLI)
    self.optionFile = tmpDir .. '/client.cnf'
    -- Credentials go in an option file so they never appear on a command line.
    writeFile(self.optionFile, string.format('[client]\nhost=%s\nport=%s\nuser=%s\npassword="%s"\n',
        cfg.host, cfg.port, cfg.user, cfg.password:gsub('"', '\\"')))
    self.sqlFile = tmpDir .. '/statement.sql'
    return self
end

-- Run an SQL script. mode: 'xml' (data, default) or 'meta' (column types;
-- the client only prints them in table mode). Returns output or nil, error.
function CLI:runScript(script, database, mode)
    writeFile(self.sqlFile, script)
    local parts = {
        '"' .. self.cfg.client .. '"',
        '--defaults-extra-file="' .. self.optionFile .. '"',
        '--default-character-set=utf8mb4',
    }
    if mode == 'meta' then
        parts[#parts + 1] = '--table'
        parts[#parts + 1] = '--column-type-info'
    else
        parts[#parts + 1] = '--xml'
    end
    if database then parts[#parts + 1] = '"' .. database .. '"' end
    local cmd = table.concat(parts, ' ') .. ' < "' .. self.sqlFile .. '" 2>&1'
    if IS_WINDOWS then cmd = '"' .. cmd .. '"' end
    local p = assert(io.popen(cmd, 'r'))
    local out = p:read('a')
    local ok, _, code = p:close()
    if not ok or (code and code ~= 0) or out:match('^ERROR %d+') or out:match('\nERROR %d+') then
        local msg = out:match('(ERROR %d+.-)\r?\n') or out:match('(ERROR %d+.*)') or out
        return nil, msg
    end
    return out
end

--- Drop and recreate the test database.
function CLI:resetDatabase()
    local name = self.cfg.database
    assert(name:match('^[%w_]+$'), 'test database name must be letters, digits and _')
    assert(name:find('test', 1, true), 'refusing to reset a database whose name does not contain "test": ' .. name)
    local _, err = self:runScript(string.format(
        'DROP DATABASE IF EXISTS `%s`;\nCREATE DATABASE `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\n', name, name))
    return err == nil, err
end

-------------------------------------------------------------------------------
-- Parameters
-------------------------------------------------------------------------------

local function literal(v)
    if v == nil then return 'NULL' end
    local t = type(v)
    if t == 'boolean' then return v and '1' or '0' end
    if t == 'number' then
        if math.type(v) == 'integer' then return tostring(v) end
        return string.format('%.17g', v)
    end
    if t == 'string' then
        return "'" .. v:gsub('\\', '\\\\'):gsub("'", "\\'"):gsub('\0', '\\0'):gsub('\n', '\\n'):gsub('\r', '\\r') .. "'"
    end
    error('unsupported parameter type ' .. t, 0)
end

-- Replace each ? (outside quoted strings) with the next parameter.
local function bind(sql, params)
    local out, i, n = {}, 0, 0
    local quote = nil
    for pos = 1, #sql do
        local c = sql:sub(pos, pos)
        if quote then
            out[#out + 1] = c
            if c == quote then quote = nil end
        elseif c == "'" or c == '"' or c == '`' then
            quote = c
            out[#out + 1] = c
        elseif c == '?' then
            i = i + 1
            n = math.max(n, i)
            out[#out + 1] = literal(params[i])
        else
            out[#out + 1] = c
        end
    end
    return table.concat(out)
end

-------------------------------------------------------------------------------
-- Result parsing: column types come from a --table --column-type-info run
-- (SELECTs only, so nothing is executed twice that changes data); values
-- come from --xml output, which distinguishes NULL from the string 'NULL'.
-------------------------------------------------------------------------------

local ENTITIES = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'" }

local function xmlUnescape(s)
    return (s:gsub('&(#?x?)(%w+);', function(prefix, body)
        if prefix == '#' then return utf8.char(tonumber(body)) end
        if prefix == '#x' then return utf8.char(tonumber(body, 16)) end
        return ENTITIES[body] or ('&' .. body .. ';')
    end))
end

-- Rows from --xml output: list of { [column] = string } (NULL -> absent).
local function parseXml(out)
    local rows = {}
    for rowBody in out:gmatch('<row>(.-)</row>') do
        local row = {}
        for attrs, rest in rowBody:gmatch('<field (.-)(/?>)') do
            local name = attrs:match('name="(.-)"')
            if name and not attrs:find('xsi:nil="true"', 1, true) and rest == '>' then
                local value = rowBody:match('<field ' .. attrs:gsub('%p', '%%%0') .. '>(.-)</field>')
                row[xmlUnescape(name)] = xmlUnescape(value or '')
            end
        end
        rows[#rows + 1] = row
    end
    return rows
end

-- Column types from --column-type-info output: [name] = { type, length }.
local function parseMeta(out)
    local meta, current = {}, nil
    for line in (out .. '\n'):gmatch('(.-)\r?\n') do
        local name = line:match('^Field%s+%d+:%s+`(.*)`$')
        if name then
            current = { name = name }
            meta[name] = current
        elseif current then
            local ty = line:match('^Type:%s+(%S+)')
            if ty then current.type = ty end
            local len = line:match('^Length:%s+(%d+)')
            if len then current.length = tonumber(len) end
        end
    end
    return meta
end

-- Convert a text value the way oxmysql (mysql2 + its typeCast) would.
local function cast(value, m)
    if value == nil then return nil end
    local t = m and m.type
    if t == 'TINY' and m.length == 1 then return value == '1' end
    if t == 'TINY' or t == 'SHORT' or t == 'LONG' or t == 'INT24' or t == 'LONGLONG' or t == 'YEAR' then
        return math.tointeger(tonumber(value)) or tonumber(value)
    end
    if t == 'FLOAT' or t == 'DOUBLE' then return tonumber(value) end
    -- DATETIME (oxmysql: epoch ms; the framework reads UNIX_TIMESTAMP() instead),
    -- NEWDECIMAL (mysql2: string), strings and text stay strings.
    return value
end

-------------------------------------------------------------------------------
-- Backend interface (same as MemoryDB)
-------------------------------------------------------------------------------

local function isSelect(sql)
    local head = sql:match('^%s*(%a+)')
    return head and head:upper() == 'SELECT'
end

function CLI:select(sqlBound)
    local metaOut, err = self:runScript(sqlBound .. ';\n', self.cfg.database, 'meta')
    if not metaOut then return nil, err end
    local out, err2 = self:runScript(sqlBound .. ';\n', self.cfg.database, 'xml')
    if not out then return nil, err2 end
    local meta = parseMeta(metaOut)
    local rows = parseXml(out)
    for _, row in ipairs(rows) do
        for k, v in pairs(row) do row[k] = cast(v, meta[k]) end
    end
    return rows, nil, meta
end

function CLI:execute(kind, sql, params)
    local bound = bind(sql, params or {})
    self.log[#self.log + 1] = { sql = (sql:gsub('%s+', ' ')), params = params }
    if self.failPattern and bound:find(self.failPattern, 1, true) then return nil, 'simulated database error' end
    if isSelect(sql) then
        local rows, err = self:select(bound)
        if not rows then return nil, err end
        if kind == 'single' then return rows[1] end
        if kind == 'scalar' then
            local first = rows[1]
            if not first then return nil end
            local _, v = next(first)
            return v
        end
        return rows
    end
    local out, err = self:runScript(bound .. ';\nSELECT LAST_INSERT_ID() AS insertId, ROW_COUNT() AS affectedRows;\n', self.cfg.database, 'xml')
    if not out then return nil, err end
    local r = parseXml(out)[1] or {}
    local hdr = { insertId = tonumber(r.insertId) or 0, affectedRows = tonumber(r.affectedRows) or 0 }
    if hdr.affectedRows < 0 then hdr.affectedRows = 0 end
    if kind == 'insert' then return hdr.insertId end
    if kind == 'update' then return hdr.affectedRows end
    return hdr
end

function CLI:transaction(statements)
    local script = { 'START TRANSACTION;' }
    for _, st in ipairs(statements) do
        local bound = bind(st[1], st[2] or {})
        self.log[#self.log + 1] = { sql = (st[1]:gsub('%s+', ' ')), params = st[2] }
        if self.failPattern and bound:find(self.failPattern, 1, true) then return false, 'simulated database error' end
        script[#script + 1] = bound .. ';'
    end
    script[#script + 1] = 'COMMIT;'
    -- The client stops at the first error and disconnects, which rolls the
    -- open transaction back.
    local out, err = self:runScript(table.concat(script, '\n') .. '\n', self.cfg.database)
    if not out then return false, err end
    return true
end

--- Run a SELECT directly (for assertions). Returns rows or raises.
function CLI:rows(sql, params)
    local rows, err = self:execute('query', sql, params)
    if err then error(err, 2) end
    return rows
end

function CLI:calls(needle)
    local out = {}
    for _, l in ipairs(self.log) do
        if not needle or l.sql:find(needle, 1, true) then out[#out + 1] = l end
    end
    return out
end

return CLI
