-- wasteland_camps :: shared/zones.lua
-- Pure rules (no natives): which camp a point is in, and trade checks.
-- Unit-tested.

WLC = WLC or {}
local Zones = {}
WLC.Zones = Zones

local function dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
Zones.dist2d = dist2d

function Zones.dist3d(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- The camp `p` is in (circle on the ground, any height), or nil.
--- camps: list of { id, coords, radius, safe }
function Zones.campAt(camps, p)
    if not p then return nil end
    for _, c in ipairs(camps) do
        if dist2d(c.coords, p) <= c.radius then return c end
    end
    return nil
end

--- Is `p` inside a safe camp?
function Zones.isSafe(camps, p)
    local c = Zones.campAt(camps, p)
    return c ~= nil and c.safe ~= false
end

--- Can the player buy `count` of a shop entry? entry = { buy, stock }.
--- Returns total price or nil, reason.
function Zones.buyCheck(entry, count, stock, cash)
    if not entry or not entry.buy then return nil, 'This trader does not sell that.' end
    if math.type(count) ~= 'integer' or count < 1 then return nil, 'Choose how many.' end
    if stock < count then return nil, stock == 0 and 'Sold out. Come back later.' or string.format('Only %d left.', stock) end
    local price = entry.buy * count
    if cash < price then return nil, string.format('You need $%d (you have $%d).', price, cash) end
    return price
end

--- Can the player sell `count`? entry = { sell }. Returns total pay or nil, reason.
function Zones.sellCheck(entry, count, have)
    if not entry or not entry.sell then return nil, 'This trader does not buy that.' end
    if math.type(count) ~= 'integer' or count < 1 then return nil, 'Choose how many.' end
    if have < count then return nil, string.format('You only have %d.', have) end
    return entry.sell * count
end

--- What a trader pays for an item not on its list (buyAnything in camps.lua):
--- prices[name], else blueprints for blueprint_*, else categories[category],
--- else default; never more than half the lowest price any trader sells it
--- for (no buying low and selling high). nil: not bought.
--- def: item definition (category); cheapestBuy: lowest buy price or nil.
function Zones.anyPrice(cfg, name, def, cheapestBuy)
    if not cfg or not cfg.enabled or not def then return nil end
    for _, n in ipairs(cfg.except or {}) do if n == name then return nil end end
    local p = cfg.prices and cfg.prices[name]
    if not p and name:sub(1, 10) == 'blueprint_' then p = cfg.blueprints end
    if not p then p = cfg.categories and cfg.categories[def.category] end
    p = p or cfg.default
    if cheapestBuy then p = math.min(p, math.floor(cheapestBuy / 2)) end
    if not p or p < 1 then return nil end
    return math.floor(p)
end

--- Restock: every entry with a stock limit gains `restock` up to `stock`.
function Zones.restock(entries, current)
    for _, e in ipairs(entries) do
        if e.stock then
            current[e.name] = math.min(e.stock, (current[e.name] or e.stock) + (e.restock or 1))
        end
    end
end

return Zones
