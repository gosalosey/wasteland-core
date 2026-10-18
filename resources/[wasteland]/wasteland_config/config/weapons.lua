-- Weapons: what the weapon items (defined in inventory.lua) do.
--
-- Use a weapon item (hotbar key or right-click → Use) to hold it; use it
-- again to put it away. Guns take their ammo straight from the inventory
-- (pockets and worn bag); every shot uses one round and wears the weapon.
-- Melee weapons wear with every hit. A broken weapon (durability 0) can be
-- held but not used until it is repaired with a repair kit.
--
-- Per weapon:
--   hash    GTA weapon name
--   ammo    ammo item (guns only; leave out for melee)
--   wear    durability lost per shot or hit (default 1)
--   noise   metres a shot or hit can be heard (zombies use this)
return {
    weapons = {
        crowbar = { hash = 'WEAPON_CROWBAR', noise = 8 },
        weapon_knife = { hash = 'WEAPON_KNIFE', noise = 5 },
        weapon_bat = { hash = 'WEAPON_BAT', noise = 10 },
        weapon_hatchet = { hash = 'WEAPON_HATCHET', noise = 8 },
        weapon_machete = { hash = 'WEAPON_MACHETE', noise = 6 },
        weapon_hammer = { hash = 'WEAPON_HAMMER', noise = 8 },
        weapon_wrench = { hash = 'WEAPON_WRENCH', noise = 9 },
        weapon_battleaxe = { hash = 'WEAPON_BATTLEAXE', noise = 9 },
        weapon_knuckle = { hash = 'WEAPON_KNUCKLE', noise = 4 },
        weapon_switchblade = { hash = 'WEAPON_SWITCHBLADE', noise = 4 },

        weapon_pistol = { hash = 'WEAPON_PISTOL', ammo = 'ammo_9mm', noise = 120 },
        weapon_revolver = { hash = 'WEAPON_REVOLVER', ammo = 'ammo_44', noise = 150 },
        weapon_dbshotgun = { hash = 'WEAPON_DBSHOTGUN', ammo = 'ammo_12g', noise = 180, wear = 2 },
        weapon_pumpshotgun = { hash = 'WEAPON_PUMPSHOTGUN', ammo = 'ammo_12g', noise = 180 },
        weapon_microsmg = { hash = 'WEAPON_MICROSMG', ammo = 'ammo_9mm', noise = 130 },
        weapon_smg = { hash = 'WEAPON_SMG', ammo = 'ammo_9mm', noise = 140 },
        weapon_carbine = { hash = 'WEAPON_CARBINERIFLE', ammo = 'ammo_556', noise = 250 },
        weapon_assaultrifle = { hash = 'WEAPON_ASSAULTRIFLE', ammo = 'ammo_762', noise = 250 },
        weapon_huntingrifle = { hash = 'WEAPON_SNIPERRIFLE', ammo = 'ammo_308', noise = 300, wear = 2 },
    },

    -- Attachment items (inventory.lua `attachment`), and how far a suppressed
    -- shot is heard compared with the gun's own noise (0.5 = half as far).
    attachmentItems = { 'att_suppressor', 'att_flashlight', 'att_scope', 'att_grip', 'att_extmag' },
    suppressorNoise = 0.5,

    -- Repair items: percentage of full durability restored to the weapon
    -- in your hands.
    repairItems = {
        weapon_repair_kit = { percent = 40 },
    },
}
