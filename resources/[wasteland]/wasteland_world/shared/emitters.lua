-- wasteland_world :: shared/emitters.lua
-- Static audio emitters that play music in the world (clubs, bars, shops,
-- radios). Names that do not exist in a game build are ignored by the game.
-- Add more in wasteland_config/config/world.lua (audio.emitters).

WLW = WLW or {}

WLW.MUSIC_EMITTERS = {
    'LOS_SANTOS_VANILLA_UNICORN_01_STAGE',
    'LOS_SANTOS_VANILLA_UNICORN_02_MAIN_ROOM',
    'LOS_SANTOS_VANILLA_UNICORN_03_BACK_ROOM',
    'LOS_SANTOS_AMMUNATION_GUN_RANGE',
    'SE_LS_DOCKS_RADIO_01',
    'SE_LS_DOCKS_RADIO_02',
    'SE_LS_DOCKS_RADIO_03',
    'SE_LS_DOCKS_RADIO_04',
    'SE_LS_DOCKS_RADIO_05',
    'SE_LS_DOCKS_RADIO_06',
    'SE_LS_DOCKS_RADIO_07',
    'SE_LS_DOCKS_RADIO_08',
    'SE_DMOD_Trailer_Radio',
    'SE_MP_APT_NEW_RADIO',
    'SE_MP_GARAGE_L_RADIO',
    'SE_MP_GARAGE_M_RADIO',
    'SE_MP_GARAGE_S_RADIO',
    'SE_BA_DLC_CLUB_EXTERIOR',
    'SE_DLC_APT_YACHT_BAR',
    'SE_DLC_APT_YACHT_BEDROOM',
    'SE_DLC_APT_YACHT_EXTERIOR_01',
    'SE_DLC_APT_YACHT_EXTERIOR_02',
    'SE_DLC_APT_YACHT_EXTERIOR_03',
    'SE_DLC_APT_YACHT_EXTERIOR_04',
    'SE_Bank_01_Radio',
    'SE_Hillbilly_Bar_01',
    'SE_COUNTRY_SALOON_01',
    'SE_RECYCLING_PLANT_01',
    'SE_STRIPCLUB_01',
    'TREVOR_TRAILER_RADIO',
    'MICHAELS_HOUSE_RADIO',
    'FRANKLIN_HOUSE_RADIO',
    'LOS_SANTOS_CUSTOMS_RADIO',
    'SE_LS_BURGERSHOT_RADIO',
    'SE_LS_TATTOO_RADIO',
    'SE_LS_BARBER_RADIO',
    'SE_ID2_FACTORY_01',
}

return WLW.MUSIC_EMITTERS
