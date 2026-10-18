-- Wasteland Core :: prop placer (wasteland_props)
-- Admins type /propplacer to place props anywhere: search a preset below or
-- type any GTA prop model name (or one from a streamed props resource).
-- Every prop is saved in the database (wl_props) and comes back after a
-- restart. Presets the game does not know are hidden from the list.
return {
    adminAce = 'wasteland.admin',  -- who may place (same as the admin panel)
    maxProps = 5000,               -- total placed props on the server
    streamDistance = 200,          -- players see props this close (metres)
    maxPlaceDistance = 30,         -- an admin places this far from themselves at most

    -- { group, label, model }: shown as buttons in the placer.
    presets = {
        { group = 'Barricades', label = 'Concrete barrier', model = 'prop_mp_barrier_01' },
        { group = 'Barricades', label = 'Road barrier', model = 'prop_mp_barrier_02b' },
        { group = 'Barricades', label = 'Work barrier', model = 'prop_barrier_work05' },
        { group = 'Barricades', label = 'Work barrier (long)', model = 'prop_barrier_work06a' },
        { group = 'Barricades', label = 'Chain-link fence', model = 'prop_fnclink_04g' },
        { group = 'Barricades', label = 'Sandbags', model = 'prop_mb_sandblock_01' },
        { group = 'Barricades', label = 'Traffic cone', model = 'prop_roadcone02a' },

        { group = 'Wrecks', label = 'Car wreck', model = 'prop_rub_carwreck_2' },
        { group = 'Wrecks', label = 'Car wreck (burnt)', model = 'prop_rub_carwreck_3' },
        { group = 'Wrecks', label = 'Car wreck (rusty)', model = 'prop_rub_carwreck_5' },
        { group = 'Wrecks', label = 'Car wreck (flat)', model = 'prop_rub_carwreck_7' },
        { group = 'Wrecks', label = 'Car wreck (old)', model = 'prop_rub_carwreck_9' },
        { group = 'Wrecks', label = 'Bus wreck', model = 'prop_rub_buswreck_01' },
        { group = 'Wrecks', label = 'Old tyre', model = 'prop_rub_tyre_01' },

        { group = 'Junk', label = 'Barrel', model = 'prop_barrel_02a' },
        { group = 'Junk', label = 'Barrel (rusty)', model = 'prop_barrel_02b' },
        { group = 'Junk', label = 'Explosive barrel', model = 'prop_barrel_exp_01a' },
        { group = 'Junk', label = 'Dumpster', model = 'prop_dumpster_01a' },
        { group = 'Junk', label = 'Bin bags', model = 'prop_rub_binbag_01' },
        { group = 'Junk', label = 'Old couch', model = 'prop_rub_couch04' },
        { group = 'Junk', label = 'Pallet', model = 'prop_pallet_01a' },
        { group = 'Junk', label = 'Box pile', model = 'prop_boxpile_07d' },

        { group = 'Camp', label = 'Campfire', model = 'prop_beach_fire' },
        { group = 'Camp', label = 'Hobo stove', model = 'prop_hobo_stove_01' },
        { group = 'Camp', label = 'Tent', model = 'prop_skid_tent_01' },
        { group = 'Camp', label = 'Gazebo', model = 'prop_gazebo_02' },
        { group = 'Camp', label = 'Generator', model = 'prop_generator_03b' },
        { group = 'Camp', label = 'Work light', model = 'prop_worklight_03b' },
        { group = 'Camp', label = 'Wood pile', model = 'prop_woodpile_01a' },
        { group = 'Camp', label = 'Portable toilet', model = 'prop_portaloo_01a' },
        { group = 'Camp', label = 'Table', model = 'prop_table_03' },
        { group = 'Camp', label = 'Chair', model = 'prop_chair_01a' },
        { group = 'Camp', label = 'Bench', model = 'prop_bench_01a' },

        { group = 'Structures', label = 'Shipping container', model = 'prop_container_01a' },
        { group = 'Structures', label = 'Portacabin', model = 'prop_portacabin01' },
    },
}
