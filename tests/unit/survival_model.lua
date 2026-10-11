-- Survival rules (wasteland_survival/shared/model.lua) with the shipped config.

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_survival/shared/model.lua', 't', env))()
local Model = env.WLS.Model

-- The shipped config file, evaluated like the core does (sandbox).
local function shippedConfig()
    local f = assert(io.open(RESOURCES .. '/wasteland_config/config/survival.lua', 'rb'))
    local src = f:read('a'); f:close()
    return assert(load(src, '@survival.lua', 't', { math = math }))()
end
local cfg = shippedConfig()

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

describe('hunger and thirst', function()
    it('drain at the configured pace: food 2 hours, water 1.5 hours', function()
        local s = Model.fresh(cfg)
        Model.tick(s, 3600, cfg, { ambient = 20 })
        expect(near(s.hunger, 50)).toBe(true)
        expect(near(s.thirst, 100 - 66.7, 0.01)).toBe(true)
    end)
    it('hurt once empty', function()
        local s = Model.fresh(cfg)
        s.hunger, s.thirst = 0, 0
        local dmg, why = Model.tick(s, 60, cfg, { ambient = 20 })
        expect(near(dmg, 2 + 3)).toBe(true)
        expect(why.starving).toBe(true); expect(why.dehydrated).toBe(true)
    end)
    it('overheating makes you thirstier', function()
        local s = Model.fresh(cfg)
        s.temperature = 39
        Model.tick(s, 3600, cfg, { ambient = 30 })
        expect(s.thirst < 100 - 66.7).toBe(true)
    end)
end)

describe('bleeding', function()
    it('starts from big enough hits, by chance, worse for heavy hits', function()
        local s = Model.fresh(cfg)
        expect(Model.onDamage(s, cfg, 5, 0)).toBe(false)        -- below minDamage
        expect(Model.onDamage(s, cfg, 20, 0.6)).toBe(false)     -- 50% chance, roll 0.6
        expect(Model.onDamage(s, cfg, 20, 0.1)).toBe(true)
        expect(s.bleeding).toBe(1)
        expect(Model.onDamage(s, cfg, 50, 0.1)).toBe(true)      -- heavy: +2
        expect(s.bleeding).toBe(3)
    end)
    it('drains health per level and light bleeding can clot', function()
        local s = Model.fresh(cfg)
        s.bleeding = 2
        local dmg = Model.tick(s, 60, cfg, { ambient = 20 })
        expect(near(dmg, 6)).toBe(true)
        s.bleeding = 1
        expect(near(Model.clotChance(cfg, s, 60), 0.2)).toBe(true)
        s.bleeding = 3
        expect(Model.clotChance(cfg, s, 60)).toBe(0)
    end)
end)

describe('infection', function()
    it('grows untreated and hurts above the threshold, lethally at 100', function()
        local s = Model.fresh(cfg)
        s.infection = 59.9
        local dmg = Model.tick(s, 60, cfg, { ambient = 20 })
        expect(s.infection > 60).toBe(true)
        expect(dmg > 0).toBe(true)
        s.infection = 100
        local lethal = Model.tick(s, 60, cfg, { ambient = 20 })
        expect(near(lethal, 20)).toBe(true)
    end)
    it('antibiotics reduce it and stop growth while they work', function()
        local s = Model.fresh(cfg)
        s.infection = 70
        Model.consume(s, cfg.consumables.antibiotics)
        expect(s.infection).toBe(30)
        expect(s.treatment).toBe(20 * 60)
        Model.tick(s, 60, cfg, { ambient = 20 })
        expect(near(s.infection, 27)).toBe(true)
    end)
end)

describe('body temperature', function()
    it('stays normal in comfortable weather with ordinary clothes', function()
        local target = Model.targetTemperature(cfg, { ambient = 15, warmth = 6 })
        expect(target).toBe(37.0)
    end)
    it('gets colder when cold, wet and underdressed; clothes help', function()
        local cold = Model.targetTemperature(cfg, { ambient = 2, wet = true, warmth = 0 })
        local dressed = Model.targetTemperature(cfg, { ambient = 2, wet = false, warmth = 14 })
        expect(cold < 35).toBe(true)
        expect(dressed > cold).toBe(true)
    end)
    it('moves slowly towards the target and hurts at hypothermia', function()
        local s = Model.fresh(cfg)
        Model.tick(s, 60, cfg, { ambient = -20, wet = true })
        expect(near(s.temperature, 36.7)).toBe(true)
        s.temperature = 34.9
        local dmg, why = Model.tick(s, 60, cfg, { ambient = -20, wet = true })
        expect(why.cold).toBe(true)
        expect(dmg >= 2).toBe(true)
    end)
end)

describe('consumables', function()
    it('apply their effects within limits and report healing', function()
        local s = Model.fresh(cfg)
        s.hunger, s.thirst, s.bleeding = 90, 50, 2
        expect(Model.consume(s, cfg.consumables.canned_beans)).toBe(0)
        expect(s.hunger).toBe(100)
        expect(s.thirst).toBe(45)
        expect(Model.consume(s, cfg.consumables.bandage)).toBe(10)
        expect(s.bleeding).toBe(0)
    end)
    it('are refused when they would do nothing', function()
        local s = Model.fresh(cfg)
        expect(Model.useful(s, cfg.consumables.canned_beans)).toBe(false) -- full
        expect(Model.useful(s, cfg.consumables.rag)).toBe(false)          -- not bleeding
        expect(Model.useful(s, cfg.consumables.antibiotics)).toBe(false)  -- not infected
        expect(Model.useful(s, cfg.consumables.bandage)).toBe(true)       -- heals
    end)
end)

describe('clothing warmth', function()
    it('full when new, at least half while worn, none when ruined', function()
        expect(Model.clothingWarmth(6, 100, 100)).toBe(6)
        expect(Model.clothingWarmth(6, nil, 100)).toBe(6)
        expect(Model.clothingWarmth(6, 50, 100)).toBe(4.5)
        expect(Model.clothingWarmth(6, 1, 100) >= 3).toBe(true)
        expect(Model.clothingWarmth(6, 0, 100)).toBe(0)
        expect(Model.clothingWarmth(6, 0, 0)).toBe(6) -- no durability
    end)
end)
