-- wasteland_scrapweapons :: shared/catalog.lua
-- Every scrap weapon this resource brings. Weapons are added here one at a
-- time, each only once its model, data and icon are finished.
--
-- Per weapon (key = the inventory item name, scrap_*):
--   item    inventory item definition (as in inventory.lua items; category = 'weapon')
--   weapon  { hash = 'WEAPON_WL_...', ammo?, wear?, noise? } (as in weapons.lua)
--   recipe  { label, result, ingredients, seconds?, blueprint?, station? } (as in crafting.lua)
--           (optional; leave out for loot-only weapons)
--   status  'testing' | 'approved'   (kept in step with docs/scrapweapons.md)

WLSW = WLSW or {}

WLSW.catalog = {
}

return WLSW.catalog
