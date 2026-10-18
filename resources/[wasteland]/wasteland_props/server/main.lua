-- wasteland_props :: server/main.lua
-- Prop placer: admins place any GTA (or streamed) prop anywhere, move it,
-- delete it; every prop is saved and comes back after a restart. Players'
-- games spawn the props near them (not networked: no entity cost).
-- /propplacer (admins) opens the placer.

local SQL = WLPR.SQL
local M
local props = {}   -- id -> { id, model, x, y, z, rx, ry, rz, collision }
local count = 0
local runToken = nil

local COORD = { type = 'number', required = true, min = -20000, max = 20000 }
local ANGLE = { type = 'number', required = true, min = -720, max = 720 }
local MODEL = { type = 'string', required = true, pattern = '^[%w_%-]+$', minLength = 2, maxLength = 64 }

local function isAdmin(src)
    return src and src > 0 and IsPlayerAceAllowed(tostring(src), M.config.adminAce) == true
end

local function list()
    local out = {}
    for _, p in pairs(props) do out[#out + 1] = p end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function round(v, places)
    local m = 10 ^ places
    return math.floor(v * m + 0.5) / m
end

local function clean(x, y, z, rx, ry, rz)
    return round(x, 3), round(y, 3), round(z, 3), round(rx % 360, 2), round(ry % 360, 2), round(rz % 360, 2)
end

local function deny(src)
    TriggerClientEvent('wasteland:props:client:notice', src, 'Only admins can place props.', true)
end

local function notice(src, msg, bad) TriggerClientEvent('wasteland:props:client:notice', src, msg, bad == true) end

local function nameOf(src)
    local ok, lic = pcall(GetPlayerIdentifierByType, tostring(src), 'license')
    return (ok and lic) or GetPlayerName(tostring(src)) or tostring(src)
end

M = Wasteland.DefineModule({
    name = 'props',
    version = '1.0.0',
    description = 'Prop placer: admins place, move and delete saved props anywhere',
    core = '^1.1.0',
    dependencies = { database = '^0.1.0' },
    async = true,
    config = {
        file = 'props.lua',
        optional = true,
        schema = { type = 'table', fields = {
            adminAce = { type = 'string', default = 'wasteland.admin', maxLength = 64 },
            maxProps = { type = 'integer', default = 5000, min = 1, max = 100000 },
            streamDistance = { type = 'number', default = 200, min = 30, max = 1000,
                description = 'Players see props this close (metres)' },
            maxPlaceDistance = { type = 'number', default = 30, min = 5, max = 200,
                description = 'How far from the admin a prop can be placed' },
            presets = { type = 'array', default = {}, items = { type = 'table', fields = {
                group = { type = 'string', required = true, maxLength = 32 },
                label = { type = 'string', required = true, maxLength = 48 },
                model = { type = 'string', required = true, pattern = '^[%w_%-]+$', maxLength = 64 },
            } } },
        } },
    },

    onInit = function(mod)
        M = mod
        props, count = {}, 0
        local token = {}
        runToken = token
        Citizen.CreateThread(function()
            local ok, err = WDB.migrate('props', WLPR.MIGRATIONS)
            if runToken ~= token then return end
            if not ok then return M.fail('database migrations failed: ' .. tostring(err)) end
            local rows, e = WDB.query(SQL.select, {})
            if runToken ~= token then return end
            if not rows then return M.fail('could not load props: ' .. tostring(e)) end
            for _, r in ipairs(rows) do
                props[r.id] = { id = r.id, model = r.model, x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0,
                    rx = r.rx + 0.0, ry = r.ry + 0.0, rz = r.rz + 0.0, collision = r.collision == 1 or r.collision == true }
                count = count + 1
            end
            M.log:info('%d placed props loaded', count)
            M.ready()
            TriggerClientEvent('wasteland:props:client:list', -1, list(), M.config.streamDistance)
        end)
        return true
    end,

    onShutdown = function()
        runToken = nil
        TriggerClientEvent('wasteland:props:client:list', -1, {}, 0)
    end,
})

-- Everyone: the props to show.
M.netEvent('wasteland:props:server:request', { rateLimit = { burst = 3, perSecond = 0.2 } }, function(src)
    TriggerClientEvent('wasteland:props:client:list', src, list(), M.config.streamDistance)
end)

-- Admins: open the placer.
M.netEvent('wasteland:props:server:open', { rateLimit = { burst = 4, perSecond = 1 } }, function(src)
    if not isAdmin(src) then return deny(src) end
    TriggerClientEvent('wasteland:props:client:open', src, { presets = M.config.presets, maxPlaceDistance = M.config.maxPlaceDistance })
end)

local function nearEnough(src, x, y, z)
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 then return true end -- no OneSync position: trust the admin
    local c = GetEntityCoords(ped)
    if not c then return true end
    local dx, dy, dz = c.x - x, c.y - y, c.z - z
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= M.config.maxPlaceDistance + 5
end

M.netEvent('wasteland:props:server:place', {
    args = { MODEL, COORD, COORD, COORD, ANGLE, ANGLE, ANGLE, { type = 'boolean', required = true } },
    rateLimit = { burst = 6, perSecond = 3 },
}, function(src, model, x, y, z, rx, ry, rz, collision)
    if not isAdmin(src) then return deny(src) end
    if count >= M.config.maxProps then return notice(src, 'The prop limit is reached (props.lua maxProps).', true) end
    if not nearEnough(src, x, y, z) then return notice(src, 'That spot is too far from you.', true) end
    x, y, z, rx, ry, rz = clean(x, y, z, rx, ry, rz)
    local now = os.time()
    Citizen.CreateThread(function()
        local id, err = WDB.insert(SQL.insert, { model, x, y, z, rx, ry, rz, collision and 1 or 0, nameOf(src), now })
        if not id then return notice(src, 'Could not save the prop: ' .. tostring(err), true) end
        local p = { id = id, model = model, x = x, y = y, z = z, rx = rx, ry = ry, rz = rz, collision = collision }
        props[id] = p
        count = count + 1
        M.log:info('prop %d (%s) placed by %s at %.1f %.1f %.1f', id, model, GetPlayerName(tostring(src)) or src, x, y, z)
        TriggerClientEvent('wasteland:props:client:set', -1, p)
        notice(src, ('Placed %s (#%d).'):format(model, id))
    end)
end)

M.netEvent('wasteland:props:server:update', {
    args = { { type = 'integer', required = true, min = 1 }, COORD, COORD, COORD, ANGLE, ANGLE, ANGLE, { type = 'boolean', required = true } },
    rateLimit = { burst = 6, perSecond = 3 },
}, function(src, id, x, y, z, rx, ry, rz, collision)
    if not isAdmin(src) then return deny(src) end
    local p = props[id]
    if not p then return notice(src, 'That prop is gone.', true) end
    if not nearEnough(src, x, y, z) then return notice(src, 'That spot is too far from you.', true) end
    x, y, z, rx, ry, rz = clean(x, y, z, rx, ry, rz)
    Citizen.CreateThread(function()
        local ok, err = WDB.update(SQL.update, { x, y, z, rx, ry, rz, collision and 1 or 0, id })
        if not ok then return notice(src, 'Could not save the move: ' .. tostring(err), true) end
        p.x, p.y, p.z, p.rx, p.ry, p.rz, p.collision = x, y, z, rx, ry, rz, collision
        TriggerClientEvent('wasteland:props:client:set', -1, p)
        notice(src, ('Moved %s (#%d).'):format(p.model, id))
    end)
end)

M.netEvent('wasteland:props:server:delete', {
    args = { { type = 'integer', required = true, min = 1 } },
    rateLimit = { burst = 6, perSecond = 3 },
}, function(src, id)
    if not isAdmin(src) then return deny(src) end
    local p = props[id]
    if not p then return notice(src, 'That prop is gone.', true) end
    Citizen.CreateThread(function()
        local ok, err = WDB.update(SQL.delete, { id })
        if not ok then return notice(src, 'Could not delete the prop: ' .. tostring(err), true) end
        props[id] = nil
        count = count - 1
        M.log:info('prop %d (%s) deleted by %s', id, p.model, GetPlayerName(tostring(src)) or src)
        TriggerClientEvent('wasteland:props:client:remove', -1, id)
        notice(src, ('Deleted %s (#%d).'):format(p.model, id))
    end)
end)

--- GetProps() -> list of placed props (for other modules).
exports('GetProps', function() return list() end)
