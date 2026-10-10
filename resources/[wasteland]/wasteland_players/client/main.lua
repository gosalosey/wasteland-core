-- wasteland_players :: client/main.lua
-- Places the player at the loaded character's saved position. Everything
-- else (which character, where) is decided by the server.

local function teleport(pos)
    local ped = PlayerPedId()
    local x, y, z = pos.x + 0.0, pos.y + 0.0, pos.z + 0.0
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Citizen.Wait(0) end
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, (pos.heading or 0.0) + 0.0)
    local deadline = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        Citizen.Wait(0)
    end
    DoScreenFadeIn(500)
end

RegisterNetEvent('wasteland:players:client:characterLoaded', function(info)
    if type(info) ~= 'table' then return end
    local pos = info.position
    if type(pos) == 'table' and type(pos.x) == 'number' and type(pos.y) == 'number' and type(pos.z) == 'number' then
        Citizen.CreateThread(function() teleport(pos) end)
    end
end)
