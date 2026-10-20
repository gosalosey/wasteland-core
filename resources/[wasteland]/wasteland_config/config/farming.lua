-- Wasteland Core :: farming (wasteland_farming)
--
-- Farm plots are crafted (small, medium, large) and placed anywhere, inside
-- or outside. Plant seeds, keep the plot watered (water bottles; a plot
-- outdoors waters itself while it rains), and harvest when the crop is ripe.
-- Plants only grow while the plot has water. Left Alt on a plot opens it:
-- every spot's crop, its water and how long until it can be harvested.
return {
    tickSeconds = 60,          -- how often plants grow (and water is used), real seconds
    streamDistance = 150,      -- players see plots this close (metres)
    maxPlotsPerPlayer = 12,    -- plots one character may have placed
    waterItem = 'water_bottle',
    maxWaterMinutes = 180,     -- a plot holds at most this much water (minutes of growing)
    seedBackChance = 0.6,      -- chance a harvest also gives 1 - 2 seeds back
    rainWeathers = { 'RAIN', 'THUNDER' }, -- a plot outdoors (no roof over it) is watered in these

    -- Rain catcher: crafted, placed outdoors (not under a roof). Fills only
    -- while it rains (litresPerMinute), up to capacityLitres; Left Alt >
    -- Collect water turns it into water bottles (litresPerBottle each).
    rainCatcher = { item = 'rain_catcher', model = 'wl_farm_raincatcher', capacityLitres = 10, litresPerMinute = 0.35,
        litresPerBottle = 0.5, maxPerPlayer = 6 },

    -- size: spots per side (1 = 1 spot, 2 = 4 spots, 3 = 9 spots);
    -- waterPerBottle: minutes of water one bottle gives the whole plot.
    plots = {
        small = { label = 'Small farm plot', item = 'farm_plot_small', model = 'wl_farm_plot_small', size = 1, waterPerBottle = 90 },
        medium = { label = 'Medium farm plot', item = 'farm_plot_medium', model = 'wl_farm_plot_medium', size = 2, waterPerBottle = 45 },
        large = { label = 'Large farm plot', item = 'farm_plot_large', model = 'wl_farm_plot_large', size = 3, waterPerBottle = 30 },
    },

    -- Plant models by growth: sprout (0 - 25%), young (to 60%), grown (to
    -- 100%), then ripe (fruit in the crop's colour: red, orange, yellow,
    -- green, purple, blue, brown or white).
    stages = { sprout = 'wl_farm_plant_sprout', young = 'wl_farm_plant_young', grown = 'wl_farm_plant_grown', ripe = 'wl_farm_plant_ripe_%s' },

    -- Crops: seed item, what it gives (produce item, yield { min, max }),
    -- minutes of watered growing until ripe, and the fruit colour.
    -- Food values of the produce: survival.lua consumables.
    crops = {
        lettuce = { label = 'Lettuce', seed = 'seeds_lettuce', produce = 'lettuce', minutes = 25, yield = { 1, 3 }, color = 'green' },
        strawberry = { label = 'Strawberries', seed = 'seeds_strawberry', produce = 'strawberry', minutes = 30, yield = { 4, 8 }, color = 'red' },
        carrot = { label = 'Carrots', seed = 'seeds_carrot', produce = 'carrot', minutes = 35, yield = { 3, 6 }, color = 'orange' },
        cucumber = { label = 'Cucumbers', seed = 'seeds_cucumber', produce = 'cucumber', minutes = 35, yield = { 2, 4 }, color = 'green' },
        onion = { label = 'Onions', seed = 'seeds_onion', produce = 'onion', minutes = 40, yield = { 2, 4 }, color = 'white' },
        tomato = { label = 'Tomatoes', seed = 'seeds_tomato', produce = 'tomato', minutes = 40, yield = { 3, 6 }, color = 'red' },
        bell_pepper = { label = 'Bell peppers', seed = 'seeds_bell_pepper', produce = 'bell_pepper', minutes = 40, yield = { 2, 4 }, color = 'red' },
        banana = { label = 'Bananas', seed = 'seeds_banana', produce = 'banana', minutes = 45, yield = { 3, 5 }, color = 'yellow' },
        blueberry = { label = 'Blueberries', seed = 'seeds_blueberry', produce = 'blueberry', minutes = 45, yield = { 6, 10 }, color = 'blue' },
        cranberry = { label = 'Cranberries', seed = 'seeds_cranberry', produce = 'cranberry', minutes = 45, yield = { 6, 10 }, color = 'red' },
        beetroot = { label = 'Beetroot', seed = 'seeds_beetroot', produce = 'beetroot', minutes = 45, yield = { 2, 4 }, color = 'purple' },
        corn = { label = 'Corn', seed = 'seeds_corn', produce = 'corn', minutes = 50, yield = { 2, 4 }, color = 'yellow' },
        potato = { label = 'Potatoes', seed = 'seeds_potato', produce = 'potato', minutes = 50, yield = { 3, 6 }, color = 'brown' },
        cabbage = { label = 'Cabbage', seed = 'seeds_cabbage', produce = 'cabbage', minutes = 60, yield = { 1, 2 }, color = 'green' },
        watermelon = { label = 'Watermelon', seed = 'seeds_watermelon', produce = 'watermelon', minutes = 75, yield = { 1, 2 }, color = 'green' },
        pumpkin = { label = 'Pumpkin', seed = 'seeds_pumpkin', produce = 'pumpkin', minutes = 80, yield = { 1, 2 }, color = 'orange' },
    },
}
