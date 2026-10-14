-- wasteland_survival :: shared/model.lua
-- The survival rules as pure functions (no natives, no state). The server
-- runs them; the tests check them exactly.
--
-- state = {
--   hunger, thirst      0..100 (100 = full)
--   infection           0..100 (100 = lethal)
--   treatment           seconds of antibiotic treatment left (infection does not grow)
--   bleeding            0 = none, 1 light, 2 heavy, 3 severe
--   temperature         body temperature in degrees C (37 = normal)
--   dead                boolean
-- }
-- env = { ambient = degrees C, wet = boolean, warmth = degrees C of worn insulation }

WLS = WLS or {}
WLS.Model = WLS.Model or {}
local Model = WLS.Model

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
Model.clamp = clamp

function Model.fresh(cfg)
    return {
        hunger = cfg.start.hunger, thirst = cfg.start.thirst, infection = 0, treatment = 0,
        bleeding = 0, temperature = cfg.temperature.normal, dead = false,
        bladder = 0, bowel = 0,
    }
end

--- Temperature the body moves towards, from what it "feels like".
function Model.targetTemperature(cfg, env)
    local t = cfg.temperature
    local feels = (env.ambient or 20) + (env.warmth or 0) - ((env.wet and t.wetPenalty) or 0)
    local target = t.normal
    if feels < t.comfortLow then
        target = t.normal - (t.comfortLow - feels) * t.coldFactor
    elseif feels > t.comfortHigh then
        target = t.normal + (feels - t.comfortHigh) * t.heatFactor
    end
    return clamp(target, t.min, t.max), feels
end

--- Advance `state` by `dt` seconds. Returns damage (hit points, fractional)
--- and a set of reasons ({ starving = true, ... }) for the damage.
function Model.tick(state, dt, cfg, env)
    local minutes = dt / 60
    local hours = dt / 3600
    local reasons, damage = {}, 0
    if state.dead then return 0, reasons end

    -- hunger and thirst (heat makes you thirstier)
    state.hunger = clamp(state.hunger - cfg.hunger.drainPerHour * hours, 0, 100)
    local thirstRate = cfg.thirst.drainPerHour
    if cfg.temperature.enabled and state.temperature > cfg.temperature.normal + 1 then
        thirstRate = thirstRate * cfg.thirst.hotMultiplier
    end
    state.thirst = clamp(state.thirst - thirstRate * hours, 0, 100)
    local t = cfg.toilet
    if t and t.enabled then
        state.bladder = clamp((state.bladder or 0) + t.bladderPerHour * hours, 0, 100)
        state.bowel = clamp((state.bowel or 0) + t.bowelPerHour * hours, 0, 100)
    end
    if state.hunger <= 0 then
        damage = damage + cfg.hunger.starvingDamagePerMinute * minutes
        reasons.starving = true
    end
    if state.thirst <= 0 then
        damage = damage + cfg.thirst.dehydratedDamagePerMinute * minutes
        reasons.dehydrated = true
    end

    -- bleeding: drains health; light bleeding may stop by itself
    if cfg.bleeding.enabled and state.bleeding > 0 then
        damage = damage + (cfg.bleeding.damagePerMinute[state.bleeding] or 0) * minutes
        reasons.bleeding = true
    end

    -- infection: grows unless treated; hurts above a threshold
    if cfg.infection.enabled and state.infection > 0 then
        if state.treatment > 0 then
            state.treatment = math.max(0, state.treatment - dt)
            state.infection = clamp(state.infection - cfg.infection.recoveryPerMinute * minutes, 0, 100)
        else
            state.infection = clamp(state.infection + cfg.infection.growthPerMinute * minutes, 0, 100)
        end
        if state.infection >= 100 then
            damage = damage + cfg.infection.lethalDamagePerMinute * minutes
            reasons.infection = true
        elseif state.infection >= cfg.infection.damageThreshold then
            damage = damage + cfg.infection.damagePerMinute * minutes
            reasons.infection = true
        end
    elseif state.treatment > 0 then
        state.treatment = math.max(0, state.treatment - dt)
    end

    -- body temperature moves towards what the surroundings dictate
    if cfg.temperature.enabled then
        local t = cfg.temperature
        local target = Model.targetTemperature(cfg, env)
        local step = t.changePerMinute * minutes
        if state.temperature < target then
            state.temperature = math.min(target, state.temperature + step)
        else
            state.temperature = math.max(target, state.temperature - step)
        end
        if state.temperature <= t.hypothermia then
            damage = damage + t.coldDamagePerMinute * minutes
            reasons.cold = true
        elseif state.temperature >= t.hyperthermia then
            damage = damage + t.heatDamagePerMinute * minutes
            reasons.heat = true
        end
    end
    return damage, reasons
end

--- Chance per minute that light bleeding stops: roll once per tick.
function Model.clotChance(cfg, state, dt)
    local perMinute = cfg.bleeding.clotChancePerMinute[state.bleeding] or 0
    return 1 - (1 - perMinute) ^ (dt / 60)
end

--- The player took `amount` damage from the world: maybe start bleeding.
--- `roll` is a random number 0..1. Returns true if bleeding got worse.
function Model.onDamage(state, cfg, amount, roll)
    if state.dead or not cfg.bleeding.enabled or amount < cfg.bleeding.minDamage then return false end
    local chance = math.min(1, cfg.bleeding.chancePer10Damage * amount / 10)
    if roll >= chance then return false end
    local levels = amount >= cfg.bleeding.heavyDamage and 2 or 1
    local before = state.bleeding
    state.bleeding = math.min(3, state.bleeding + levels)
    return state.bleeding > before
end

--- Apply a consumable's effect. Returns the health to restore (hit points).
--- effect = { hunger, thirst, infection, treatmentMinutes, stopBleeding (levels),
---            temperature, health }
function Model.consume(state, effect)
    if effect.hunger then state.hunger = clamp(state.hunger + effect.hunger, 0, 100) end
    if effect.thirst then state.thirst = clamp(state.thirst + effect.thirst, 0, 100) end
    if effect.infection then state.infection = clamp(state.infection + effect.infection, 0, 100) end
    if effect.treatmentMinutes then state.treatment = math.max(state.treatment, effect.treatmentMinutes * 60) end
    if effect.stopBleeding then state.bleeding = math.max(0, state.bleeding - effect.stopBleeding) end
    if effect.temperature then state.temperature = state.temperature + effect.temperature end
    return effect.health or 0
end

--- Would this consumable do anything right now? (refuse wasting items)
function Model.useful(state, effect)
    if effect.health and effect.health > 0 then return true end
    if effect.hunger and effect.hunger > 0 and state.hunger < 100 then return true end
    if effect.thirst and effect.thirst > 0 and state.thirst < 100 then return true end
    if effect.stopBleeding and state.bleeding > 0 then return true end
    if (effect.infection and effect.infection < 0 or effect.treatmentMinutes) and state.infection > 0 then return true end
    if effect.temperature then return true end
    return false
end

--- Warmth a worn piece still gives: full when new, half when nearly worn
--- out, nothing when ruined. max = 0: no durability (always full).
function Model.clothingWarmth(warmth, current, max)
    warmth = tonumber(warmth) or 0
    if not max or max <= 0 then return warmth end
    current = tonumber(current) or max
    if current <= 0 then return 0 end
    return warmth * (0.5 + 0.5 * math.min(1, current / max))
end

return Model
