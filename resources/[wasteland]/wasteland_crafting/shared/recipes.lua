-- wasteland_crafting :: shared/recipes.lua
-- Pure rules (no natives): who knows a recipe and what is missing.
-- Unit-tested.

WLCR = WLCR or {}
local Recipes = {}
WLCR.Recipes = Recipes

--- Does a character know this recipe? Recipes without a blueprint are
--- known by everyone; the others once their blueprint was used.
--- known: { [recipeName] = true }
function Recipes.knows(known, name, recipe)
    if not recipe then return false end
    if not recipe.blueprint then return true end
    return known ~= nil and known[name] == true
end

--- What is missing to craft `recipe`: list of { name, need, have }.
--- count(itemName) -> how many the player carries.
function Recipes.missing(recipe, count)
    local out = {}
    for _, ing in ipairs(recipe.ingredients) do
        local have = count(ing.name) or 0
        if have < ing.count then out[#out + 1] = { name = ing.name, need = ing.count, have = have } end
    end
    return out
end

--- Recipe names a blueprint item teaches (sorted).
function Recipes.taughtBy(recipes, blueprintItem)
    local out = {}
    for name, r in pairs(recipes) do
        if r.blueprint == blueprintItem then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

return Recipes
