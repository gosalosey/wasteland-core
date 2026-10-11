-- Wasteland Core :: survival (module "survival", resource wasteland_survival)
-- Hunger, thirst, bleeding, infection, body temperature, death and respawn.
-- The server keeps the numbers; players see them on the HUD (/hud cycles
-- compact -> only when it matters -> off).
return {
    -- How often (seconds) the server updates everyone's survival stats.
    tickSeconds = 10,

    -- A new character starts with these (0 - 100).
    start = { hunger = 100, thirst = 100 },

    -- Moderate pace: full to empty in 2 hours (food) and 1.5 hours (water).
    hunger = { drainPerHour = 50, starvingDamagePerMinute = 2 },
    thirst = { drainPerHour = 66.7, dehydratedDamagePerMinute = 3,
        hotMultiplier = 1.5 },   -- thirst drains faster while overheated

    bleeding = {
        enabled = true,
        minDamage = 10,           -- hits below this never cause bleeding
        chancePer10Damage = 0.25, -- 25% per 10 damage of one hit (capped at 100%)
        heavyDamage = 40,         -- one hit this big starts heavy bleeding at once
        damagePerMinute = { 2, 6, 12 },          -- light, heavy, severe
        clotChancePerMinute = { 0.2, 0.02, 0 },  -- chance it gets one level better by itself
    },

    infection = {
        enabled = true,
        growthPerMinute = 0.8,     -- an untreated infection gets worse (about 2 hours from 1 to 100)
        recoveryPerMinute = 3,     -- while antibiotics work
        damageThreshold = 60,      -- symptoms and damage from here
        damagePerMinute = 2,
        lethalDamagePerMinute = 20, -- at 100
    },

    temperature = {
        enabled = true,
        normal = 37.0,
        comfortLow = 12, comfortHigh = 30, -- "feels like" (air + clothing warmth - wet) in this range: no change
        wetPenalty = 10,                   -- being wet (swimming, rain) feels this much colder
        coldFactor = 0.2, heatFactor = 0.15, -- how far the body drifts per degree outside comfort
        changePerMinute = 0.3,
        hypothermia = 35.0, hyperthermia = 39.5,
        coldDamagePerMinute = 2, heatDamagePerMinute = 1,
        min = 30.0, max = 42.0,
    },

    -- Death and respawn.
    respawn = {
        delaySeconds = 15,                  -- before the Respawn button works
        stats = { hunger = 70, thirst = 70 }, -- after respawning (infection and bleeding reset)
        -- Random respawn points. z is corrected to the ground on arrival.
        points = {
            { x = -275.0, y = 6635.0, z = 7.4, heading = 45.0 },     -- Paleto Bay beach
            { x = 1308.0, y = 4241.0, z = 33.9, heading = 170.0 },   -- Alamo Sea shore
            { x = 1200.0, y = 2650.0, z = 37.8, heading = 0.0 },     -- Harmony
            { x = 2450.0, y = 4950.0, z = 45.0, heading = 0.0 },     -- Grapeseed
            { x = -3190.0, y = 1100.0, z = 20.5, heading = 270.0 },  -- Chumash
        },
    },

    -- What eating, drinking and medicine do (item names from inventory.lua).
    -- Fields: hunger, thirst, health (hit points), stopBleeding (levels),
    -- infection (+/-), treatmentMinutes (infection cannot grow meanwhile),
    -- temperature (degrees), animation ('eat' | 'drink' | 'treat'), message.
    consumables = {
        water_bottle = { thirst = 45, animation = 'drink' },
        soda_can = { thirst = 25, hunger = 5, animation = 'drink' },
        canned_beans = { hunger = 35, thirst = -5, animation = 'eat' },
        canned_peaches = { hunger = 25, thirst = 10, animation = 'eat' },
        energy_bar = { hunger = 15, animation = 'eat' },
        bandage = { stopBleeding = 3, health = 10, animation = 'treat', message = 'You bandage your wounds.' },
        rag = { stopBleeding = 1, animation = 'treat', message = 'You press the rag on the wound.' },
        painkillers = { health = 15, animation = 'eat', message = 'The pain fades a little.' },
        antibiotics = { infection = -40, treatmentMinutes = 20, animation = 'eat',
            message = 'You take the antibiotics.' },
    },
}
