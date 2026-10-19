fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_buildprops'
author 'Wasteland Core contributors'
description 'Wasteland Core - EXPERIMENTAL generated building props (not used by default: collision does not work yet)'
version '1.0.0'

-- Model names: wl_bp_<piece>_<wood|stone|metal>, wl_bp_door_*, wl_bp_gate_*,
-- wl_bp_garage_wood, wl_bp_windowbar_*, wl_bp_toolcupboard.
-- Rebuilt with tools/buildprops (see its README).
data_file 'DLC_ITYP_REQUEST' 'stream/wl_buildprops.ytyp'

-- Collision test walls (wl_bp_test_a .. d): place them with /propplacer.
data_file 'DLC_ITYP_REQUEST' 'stream/wl_bp_tests.ytyp'
