-- wasteland_appearance :: shared/defs.lua
-- Appearance data format, validation schema and labels, shared by server
-- (validation) and client (creator, applying to the ped).
--
-- Stored per character as character data key "appearance" (players module):
-- {
--   v = 1,
--   model = 'mp_m_freemode_01' | 'mp_f_freemode_01',
--   heritage = { mother = 0..45, father = 0..45, shapeMix = 0..1, skinMix = 0..1 },
--   features = { 20 numbers -1..1 },          -- face features 0..19
--   hair = { style, color = 0..63, highlight = 0..63 },
--   eyeColor = 0..31,
--   overlays = { 13 x { style = 0..254 | 255 (none), opacity = 0..1, color = 0..63 } }, -- overlay i at [i+1]
--   components = { { id = 3|4|6|8|11, drawable, texture }, ... },   -- clothing
--   props = { { id = 0|1, drawable = -1 (none) .., texture }, ... }, -- hat, glasses
-- }
-- The server cannot know how many drawables each model has (that is client
-- game data); it checks types, bounds and allowed ids. The client clamps to
-- real counts before applying.

WLA = WLA or {}

WLA.VERSION = 1
WLA.MODELS = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
WLA.FEATURE_COUNT = 20
WLA.OVERLAY_COUNT = 13
WLA.PARENT_MAX = 45
WLA.COMPONENT_IDS = { 11, 8, 3, 4, 6 }   -- tops, undershirt, arms, legs, shoes (display order)
WLA.PROP_IDS = { 0, 1 }                  -- hat, glasses

WLA.FEATURE_LABELS = {
    'Nose width', 'Nose peak height', 'Nose peak length', 'Nose bone height', 'Nose peak lowering',
    'Nose bone twist', 'Eyebrow height', 'Eyebrow depth', 'Cheekbone height', 'Cheekbone width',
    'Cheek width', 'Eye opening', 'Lip thickness', 'Jaw width', 'Jaw length',
    'Chin height', 'Chin length', 'Chin width', 'Chin cleft', 'Neck thickness',
}

-- colorType: 0 = no colour, 1 = hair colours, 2 = makeup colours
WLA.OVERLAYS = {
    { index = 0, label = 'Blemishes', colorType = 0 },
    { index = 1, label = 'Facial hair', colorType = 1 },
    { index = 2, label = 'Eyebrows', colorType = 1 },
    { index = 3, label = 'Ageing', colorType = 0 },
    { index = 4, label = 'Makeup', colorType = 0 },
    { index = 5, label = 'Blush', colorType = 2 },
    { index = 6, label = 'Complexion', colorType = 0 },
    { index = 7, label = 'Sun damage', colorType = 0 },
    { index = 8, label = 'Lipstick', colorType = 2 },
    { index = 9, label = 'Moles and freckles', colorType = 0 },
    { index = 10, label = 'Chest hair', colorType = 1 },
    { index = 11, label = 'Body blemishes', colorType = 0 },
    { index = 12, label = 'More body blemishes', colorType = 0 },
}

WLA.COMPONENT_LABELS = { [11] = 'Top', [8] = 'Undershirt', [3] = 'Arms', [4] = 'Legs', [6] = 'Shoes' }
WLA.PROP_LABELS = { [0] = 'Hat', [1] = 'Glasses' }

-- Starting point for a new character (the player changes everything).
function WLA.defaults(model)
    local female = model == 'mp_f_freemode_01'
    local overlays = {}
    for i = 1, WLA.OVERLAY_COUNT do overlays[i] = { style = 255, opacity = 1.0, color = 0 } end
    local features = {}
    for i = 1, WLA.FEATURE_COUNT do features[i] = 0.0 end
    return {
        v = WLA.VERSION,
        model = female and 'mp_f_freemode_01' or 'mp_m_freemode_01',
        heritage = { mother = 21, father = 0, shapeMix = female and 0.2 or 0.8, skinMix = 0.5 },
        features = features,
        hair = { style = female and 4 or 2, color = 0, highlight = 0 },
        eyeColor = 0,
        overlays = overlays,
        components = {
            { id = 11, drawable = female and 0 or 0, texture = 0 },
            { id = 8, drawable = female and 14 or 15, texture = 0 },
            { id = 3, drawable = female and 0 or 0, texture = 0 },
            { id = 4, drawable = female and 0 or 0, texture = 0 },
            { id = 6, drawable = female and 1 or 1, texture = 0 },
        },
        props = { { id = 0, drawable = -1, texture = 0 }, { id = 1, drawable = -1, texture = 0 } },
    }
