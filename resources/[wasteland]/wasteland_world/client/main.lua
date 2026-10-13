-- wasteland_world :: client/main.lua
-- Shows the server's clock and weather, keeps the world empty (no ambient
-- NPCs, traffic, parked cars, police) and silent (no ambience, music,
-- scanner, sirens). Gameplay sounds (weapons, footsteps, your own vehicle)
-- are left alone. Scripted peds (zombies) are not affected.

local settings = nil   -- last sync from the server
local clock = { hour = 12, minute = 0, carry = 0, frozen = false }
local msPerMinute = 2000
local currentWeather = nil

-------------------------------------------------------------------------------
-- Clock and weather
-------------------------------------------------------------------------------

local function applyWeather(name, transition)
    if name == currentWeather then return end
    currentWeather = name
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    if transition and transition > 0 then
        SetWeatherTypeOvertimePersist(name, transition + 0.0)
        Citizen.SetTimeout(transition * 1000, function()
            if currentWeather ~= name then return end
            SetWeatherTypePersist(name)
            SetWeatherTypeNow(name)
            SetWeatherTypeNowPersist(name)
        end)
    else
        SetWeatherTypePersist(name)
        SetWeatherTypeNow(name)
        SetWeatherTypeNowPersist(name)
    end
    SetForceVehicleTrails(name == 'XMAS' or name == 'SNOW' or name == 'BLIZZARD')
    SetForcePedFootstepsTracks(name == 'XMAS' or name == 'SNOW' or name == 'BLIZZARD')
end

RegisterNetEvent('wasteland:world:client:sync', function(p)
    if type(p) ~= 'table' then return end
    settings = p
    clock.hour, clock.minute, clock.frozen, clock.carry = p.hour, p.minute, p.frozen, 0
    msPerMinute = p.msPerMinute or 2000
    applyWeather(p.weather, p.transition)
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        if settings then
            WLW.Clock.advance(clock, 1000, msPerMinute) -- smooth between server syncs
            NetworkOverrideClockTime(clock.hour, clock.minute, 0)
        end
    end
end)

-------------------------------------------------------------------------------
-- No idle camera: standing still must not start GTA's slow camera pan
-------------------------------------------------------------------------------

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000)
        if not (settings and settings.idleCamera) then
            InvalidateIdleCam()
            InvalidateVehicleIdleCam()
        end
    end
end)

-------------------------------------------------------------------------------
-- Empty world
-------------------------------------------------------------------------------

local function applyOnce(p)
    local pop, audio = p.population, p.audio
    if not pop.police then
        for i = 1, 15 do EnableDispatchService(i, false) end
        SetMaxWantedLevel(0)
        SetCreateRandomCops(false)
        SetCreateRandomCopsNotOnScenarios(false)
        SetCreateRandomCopsOnScenarios(false)
    end
    if not pop.vehicles then
        SetGarbageTrucks(false)
        SetRandomBoats(false)
        SetRandomTrains(false)
        SetDistantCarsEnabled(false)
        DisableVehicleDistantlights(true)
    end
    if not pop.peds then SetPedPopulationBudget(0) end
    if not pop.vehicles then SetVehiclePopulationBudget(0) end

    -- Sound
    if not audio.ambience then StartAudioScene('FBI_HEIST_H5_MUTE_AMBIENCE_SCENE') end
    if not audio.scanner then
        SetAudioFlag('PoliceScannerDisabled', true)
        DistantCopCarSirens(false)
    end
    if not audio.music then
        SetAudioFlag('DisableFlightMusic', true)
        SetAudioFlag('MobileRadioInGame', false)
        SetMobileRadioEnabledDuringGameplay(false)
        SetUserRadioControlEnabled(false)
        for _, emitter in ipairs(WLW.MUSIC_EMITTERS) do SetStaticEmitterEnabled(emitter, false) end
        for _, emitter in ipairs(audio.emitters or {}) do SetStaticEmitterEnabled(emitter, false) end
    end
end

-- Density has to be set every frame; the rest once per sync.
Citizen.CreateThread(function()
    while not settings do
        TriggerServerEvent('wasteland:world:server:request')
        Citizen.Wait(3000)
    end
    local applied = nil
    while true do
        local p = settings
        if p ~= applied then
            applyOnce(p)
            applied = p
        end
        local pop = p.population
        if not pop.peds then
            SetPedDensityMultiplierThisFrame(0.0)
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
        end
        if not pop.vehicles then
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
        end
        if not pop.parkedVehicles then SetParkedVehicleDensityMultiplierThisFrame(0.0) end
        Citizen.Wait(0)
    end
end)

-- Radio off in every vehicle the player uses.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        if settings and not settings.audio.music then
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                SetVehRadioStation(veh, 'OFF')
                SetVehicleRadioEnabled(veh, false)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    StopAudioScene('FBI_HEIST_H5_MUTE_AMBIENCE_SCENE')
    SetPedPopulationBudget(3)
    SetVehiclePopulationBudget(3)
end)
