-- wasteland_moonshine :: shared/rules.lua
-- Pure rules (unit-tested): drinking, wearing off, and when zombies cannot
-- smell you (full meter) or can again (below the line).

WLM = WLM or {}
local Rules = {}
WLM.Rules = Rules

local function clamp(v) return math.max(0, math.min(100, v)) end

--- A jar: drunk and blind go up; the meter being full masks you.
function Rules.drink(st, d)
    st.drunk = clamp((st.drunk or 0) + d.drunk)
    st.blind = clamp((st.blind or 0) + d.blind)
    if st.blind >= 100 then st.masked = true end
    return st
end

--- Time passes (minutes): both wear off; below the line zombies smell you again.
function Rules.decay(st, minutes, cfg)
    if not st.masked then st.drunk = clamp((st.drunk or 0) - cfg.soberPerMinute * minutes) end -- stays drunk while zombies cannot smell you
    st.blind = clamp((st.blind or 0) - cfg.blindPerMinute * minutes)
    if st.masked and st.blind < cfg.unmaskBelow then st.masked = false; st.drunk = 0 end -- sober when they can smell you again
    if st.blind <= 0 then st.drunk = 0 end
    return st
end

--- Nothing left to track?
function Rules.idle(st) return (st.drunk or 0) <= 0 and (st.blind or 0) <= 0 and not st.masked end

return Rules
