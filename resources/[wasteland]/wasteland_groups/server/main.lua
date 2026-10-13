-- wasteland_groups :: server/main.lua
-- Module "groups": players make named groups and invite others. Members see
-- each other on the map. Groups belong to characters, are stored in the
-- database and last until the leader disbands them. A character is in at
-- most one group.

local Rules = WLG.Rules
local SQL = WLG.SQL
local M
local groups = {}     -- id -> { id, name, leader, members = { [characterId] = name } }
local memberOf = {}   -- characterId -> group id
local invites = {}    -- characterId -> { group, by, expiresAt }
local runToken = nil

local function now() return GetGameTimer() end
local function players() return exports.wasteland_players end
local function notice(src, msg) TriggerClientEvent('wasteland:groups:client:notice', src, msg) end

-- Database writes in their own thread (callers are often event handlers).
local function write(sql, params, what)
    Citizen.CreateThread(function()
        local _, err = WDB.update(sql, params)
        if err then M.log:warn('%s failed: %s', what, tostring(err)) end
    end)
end

local function characterOf(src)
    local ok, cid = pcall(function() return players():GetCharacterId(src) end)
    return ok and cid or nil
end

local function sourceOf(cid)
    local ok, src = pcall(function() return players():GetSourceByCharacterId(cid) end)
    return ok and src or nil
end

local function nameOf(src)
    local ok, c = pcall(function() return players():GetCharacter(src) end)
    if ok and c then return c.firstName .. ' ' .. c.lastName end
    return GetPlayerName(tostring(src)) or ('Player ' .. src)
end

local function count(g)
    local n = 0
    for _ in pairs(g.members) do n = n + 1 end
    return n
end

-------------------------------------------------------------------------------
-- Group radio (pma-voice): every group has its own radio channel; members
-- online are on it and talk to each other anywhere on the map.
-------------------------------------------------------------------------------

local function voiceRunning() return M.config.radio.enabled and GetResourceState('pma-voice') == 'started' end

local function setRadio(src, groupId)
    if not src or not voiceRunning() then return end
    local channel = groupId and (M.config.radio.channelBase + groupId) or 0
    local ok, err = pcall(function() exports['pma-voice']:setPlayerRadio(src, channel) end)
    if not ok then M.log:warn('group radio for player %d: %s', src, tostring(err)) end
end

local function radioFor(cid, groupId)
    local s = sourceOf(cid)
    if s then setRadio(s, groupId) end
end

local function radioAll()
    for cid, gid in pairs(memberOf) do radioFor(cid, gid) end
end

-------------------------------------------------------------------------------
-- What a player sees on the group screen
-------------------------------------------------------------------------------

