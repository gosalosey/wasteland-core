-- wasteland_scrapweapons :: server/main.lua
-- Registers the catalog with the framework: each weapon's item with
-- wasteland_inventory, then the weapon with wasteland_weapons, then its
-- recipe with wasteland_crafting. Done again whenever one of those modules
-- (re)starts, so the start order does not matter. Holding, ammo, wear,
-- saving and trading are all handled by those modules.

local RES = GetCurrentResourceName()

local function log(fmt, ...) print(('[%s] ' .. fmt):format(RES, ...)) end

local function started(res) return GetResourceState(res) == 'started' end

local function call(res, fn, ...)
    local args = { ... }
    local ok, a, b = pcall(function() return exports[res][fn](exports[res], table.unpack(args)) end)
    if not ok then return false, tostring(a) end
    return a, b
end

local function registerItems()
    if not started('wasteland_inventory') then return 0 end
    local n = 0
    for name, w in pairs(WLSW.catalog) do
        local ok, err = call('wasteland_inventory', 'RegisterItem', name, w.item)
        if ok then n = n + 1 else log('item %s: %s', name, tostring(err)) end
    end
    return n
end

local function registerWeapons()
    if not started('wasteland_weapons') then return 0 end
    local n = 0
    for name, w in pairs(WLSW.catalog) do
        local ok, err = call('wasteland_weapons', 'RegisterWeapon', name, w.weapon)
        if ok then n = n + 1 else log('weapon %s: %s', name, tostring(err)) end
    end
    return n
end

local function registerRecipes()
    if not started('wasteland_crafting') then return 0 end
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
    local items, weapons, recipes = registerItems(), registerWeapons(), registerRecipes()
    local total = 0
    for _ in pairs(WLSW.catalog) do total = total + 1 end
    log('%d weapon(s) in the catalog: %d item(s), %d weapon(s), %d recipe(s) registered', total, items, weapons, recipes)
end

-- A module (re)started: what it holds was reset, so register again (in order:
-- items first, the weapons and recipes need them).
AddEventHandler('wasteland:core:moduleState', function(name, state)
    if state ~= 'running' then return end
    if name == 'inventory' then registerAll()
    elseif name == 'weapons' then registerWeapons()
    elseif name == 'crafting' then registerRecipes() end
end)

Citizen.CreateThread(function()
    Citizen.Wait(0)
    registerAll()
end)

--- GetCatalog() -> { [item] = { status, hash } }   (admin / tests)
exports('GetCatalog', function()
    local out = {}
    for name, w in pairs(WLSW.catalog) do out[name] = { status = w.status, hash = w.weapon and w.weapon.hash } end
    return out
end)
