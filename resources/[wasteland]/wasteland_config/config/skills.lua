-- Skills: get better at what you do. Every skill levels 1 - 10 by doing it;
-- each level makes it a little better (level 1 = no bonus, 10 = the full
-- bonus below). /skills (or F7) shows your levels.
return {
    maxLevel = 10,

    -- XP from one level to the next: base x level ^ growth
    -- (100, 283, 520 ... about 11 000 XP in all to reach 10).
    xpCurve = { base = 100, growth = 1.5 },

    -- What dying costs. mode: 'none' (keep everything), 'some' (lose
    -- `percent` of the progress into each skill's current level - never a
    -- level), 'all' (every skill back to level 1).
    deathPenalty = { mode = 'some', percent = 10 },

    -- Each skill: label, XP per action, bonuses at the top level (shares:
    -- 0.3 = 30 %).
    skills = {
        scavenging = { label = 'Scavenging',
            xp = { search = 10 },                                -- searching a container or body that had something
            bonus = { searchTime = 0.3, extraLoot = 0.25 } },    -- 30 % faster searches; 25 % chance of an extra find when it refills
        crafting = { label = 'Crafting',
            xp = { craft = 15 },
            bonus = { craftTime = 0.3, saveChance = 0.2 } },     -- 30 % faster; 20 % chance to get one material back
        medicine = { label = 'Medicine',
            xp = { treat = 15 },                                 -- bandages, medkits, antibiotics...
            bonus = { heal = 0.5 } },                            -- healing items heal 50 % more
        hunting = { label = 'Hunting',
            xp = { harvest = 25 },
            bonus = { extraMeat = 0.5 } },                       -- 50 % more meat
        fitness = { label = 'Fitness',
            xp = { sprintMinute = 6 },                           -- a minute of sprinting
            bonus = { stamina = 0.3 } },                         -- stamina lasts longer
        combat = { label = 'Combat',
            xp = { kill = 8 },                                   -- a zombie you killed
            bonus = { meleeDamage = 0.2, weaponWear = 0.3 } },   -- 20 % more melee damage; weapons wear 30 % slower
    },

    -- XP gained is multiplied by this (2 = double XP weekend).
    xpMultiplier = 1.0,
}
