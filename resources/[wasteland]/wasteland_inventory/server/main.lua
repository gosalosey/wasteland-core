-- wasteland_inventory :: server/main.lua
-- Module "inventory": item definitions, grid inventories, equipment,
-- hotbar, drops and stashes, persisted in wl_items / wl_drops.

local Inv = WLI.Inv
local Store = WLI.Store
local Drops = WLI.Drops
local Sync = WLI.Sync
local Clothing = WLI.Clothing
local Interface = WLI.Interface

local commandRegistered = false
local netEventsRegistered = false
local runToken = nil

local function appearanceOf(characterId)
    if GetResourceState('wasteland_appearance') ~= 'started' then return nil end
    local ok, a = pcall(function() return exports.wasteland_appearance:GetAppearance(characterId) end)
    return ok and a or nil
end

--- Load a character's inventories (thread only).
local giveStarting -- below

function Inv.loadCharacter(src, cid)
    local c = { id = cid, source = src, pockets = 'player:' .. cid, equip = 'equip:' .. cid, loaded = false,
        hotbar = { false, false, false, false, false } }
    WLI.chars[cid] = c
    local pocketItems, e1 = Store.loadItems(c.pockets)
    local equipItems, e2 = pocketItems and Store.loadItems(c.equip)
    if WLI.chars[cid] ~= c then return end -- unloaded meanwhile
    if not pocketItems or not equipItems then
        WLI.M.log:error('could not load the inventory of character %d: %s', cid, tostring(e1 or e2))
        Sync.error(src, 'Your inventory could not be loaded. Reconnect, or tell an admin if this repeats.')
        WLI.chars[cid] = nil
        return
    end
    local p = WLI.cfg.pockets
    Inv.create(c.pockets, 'grid', { label = 'Pockets', width = p.width, height = p.height, maxWeight = p.maxWeight, items = pocketItems })
    Inv.create(c.equip, 'equip', { label = 'Worn', items = equipItems })
    for _, items in ipairs({ pocketItems, equipItems }) do
        for _, s in pairs(items) do
            if WLI.defs[s.name].container then
                Inv.loadContainer(s, Store.loadItems('item:' .. s.uid) or {})
            end
        end
    end
    local hotbar = exports.wasteland_players:GetCharacterData(cid, 'hotbar')
    if type(hotbar) == 'table' then
        for i = 1, 8 do c.hotbar[i] = type(hotbar[i]) == 'string' and hotbar[i] or false end
    end
    local meta = exports.wasteland_players:GetCharacterData(cid, 'inventory') or {}
    local appearance = appearanceOf(cid)
    c.model = appearance and appearance.model or nil
    c.loaded = true
    if appearance and not meta.clothingInitialized then
        Clothing.init(c, appearance)
        meta.clothingInitialized = true
    end
    -- pocket size from what is worn (nothing is lost: they stay big enough)
    Inv.fitPockets(c)
    -- Starting items once the outfit is on (worn clothes make the pockets
    -- bigger): a brand-new character gets them after the creator.
    if meta.clothingInitialized or GetResourceState('wasteland_appearance') ~= 'started' then
        giveStarting(src, cid, meta)
    end
    exports.wasteland_players:SetCharacterData(cid, 'inventory', meta)
    WLI.M.log:debug('loaded inventory of character %d', cid)
    Interface.sendDefinitions(src)
    Sync.player(src)
end

-- What a new character starts with (once).
giveStarting = function(src, cid, meta)
    if meta.startingItemsGiven then return end
    for _, entry in ipairs(WLI.cfg.startingItems) do
        local ok, err = Inv.addItem(src, entry.name, entry.count)
        if not ok then WLI.M.log:warn('starting item %s for character %d: %s', entry.name, cid, tostring(err)) end
    end
    meta.startingItemsGiven = true
end

function Inv.unloadCharacter(cid)
    local c = WLI.chars[cid]
    if not c then return end
    WLI.chars[cid] = nil
    if c.source then WLI.views[c.source] = nil end
    for _, id in ipairs({ c.pockets, c.equip }) do
        local inv = WLI.invs[id]
        if inv then
            for _, s in pairs(inv.items) do WLI.invs['item:' .. s.uid] = nil end
            WLI.invs[id] = nil
        end
    end
