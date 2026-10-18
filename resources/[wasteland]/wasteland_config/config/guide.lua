-- Survivor's guide (F2 or /guide): milestones that tick off by themselves,
-- your survivor stats, what to try next, and how-to pages. Edit the text
-- freely; add or remove milestones and pages.
return {
    key = 'F2',

    -- Milestones, in the order new players should meet them (the guide
    -- suggests the first unfinished ones). Done when the stat reaches count.
    -- Stats (counted by the server):
    --   searches, meals, kills, crafts, treated, trades, blueprints, fires,
    --   harvests, cooked, groups, vehicleWork, cupboards, jobs, drops, events,
    --   playerTrades, bestSkill (highest skill level), lifeMinutes (longest
    --   life in minutes played), deaths
    milestones = {
        { id = 'search', label = 'Search a container', stat = 'searches', count = 1,
            hint = 'Hold Left Alt on a dumpster, fridge, car or body and choose Search.' },
        { id = 'eat', label = 'Eat or drink something', stat = 'meals', count = 1,
            hint = 'Open your inventory (Tab), right-click food or water and choose Use.' },
        { id = 'kill1', label = 'Kill your first zombie', stat = 'kills', count = 1,
            hint = 'A melee weapon is quiet. A gunshot brings more of them.' },
        { id = 'craft', label = 'Craft something', stat = 'crafts', count = 1,
            hint = 'Press K. Start with rags from old clothes, then bandages.' },
        { id = 'treat', label = 'Treat a wound', stat = 'treated', count = 1,
            hint = 'When you bleed, use a bandage or a rag before it gets worse.' },
        { id = 'trade', label = 'Trade at a camp', stat = 'trades', count = 1,
            hint = 'Camps are safe zones on the map. Traders buy anything you loot.' },
        { id = 'blueprint', label = 'Learn a blueprint', stat = 'blueprints', count = 1,
            hint = 'Blueprints turn up in loot. Use one to learn its recipe for good.' },
        { id = 'fire', label = 'Light a campfire', stat = 'fires', count = 1,
            hint = 'You need a campfire kit, matches and firewood. Use the kit to place it.' },
        { id = 'hunt', label = 'Harvest an animal', stat = 'harvests', count = 1,
            hint = 'Kill a deer or boar, then hold Left Alt on it with a knife in your pockets.' },
        { id = 'cook', label = 'Cook meat', stat = 'cooked', count = 1,
            hint = 'Hold Left Alt on a burning campfire and choose Cook. Raw meat makes you sick.' },
        { id = 'group', label = 'Join or start a group', stat = 'groups', count = 1,
            hint = 'Press F6. A group shares map markers and its own radio channel.' },
        { id = 'vehicle', label = 'Work on a vehicle', stat = 'vehicleWork', count = 1,
            hint = 'Hold Left Alt on a car: fit a battery, wheels, engine parts, or refuel it.' },
        { id = 'kill25', label = 'Kill 25 zombies', stat = 'kills', count = 25,
            hint = 'Stay out of the open. Pack hunters come from every side.' },
        { id = 'job', label = 'Finish a camp job', stat = 'jobs', count = 1,
            hint = 'Camp traders hand out jobs: scrap, food, clearing places out.' },
        { id = 'cupboard', label = 'Place a tool cupboard', stat = 'cupboards', count = 1,
            hint = 'Use a building plan. The cupboard claims the land and keeps zombies out of a small area.' },
        { id = 'drop', label = 'Open a supply drop', stat = 'drops', count = 1,
            hint = 'Watch the sky for a plane. Everyone else will be watching too.' },
        { id = 'playertrade', label = 'Trade with another player', stat = 'playerTrades', count = 1,
            hint = 'Hold Left Alt on a player and choose Trade.' },
        { id = 'skill5', label = 'Reach level 5 in any skill', stat = 'bestSkill', count = 5,
            hint = 'Skills grow by doing. Press F9 to see them.' },
        { id = 'survive2h', label = 'Survive two hours without dying', stat = 'lifeMinutes', count = 120,
            hint = 'Eat, drink, stay warm, treat wounds - and do not get bitten.' },
        { id = 'event', label = 'Loot a world event', stat = 'events', count = 1,
            hint = 'Helicopter crashes, convoys and bandit hideouts show up on the map.' },
        { id = 'kill250', label = 'Kill 250 zombies', stat = 'kills', count = 250,
            hint = 'A veteran. Keep your weapons repaired.' },
        { id = 'skill10', label = 'Max out a skill', stat = 'bestSkill', count = 10,
            hint = 'Level 10 gives the full bonus.' },
    },

    -- How-to pages: a title and lines of text.
    pages = {
        { title = 'Controls', lines = {
            'Tab - inventory.  Left Alt (hold) - look at something and interact: search, trade, repair, open.',
            'K - crafting.  F2 - this guide.  F4 - emotes.  F6 - group.  F9 - skills.  X - hands up.',
            'Caps Lock - talk on the radio.  1 - 5 - hotbar slots.',
            '/hud - change the HUD.  /pee, /poop - when you need to go.',
            '/stuck - stuck somewhere? Stand still 10 seconds and you are taken to the nearest safe camp (once every 30 minutes).',
        } },
        { title = 'Staying alive', lines = {
            'Hunger, thirst, bleeding, infection and body temperature all matter. Watch the HUD.',
            'Bleeding never stops on its own - bandage it. Infection grows slowly, then fast: antibiotics.',
            'Cold kills. Wear warm clothes at night and stay out of the rain. A campfire warms you.',
            'When you die, everything but your hotbar goes into a body bag where you fell.',
        } },
        { title = 'The dead', lines = {
            'They hear you: walking carries 18 m, sprinting 45 m, crouching only a few. Standing still is quiet.',
            'Gunshots bring the nearest; keep shooting and more come from further away.',
            'Some stalk you from a distance, some lie still until you get close, packs surround you.',
            'Screamers call the others - kill them first. Brutes take a lot of shots. Spitters spit from range.',
            'Hiding behind a wall buys time: they will break through wood.',
        } },
        { title = 'Looting and crafting', lines = {
            'Search everything. Containers refill slowly and everyone shares them.',
            'Tear clothes into rags; rags make bandages. Blueprints unlock weapons, guns, parts and ammo.',
            'Traders at the camps buy anything you find.',
        } },
        { title = 'Camps, groups and trading', lines = {
            'Camps are safe zones: no zombies inside. Traders, a medic and jobs.',
            'Start or join a group with F6: members on the map and your own radio channel.',
            'Trade with another player: Left Alt on them, Trade. Both sides must accept.',
        } },
        { title = 'Vehicles', lines = {
            'A wreck needs a battery, four wheels, engine parts and fuel.',
            'Lock it and keep the key. Fuel comes from jerry cans or gas pumps (they run dry).',
            'Trunks hold a lot. Crashes are loud.',
        } },
        { title = 'Hunting and cooking', lines = {
            'Deer and boar roam the wild. Harvest a carcass with a knife for meat and hides.',
            'A campfire needs matches and firewood. Cook as much as you like while you stay near it.',
        } },
        { title = 'Building a base', lines = {
            'A building plan opens the build menu. A tool cupboard claims the land first.',
            'Walls, doors, gates and storage snap together. Upgrade wood to stone and metal.',
            'Keep supplies in the cupboard for upkeep, or your base decays.',
            'Zombies stay out of a small area around the cupboard, but they will attack walls further out.',
        } },
        { title = 'Skills', lines = {
            'Scavenging, crafting, medicine, hunting, fitness and combat grow as you do them (F9).',
            'Each level gives a small bonus. Dying costs a little progress, never a level.',
        } },
    },
}
