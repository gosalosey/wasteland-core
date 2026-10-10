-- Wasteland Core :: client/main.lua
-- Prints admin command output in the player's F8 console.

RegisterNetEvent('wasteland:core:client:consoleOutput', function(lines)
    if type(lines) ~= 'table' then return end
    for i = 1, math.min(#lines, 200) do
        if type(lines[i]) == 'string' then print(lines[i]) end
    end
end)
