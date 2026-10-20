-- Wasteland Core :: moonshine (wasteland_moonshine)
--
-- A moonshine still is crafted and placed anywhere. Each run takes the
-- flavour's crop, sugar, water and firewood, brews for `brewSeconds`, then
-- gives jars to collect. Drinking moonshine heals a little, eases the
-- zombie infection, makes you drunk, and fills the Zombie Blind meter: when
-- it is full, zombies ignore you until it drains below `unmaskBelow`.
return {
    stillItem = 'moonshine_still',
    stillModel = 'wl_moonshine_still',
    maxStillsPerPlayer = 3,
    streamDistance = 150,
    brewSeconds = 120,          -- one run
    jarsPerRun = 2,
    -- brew several runs at once (each uses a full set of ingredients and
    -- gives jarsPerRun); every extra run adds this share of brewSeconds
    maxBatch = 10,
    batchSecondsFactor = 0.5,
    -- what every run needs besides the flavour's crop
    base = { { name = 'sugar', count = 2 }, { name = 'water_bottle', count = 1 }, { name = 'firewood', count = 1 } },

    -- flavours: the crop and how many of it
    flavours = {
        corn = { label = 'Corn moonshine', item = 'moonshine_corn', crop = 'corn', count = 4 },
        strawberry = { label = 'Strawberry moonshine', item = 'moonshine_strawberry', crop = 'strawberry', count = 6 },
        cucumber = { label = 'Cucumber moonshine', item = 'moonshine_cucumber', crop = 'cucumber', count = 4 },
        blueberry = { label = 'Blueberry moonshine', item = 'moonshine_blueberry', crop = 'blueberry', count = 8 },
        cranberry = { label = 'Cranberry moonshine', item = 'moonshine_cranberry', crop = 'cranberry', count = 8 },
        potato = { label = 'Potato moonshine', item = 'moonshine_potato', crop = 'potato', count = 4 },
        watermelon = { label = 'Watermelon moonshine', item = 'moonshine_watermelon', crop = 'watermelon', count = 1 },
    },

    -- one jar: health back (of 100), infection taken off, thirst, and how
    -- much drunk (0 - 100) and Zombie Blind (0 - 100) it adds
    drink = { health = 3, infection = 3, thirst = 4, drunk = 18, blind = 34 },

    -- drunk wears off this much a minute
    soberPerMinute = 6,
    -- Zombie Blind: drains this much a minute; zombies ignore you once it is
    -- full (100), until it drains below unmaskBelow
    blindPerMinute = 10,
    unmaskBelow = 40,
}
