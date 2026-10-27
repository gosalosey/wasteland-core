-- wasteland_scrapweapons :: server/main.lua
-- Registers the catalog with the framework: each weapon's item with
-- wasteland_inventory, then the weapon with wasteland_weapons, then its
-- recipe with wasteland_crafting. Done again whenever one of those modules
-- (re)starts, so the start order does not matter. Holding, ammo, wear,
-- saving and trading are all handled by those modules.

local RES = GetCurrentResourceName()

local function log(fmt, ...) print(('[%s] ' .. fmt):format(RES, ...)) end

-- A module's resource can be started before the module itself is ready
-- (settings, database); only register with modules that are running. The
-- moduleState handler below registers again the moment each one is.
local function started(res, module)
    if GetResourceState(res) ~= 'started' then return false end
    local ok, running = pcall(function() return exports.wasteland_core:IsModuleRunning(module) end)
    return ok and running == true
end

local function call(res, fn, ...)
    local args = { ... }
    local ok, a, b = pcall(function() return exports[res][fn](exports[res], table.unpack(args)) end)
    if not ok then return false, tostring(a) end
    return a, b
end

local function registerItems()
    if not started('wasteland_inventory', 'inventory') then return nil end
    local n = 0
    for name, w in pairs(WLSW.catalog) do
        -- inventory.lua defines them (so loot, traders and drops know them from
        -- the start); register only what a server's own inventory.lua lacks
        local defined = call('wasteland_inventory', 'GetItemDefinition', name)
        local ok, err = true, nil
        if not defined then ok, err = call('wasteland_inventory', 'RegisterItem', name, w.item) end
        if ok then n = n + 1 else log('item %s: %s', name, tostring(err)) end
    end
    return n
end

local function registerWeapons()
    if not started('wasteland_weapons', 'weapons') then return nil end
    local n = 0
    for name, w in pairs(WLSW.catalog) do
        local ok, err = call('wasteland_weapons', 'RegisterWeapon', name, w.weapon)
        if ok then n = n + 1 else log('weapon %s: %s', name, tostring(err)) end
    end
    return n
end

local function registerRecipes()
    if not started('wasteland_crafting', 'crafting') then return nil end
    local n = 0
    for name, w in pairs(WLSW.catalog) do
        if w.recipe then
            local ok, err = call('wasteland_crafting', 'RegisterRecipe', name, w.recipe)
            if ok then n = n + 1 else log('recipe %s: %s', name, tostring(err)) end
        end
    end
    return n
end

local function registerAll()
    local items = registerItems()
    if not items then return end   -- inventory not running yet: its moduleState event brings us back
    local weapons, recipes = registerWeapons(), registerRecipes()
    local total = 0
    for _ in pairs(WLSW.catalog) do total = total + 1 end
    log('%d weapon(s) in the catalog: %d item(s), %d weapon(s), %d recipe(s) registered', total, items, weapons or 0, recipes or 0)
end

-- A module (re)started: what it holds was reset, so register again (in order:
-- items first, the weapons and recipes need them).
AddEventHandler('wasteland:core:moduleState', function(name, state)
    if state ~= 'running' then return end
    if name == 'inventory' then registerAll()
    elseif name == 'weapons' then registerWeapons()
    elseif name == 'crafting' then registerRecipes() end
end)

registerAll()   -- at once, in case the inventory is already running

--- GetCatalog() -> { [item] = { status, hash } }   (admin / tests)
exports('GetCatalog', function()
    local out = {}
    for name, w in pairs(WLSW.catalog) do out[name] = { status = w.status, hash = w.weapon and w.weapon.hash } end
    return out
end)
