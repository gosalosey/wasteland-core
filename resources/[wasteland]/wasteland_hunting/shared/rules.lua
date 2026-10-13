-- wasteland_hunting :: shared/rules.lua
-- Pure rules (no game calls, unit-tested).

WLH = WLH or {}
local Rules = {}
WLH.Rules = Rules

-- Every animal ped model in GTA V. Any of these can be harvested when dead
-- (also ones this module did not spawn). The server cannot ask the game if a
-- ped is human, so it checks the model against this list.
Rules.ANIMAL_MODELS = {
    'a_c_boar', 'a_c_cat_01', 'a_c_chickenhawk', 'a_c_chimp', 'a_c_chop', 'a_c_cormorant', 'a_c_cow', 'a_c_coyote',
    'a_c_crow', 'a_c_deer', 'a_c_dolphin', 'a_c_fish', 'a_c_hen', 'a_c_humpback', 'a_c_husky', 'a_c_killerwhale',
    'a_c_mtlion', 'a_c_pig', 'a_c_pigeon', 'a_c_poodle', 'a_c_pug', 'a_c_rabbit_01', 'a_c_rat', 'a_c_retriever',
    'a_c_rhesus', 'a_c_rottweiler', 'a_c_seagull', 'a_c_sharkhammer', 'a_c_sharktiger', 'a_c_shepherd', 'a_c_stingray',
    'a_c_westy', 'a_c_panther', 'a_c_rabbit_02', 'a_c_coyote_02', 'a_c_deer_02', 'a_c_mtlion_02', 'a_c_boar_02',
}

--- Pick one entry by `weight` (r: a number in [0, 1)).
function Rules.pick(list, r)
    local total = 0
    for _, e in ipairs(list) do total = total + (e.weight or 1) end
    if total <= 0 then return nil end
    local at = r * total
    for _, e in ipairs(list) do
        at = at - (e.weight or 1)
        if at < 0 then return e end
    end
    return list[#list]
end

--- What a dead animal gives. animal: its entry in hunting.lua `animals` or
--- nil (another animal: `other`). r1, r2: numbers in [0, 1).
--- -> meat count, pelt count
function Rules.yield(animal, other, r1)
    local m = (animal and animal.meat) or other or { 1, 1 }
    local lo, hi = m[1] or 1, m[2] or m[1] or 1
    local meat = lo + math.floor(r1 * (hi - lo + 1))
    if meat > hi then meat = hi end
    return meat, (animal and animal.pelt) or 0
end

--- How many to cook: what was asked, at least 1, at most what is carried
--- and at most `max` in one go. 0 when nothing is carried.
function Rules.cookCount(want, have, max)
    want = math.floor(tonumber(want) or 1)
    if have <= 0 then return 0 end
    return math.max(1, math.min(want, have, max or 50))
end

--- Where a placed thing goes: `dist` metres in front of (x, y) facing `heading` (GTA degrees).
function Rules.inFront(x, y, heading, dist)
    local a = math.rad(heading or 0.0)
    return x - math.sin(a) * dist, y + math.cos(a) * dist
end

return Rules