end

AddEventHandler('wasteland:players:characterLoaded', function(src, character)
    if not (WLI.M and WLI.M.active) or type(character) ~= 'table' then return end
    Citizen.CreateThread(function() Inv.loadCharacter(src, character.id) end)
end)

AddEventHandler('wasteland:players:characterUnloading', function(_, character)
    if type(character) == 'table' then Inv.unloadCharacter(character.id) end
end)

-- A new character finished the creator: its outfit becomes worn items.
AddEventHandler('wasteland:appearance:saved', function(src, characterId, appearance)
    local c = WLI.chars[characterId]
    if not c or not c.loaded or type(appearance) ~= 'table' then return end
    c.model = appearance.model
    local meta = exports.wasteland_players:GetCharacterData(characterId, 'inventory') or {}
    if not meta.clothingInitialized then
        Clothing.init(c, appearance)
        meta.clothingInitialized = true
        Inv.fitPockets(c)
        giveStarting(src, characterId, meta)
        exports.wasteland_players:SetCharacterData(characterId, 'inventory', meta)
        Sync.player(src)
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then WLI.views[src] = nil end
end)

local function maintenance(token)
    while runToken == token do
        Citizen.Wait(60000)
        if runToken ~= token then return end
        Drops.expire()
    end
end

local cell = function(max) return { type = 'integer', required = true, min = 1, max = max } end
local XY = function(w, h) return { type = 'table', fields = { width = cell(w), height = cell(h) } } end
local PART = { type = 'array', minItems = 2, maxItems = 2, items = { type = 'integer', min = 0, max = 1023 } }

