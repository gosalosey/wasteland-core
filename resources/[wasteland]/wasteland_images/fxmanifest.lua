fx_version 'cerulean'
game 'gta5'

name 'wasteland_images'
author 'Wasteland Core contributors'
description 'Wasteland Core - item pictures (from the community MK-Items pack; imported with tools/import_images.py)'
version '0.1.0'

-- html/index.txt lists every picture; the inventory reads it to decide
-- which items have one. Players download the pictures once (cached).
files {
    'html/index.txt',
    'html/images/*.webp',
}
