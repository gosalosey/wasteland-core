fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'wasteland_buildprops_scrap'
author 'Wasteland Core contributors'
description 'Wasteland Core - OPTIONAL "scrap barricade" look for building pieces (test). Replaces wasteland_buildprops models of the same name while it runs.'
version '0.1.0'

-- TEST PACK. Not started by default. To try it, add to server.cfg AFTER
-- `ensure wasteland_buildprops`:
--     ensure wasteland_buildprops_scrap
-- Remove that line to go back. Only the wood wall (wl_bp_wall_wood) so far.
-- Built in Blender with Sollumz from tools/buildprops/scrap (textures: ambientCG, CC0).
dependency 'wasteland_buildprops'
