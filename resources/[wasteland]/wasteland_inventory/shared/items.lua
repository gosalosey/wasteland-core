-- wasteland_inventory :: shared/items.lua
-- Item definitions: schema, equipment slots and clothing mapping. Loaded on
-- server and client (the client gets the validated definitions from the
-- server; this file only provides the constants and the schema).

WLI = WLI or {}

-- Equipment slots, in display order. `back` holds a backpack (container).
WLI.EQUIP_SLOTS = { 'head', 'eyes', 'torso', 'back', 'legs', 'feet' }
WLI.EQUIP_SLOT_LABELS = {
    head = 'Head', eyes = 'Eyes', torso = 'Torso', back = 'Back', legs = 'Legs', feet = 'Feet',
}

-- Which part of the ped a clothing slot changes.
--   component: SetPedComponentVariation ids; prop: SetPedPropIndex ids
-- torso clothing carries three parts (top, undershirt, arms) because they
-- only look right together.
WLI.CLOTHING_PARTS = {
    torso = { { key = 'top', component = 11 }, { key = 'undershirt', component = 8 }, { key = 'arms', component = 3 } },
    legs = { { key = 'legs', component = 4 } },
    feet = { { key = 'shoes', component = 6 } },
    head = { { key = 'hat', prop = 0 } },
    eyes = { { key = 'glasses', prop = 1 } },
}

-- Stack size of items that do not set one (and can stack).
WLI.DEFAULT_STACK = 50

WLI.CATEGORIES = { 'food', 'drink', 'medical', 'material', 'tool', 'clothing', 'container', 'weapon', 'ammo', 'misc' }

WLI.ITEM_SCHEMA = {
    type = 'table',
    fields = {
        label = { type = 'string', required = true, minLength = 1, maxLength = 48 },
        description = { type = 'string', default = '', maxLength = 300 },
        category = { type = 'enum', values = WLI.CATEGORIES, default = 'misc' },
        width = { type = 'integer', default = 1, min = 1, max = 10, description = 'Grid cells wide' },
        height = { type = 'integer', default = 1, min = 1, max = 10, description = 'Grid cells high' },
        weight = { type = 'number', default = 0.1, min = 0, max = 1000, description = 'Kilograms per unit' },
        stack = { type = 'integer', min = 1, max = 1000000, description = 'Units per stack (1 = not stackable; default 50, or 1 for items that cannot stack)' },
        durability = { type = 'integer', default = 0, min = 0, max = 100000, description = '0 = no durability' },
        equip = { type = 'enum', values = WLI.EQUIP_SLOTS, description = 'Equipment slot this item can be worn in' },
        image = { type = 'string', pattern = '^[a-z0-9_%-]+$', maxLength = 96,
            description = 'Picture from wasteland_images (file name without .webp); default: the item name' },
        container = {
            type = 'table', nullable = true,
            description = 'Wearing this item adds a grid (backpacks)',
            fields = {
                width = { type = 'integer', required = true, min = 1, max = 12 },
                height = { type = 'integer', required = true, min = 1, max = 12 },
                maxWeight = { type = 'number', required = true, min = 0, max = 1000 },
            },
        },
        color = { type = 'string', pattern = '^#%x%x%x%x%x%x$', description = 'Tile colour in the UI' },
        warmth = { type = 'number', default = 0, min = 0, max = 30,
            description = 'Degrees C of insulation while worn (survival temperature)' },
        repairs = { type = 'enum', values = WLI.CATEGORIES,
            description = 'Category of items this one repairs: the screen offers "Repair with ..." on damaged items of it' },
    },
}

WLI.NAME_PATTERN = '^[a-z][a-z0-9_]*$'

--- Validate one definition. Returns def or nil, error.
function WLI.validateItem(Schema, name, raw)
    if type(name) ~= 'string' or not name:match(WLI.NAME_PATTERN) or #name > 48 then
        return nil, string.format('item name %q must match [a-z][a-z0-9_]* (max 48)', tostring(name))
    end
    local def, errors = Schema.validate(WLI.ITEM_SCHEMA, raw)
    if #errors > 0 then
        local e = errors[1]
        return nil, string.format('item "%s": %s: %s', name, e.path ~= '' and e.path or 'definition', e.message)
    end
    if def.container and def.equip ~= 'back' then
        return nil, string.format('item "%s": a container must be worn on the back (equip = "back")', name)
    end
    local unstackable = def.durability > 0 or def.container ~= nil or def.equip ~= nil
    if def.stack == nil then def.stack = unstackable and 1 or WLI.DEFAULT_STACK end
    if def.stack > 1 and unstackable then
        return nil, string.format('item "%s": items with durability, containers and wearables cannot stack', name)
    end
    def.name = name
    return def
end

return WLI