local function view(src)
    local cid = characterOf(src)
    if not cid then return nil end
    local out = { me = cid, maxMembers = M.config.maxMembers, nameMin = M.config.nameMin, nameMax = M.config.nameMax }
    local g = groups[memberOf[cid]]
    if g then
        local members = {}
        for mcid, name in pairs(g.members) do
            local s = sourceOf(mcid)
            members[#members + 1] = { id = mcid, name = name, leader = mcid == g.leader, online = s ~= nil, server = s }
        end
        table.sort(members, function(a, b)
            if a.leader ~= b.leader then return a.leader end
            return a.name < b.name
        end)
        out.group = { id = g.id, name = g.name, leader = g.leader == cid, members = members }
    end
    local inv = invites[cid]
    if inv and now() < inv.expiresAt and groups[inv.group] then
        out.invite = { group = inv.group, name = groups[inv.group].name, by = inv.byName }
    end
    return out
end

local function sendView(src)
    local v = view(src)
    if v then TriggerClientEvent('wasteland:groups:client:view', src, v) end
end

-- Everyone online in a group gets a fresh screen (if open) and markers.
local function refreshGroup(g)
    for cid in pairs(g.members) do
        local s = sourceOf(cid)
        if s then sendView(s) end
    end
end

local function clearMarkers(cid)
    local s = sourceOf(cid)
    if s then TriggerClientEvent('wasteland:groups:client:positions', s, nil) end
end

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------

local function create(src, name)
    local cid = characterOf(src)
    if not cid then return end
    if memberOf[cid] then notice(src, 'You are already in a group. Leave it first.'); return end
    local clean, why = Rules.cleanName(name, M.config.nameMin, M.config.nameMax)
    if not clean then notice(src, why); return end
    if Rules.nameTaken(groups, clean) then notice(src, 'A group with that name already exists.'); return end
    local id, err = WDB.insert(SQL.insertGroup, { clean, cid, os.time() })
    if not id then notice(src, 'The group could not be saved. Try again.'); M.log:warn('create group: %s', tostring(err)); return end
    local myName = nameOf(src)
    local g = { id = id, name = clean, leader = cid, members = { [cid] = myName } }
    groups[id], memberOf[cid] = g, id
    WDB.update(SQL.insertMember, { cid, id, myName, os.time() })
    M.log:info('player %d (character %d) created group %d "%s"', src, cid, id, clean)
    setRadio(src, id)
    notice(src, 'Group "' .. clean .. '" created. Invite players from /group.')
    TriggerEvent('wasteland:groups:created', id, cid)
    sendView(src)
end

local function invite(src, targetSrc)
    local cid = characterOf(src)
    local g = cid and groups[memberOf[cid]]
    if not g then notice(src, 'You are not in a group.'); return end
    if g.leader ~= cid then notice(src, 'Only the leader can invite players.'); return end
    if targetSrc == src then return end
    local tcid = characterOf(targetSrc)
    if not tcid then notice(src, 'No player with id ' .. targetSrc .. ' is playing right now.'); return end
    if memberOf[tcid] then notice(src, nameOf(targetSrc) .. ' is already in a group.'); return end
    if count(g) >= M.config.maxMembers then notice(src, 'The group is full (' .. M.config.maxMembers .. ' members).'); return end
    invites[tcid] = { group = g.id, by = cid, byName = nameOf(src), expiresAt = now() + M.config.inviteSeconds * 1000 }
    notice(src, 'Invited ' .. nameOf(targetSrc) .. '.')
    notice(targetSrc, string.format('%s invites you to the group "%s". Type /group to accept.', nameOf(src), g.name))
    sendView(targetSrc)
end

local function respond(src, groupId, accept)
    local cid = characterOf(src)
    local inv = cid and invites[cid]
    if not inv or inv.group ~= groupId then return end
    invites[cid] = nil
    local g = groups[groupId]
    if not accept then
        local by = sourceOf(inv.by)
        if by then notice(by, nameOf(src) .. ' declined the invitation.') end
        sendView(src)
        return
    end
    if now() > inv.expiresAt then notice(src, 'The invitation has expired.'); sendView(src); return end
    if not g then notice(src, 'That group no longer exists.'); sendView(src); return end
    if memberOf[cid] then notice(src, 'You are already in a group.'); return end
    if count(g) >= M.config.maxMembers then notice(src, 'The group is full.'); sendView(src); return end
    local myName = nameOf(src)
    g.members[cid], memberOf[cid] = myName, g.id
    write(SQL.insertMember, { cid, g.id, myName, os.time() }, 'joining group ' .. g.id)
    for mcid in pairs(g.members) do
        local s = sourceOf(mcid)
        if s and mcid ~= cid then notice(s, myName .. ' joined the group.') end
    end
    notice(src, 'You joined "' .. g.name .. '".' .. (voiceRunning() and (' Group radio: hold ' .. M.config.radio.keyName .. ' to talk to your group.') or ''))
    setRadio(src, g.id)
    TriggerEvent('wasteland:groups:joined', g.id, cid)
    refreshGroup(g)
end

local function removeMember(g, cid, why)
    g.members[cid], memberOf[cid] = nil, nil
    radioFor(cid, nil)
    write(SQL.deleteMember, { cid }, 'leaving group ' .. g.id)
    clearMarkers(cid)
    TriggerEvent('wasteland:groups:left', g.id, cid, why)
end

local function disband(g, why)
    for cid in pairs(g.members) do
        memberOf[cid] = nil
        clearMarkers(cid)
        radioFor(cid, nil)
        local s = sourceOf(cid)
        if s then
            notice(s, 'The group "' .. g.name .. '" was disbanded.')
            sendView(s)
        end
    end
    groups[g.id] = nil
    for cid, inv in pairs(invites) do if inv.group == g.id then invites[cid] = nil end end
    write(SQL.deleteMembers, { g.id }, 'disbanding group ' .. g.id)
    write(SQL.deleteGroup, { g.id }, 'disbanding group ' .. g.id)
    M.log:info('group %d "%s" disbanded (%s)', g.id, g.name, why)
    TriggerEvent('wasteland:groups:disbanded', g.id)
end

local function leave(src)
    local cid = characterOf(src)
    local g = cid and groups[memberOf[cid]]
    if not g then return end
    if g.leader == cid then
        if count(g) > 1 then notice(src, 'You lead the group: make someone else leader first, or disband it.'); return end
        disband(g, 'the last member left')
        return
    end
    local name = g.members[cid]
    removeMember(g, cid, 'left')
    notice(src, 'You left "' .. g.name .. '".')
    sendView(src)
    for mcid in pairs(g.members) do
        local s = sourceOf(mcid)
        if s then notice(s, name .. ' left the group.') end
    end
    refreshGroup(g)
end

local function leaderAction(src, targetCid, action)
    local cid = characterOf(src)
    local g = cid and groups[memberOf[cid]]
    if not g or g.leader ~= cid then notice(src, 'Only the leader can do that.'); return end
    if action == 'disband' then disband(g, 'by the leader'); return end
    if not g.members[targetCid] or targetCid == cid then return end
    local name = g.members[targetCid]
    if action == 'kick' then
        removeMember(g, targetCid, 'kicked')
        local s = sourceOf(targetCid)
        if s then notice(s, 'You were removed from "' .. g.name .. '".'); sendView(s) end
        notice(src, name .. ' was removed from the group.')
    elseif action == 'promote' then
        g.leader = targetCid
        write(SQL.setLeader, { targetCid, g.id }, 'new leader of group ' .. g.id)
        for mcid in pairs(g.members) do
            local s = sourceOf(mcid)
            if s then notice(s, name .. ' now leads the group.') end
        end
    end
    refreshGroup(g)
end

local function rename(src, name)
    local cid = characterOf(src)
    local g = cid and groups[memberOf[cid]]
    if not g or g.leader ~= cid then notice(src, 'Only the leader can rename the group.'); return end
    local clean, why = Rules.cleanName(name, M.config.nameMin, M.config.nameMax)
    if not clean then notice(src, why); return end
    if Rules.nameTaken(groups, clean, g.id) then notice(src, 'A group with that name already exists.'); return end
    g.name = clean
    write(SQL.rename, { clean, g.id }, 'renaming group ' .. g.id)
    refreshGroup(g)
end

-------------------------------------------------------------------------------
-- Map markers: every few seconds each online member gets the others' positions
-------------------------------------------------------------------------------

local function positions()
    for _, g in pairs(groups) do
        local online = {}
        for cid, name in pairs(g.members) do
            local s = sourceOf(cid)
            local ped = s and GetPlayerPed(tostring(s))
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local c = GetEntityCoords(ped)
                online[#online + 1] = { id = cid, src = s, name = name, x = c.x, y = c.y, z = c.z, leader = cid == g.leader,
                    dead = GetEntityHealth(ped) <= 0 }
            end
        end
        for _, me in ipairs(online) do
            local others = {}
            for _, o in ipairs(online) do
                if o.id ~= me.id then others[#others + 1] = { id = o.id, name = o.name, x = o.x, y = o.y, z = o.z, leader = o.leader, dead = o.dead } end
            end
            TriggerClientEvent('wasteland:groups:client:positions', me.src, { group = g.name, members = others })
        end
    end
end

local function loop(token)
    while runToken == token do
        Citizen.Wait(M.config.markerSeconds * 1000)
        if runToken ~= token then return end
        positions()
        local t = now()
        for cid, inv in pairs(invites) do if t > inv.expiresAt then invites[cid] = nil end end
    end
end

-- A member logs in: keep the stored name current, show them their group.
AddEventHandler('onResourceStart', function(res)
    if res == 'pma-voice' and M and M.active then Citizen.SetTimeout(2000, radioAll) end
end)

AddEventHandler('wasteland:players:characterLoaded', function(src, character)
    if not (M and M.active) or type(character) ~= 'table' then return end
    local g = groups[memberOf[character.id]]
    if not g then return end
    setRadio(src, g.id)
    local name = character.firstName .. ' ' .. character.lastName
    if g.members[character.id] ~= name then
        g.members[character.id] = name
        write(SQL.memberName, { name, character.id }, 'member name')
    end
    for cid in pairs(g.members) do
        local s = sourceOf(cid)
        if s and cid ~= character.id then notice(s, name .. ' is online.') end
    end
end)

AddEventHandler('wasteland:players:characterUnloaded', function(src, cid)
    if not (M and M.active) or not cid then return end
    if memberOf[cid] and GetPlayerName(tostring(src)) then setRadio(src, nil) end
    invites[cid] = nil
    local g = groups[memberOf[cid]]
    if g then Citizen.SetTimeout(500, function() if groups[g.id] then refreshGroup(g) end end) end
end)

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

M = Wasteland.DefineModule({
    name = 'groups',
    version = '0.1.0',
    description = 'Player groups: create, invite, map markers for members, persistent',
    core = '^1.1.0',
    dependencies = { database = '^0.1.0', players = '^0.1.0' },
    async = true,
    config = {
        file = 'groups.lua',
        optional = true,
        schema = { type = 'table', fields = {
            maxMembers = { type = 'integer', default = 8, min = 2, max = 50 },
            nameMin = { type = 'integer', default = 3, min = 1, max = 32 },
            nameMax = { type = 'integer', default = 24, min = 3, max = 32 },
            inviteSeconds = { type = 'integer', default = 120, min = 10, max = 3600 },
            markerSeconds = { type = 'number', default = 2, min = 0.5, max = 30, description = 'How often member markers move' },
            command = { type = 'string', default = 'group', pattern = '^[a-z][a-z0-9_]*$' },
            radio = { type = 'table', fields = {
                enabled = { type = 'boolean', default = true, description = 'Group radio through pma-voice (if it runs)' },
                channelBase = { type = 'integer', default = 1000, min = 1, max = 100000,
                    description = 'Group N talks on radio channel channelBase + N' },
                keyName = { type = 'string', default = 'Caps Lock', description = 'Shown to players (the key is pma-voice voice_defaultRadio)' },
            } },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        groups, memberOf, invites = {}, {}, {}
        local token = {}
        runToken = token
        Citizen.CreateThread(function()
            local ok, err = WDB.migrate('groups', WLG.MIGRATIONS)
            if runToken ~= token then return end
            if not ok then return M.fail('database migrations failed: ' .. tostring(err)) end
            local rows, qerr = WDB.query(SQL.selectGroups, {})
            local members, merr = WDB.query(SQL.selectMembers, {})
            if runToken ~= token then return end
            if not rows or not members then return M.fail('could not load groups: ' .. tostring(qerr or merr)) end
            for _, r in ipairs(rows) do groups[r.id] = { id = r.id, name = r.name, leader = r.leader_id, members = {} } end
            for _, r in ipairs(members) do
                local g = groups[r.group_id]
                if g then g.members[r.character_id], memberOf[r.character_id] = r.name, g.id end
            end
            -- A group whose leader is gone keeps going with another leader.
            for _, g in pairs(groups) do
                if not g.members[g.leader] then
                    local next = nil
                    for cid in pairs(g.members) do if not next or cid < next then next = cid end end
                    if next then g.leader = next; write(SQL.setLeader, { next, g.id }, 'repair leader') else
                        groups[g.id] = nil
                        write(SQL.deleteGroup, { g.id }, 'empty group')
                    end
                end
            end
            local n = 0
            for _ in pairs(groups) do n = n + 1 end
            M.log:info('%d groups loaded', n)
            Citizen.CreateThread(function() loop(token) end)
            radioAll()
            M.ready()
        end)
        return true
    end,
    onShutdown = function()
        runToken = nil
        TriggerClientEvent('wasteland:groups:client:positions', -1, nil)
    end,
})

local RATE = { burst = 5, perSecond = 1 }
local NAME = { type = 'string', required = true, maxLength = 64 }
local ID = { type = 'integer', required = true, min = 1 }

M.netEvent('wasteland:groups:server:view', { rateLimit = RATE }, function(src) sendView(src) end)
M.netEvent('wasteland:groups:server:create', { args = { NAME }, rateLimit = { burst = 3, perSecond = 0.3 } }, function(src, name)
    Citizen.CreateThread(function() create(src, name) end)
end)
M.netEvent('wasteland:groups:server:invite', { args = { { type = 'integer', required = true, min = 1, max = 65535 } }, rateLimit = RATE },
    function(src, target) invite(src, target) end)
M.netEvent('wasteland:groups:server:respond', { args = { ID, { type = 'boolean', required = true } }, rateLimit = RATE },
    function(src, groupId, accept) respond(src, groupId, accept) end)
M.netEvent('wasteland:groups:server:leave', { rateLimit = RATE }, function(src) leave(src) end)
M.netEvent('wasteland:groups:server:kick', { args = { ID }, rateLimit = RATE }, function(src, cid) leaderAction(src, cid, 'kick') end)
M.netEvent('wasteland:groups:server:promote', { args = { ID }, rateLimit = RATE }, function(src, cid) leaderAction(src, cid, 'promote') end)
M.netEvent('wasteland:groups:server:disband', { rateLimit = RATE }, function(src) leaderAction(src, nil, 'disband') end)
M.netEvent('wasteland:groups:server:rename', { args = { NAME }, rateLimit = { burst = 3, perSecond = 0.3 } }, function(src, name) rename(src, name) end)

-------------------------------------------------------------------------------
-- Exports (groups api 0.1)
-------------------------------------------------------------------------------

--- GetGroupOf(characterId) -> { id, name, leader, members = { characterId... } } | nil
exports('GetGroupOf', function(cid)
    local g = groups[memberOf[tonumber(cid)]]
    if not g then return nil end
    local list = {}
    for mcid in pairs(g.members) do list[#list + 1] = mcid end
    table.sort(list)
    return { id = g.id, name = g.name, leader = g.leader, members = list }
end)

--- SameGroup(characterIdA, characterIdB) -> boolean
exports('SameGroup', function(a, b)
    local ga = memberOf[tonumber(a)]
    return ga ~= nil and ga == memberOf[tonumber(b)]
end)

-- Server events: wasteland:groups:created(groupId, characterId), :joined(groupId, characterId),
-- :left(groupId, characterId, why), :disbanded(groupId)
