-- Wasteland Core :: appearance (module "appearance", resource wasteland_appearance)
-- The character creator opens automatically for every new character.
return {
    -- Admin command to reopen the creator for a player: /appearance <server id>
    commandName = 'appearance',

    -- ACE an admin needs for that command.
    adminAce = 'wasteland.admin',

    -- Clothing players may not pick in the creator (for example police or
    -- military uniforms), per model and clothing slot:
    --   slots: 11 = top, 8 = undershirt, 3 = arms, 4 = legs, 6 = shoes
    -- Example:
    --   mp_m_freemode_01 = { [11] = { 55, 93 } },
    blockedClothing = {
        -- mp_m_freemode_01 = { [11] = {} },
        -- mp_f_freemode_01 = { [11] = {} },
    },
}
