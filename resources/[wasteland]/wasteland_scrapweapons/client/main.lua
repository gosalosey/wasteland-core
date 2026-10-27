-- wasteland_scrapweapons :: client/main.lua
-- The game-side extras of each scrap weapon: the name the game shows for it
-- and how hard it hits compared with the weapon it is based on. Holding,
-- ammo and wear are wasteland_weapons' job.

local function apply()
    for _, w in pairs(WLSW.catalog) do
        if w.labelKey and w.label then AddTextEntry(w.labelKey, w.label) end
        if w.weapon and w.damage and w.damage ~= 1.0 then
            SetWeaponDamageModifier(GetHashKey(w.weapon.hash), w.damage + 0.0)
        end
    end
end

Citizen.CreateThread(apply)
