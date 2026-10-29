-- wasteland_survivors :: shared/rules.lua
-- Pure rules (no game calls, unit-tested).

WLSV = WLSV or {}
local Rules = {}
WLSV.Rules = Rules

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

--- A whole number from lo to hi (r in [0, 1)).
function Rules.between(lo, hi, r)
    lo, hi = lo or 1, hi or lo or 1
    if hi < lo then hi = lo end
    return math.min(hi, lo + math.floor(r * (hi - lo + 1)))
end

--- `n` different entries of `list` by weight (rand: a function -> [0, 1)).
function Rules.pickSome(list, n, rand)
    local left, out = {}, {}
    for i, e in ipairs(list) do left[i] = e end
    while #out < n and #left > 0 do
        local e = Rules.pick(left, rand())
        for i, x in ipairs(left) do if x == e then table.remove(left, i); break end end
        out[#out + 1] = e
    end
    return out
end

--- A survivor's own trades: copies of `n` offers, each with `left` times.
function Rules.offers(pool, n, rand)
    local out = {}
    for i, o in ipairs(Rules.pickSome(pool, n, rand)) do
        out[i] = { give = { name = o.give.name, count = o.give.count }, get = { name = o.get.name, count = o.get.count },
            left = o.times or 1 }
    end
    return out
end

--- What a survivor gives for help: { { name, count } } from `rewards`.
function Rules.reward(rewards, picks, rand)
    local out = {}
    for i, e in ipairs(Rules.pickSome(rewards, picks, rand)) do
        out[i] = { name = e.name, count = Rules.between(e.min, e.max, rand()) }
    end
    return out
end

--- Has this player helped enough to be thanked? (help: kills near it)
function Rules.helped(kills, needed) return (kills or 0) >= (needed or 1) end

return Rules
