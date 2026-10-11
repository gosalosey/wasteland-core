-- Crafting rules (wasteland_crafting/shared/recipes.lua) with the shipped config.

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_crafting/shared/recipes.lua', 't', env))()
local Recipes = env.WLCR.Recipes

local f = assert(io.open(RESOURCES .. '/wasteland_config/config/crafting.lua', 'rb'))
local cfg = assert(load(f:read('a'), '@crafting.lua', 't', {}))(); f:close()

describe('crafting recipes', function()
    it('bandages and rags are known from the start; the rest need a blueprint', function()
        expect(Recipes.knows({}, 'bandage', cfg.recipes.bandage)).toBe(true)
        expect(Recipes.knows({}, 'rag', cfg.recipes.rag)).toBe(true)
        expect(Recipes.knows({}, 'weapon_knife', cfg.recipes.weapon_knife)).toBe(false)
        expect(Recipes.knows({ weapon_knife = true }, 'weapon_knife', cfg.recipes.weapon_knife)).toBe(true)
        expect(Recipes.knows({}, 'nope', nil)).toBe(false)
    end)
    it('lists what is missing', function()
        local have = { scrap_metal = 1, duct_tape = 5 }
        local m = Recipes.missing(cfg.recipes.weapon_repair_kit, function(n) return have[n] end)
        expect(#m).toBe(1); expect(m[1].name).toBe('scrap_metal'); expect(m[1].need).toBe(3); expect(m[1].have).toBe(1)
        have.scrap_metal = 3
        expect(#Recipes.missing(cfg.recipes.weapon_repair_kit, function(n) return have[n] end)).toBe(0)
    end)
    it('a blueprint teaches its recipes', function()
        local t = Recipes.taughtBy(cfg.recipes, 'blueprint_machete')
        expect(#t).toBe(1); expect(t[1]).toBe('weapon_machete')
        expect(#Recipes.taughtBy(cfg.recipes, 'bandage')).toBe(0)
    end)
end)