end

local unit = { type = 'number', required = true, min = 0, max = 1 }
local signed = { type = 'number', required = true, min = -1, max = 1 }
local color = { type = 'integer', required = true, min = 0, max = 63 }

WLA.SCHEMA = {
    type = 'table',
    required = true,
    fields = {
        v = { type = 'integer', required = true, min = 1, max = WLA.VERSION },
        model = { type = 'enum', required = true, values = WLA.MODELS },
        heritage = {
            type = 'table', required = true,
            fields = {
                mother = { type = 'integer', required = true, min = 0, max = WLA.PARENT_MAX },
                father = { type = 'integer', required = true, min = 0, max = WLA.PARENT_MAX },
                shapeMix = unit,
                skinMix = unit,
            },
        },
        features = { type = 'array', required = true, minItems = WLA.FEATURE_COUNT, maxItems = WLA.FEATURE_COUNT, items = signed },
        hair = {
            type = 'table', required = true,
            fields = {
                style = { type = 'integer', required = true, min = 0, max = 511 },
                color = color,
                highlight = color,
            },
        },
        eyeColor = { type = 'integer', required = true, min = 0, max = 31 },
        overlays = {
            type = 'array', required = true, minItems = WLA.OVERLAY_COUNT, maxItems = WLA.OVERLAY_COUNT,
            items = {
                type = 'table', required = true,
                fields = {
                    style = { type = 'integer', required = true, min = 0, max = 255 },
                    opacity = unit,
                    color = color,
                },
            },
        },
        components = {
            type = 'array', required = true, minItems = 0, maxItems = #WLA.COMPONENT_IDS,
            items = {
                type = 'table', required = true,
                fields = {
                    id = { type = 'integer', required = true, min = 0, max = 11 },
                    drawable = { type = 'integer', required = true, min = 0, max = 1023 },
                    texture = { type = 'integer', required = true, min = 0, max = 63 },
                },
            },
        },
        props = {
            type = 'array', required = true, minItems = 0, maxItems = #WLA.PROP_IDS,
            items = {
                type = 'table', required = true,
                fields = {
                    id = { type = 'integer', required = true, min = 0, max = 7 },
                    drawable = { type = 'integer', required = true, min = -1, max = 1023 },
                    texture = { type = 'integer', required = true, min = 0, max = 63 },
                },
            },
        },
    },
}

local function contains(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

--- Validate an appearance. `blocked` = { [model] = { [componentId] = { drawable, ... } } }.
--- Returns the cleaned appearance or nil, error message.
function WLA.validate(Schema, value, blocked)
    local clean, errors = Schema.validate(WLA.SCHEMA, value)
    if #errors > 0 then
        local e = errors[1]
        return nil, string.format('%s: %s', (e.path ~= '' and e.path) or 'appearance', e.message)
    end
    local seen = {}
    for i, c in ipairs(clean.components) do
        if not contains(WLA.COMPONENT_IDS, c.id) then
            return nil, string.format('components[%d]: clothing slot %d cannot be changed here', i, c.id)
        end
        if seen[c.id] then return nil, string.format('components[%d]: clothing slot %d appears twice', i, c.id) end
        seen[c.id] = true
        local list = blocked and blocked[clean.model] and blocked[clean.model][c.id]
        if list and contains(list, c.drawable) then
            return nil, string.format('components[%d]: that clothing item is not available', i)
        end
    end
    seen = {}
    for i, p in ipairs(clean.props) do
        if not contains(WLA.PROP_IDS, p.id) then
            return nil, string.format('props[%d]: accessory slot %d cannot be changed here', i, p.id)
        end
        if seen[p.id] then return nil, string.format('props[%d]: accessory slot %d appears twice', i, p.id) end
        seen[p.id] = true
    end
    return clean
end

return WLA
