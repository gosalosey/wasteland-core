-- wasteland_inventory :: server/clothing.lua
-- Clothing as items. A character's starting outfit (chosen in the
-- appearance creator) becomes worn clothing items once; after that,
-- clothes are found, worn and taken off like any other item.
--
-- Clothing item metadata: { model = 'mp_m_freemode_01', <part> = { d, t }, ... }
-- with parts per slot from WLI.CLOTHING_PARTS (torso: top, undershirt, arms).

local Inv = WLI.Inv
local Store = WLI.Store
local Clothing = {}
WLI.Clothing = Clothing

local function findPart(list, id)
    for _, p in ipairs(list or {}) do if p.id == id then return p end end
    return nil
end

--- Worn clothing items described by an appearance: { { slot, metadata } }.
function Clothing.fromAppearance(a)
    local out = {}
    for _, slot in ipairs(WLI.EQUIP_SLOTS) do
        local parts = WLI.CLOTHING_PARTS[slot]
        if parts and WLI.cfg.clothingItems[slot] then
            local meta, any = { model = a.model }, false
            for _, part in ipairs(parts) do
                if part.component then
                    local c = findPart(a.components, part.component)
                    if c then meta[part.key] = { c.drawable, c.texture }; any = true end
                else
                    local p = findPart(a.props, part.prop)
                    if p and p.drawable >= 0 then meta[part.key] = { p.drawable, p.texture }; any = true end
                end
            end
            if any then out[#out + 1] = { slot = slot, metadata = meta } end
        end
    end
    return out
end

--- Give a character the worn items of its starting outfit (once).
--- Returns the number of items created.
function Clothing.init(c, appearance)
    local equip = WLI.invs[c.equip]
    if not equip then return 0 end
    local statements, n = {}, 0
    for _, entry in ipairs(Clothing.fromAppearance(appearance)) do
        local taken = false
        for _, s in pairs(equip.items) do if s.slot == entry.slot then taken = true end end
        local name = WLI.cfg.clothingItems[entry.slot]
        if not taken and WLI.defs[name] then
            local s = { uid = Inv.newUid(), name = name, count = 1, slot = entry.slot, rotated = false, metadata = entry.metadata }
            equip.items[s.uid] = s
            statements[#statements + 1] = Store.upsert(s, equip.id)
            n = n + 1
        end
    end
    Store.enqueue(statements, string.format('starting outfit for character %d', c.id))
    Inv.fitPockets(c) -- the outfit makes the pockets bigger
    return n
end

return Clothing
