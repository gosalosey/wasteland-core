-- Camps: safe zones (no zombies), map blips, traders.
--
-- A camp is a circle on the map (coords + radius). Zombies never spawn in
-- a safe camp, ones that wander in are removed, and they stop chasing a
-- player who is inside. Players see the camp on the map and a message when
-- they enter or leave.
--
-- Traders stand at fixed spots; hold Left Alt on one and choose "Trade".
-- They buy and sell for cash. Each item they sell has a stock that refills
-- by `restock` every `restockMinutes` (up to `stock`). Selling an item to a
-- trader that also sells it raises its stock.
--
-- VERIFY IN-GAME: trader positions and headings are picked from the map;
-- move a trader by editing its coords (x, y, z, heading).
return {
    restockMinutes = 10,

    shops = {
        general = {
            label = 'General trader',
            items = {
                { name = 'water_bottle', buy = 20, sell = 5, stock = 10, restock = 2 },
                { name = 'soda_can', buy = 12, sell = 3, stock = 10, restock = 2 },
                { name = 'canned_beans', buy = 25, sell = 6, stock = 8, restock = 2 },
                { name = 'canned_peaches', buy = 25, sell = 6, stock = 8, restock = 2 },
                { name = 'energy_bar', buy = 15, sell = 4, stock = 10, restock = 2 },
                { name = 'duct_tape', buy = 30, sell = 8, stock = 5, restock = 1 },
                { name = 'flashlight', buy = 80, sell = 20, stock = 2, restock = 1 },
                { name = 'backpack_small', buy = 400, sell = 100, stock = 2, restock = 1 },
                { name = 'clothing_top', buy = 40, sell = 10, stock = 4, restock = 1 },
                { name = 'clothing_pants', buy = 40, sell = 10, stock = 4, restock = 1 },
                { name = 'clothing_shoes', buy = 35, sell = 8, stock = 4, restock = 1 },
                { name = 'clothing_hat', buy = 20, sell = 5, stock = 4, restock = 1 },
                { name = 'sewing_kit', buy = 70, sell = 15, stock = 3, restock = 1 },
                { name = 'scrap_metal', sell = 4 },
                { name = 'rag', sell = 2 },
                { name = 'jerry_can', buy = 120, sell = 30, stock = 3, restock = 1 },
                { name = 'siphon_hose', buy = 60, sell = 15, stock = 3, restock = 1 },
                { name = 'vehicle_repair_kit', buy = 350, sell = 90, stock = 2, restock = 1 },
                { name = 'car_battery', buy = 500, sell = 120, stock = 1, restock = 1 },
                { name = 'engine_parts', buy = 600, sell = 150, stock = 1, restock = 1 },
                { name = 'car_wheel', buy = 250, sell = 60, stock = 4, restock = 1 },
                { name = 'vehicle_lock', buy = 200, sell = 50, stock = 3, restock = 1 },
                { name = 'lockpick', buy = 60, sell = 15, stock = 5, restock = 2 },
            },
        },
        medic = {
            label = 'Medic',
            items = {
                { name = 'bandage', buy = 25, sell = 8, stock = 10, restock = 2 },
                { name = 'rag', buy = 8, sell = 2, stock = 10, restock = 3 },
                { name = 'painkillers', buy = 60, sell = 15, stock = 5, restock = 1 },
                { name = 'antibiotics', buy = 250, sell = 60, stock = 2, restock = 1 },
            },
        },
        gunsmith = {
            label = 'Gunsmith',
            items = {
                { name = 'weapon_knife', buy = 120, sell = 30, stock = 3, restock = 1 },
                { name = 'weapon_bat', buy = 90, sell = 20, stock = 3, restock = 1 },
                { name = 'weapon_machete', buy = 200, sell = 50, stock = 2, restock = 1 },
                { name = 'weapon_pistol', buy = 1500, sell = 400, stock = 1, restock = 1 },
                { name = 'weapon_pumpshotgun', buy = 3000, sell = 800, stock = 1, restock = 1 },
                { name = 'ammo_9mm', buy = 4, sell = 1, stock = 120, restock = 30 },
                { name = 'ammo_12g', buy = 8, sell = 2, stock = 40, restock = 10 },
                { name = 'weapon_repair_kit', buy = 300, sell = 80, stock = 2, restock = 1 },
                { name = 'weapon_smg', sell = 900 },
                { name = 'weapon_carbine', sell = 1800 },
                { name = 'weapon_assaultrifle', sell = 1800 },
                { name = 'weapon_huntingrifle', sell = 1200 },
            },
        },
    },

    -- blip: GTA blip sprite and colour (2 = green).
    camps = {
        {
            id = 'sandy', label = 'Sandy Shores Camp', coords = { x = 1853.0, y = 3686.0, z = 34.3 }, radius = 70,
            blip = { sprite = 40, color = 2 },
            traders = {
                { shop = 'general', model = 's_m_m_trucker_01', coords = { x = 1857.72, y = 3687.84, z = 34.27, heading = 110.12 } },
                { shop = 'medic', model = 's_m_m_paramedic_01', coords = { x = 1848.97, y = 3689.71, z = 34.27, heading = 211.41 } },
                { shop = 'gunsmith', model = 's_m_y_ammucity_01', coords = { x = 1851.35, y = 3683.84, z = 34.27, heading = 296.83 } },
            },
        },
        {
            id = 'paleto', label = 'Paleto Bay Camp', coords = { x = -447.0, y = 6012.0, z = 31.7 }, radius = 65,
            blip = { sprite = 40, color = 2 },
            traders = {
                { shop = 'general', model = 's_m_m_trucker_01', coords = { x = -444.6, y = 6013.4, z = 31.72, heading = 45.0 } },
                { shop = 'medic', model = 's_m_m_paramedic_01', coords = { x = -449.8, y = 6016.6, z = 31.72, heading = 225.0 } },
            },
        },
        {
            id = 'legion', label = 'Legion Square Camp', coords = { x = 195.0, y = -934.0, z = 30.7 }, radius = 60,
            blip = { sprite = 40, color = 2 },
            traders = {
                { shop = 'general', model = 's_m_m_trucker_01', coords = { x = 190.4, y = -931.2, z = 30.69, heading = 240.0 } },
                { shop = 'medic', model = 's_m_m_paramedic_01', coords = { x = 199.0, y = -937.6, z = 30.69, heading = 60.0 } },
            },
        },
    },
}
