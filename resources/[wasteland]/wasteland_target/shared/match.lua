-- wasteland_target :: shared/match.lua
-- Pure matching (no natives): which registered targets apply to what the
-- player is looking at, and which of their options are close enough.
-- Unit-tested.
--
-- A registration: { id, kind, options, ... } where kind is
--   'model'  models = { [hash] = true }
--   'entity' entity = handle (local)
--   'net'    netId = network id
--   'global' global = 'ped' | 'vehicle' | 'object' | 'player'
--   'zone'   zone = { shape = 'sphere', coords, radius } | { shape = 'box', coords, size = { x, y, z }, heading }
-- A hit: { entity, type = 'ped' | 'vehicle' | 'object' | 'player' | nil, model, netId, coords, distance }

WLT = WLT or {}
local Match = {}
WLT.Match = Match

Match.DEFAULT_DISTANCE = 2.5

--- Is point p inside the zone?
function Match.inZone(zone, p)
    if not zone or not p then return false end
    local c = zone.coords
    local dx, dy, dz = p.x - c.x, p.y - c.y, (p.z or 0) - (c.z or 0)
    if zone.shape == 'sphere' then
        return dx * dx + dy * dy + dz * dz <= zone.radius * zone.radius
    elseif zone.shape == 'box' then
        local h = -math.rad(zone.heading or 0)
        local lx = dx * math.cos(h) - dy * math.sin(h)
        local ly = dx * math.sin(h) + dy * math.cos(h)
        local s = zone.size
        return math.abs(lx) <= s.x / 2 and math.abs(ly) <= s.y / 2 and math.abs(dz) <= s.z / 2
    end
    return false
end

local function applies(r, hit)
    if r.kind == 'model' then return hit.entity ~= nil and hit.model ~= nil and r.models[hit.model] == true end
    if r.kind == 'entity' then return hit.entity ~= nil and r.entity == hit.entity end
    if r.kind == 'net' then return hit.netId ~= nil and r.netId == hit.netId end
    if r.kind == 'global' then return hit.type ~= nil and r.global == hit.type end
    if r.kind == 'zone' then return Match.inZone(r.zone, hit.coords) end
    return false
end
Match.applies = applies

--- Options that apply to `hit`, in registration order:
--- list of { reg, option, index }. `allowed(reg, option)` (optional)
--- decides the rest (canInteract); errors in it count as "no".
function Match.collect(registrations, hit, allowed)
    local out = {}
    if not hit or not hit.coords then return out end
    local ids = {}
    for id in pairs(registrations) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local r = registrations[id]
        if applies(r, hit) then
            for i, o in ipairs(r.options) do
                if (hit.distance or 0) <= (o.distance or Match.DEFAULT_DISTANCE) then
                    local ok, yes = true, true
                    if allowed then ok, yes = pcall(allowed, r, o) end
                    if ok and yes then out[#out + 1] = { reg = r, option = o, index = i } end
                end
            end
        end
    end
    return out
end

--- Normalise models given as a name, a hash or a list of either.
--- hash(name) turns a name into a hash (GetHashKey in the game).
function Match.models(list, hash)
    local out = {}
    if type(list) ~= 'table' then list = { list } end
    for _, m in ipairs(list) do
        if type(m) == 'string' then out[hash(m)] = true
        elseif type(m) == 'number' and math.tointeger(m) then
            -- A hash may be read signed or unsigned: match both forms.
            local u = math.tointeger(m) & 0xffffffff
            out[u] = true
            out[u >= 0x80000000 and u - 0x100000000 or u] = true
        end
    end
    return out
end

--- Check a list of options; returns a clean copy or nil, error.
function Match.options(list)
    if type(list) ~= 'table' then return nil, 'options must be a list' end
    if list.label then list = { list } end -- a single option
    local out = {}
    for i, o in ipairs(list) do
        if type(o) ~= 'table' or type(o.label) ~= 'string' or o.label == '' then
            return nil, string.format('option %d needs a label', i)
        end
        if o.onSelect == nil and o.event == nil and o.serverEvent == nil then
            return nil, string.format('option %d ("%s") needs onSelect, event or serverEvent', i, o.label)
        end
        out[i] = {
            label = o.label, icon = o.icon, name = o.name, distance = tonumber(o.distance),
            canInteract = o.canInteract, onSelect = o.onSelect, event = o.event, serverEvent = o.serverEvent, args = o.args,
        }
    end
    if #out == 0 then return nil, 'no options' end
    return out
end

return Match
