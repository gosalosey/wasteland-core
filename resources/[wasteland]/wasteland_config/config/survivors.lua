-- Survivors (module "survivors", resource wasteland_survivors).
--
-- People who made it: a few wander the map near players. They leave you
-- alone unless you hurt them; then they fight back (and survivors close by
-- turn on you too). They fight the zombies, and the zombies go for them.
--
-- Help one: kill zombies close to a survivor (helpRadius). After helpKills
-- of them, hold Left Alt on the survivor: Talk - they give you something
-- (once per survivor). Trade: every survivor has a few swaps of their own
-- (your items for theirs), each a limited number of times.
--
-- Voices: the game's own voice lines (screams for help, thanks, hello,
-- insults), with what they shout written above their head.
return {
    spawn = {
        enabled = true,
        perPlayer = 1,           -- survivors near each player
        max = 12,                -- on the whole map
        minDistance = 110,       -- metres from the player (out of sight)
        maxDistance = 220,
        everySeconds = 45,
        chance = 0.5,            -- each time: the chance one comes near a player who has none
        despawnDistance = 400,   -- no player this close ...
        despawnAfterSeconds = 60, -- ... for this long: gone
        deadMinutes = 5,         -- a body lasts this long
    },

    -- Ped models (any GTA ped) and the guns / blades they carry (GTA weapon
    -- names; what a survivor carries is never dropped).
    models = {
        'a_m_m_hillbilly_01', 'a_m_m_hillbilly_02', 'a_m_m_salton_01', 'a_m_m_salton_02', 'a_m_y_hippy_01',
        'a_m_m_farmer_01', 'a_m_y_methhead_01', 'a_f_m_salton_01', 'a_f_y_hippie_01', 'a_m_m_trampbeac_01',
        's_m_y_construct_01', 'a_m_y_cyclist_01', 'a_f_y_tourist_01', 'a_m_m_tramp_01',
    },
    weapons = { 'WEAPON_PISTOL', 'WEAPON_PUMPSHOTGUN', 'WEAPON_MACHETE', 'WEAPON_BAT', 'WEAPON_DBSHOTGUN', 'WEAPON_HATCHET' },
    names = { 'Dale', 'Marisol', 'Hank', 'Rosa', 'Wes', 'Tammy', 'Earl', 'June', 'Boone', 'Nadia', 'Cody', 'Lupe', 'Vern', 'Ivy' },

    health = 250,                -- more than a person in the city
    armour = 25,
    accuracy = 35,               -- 0-100
    engageRadius = 40,           -- they go for zombies this close

    -- Helping and the reward.
    helpRadius = 30,             -- a zombie killed this close to a survivor counts as help
    helpKills = 2,
    rewardPicks = 2,             -- how many things from the list below
    rewards = {
        { name = 'ammo_12g', min = 4, max = 10, weight = 20 },
        { name = 'ammo_308', min = 3, max = 8, weight = 10 },
        { name = 'bandage', min = 1, max = 3, weight = 20 },
        { name = 'painkillers', min = 1, max = 2, weight = 10 },
        { name = 'canned_beans', min = 1, max = 2, weight = 15 },
        { name = 'water_bottle', min = 1, max = 2, weight = 15 },
        { name = 'scrap_metal', min = 3, max = 8, weight = 15 },
        { name = 'duct_tape', min = 1, max = 2, weight = 10 },
        { name = 'gun_parts', min = 1, max = 2, weight = 5 },
        { name = 'antibiotics', min = 1, max = 1, weight = 3 },
    },

    -- Hurting one: the survivors this close turn on you too.
    hostileSpreadRadius = 40,

    -- Trading: every survivor has `offersEach` of these swaps, each a few
    -- `times` (give: what you hand over; get: what you get).
    trade = {
        offersEach = 3,
        offers = {
            { give = { name = 'scrap_metal', count = 10 }, get = { name = 'ammo_12g', count = 6 }, times = 3, weight = 15 },
            { give = { name = 'raw_meat', count = 3 }, get = { name = 'canned_beans', count = 2 }, times = 3, weight = 10 },
            { give = { name = 'cooked_meat', count = 2 }, get = { name = 'bandage', count = 2 }, times = 3, weight = 10 },
            { give = { name = 'animal_pelt', count = 2 }, get = { name = 'ammo_308', count = 5 }, times = 2, weight = 8 },
            { give = { name = 'water_bottle', count = 2 }, get = { name = 'painkillers', count = 1 }, times = 3, weight = 10 },
            { give = { name = 'wood_planks', count = 10 }, get = { name = 'nails', count = 20 }, times = 2, weight = 8 },
            { give = { name = 'firewood', count = 4 }, get = { name = 'matches', count = 2 }, times = 3, weight = 8 },
            { give = { name = 'canned_beans', count = 3 }, get = { name = 'duct_tape', count = 2 }, times = 2, weight = 8 },
            { give = { name = 'beer', count = 3 }, get = { name = 'gun_parts', count = 1 }, times = 2, weight = 5 },
            { give = { name = 'moonshine_corn', count = 1 }, get = { name = 'antibiotics', count = 1 }, times = 2, weight = 4 },
            { give = { name = 'stone', count = 10 }, get = { name = 'metal_sheet', count = 1 }, times = 2, weight = 6 },
            { give = { name = 'scrap_metal', count = 6 }, get = { name = 'water_bottle', count = 2 }, times = 3, weight = 10 },
        },
    },

    -- What they say. Each line is a game voice line (any GTA speech name)
    -- and the words shown above their head.
    voice = {
        help = { lines = { 'GENERIC_FRIGHTENED_HIGH', 'GENERIC_SHOCKED_HIGH', 'GENERIC_FRIGHTENED_MED' },
            text = { 'Help! Somebody help me!', 'Over here! They\'re everywhere!', 'Get them off me!', 'I can\'t hold them back!' },
            everySeconds = 10 },
        thanks = { lines = { 'GENERIC_THANKS' }, text = { 'Thank you! Come talk to me.', 'You saved my life!' } },
        greet = { lines = { 'GENERIC_HI', 'GENERIC_HOWS_IT_GOING' }, text = { 'Hey. Easy now.', 'You\'re not one of them. Good.' },
            everySeconds = 45 },
        angry = { lines = { 'GENERIC_INSULT_HIGH', 'GENERIC_CURSE_HIGH' }, text = { 'You\'ll pay for that!', 'Big mistake!' },
            everySeconds = 15 },
        bye = { lines = { 'GENERIC_BYE' }, text = { 'Stay alive out there.' } },
    },
    hearDistance = 60,           -- players this close hear (and see) what they say

    adminCommand = 'survivors',  -- /survivors count | clear | spawn (admins)
}
