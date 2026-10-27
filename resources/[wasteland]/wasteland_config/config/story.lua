-- Story: a quest chain with a story, characters, choices and endings.
-- Every character plays it once (progress is saved). Group members near you
-- share kills and defending. Open the journal with /journal.
--
-- An act is a list of steps, done in order (or jumped by a choice: `goto`).
-- Step types:
--   talk     talk to an NPC (hold Left Alt on them); the dialogue has lines and
--            choices. A choice can need items (`bring`, taken), give items
--            (`give`), cash, set flags, end the act (`ending`), or go to a step.
--   visit    reach a place (coords, radius)
--   collect  pick up a story item placed in the world (prop at coords)
--   read     read a note / recording placed in the world
--   kill     kill zombies (count; `near` limits it to a place)
--   defend   stay in a place for `seconds` while zombies come in waves
--            (`needs`: an item the player must carry to start it)
-- Dialogue lines can depend on flags: { who, text, ifFlag = 'x' } / ifNotFlag.
-- `journal`: what the journal says once the step is done (past tense).
--
-- Places: pick open ground next to a road (no roofs, no interiors). As a
-- safety net, a story NPC or item whose spot turns out to be inside a
-- building, high up or without ground is moved to the nearest road edge.
-- An NPC with `exact = true` (a spot placed by hand) is never moved.
-- VERIFY IN-GAME: the places are picked from the map.
return {
    enabled = true,
    groupRange = 120,          -- group members this close share kills / defending
    -- Acts are played in order: Act II starts when Act I is done. Flags (the
    -- choices you made) carry over, so later acts can react to them.
    acts = {
    {
        id = 'act1',
        title = 'Patient Zero',
        subtitle = 'Act I: The Lazarus File',
        intro = 'Everyone has a theory about how it started. Hollis, the radio man at Sandy Shores, says he has more than a theory.',

        npcs = {
            hollis = { name = 'Hollis', role = 'Radio operator, Sandy Shores Camp', model = 'a_m_m_hillbilly_01',
                coords = { x = 1855.09, y = 3688.89, z = 34.27, heading = 144.91 }, exact = true, scenario = 'WORLD_HUMAN_STAND_MOBILE',
                idle = 'Static, static, static. Come back when you have something.' },
            tomas = { name = 'Tomas Reyes', role = "Dr. Ward's assistant", model = 'a_m_y_genstreet_01',
                coords = { x = 2432.5, y = 4972.2, z = 46.8, heading = 140.0 }, scenario = 'WORLD_HUMAN_BUM_SLUMPED',
                onlyDuring = { 'tomas' },
                idle = 'Go away. Please. I don\'t know how long I have.' },
            crane = { name = 'Mr. Crane', role = 'A man in a clean suit', model = 's_m_m_highsec_01',
                coords = { x = 1849.8, y = 3676.6, z = 34.27, heading = 20.0 }, scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
                onlyDuring = { 'the_choice' },
                idle = 'I am a patient man. Not that patient.' },
        },

        steps = {
            -- 1 ---------------------------------------------------------
            { id = 'static', type = 'talk', npc = 'hollis', title = 'Static',
                objective = 'Talk to Hollis, the radio operator at Sandy Shores Camp.',
                dialogue = {
                    lines = {
                        { who = 'hollis', text = 'You hear that? No? Nobody hears it but me. Every night at 3:12, the same burst. Numbers, then a voice.' },
                        { who = 'hollis', text = '"Courier Lazarus-Nine, diverting to Sandy. Cargo intact. Do not open." Then it cuts out. That was the night before it all went to hell.' },
                        { who = 'hollis', text = 'A plane came down on the airfield that night. Nobody went near it. Folks say it was full of the sick. I say it was full of answers.' },
                    },
                    choices = {
                        { id = 'go', text = 'I\'ll go take a look at the crash.' },
                        { id = 'why', text = 'Why should I care how it started?', reply = 'Because if somebody started it, somebody might know how to stop it. Go. Airfield, north end.' },
                    },
                },
                journal = 'Hollis picked up a looped radio message about a courier called Lazarus-Nine. A plane went down on the Sandy Shores airfield the night it all began.' },

            -- 2 ---------------------------------------------------------
            { id = 'crash_site', type = 'visit', title = 'The crash',
                objective = 'Find the crashed courier plane at the Sandy Shores airfield.',
                coords = { x = 1730.0, y = 3300.0, z = 41.2 }, radius = 40,
                arrive = 'The wreck is old, picked over by birds. But someone chained the cargo door shut from the outside.',
                journal = 'The courier plane was chained shut from the outside. Someone did not want anything getting out, or in.' },

            -- 3 ---------------------------------------------------------
            { id = 'courier_case', type = 'collect', title = 'Cargo intact',
                objective = 'Search the wreck for the courier\'s cargo.',
                coords = { x = 1736.5, y = 3297.0, z = 41.2 }, prop = 'prop_ld_case_01', label = 'Take the steel case',
                item = 'story_courier_case',
                found = 'A steel case, still sealed. Stencilled on the side: LAZARUS-9 / HUMANE LABS / BIOHAZARD.',
                journal = 'In the wreck: a sealed steel case marked LAZARUS-9, Humane Labs.' },

            -- 4 ---------------------------------------------------------
            { id = 'flight_log', type = 'read', title = 'The flight log',
                objective = 'Read the pilot\'s log in the wreck.',
                coords = { x = 1739.0, y = 3294.5, z = 41.2 }, prop = 'prop_notepod_01', label = 'Read the flight log',
                note = {
                    title = 'Flight log, Courier Lazarus-9',
                    text = 'Passenger: Dr. Elena Ward (Humane Labs, Project LAZARUS).\n\n'
                        .. '02:40 - Dr. Ward insists we land at Paleto, says her clinic is the only safe lab left.\n'
                        .. '02:55 - Passenger in the back is coughing blood. Ward says it is "expected". It is NOT expected.\n'
                        .. '03:05 - He bit Marks. Marks is not breathing. Marks is MOVING.\n'
                        .. '03:12 - Mayday, mayday. Courier Lazarus-Nine, diverting to Sandy. Cargo intact. Do not open.\n'
                        .. '03:12 - Do not open.',
                },
                journal = 'The pilot\'s log: Dr. Elena Ward of Humane Labs was on board, headed for her clinic in Paleto Bay. One of the passengers turned mid-flight.' },

            -- 5 ---------------------------------------------------------
            { id = 'hollis_case', type = 'talk', npc = 'hollis', title = 'Do not open',
                objective = 'Bring the steel case to Hollis.',
                dialogue = {
                    lines = {
                        { who = 'hollis', text = 'Lazarus. Like the guy who came back from the dead. Real subtle, eggheads.' },
                        { who = 'hollis', text = 'This lock wants a thumbprint and a code. Dr. Ward\'s, I bet. If she made it to her clinic in Paleto, there might be notes. Or what\'s left of her.' },
                    },
                    choices = {
                        { id = 'give', text = 'Hand over the case.', bring = { { name = 'story_courier_case', count = 1 } },
                            reply = 'I\'ll keep it under the radio. Nobody touches my radio. Paleto Bay medical clinic. Watch yourself.' },
                        { id = 'later', text = 'Not yet.', stay = true },
                    },
                },
                journal = 'Hollis keeps the case locked away. It needs Dr. Ward\'s code. Her clinic in Paleto Bay was the next lead.' },

            -- 6 ---------------------------------------------------------
            { id = 'clinic_nest', type = 'kill', title = 'The clinic',
                objective = 'Clear the infected around the Paleto Bay medical clinic.',
                count = 8, near = { x = -247.0, y = 6331.0, z = 32.4, radius = 70 }, placeLabel = 'Paleto Bay clinic',
                journal = 'The clinic was a nest. Most of them still wore hospital gowns.' },

            -- 7 ---------------------------------------------------------
            { id = 'ward_journal', type = 'read', title = 'Ward\'s notes',
                objective = 'Find Dr. Ward\'s notes in the clinic.',
                coords = { x = -252.0, y = 6324.0, z = 32.4 }, prop = 'prop_notepod_01', label = 'Read Dr. Ward\'s notes',
                note = {
                    title = 'Personal notes, Dr. E. Ward',
                    text = 'Day 3. LAZARUS was supposed to restart dead tissue. It does. It does not stop.\n\n'
                        .. 'Day 4. Tomas was bitten in the cold room. I gave him the trial dose. He is holding on, for now. '
                        .. 'I sent him to the old ranch near Grapeseed with my keycard. If I do not come back, he must not give it to them.\n\n'
                        .. 'Day 5. The men in suits came again. They want the sample, not the cure. There is a difference.\n\n'
                        .. 'I am going back to the lab. The last sample is still in the cold store. God forgive me.',
                },
                journal = 'Dr. Ward\'s notes: her assistant Tomas was bitten and given a trial dose. He has her keycard, hiding at the old ranch near Grapeseed. She went back to Humane Labs.' },

            -- 8 ---------------------------------------------------------
            { id = 'tomas', type = 'talk', npc = 'tomas', title = 'The assistant',
                objective = 'Find Tomas at the old ranch near Grapeseed.',
                coords = { x = 2432.5, y = 4972.2, z = 46.8 }, radius = 30,
                dialogue = {
                    lines = {
                        { who = 'tomas', text = 'Stay back! Did... did she send you? Elena?' },
                        { who = 'tomas', text = 'She gave me something. It slows it down. My hands are cold all the time. I hear them, at night. Calling.' },
                        { who = 'tomas', text = 'The keycard opens the cold store. But if they get the sample, they will not make a cure. They will make a weapon.' },
                    },
                    choices = {
                        { id = 'mercy', text = 'Give him antibiotics to ease the fever. (Antibiotics x1)', bring = { { name = 'antibiotics', count = 1 } },
                            give = { { name = 'story_keycard', count = 1 } }, flags = { 'mercy' },
                            reply = 'You... thank you. Here. Take the card. Promise me you will do the right thing with it.' },
                        { id = 'force', text = 'Take the keycard from him.', give = { { name = 'story_keycard', count = 1 } }, flags = { 'ruthless' },
                            effect = 'turn', reply = 'No, no, wait... it\'s... coming... RUN.' },
                        { id = 'leave', text = 'Leave him for now.', stay = true },
                    },
                },
                journal = 'Tomas was alive, barely, with Dr. Ward\'s keycard.',
                journalIf = { mercy = 'You eased his fever. He gave you the keycard and made you promise to do the right thing.',
                    ruthless = 'You took the keycard by force. He turned before you were done.' } },

            -- 9 ---------------------------------------------------------
            { id = 'lab_gate', type = 'defend', title = 'Humane Labs',
                objective = 'Get the Humane Labs gate open: hold the area while the keycard reader boots.',
                coords = { x = 3619.7, y = 3731.0, z = 28.7 }, radius = 30, seconds = 90, waveSeconds = 15, waveSize = 4,
                needs = 'story_keycard',      -- must be carried (not taken)
                start = 'The reader blinks red. Booting. The noise carries a long way.',
                journal = 'At Humane Labs the gate reader took its time. The dead came to listen.' },

            -- 10 --------------------------------------------------------
            { id = 'lazarus', type = 'collect', title = 'The cold store',
                objective = 'Take the last LAZARUS sample from the cold store.',
                coords = { x = 3612.0, y = 3727.0, z = 28.7 }, prop = 'prop_med_bag_01', label = 'Open the cold-store case',
                item = 'story_lazarus_sample',
                found = 'One vial left, frost on the glass. The label is hand-written: L-9 / FINAL / CURE?',
                journal = 'You took the last LAZARUS sample from the cold store.' },

            -- 11 --------------------------------------------------------
            { id = 'ward_recording', type = 'read', title = 'The last recording',
                objective = 'Listen to the dictaphone next to the cold store.',
                coords = { x = 3610.5, y = 3725.5, z = 28.7 }, prop = 'prop_boombox_01', label = 'Play the recording',
                note = {
                    title = 'Dictaphone, Dr. E. Ward (last entry)',
                    text = '"If you are hearing this, I did not make it out. Listen. The first patient was not a prisoner. It was me. '
                        .. 'I tested LAZARUS on myself. Patient zero is a doctor who wanted to cheat death.\n\n'
                        .. 'The vial in the cold store is different. It is the counter-agent. It can be grown, refined, given to people. '
                        .. 'The men in clean suits will offer you anything for it. They do not want people cured. They want control.\n\n'
                        .. 'Whatever you choose... choose it like the world is watching. Because it is all that is left."',
                },
                journal = 'Dr. Ward\'s last recording: she was patient zero. The vial is a counter-agent that could become a cure, and the men in suits want it.' },

            -- 12 --------------------------------------------------------
            { id = 'the_choice', type = 'talk', npc = 'hollis', title = 'The choice',
                objective = 'Go back to Sandy Shores. Hollis has a visitor.',
                dialogue = {
                    lines = {
                        { who = 'hollis', text = 'You made it. Good. Bad news: we have company. Suit showed up an hour ago, says he is "with the company". Hasn\'t blinked once.' },
                        { who = 'crane', text = 'Name\'s Crane. That vial belongs to my employer. I am prepared to be generous. Very generous.' },
                        { who = 'hollis', text = 'Or our medic grows it into something. Slow. Might not work. But it would be ours.', ifNotFlag = 'ruthless' },
                        { who = 'hollis', text = 'Heard what happened with the Reyes kid. Not judging. Just saying, people here are watching what you do next.', ifFlag = 'ruthless' },
                        { who = 'crane', text = 'Sentiment is expensive. Take the money.' },
                    },
                    choices = {
                        { id = 'share', text = 'Give the vial to the camp medic.', bring = { { name = 'story_lazarus_sample', count = 1 } },
                            give = { { name = 'lazarus_serum', count = 3 } }, cash = 500, flags = { 'shared' }, ending = 'shared',
                            reply = 'Hollis: Took you long enough to be a decent person. Medic says the first batch is yours. Crane is gone. He did not look happy. That worries me.' },
                        { id = 'sell', text = 'Sell it to Crane.', bring = { { name = 'story_lazarus_sample', count = 1 } },
                            give = { { name = 'scrap_lever_rifle', count = 1 }, { name = 'ammo_44', count = 120 } }, cash = 3000, flags = { 'sold' }, ending = 'sold',
                            reply = 'Crane: A pleasure. My employer remembers friends. Hollis did not say a word. He switched the radio off, for the first time in years.' },
                    },
                },
                journal = 'Mr. Crane came for the vial.',
                journalIf = { shared = 'You gave the vial to the camp medic. The first serum batch is yours. Crane left without a word.',
                    sold = 'You sold the vial to Crane. The money is real. So is the silence at Sandy Shores.' } },
        },

        endings = {
            shared = { title = 'A Cure, Maybe', text = 'The camp has the vial. It might become a cure. It might not. Crane will be back.' },
            sold = { title = 'Thirty Pieces', text = 'The company has the vial. You have a rifle and a full wallet. Hollis has stopped listening to the radio.' },
        },
    },
    {
        id = 'act2',
        title = 'Patient Zero',
        subtitle = 'Act II: The Company',
        intro = 'Crane said his employer remembers friends. It turns out the company remembers everyone.',
        -- All places are open ground next to roads: no climbing, no buildings.

        npcs = {
            hollis = { name = 'Hollis', role = 'Radio operator, Sandy Shores Camp', model = 'a_m_m_hillbilly_01',
                coords = { x = 1855.09, y = 3688.89, z = 34.27, heading = 144.91 }, exact = true, scenario = 'WORLD_HUMAN_STAND_MOBILE',
                idle = 'Keep your head down out there. And your radio off.' },
            rook = { name = 'Rook', role = 'A deserter, Fort Zancudo', model = 's_m_y_marine_01',
                coords = { x = -1582.0, y = 2786.0, z = 17.0, heading = 230.0 }, scenario = 'WORLD_HUMAN_SMOKING',
                onlyDuring = { 'rook' },
                idle = 'Keep walking, civilian.' },
        },

        steps = {
            -- 1 ---------------------------------------------------------
            { id = 'convoy', type = 'talk', npc = 'hollis', title = 'Headlights',
                objective = 'Talk to Hollis at Sandy Shores Camp.',
                dialogue = {
                    lines = {
                        { who = 'hollis', text = 'Our medic is gone. Took the serum notes with her. Last anyone saw, she was riding in a black truck with company plates.', ifFlag = 'shared' },
                        { who = 'hollis', text = 'Remember Crane? His people have been buying up every scrap of medicine in the valley. Paying in ammo. Nobody says no.', ifFlag = 'sold' },
                        { who = 'hollis', text = 'Three black trucks went past on Route 68 last night. They stopped at the Yellow Jack. Only two drove off.' },
                        { who = 'hollis', text = 'Whatever they are hauling, I want to know. Go look. Quietly, if you can manage quiet.' },
                    },
                    choices = {
                        { id = 'go', text = 'I\'ll check the Yellow Jack.' },
                    },
                },
                journal = 'A company convoy stopped at the Yellow Jack Inn on Route 68. One truck never left.' },

            -- 2 ---------------------------------------------------------
            { id = 'yellow_jack', type = 'visit', title = 'The Yellow Jack',
                objective = 'Go to the Yellow Jack Inn on Route 68.',
                coords = { x = 1985.6, y = 3053.5, z = 47.2 }, radius = 35,
                arrive = 'One truck, doors open, engine cold. Drag marks lead into the car park. The guards did not get far.',
                journal = 'The truck at the Yellow Jack was abandoned. Its guards had turned.' },

            -- 3 ---------------------------------------------------------
            { id = 'guards', type = 'kill', title = 'Company men',
                objective = 'Put down the turned convoy guards around the Yellow Jack.',
                count = 10, near = { x = 1985.6, y = 3053.5, z = 47.2, radius = 90 }, placeLabel = 'the Yellow Jack',
                journal = 'The guards wore company patches. Under them, bite marks.' },

            -- 4 ---------------------------------------------------------
            { id = 'manifest', type = 'collect', title = 'The manifest',
                objective = 'Search the abandoned truck for its paperwork.',
                coords = { x = 1991.0, y = 3049.0, z = 47.2 }, prop = 'prop_ld_case_01', label = 'Take the document case',
                item = 'story_manifest',
                found = 'A document case, still locked to a dead man\'s wrist. You did not need the wrist.',
                journal = 'You took the convoy\'s document case.' },

            -- 5 ---------------------------------------------------------
            { id = 'manifest_read', type = 'read', title = 'Cargo: L-10',
                objective = 'Read the convoy manifest.',
                coords = { x = 1993.0, y = 3051.5, z = 47.2 }, prop = 'prop_notepod_01', label = 'Read the manifest',
                note = {
                    title = 'Halcyon Biotech, transport manifest #4471',
                    text = 'Origin: Humane Labs (cold store, recovered).\n'
                        .. 'Cargo: LAZARUS-10 (weaponised strain), 6 canisters. Do NOT expose.\n\n'
                        .. 'Route: Route 68 > Zancudo checkpoint (escort change) > El Gordo lighthouse (relay).\n\n'
                        .. 'Note from C.: The lighthouse relay goes live on my signal. When it does, the Sandy Shores camp is to be "cleared for '
                        .. 'study". Recover the counter-agent by any means.',
                },
                journal = 'The manifest: Halcyon Biotech is moving a weaponised strain, LAZARUS-10. A relay at the El Gordo lighthouse will start it. The target is Sandy Shores.' },

            -- 6 ---------------------------------------------------------
            { id = 'rook', type = 'talk', npc = 'rook', title = 'The checkpoint',
                objective = 'Find the escort change at the Fort Zancudo gate.',
                dialogue = {
                    lines = {
                        { who = 'rook', text = 'Easy. I am not with them. Not any more. I was the escort. Then I saw what was in the canisters.' },
                        { who = 'rook', text = 'They shot my sergeant for asking. I got out with a hole in my leg and the relay codes in my head.' },
                        { who = 'rook', text = 'The lighthouse. If someone holds it long enough, I can talk you through killing the signal. If not... say goodbye to Sandy.' },
                    },
                    choices = {
                        { id = 'patch', text = 'Patch up his leg first. (Bandage x3)', bring = { { name = 'bandage', count = 3 } }, flags = { 'rook_ally' },
                            reply = 'Thanks. I will be on the radio, channel nine. Get to the lighthouse. I have got your back.' },
                        { id = 'codes', text = 'Just give me the codes.', flags = { 'rook_alone' },
                            reply = 'Fine. Three-one-two, then the name of the dead. You will figure it out. I am not following you up there.' },
                    },
                },
                journal = 'Rook, a deserter from the convoy escort, knows how to kill the lighthouse relay.',
                journalIf = { rook_ally = 'You patched his leg. He promised to talk you through it on the radio.',
                    rook_alone = 'You took the codes and left him there.' } },

            -- 7 ---------------------------------------------------------
            { id = 'lighthouse', type = 'defend', title = 'El Gordo',
                objective = 'Hold the ground at the El Gordo lighthouse while the relay is shut down.',
                coords = { x = 3426.0, y = 5174.0, z = 7.4 }, radius = 35, seconds = 120, waveSeconds = 15, waveSize = 5,
                start = 'The relay screams to life. Every dead thing for miles hears it.',
                journal = 'At the lighthouse the relay howled while you held the ground.' },

            -- 8 ---------------------------------------------------------
            { id = 'crane_log', type = 'read', title = 'Crane\'s orders',
                objective = 'Find the relay operator\'s orders by the lighthouse.',
                coords = { x = 3420.0, y = 5168.0, z = 7.4 }, prop = 'prop_notepod_01', label = 'Read the orders',
                note = {
                    title = 'Orders, Halcyon relay team (signed C.)',
                    text = 'If the relay is compromised, fall back to the stash at the old lighthouse shed and wait for extraction.\n\n'
                        .. 'The stash holds the payroll and the spare kit. Leave nothing for the locals.\n\n'
                        .. 'And find me the one who took the Lazarus file. They are either very useful or very dead.',
                },
                journal = 'Crane\'s orders: a company stash by the lighthouse, and a note that he is looking for you.' },

            -- 9 ---------------------------------------------------------
            { id = 'warning', type = 'talk', npc = 'hollis', title = 'Sandy Shores',
                objective = 'Get back to Hollis. Sandy Shores needs to know.',
                dialogue = {
                    lines = {
                        { who = 'hollis', text = 'Signal\'s dead. I heard it go. You did that?' },
                        { who = 'hollis', text = 'Rook got through on channel nine. Said you watched each other\'s backs. Said to tell you "the name of the dead" was his sergeant.', ifFlag = 'rook_ally' },
                        { who = 'hollis', text = 'Some soldier kid called. Said you left him bleeding. Said he hopes it was worth it.', ifFlag = 'rook_alone' },
                        { who = 'hollis', text = 'There is the company stash, too. Payroll and kit. We could use it. Or we warn every camp on the coast before Crane tries again.' },
                    },
                    choices = {
                        { id = 'warn', text = 'Warn the other camps. Everyone needs to know.', flags = { 'warned' }, ending = 'warned',
                            give = { { name = 'antibiotics', count = 3 }, { name = 'mre_beef', count = 4 }, { name = 'armor_plate', count = 1 } }, cash = 800,
                            reply = 'Hollis: On air in five. Every camp, every channel. They will know what Halcyon is. The camps sent supplies for you.' },
                        { id = 'loot', text = 'Take the stash. Survival first.', flags = { 'looted' }, ending = 'looted',
                            give = { { name = 'scrap_pump_shotgun', count = 1 }, { name = 'ammo_12g', count = 40 }, { name = 'armor_plate', count = 1 } }, cash = 2500,
                            reply = 'Hollis: Can\'t argue with full pockets. Just... do not be surprised when nobody believes us later.' },
                    },
                },
                journal = 'Back at Sandy Shores, with the relay dead.',
                journalIf = { warned = 'You told every camp on the coast what Halcyon is.', looted = 'You took Crane\'s stash and kept quiet.' } },
        },

        endings = {
            warned = { title = 'Every Channel', text = 'The whole coast knows the name Halcyon. Crane knows yours.' },
            looted = { title = 'Payroll', text = 'You are better armed than ever. The camps still do not know what is coming.' },
        },
    },
    },
}
