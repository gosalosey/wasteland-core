-- wasteland_core :: server/updates.lua
-- Tells the server owner when Wasteland Core has updates on GitHub: a banner
-- in the server console after start (and every few hours), and a line in
-- chat for admins when they join.
--
-- The installed version is the commit in resources/[wasteland]/VERSION.txt,
-- written by the updater (tools/update.ps1). A server without that file
-- (a fresh install) records the newest commit on its first start.
-- framework.lua: updateCheck = { enabled, repo, branch, everyHours }.

Updates = Updates or {}
Updates.available = nil   -- { count, installed, latest } while updates wait

local log = WL and WL.Logger and WL.Logger.new('updates') or { info = function() end, warn = function() end }

--- Pure (unit-tested): the console banner. -> list of lines (with ^ colour codes)
function Updates.banner(info)
    local lines = {}
    local count = info.count and tostring(info.count) or 'new'
    local plural = info.count == 1 and 'update' or 'updates'
    lines[#lines + 1] = '^3==================================================================^7'
    lines[#lines + 1] = string.format('^3  Wasteland Core: %s %s available on GitHub^7', count, plural)
    lines[#lines + 1] = string.format('^3  Installed: %s   Newest: %s%s^7', info.installed:sub(1, 7), info.latest:sub(1, 7),
        info.date and (' (' .. info.date:sub(1, 10) .. ')') or '')
    for i, t in ipairs(info.titles or {}) do
        if i > 10 then
            lines[#lines + 1] = string.format('^7    ... and %d more', #info.titles - 10)
            break
        end
        lines[#lines + 1] = '^7    - ' .. t
    end
    lines[#lines + 1] = '^3  To update: stop the server and run update_wasteland.bat in your^7'
    lines[#lines + 1] = '^3  server folder (your settings are kept and a backup is made).^7'
    lines[#lines + 1] = '^3==================================================================^7'
    return lines
end

--- Pure (unit-tested): first line of each commit message, newest first.
function Updates.titles(commits)
    local out = {}
    for i = #(commits or {}), 1, -1 do
        local c = commits[i]
        local msg = c and c.commit and c.commit.message or ''
        local first = msg:match('^[^\r\n]*') or ''
        if first ~= '' then out[#out + 1] = first end
    end
    return out
end

local function settings()
    local c = Lifecycle and Lifecycle.coreConfig
    return c and c.framework and c.framework.updateCheck or nil
end

-- resources/[wasteland] (the folder this resource is in)
local function folder()
    local path = GetResourcePath(GetCurrentResourceName()) or ''
    return (path:gsub('[/\\][^/\\]+[/\\]?$', ''))
end

local function readInstalled()
    local f = io.open(folder() .. '/VERSION.txt', 'r')
    if not f then return nil end
    local sha = (f:read('a') or ''):match('%x+')
    f:close()
    if sha and #sha >= 7 then return sha end
    return nil
end

local function writeInstalled(sha)
    local f = io.open(folder() .. '/VERSION.txt', 'w')
    if not f then return false end
    f:write(sha)
    f:close()
    return true
end

local function get(url, cb)
    PerformHttpRequest(url, function(status, body) cb(status, body) end, 'GET', '',
        { ['User-Agent'] = 'wasteland-core-update-check', ['Accept'] = 'application/vnd.github+json' })
end

function Updates.check()
    local s = settings()
    if not s or not s.enabled or type(PerformHttpRequest) ~= 'function' then return end
    local api = 'https://api.github.com/repos/' .. s.repo
    get(api .. '/commits/' .. s.branch, function(status, body)
        local ok, latest = pcall(json.decode, body or '')
        if status ~= 200 or not ok or type(latest) ~= 'table' or not latest.sha then
            log:info('update check: GitHub did not answer (status %s); trying again later', tostring(status))
            return
        end
        local date = latest.commit and latest.commit.committer and latest.commit.committer.date or nil
        local installed = readInstalled()
        if not installed then
            if writeInstalled(latest.sha) then
                log:info('update check: no VERSION.txt yet; recorded %s as the installed version', latest.sha:sub(1, 7))
            end
            Updates.available = nil
            return
        end
        if installed == latest.sha then
            Updates.available = nil
            log:info('Wasteland Core is up to date (%s)', installed:sub(1, 7))
            return
        end
        get(api .. '/compare/' .. installed .. '...' .. latest.sha, function(st2, body2)
            local info = { installed = installed, latest = latest.sha, date = date }
            local ok2, cmp = pcall(json.decode, body2 or '')
            if st2 == 200 and ok2 and type(cmp) == 'table' then
                if cmp.status == 'behind' or cmp.status == 'identical' then
                    -- the installed copy is newer than the branch (a test build): nothing to say
                    Updates.available = nil
                    return
                end
                info.count = tonumber(cmp.ahead_by)
                info.titles = Updates.titles(cmp.commits)
            end
            Updates.available = info
            for _, line in ipairs(Updates.banner(info)) do print(line) end
        end)
    end)
end

-- After start, then every few hours.
Citizen.CreateThread(function()
    Citizen.Wait(15000)
    while true do
        local s = settings()
        if s and s.enabled then Updates.check() end
        Citizen.Wait(math.floor(((s and s.everyHours) or 6) * 3600 * 1000))
    end
end)

-- Admins hear about it when they join.
AddEventHandler('wasteland:players:characterLoaded', function(src)
    local info = Updates.available
    if not info then return end
    local c = Lifecycle and Lifecycle.coreConfig
    local ace = c and c.framework and c.framework.adminAce or 'wasteland.admin'
    if not IsPlayerAceAllowed(tostring(src), ace) then return end
    TriggerClientEvent('chat:addMessage', src, { color = { 232, 194, 90 }, multiline = true,
        args = { 'Wasteland Core', string.format('%s update(s) available on GitHub. Stop the server and run update_wasteland.bat to update.',
            info.count and tostring(info.count) or 'New') } })
end)

return Updates
