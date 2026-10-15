-- Wasteland Core :: survival (module "survival", resource wasteland_survival)
-- Hunger, thirst, bleeding, infection, body temperature, death and respawn.
-- The server keeps the numbers; players see them on the HUD (/hud cycles
-- compact -> only when it matters -> off).
return {
    -- How often (seconds) the server updates everyone's survival stats.
    tickSeconds = 10,

    -- Admin command for testing and support:
    --   /survival <server id> <hunger|thirst|infection|bleeding|temperature> <value>
    adminCommand = 'survival',
    adminAce = 'wasteland.admin',

    -- A new character starts with these (0 - 100).
    start = { hunger = 100, thirst = 100 },

    -- Moderate pace: full to empty in 2 hours (food) and 1.5 hours (water).
    hunger = { drainPerHour = 50, starvingDamagePerMinute = 2 },
    thirst = { drainPerHour = 66.7, dehydratedDamagePerMinute = 3,
        hotMultiplier = 1.5 },   -- thirst drains faster while overheated

    -- Needing the toilet (0 = empty, 100 = you really have to go). /pee and
    -- /poop empty them (with an animation); drinking fills the bladder and
    -- eating the bowels a bit faster. minToGo: below this you do not need to.
    toilet = {
        enabled = true,
        bladderPerHour = 50, bowelPerHour = 25,
        drinkToBladder = 0.4, foodToBowel = 0.3, -- share of thirst / hunger restored
        minToGo = 20,
        -- Where the pee stream starts, from the hips: offset { right, forward,
        -- up } in metres, rotation, size. Find good numbers in-game with
        -- /peetest x y z rx ry rz scale (e.g. /peetest 0.2 0.2 0 -110 0 0 2),
        -- then put them here.
        pee = {
            male = { offset = { 0.2, 0.2, 0.0 }, rotation = { -110.0, 0.0, 0.0 }, scale = 2.0 },
            female = { offset = { 0.2, 0.2, 0.0 }, rotation = { -110.0, 0.0, 0.0 }, scale = 1.2 },
        },
    },

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
            { x = 1856.17, y = 3681.37, z = 34.27, heading = 213.11 },   -- Sandy safe zone
            { x = -438.82, y = 6021.24, z = 31.49, heading = 313.63 },   -- Paleto safe zone
            { x = 292.82, y = -607.50, z = 43.34, heading = 72.26 },     -- Pillbox safe zone
            { x = -1128.59, y = 4924.85, z = 219.44, heading = 133.84 }, -- Chiliad safe zone
        },
    },

    -- What eating, drinking and medicine do (item names from inventory.lua).
    -- Fields: hunger, thirst, health (hit points), stopBleeding (levels),
    -- infection (+/-), treatmentMinutes (infection cannot grow meanwhile),
    -- temperature (degrees), animation ('eat' | 'drink' | 'treat'), message,
    -- prop (game model held in the hand while using it; an unknown model is skipped).
    consumables = {
        water_bottle = { thirst = 45, animation = 'drink', prop = 'prop_ld_flow_bottle' },
        soda_can = { thirst = 25, hunger = 5, animation = 'drink', prop = 'prop_ecola_can' },
        canned_beans = { hunger = 35, thirst = -5, animation = 'eat', prop = 'prop_ecola_can' },
        canned_peaches = { hunger = 25, thirst = 10, animation = 'eat', prop = 'prop_ecola_can' },
        energy_bar = { hunger = 15, animation = 'eat', prop = 'prop_choc_ego' },
        raw_meat = { hunger = 10, infection = 5, animation = 'eat', prop = 'prop_cs_steak',
            message = 'Raw meat. Your stomach does not like it.' },
        cooked_meat = { hunger = 45, thirst = -5, health = 5, animation = 'eat', prop = 'prop_cs_steak' },
        canned_tuna = { hunger = 25, thirst = -5, animation = 'eat', prop = 'prop_ld_can_01' },
        canned_salmon = { hunger = 30, thirst = -5, animation = 'eat', prop = 'prop_ld_can_01' },
        canned_soup = { hunger = 25, thirst = 15, temperature = 0.5, animation = 'eat', prop = 'prop_ld_can_01' },
        canned_stew = { hunger = 40, thirst = 5, temperature = 0.5, animation = 'eat', prop = 'prop_ld_can_01' },
        mre_beef = { hunger = 60, thirst = -5, health = 5, animation = 'eat', prop = 'prop_food_bs_chips' },
        mre_chicken = { hunger = 60, thirst = -5, health = 5, animation = 'eat', prop = 'prop_food_bs_chips' },
        crisps = { hunger = 10, thirst = -10, animation = 'eat', prop = 'ng_proc_food_chips01a' },
        peanut_butter = { hunger = 30, thirst = -10, animation = 'eat', prop = 'prop_ld_can_01' },
        bread = { hunger = 20, thirst = -5, animation = 'eat', prop = 'prop_food_bs_burger2' },
        apple = { hunger = 10, thirst = 8, animation = 'eat', prop = 'ng_proc_food_aple1a' },
        banana = { hunger = 12, thirst = 3, animation = 'eat', prop = 'ng_proc_food_bag01a' },
        orange = { hunger = 8, thirst = 12, animation = 'eat', prop = 'ng_proc_food_ornge1a' },
        sprunk = { thirst = 25, hunger = 5, animation = 'drink', prop = 'ng_proc_sodacan_01b' },
        coffee = { thirst = 15, temperature = 0.8, animation = 'drink', prop = 'p_amb_coffeecup_01', message = 'The coffee warms you up.' },
        milk = { thirst = 30, hunger = 10, animation = 'drink', prop = 'prop_cs_milk_01' },
        grape_juice = { thirst = 35, hunger = 3, animation = 'drink', prop = 'prop_ld_flow_bottle' },
        beer = { thirst = 15, hunger = 3, animation = 'drink', prop = 'prop_cs_beer_bot_01' },
        whiskey = { thirst = -10, temperature = 1.0, health = 3, animation = 'drink', prop = 'prop_whiskey_bottle',
            message = 'It burns on the way down, but you feel warmer.' },
        bandage = { stopBleeding = 3, health = 10, animation = 'treat', prop = 'prop_ld_health_pack',
            message = 'You bandage your wounds.' },
        rag = { stopBleeding = 1, animation = 'treat', prop = 'prop_shower_towel',
            message = 'You press the rag on the wound.' },
        painkillers = { health = 15, animation = 'eat', prop = 'prop_cs_pills', message = 'The pain fades a little.' },
        antibiotics = { infection = -40, treatmentMinutes = 20, animation = 'eat', prop = 'prop_cs_pills',
            message = 'You take the antibiotics.' },
    },

    -- Clothing durability (clothing items with `durability` in inventory.lua).
    -- A zombie hit wears one worn piece; a ruined piece gives no warmth
    -- (a worn one gives at least half). Repair items: how much one use mends
    -- (percent of new); each use uses up one.
    clothing = {
        hitWear = { 4, 10 },
        repairItems = { sewing_kit = { percent = 50 } },
    },

    -- Armor plates (items worn in the Armor slot): while a plate holds, all
    -- incoming damage is stopped (and zombie hits cannot cause bleeding;
    -- infection still can). The plate loses wearPerDamage durability per
    -- point of damage it stops (0.25: a new plate stops about 400 damage).
    -- Repair items: how much one use repairs (percent of new).
    armor = {
        wearPerDamage = 0.25,
        repairItems = { armor_repair_kit = { percent = 40 } },
    },
}