WLI.M = Wasteland.DefineModule({
    name = 'inventory',
    version = '0.1.0',
    description = 'Grid inventories, equipment, hotbar, drops and stashes',
    core = '^1.1.0',
    dependencies = { database = '^0.1.0', players = '^0.1.0', ui = '^0.1.0' },
    optionalDependencies = { appearance = '^0.1.0' },
    async = true,
    config = {
        file = 'inventory.lua',
        optional = true,
        schema = {
            type = 'table',
            fields = {
                pockets = { type = 'table', fields = {
                    width = { type = 'integer', default = 6, min = 1, max = 20 },
                    height = { type = 'integer', default = 4, min = 1, max = 20 },
                    maxWeight = { type = 'number', default = 12, min = 0, max = 1000 },
                    maxWidth = { type = 'integer', min = 1, max = 20, description = 'Largest the pockets can get with bonuses' },
                    maxHeight = { type = 'integer', min = 1, max = 20 },
                    bonus = { type = 'map', default = {}, keys = { type = 'enum', values = WLI.EQUIP_SLOTS },
                        values = { type = 'table', fields = {
                            width = { type = 'integer', default = 0, min = 0, max = 20 },
                            height = { type = 'integer', default = 0, min = 0, max = 20 },
                        } },
                        description = 'Cells a worn item in this slot adds to the pockets' },
                } },
                dropGrid = { type = 'table', fields = {
                    width = { type = 'integer', default = 10, min = 4, max = 16 },
                    height = { type = 'integer', default = 10, min = 4, max = 16 },
                } },
                reachDistance = { type = 'number', default = 3.0, min = 1, max = 20,
                    description = 'Metres a player may be from a drop or stash to use it.' },
                dropMergeDistance = { type = 'number', default = 1.5, min = 0, max = 10,
                    description = 'Items dropped this close to an existing drop join it.' },
                dropLifetimeMinutes = { type = 'integer', default = 60, min = 1, max = 10080 },
                deathBagGrid = { type = 'table', fields = {
                    width = { type = 'integer', default = 12, min = 4, max = 16 },
                    height = { type = 'integer', default = 12, min = 4, max = 16 },
                } },
                deathBagLifetimeMinutes = { type = 'integer', default = 120, min = 1, max = 10080,
                    description = 'How long a body bag (items of a dead character) stays.' },
                maxQueuedWrites = { type = 'integer', default = 500, min = 10, max = 100000 },
                adminAce = { type = 'string', default = 'wasteland.admin', minLength = 1 },
                giveCommand = { type = 'string', default = 'give', pattern = '^[a-z][a-z0-9_]*$' },
                cashItem = { type = 'string', default = 'cash', pattern = '^[a-z][a-z0-9_]*$',
                    description = 'The item that is money (the only currency; no bank)' },
                startingItems = { type = 'array', default = {}, items = { type = 'table', fields = {
                    name = { type = 'string', required = true },
                    count = { type = 'integer', default = 1, min = 1, max = 10000 },
                } } },
                clothingItems = { type = 'map', default = {
                    torso = 'clothing_top', legs = 'clothing_pants', feet = 'clothing_shoes',
                    head = 'clothing_hat', eyes = 'clothing_glasses',
                }, keys = { type = 'enum', values = WLI.EQUIP_SLOTS }, values = { type = 'string' } },
                plain = { type = 'map', default = {}, keys = { type = 'enum', values = { 'mp_m_freemode_01', 'mp_f_freemode_01' } },
                    values = { type = 'map', values = PART },
                    description = 'Look of worn clothing items that carry none (given or looted), per model and part.' },
                naked = { type = 'map', default = {}, keys = { type = 'enum', values = { 'mp_m_freemode_01', 'mp_f_freemode_01' } },
                    values = { type = 'map', values = PART },
                    description = 'Component values shown when a clothing slot is empty, per model and part.' },
                items = { type = 'map', default = {}, keys = { type = 'string', pattern = WLI.NAME_PATTERN, maxLength = 48 },
                    values = { type = 'any' }, description = 'Item definitions (see the comments in the file).' },
            },
        },
    },

    onInit = function(M)
        WLI.M = M -- DefineModule may run onInit before it returns
        WLI.cfg = M.config
        -- Item definitions from config (each validated with a precise error).
        local defs = {}
        local Schema = Wasteland.Schema()
        for name, raw in pairs(M.config.items) do
            local d, err = WLI.validateItem(Schema, name, raw)
            if not d then return false, 'inventory.lua: items.' .. err end
            defs[name] = d
        end
        for slot, name in pairs(M.config.clothingItems) do
            if not defs[name] then return false, string.format('inventory.lua: clothingItems.%s names "%s", which is not in items', slot, name) end
            if defs[name].equip ~= slot then
                return false, string.format('inventory.lua: item "%s" must have equip = "%s" to be the %s clothing item', name, slot, slot)
            end
        end
        if not defs[M.config.cashItem] then
            return false, string.format('inventory.lua: cashItem names "%s", which is not in items', M.config.cashItem)
        end
        for _, entry in ipairs(M.config.startingItems) do
            if not defs[entry.name] then return false, string.format('inventory.lua: startingItems names unknown item "%s"', entry.name) end
        end
        WLI.defs = defs
        WLI.invs, WLI.chars, WLI.views, WLI.dropList = {}, {}, {}, {}
        if not commandRegistered then
            Interface.registerCommand(M.config)
            commandRegistered = true
        end
        if not netEventsRegistered then
            Interface.registerNetEvents(M)
            netEventsRegistered = true
        end
        local token = {}
        runToken = token
        Store.start()
        Citizen.CreateThread(function()
            local result, err = WDB.migrate('inventory', WLI.MIGRATIONS)
            if runToken ~= token then return end
            if not result then return M.fail('database migrations failed: ' .. tostring(err)) end
            local ok, derr = Drops.loadAll()
            if runToken ~= token then return end
            if not ok then return M.fail('could not load drops: ' .. tostring(derr)) end
            M.ready()
            Citizen.CreateThread(function() maintenance(token) end)
            -- Characters already playing (this resource restarted).
            for _, ch in ipairs(exports.wasteland_players:GetOnlineCharacters()) do
                if ch.source then Inv.loadCharacter(ch.source, ch.id) end
            end
            Drops.broadcast()
        end)
        return true
    end,

    onShutdown = function(M, reason)
        runToken = nil
        local n = Store.stop()
        if n > 0 then M.log:info('handed %d queued inventory change(s) to the database (%s)', n, tostring(reason)) end
        WLI.invs, WLI.chars, WLI.views, WLI.dropList = {}, {}, {}, {}
    end,
})
