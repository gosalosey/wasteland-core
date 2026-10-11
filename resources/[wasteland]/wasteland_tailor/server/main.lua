-- wasteland_tailor :: server/main.lua
-- Module "tailor": NPC tailors (tailor.lua) where players restyle the
-- clothes they are wearing. The client previews the looks; the server checks
-- the player stands at a tailor, that every piece is worn clothing and the
-- values are sane, takes the cash, then writes the new look onto the items
-- (the inventory puts it on the ped).

local M
local MODELS = { mp_m_freemode_01 = true, mp_f_freemode_01 = true }

local function inv() return exports.wasteland_inventory end
local function notice(src, msg) TriggerClientEvent('wasteland:tailor:client:notice', src, msg) end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

local function near(src, shop)
    local p = playerCoords(src)
    if not p then return false end
    local c = shop.coords
    local dx, dy, dz = p.x - c.x, p.y - c.y, p.z - c.z
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= M.config.reach
end

-- Check one slot's new look against the worn item and the slot's parts.
-- Returns { uid, patch } or nil, reason.
local function checkPiece(worn, partsBySlot, model, change)
    local item
    for _, w in ipairs(worn) do if w.slot == change.slot then item = w end end
    if not item or item.category ~= 'clothing' then return nil, 'You are not wearing anything there.' end
    local parts = partsBySlot[change.slot]
    if not parts then return nil, 'That cannot be restyled.' end
    local patch = { model = model }
    for _, part in ipairs(parts) do
        local v = change.look[part.key]
        if v ~= nil then
            local d, t = math.tointeger(v[1]), math.tointeger(v[2])
            if not d or not t or d < 0 or d > 1000 or t < 0 or t > 100 then return nil, 'That look is not possible.' end
            patch[part.key] = { d, t }
        end
    end
    return { uid = item.uid, patch = patch }
end

M = Wasteland.DefineModule({
    name = 'tailor',
    version = '0.1.0',
    description = 'Tailors: restyle the clothes you wear for cash',
    core = '^1.1.0',
    dependencies = { players = '^0.1.0', inventory = '^0.1.0' },
    config = {
        file = 'tailor.lua',
        optional = true,
        schema = { type = 'table', fields = {
            price = { type = 'integer', default = 25, min = 0, max = 1000000, description = 'Cash per piece changed' },
            reach = { type = 'number', default = 4.0, min = 1, max = 20 },
            model = { type = 'string', default = 's_f_y_shop_mid', pattern = '^[%w_]+$' },
            blip = { type = 'table', fields = {
                sprite = { type = 'integer', default = 73, min = 0, max = 1000 },
                color = { type = 'integer', default = 25, min = 0, max = 100 },
                label = { type = 'string', default = 'Tailor', maxLength = 40 },
            } },
            shops = { type = 'array', default = {}, items = { type = 'table', fields = {
                label = { type = 'string', required = true, minLength = 1, maxLength = 40 },
                coords = { type = 'table', required = true, fields = {
                    x = { type = 'number', required = true }, y = { type = 'number', required = true },
                    z = { type = 'number', required = true }, heading = { type = 'number', default = 0 },
                } },
            } } },
        } },
    },
    onInit = function(mod)
        M = mod -- DefineModule may run onInit before it returns
        TriggerClientEvent('wasteland:tailor:client:config', -1, M.config)
        return true
    end,
})

M.netEvent('wasteland:tailor:server:config', { rateLimit = { burst = 3, perSecond = 0.5 } }, function(src)
    TriggerClientEvent('wasteland:tailor:client:config', src, M.config)
end)

-- changes: list of { slot, look = { [partKey] = { drawable, texture } } }
M.netEvent('wasteland:tailor:server:buy', {
    args = {
        { type = 'integer', required = true, min = 1, max = 100 },
        { type = 'string', required = true, pattern = '^[%w_]+$', maxLength = 32 },
        { type = 'array', required = true, minItems = 1, maxItems = 10, items = { type = 'table', fields = {
            slot = { type = 'string', required = true, pattern = '^[a-z]+$', maxLength = 16 },
            look = { type = 'map', required = true, keys = { type = 'string', pattern = '^[a-z]+$', maxLength = 16 },
                values = { type = 'array', minItems = 2, maxItems = 2, items = { type = 'integer' } } },
        } } },
    },
    rateLimit = { burst = 3, perSecond = 1 },
}, function(src, shopIndex, model, changes)
    local shop = M.config.shops[shopIndex]
    if not shop or not near(src, shop) then notice(src, 'You are too far from the tailor.'); return end
    if not MODELS[model] then return end
    local worn = inv():GetWornItems(src)
    local partsBySlot = inv():GetClothingParts()
    local pieces, seen = {}, {}
    for _, change in ipairs(changes) do
        if seen[change.slot] then notice(src, 'That look is not possible.'); return end
        seen[change.slot] = true
        local piece, why = checkPiece(worn, partsBySlot, model, change)
        if not piece then notice(src, why); return end
        pieces[#pieces + 1] = piece
    end
    local cost = M.config.price * #pieces
    if cost > 0 then
        local ok = inv():RemoveCash(src, cost)
        if not ok then notice(src, string.format('That costs $%d. You do not have enough cash.', cost)); return end
    end
    for _, p in ipairs(pieces) do
        local ok, err = inv():SetItemMetadata(src, p.uid, p.patch)
        if not ok then M.log:warn('player %d restyle %s: %s', src, p.uid, tostring(err)) end
    end
    M.log:info('player %d restyled %d piece(s) for $%d at %s', src, #pieces, cost, shop.label)
    TriggerClientEvent('wasteland:tailor:client:done', src, cost, #pieces)
end)

--- GetTailors() -> list of { label, coords }
exports('GetTailors', function() return M and M.config.shops or {} end)
