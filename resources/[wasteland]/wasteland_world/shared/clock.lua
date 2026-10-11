-- wasteland_world :: shared/clock.lua
-- Game clock and weather rules as pure functions (server decides, clients
-- display; tests check them exactly).

WLW = WLW or {}
WLW.Clock = WLW.Clock or {}
local Clock = WLW.Clock

WLW.WEATHERS = {
    'EXTRASUNNY', 'CLEAR', 'NEUTRAL', 'SMOG', 'FOGGY', 'OVERCAST', 'CLOUDS', 'CLEARING',
    'RAIN', 'THUNDER', 'SNOW', 'BLIZZARD', 'SNOWLIGHT', 'XMAS', 'HALLOWEEN',
}

--- Advance the clock by `ms` real milliseconds. One game minute lasts
--- `msPerMinute`. state = { hour, minute, carry, frozen }. Returns the
--- number of game minutes that passed.
function Clock.advance(state, ms, msPerMinute)
    if state.frozen then return 0 end
    state.carry = (state.carry or 0) + ms
    local minutes = math.floor(state.carry / msPerMinute)
    if minutes <= 0 then return 0 end
    state.carry = state.carry - minutes * msPerMinute
    local total = (state.hour * 60 + state.minute + minutes) % 1440
    state.hour, state.minute = total // 60, total % 60
    return minutes
end

function Clock.set(state, hour, minute)
    state.hour = math.floor(hour) % 24
    state.minute = math.floor(minute or 0) % 60
    state.carry = 0
end

--- Pick the next weather from a weighted pool { [name] = weight }.
--- `roll` is a random number 0..1. Never returns the same weather twice in
--- a row unless it is the only one.
function Clock.nextWeather(pool, current, roll)
    local names, total = {}, 0
    for name, weight in pairs(pool) do
        if weight > 0 and (name ~= current) then
            names[#names + 1] = name
            total = total + weight
        end
    end
    if #names == 0 then return current end
    table.sort(names)
    local pick = roll * total
    for _, name in ipairs(names) do
        pick = pick - pool[name]
        if pick < 0 then return name end
    end
    return names[#names]
end

return Clock
