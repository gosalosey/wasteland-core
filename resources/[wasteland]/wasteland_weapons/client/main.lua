-- wasteland_weapons :: client/main.lua
-- Holds the one weapon the server handed us, with as many rounds as the
-- inventory has. Shots (ammo going down) and melee hits are counted and
-- reported once a second; the server takes the ammo, wears the weapon and
-- answers with the new state. GTA's own weapon switching is switched off.

local UNARMED = GetHashKey('WEAPON_UNARMED')
local REPORT_MS = 1000

local current = nil   -- state from the server (see server/main.lua state())
local hash = nil
local lastAmmo = 0    -- rounds the ped had last frame
local unreported = 0  -- shots/hits not yet sent

local function notice(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, false)
end

RegisterNetEvent('wasteland:weapons:client:notice', function(message) notice(message) end)

local function setAmmo(ped)
    if not current or current.melee then return end
    -- Shots fired since the last report are not in the server's count yet.
    local rounds = math.max(0, current.ammo - unreported)
    SetPedAmmo(ped, hash, rounds)
    lastAmmo = GetAmmoInPedWeapon(ped, hash)
end

-- The attachments the server says are on this gun (and none it does not).
local function fitComponents(ped)
    if not current or not hash then return end
    local want = {}
    for _, c in ipairs(current.components or {}) do want[GetHashKey(c)] = true end
    for c in pairs(want) do
        if not HasPedGotWeaponComponent(ped, hash, c) then GiveWeaponComponentToPed(ped, hash, c) end
    end
    for _, c in ipairs(current.removedComponents or {}) do
        local hc = GetHashKey(c)
        if not want[hc] and HasPedGotWeaponComponent(ped, hash, hc) then RemoveWeaponComponentFromPed(ped, hash, hc) end
    end
end

local function give()
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    if not current then return end
    GiveWeaponToPed(ped, hash, 0, false, true)
    fitComponents(ped)
    setAmmo(ped)
    SetCurrentPedWeapon(ped, hash, true)
end

local function report()
    if unreported <= 0 then return end
    local p = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('wasteland:weapons:server:used', math.min(unreported, 200), { x = p.x, y = p.y, z = p.z })
    unreported = 0
end

RegisterNetEvent('wasteland:weapons:client:hold', function(s)
    if type(s) ~= 'table' then return end
    report() -- shots from a previous weapon belong to it
    current, hash = s, GetHashKey(s.hash)
    unreported = 0
    give()
    if hash == STICKY then notice('Throw it at a wall or door, then press ~INPUT_DETONATE~ (G) to set it off.') end
end)

RegisterNetEvent('wasteland:weapons:client:state', function(s)
    -- (a throwable moves on to its next stack: same item, new uid)
    if type(s) ~= 'table' or not current or (s.uid ~= current.uid and s.item ~= current.item) then return end
    -- attachments taken off since the last state come off the ped's gun too
    local now = {}
    for _, c in ipairs(s.components or {}) do now[c] = true end
    local removed = {}
    for _, c in ipairs(current.components or {}) do if not now[c] then removed[#removed + 1] = c end end
    s.removedComponents = removed
    current = s
    fitComponents(PlayerPedId())
    setAmmo(PlayerPedId())
end)

RegisterNetEvent('wasteland:weapons:client:holster', function()
    report()
    current, hash = nil, nil
    unreported = 0
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    SetCurrentPedWeapon(ped, UNARMED, true)
end)

-- The body was (re)applied (spawn, respawn, appearance): weapons are gone.
AddEventHandler('wasteland:appearance:client:applied', function() if current then give() end end)

-- Melee hits: the game reports damage we dealt.
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not current or not current.melee then return end
    local attacker, weapon = args[2], args[7]
    if attacker == PlayerPedId() and weapon == hash then unreported = unreported + 1 end
end)

-- GTA weapon selection controls (wheel, scroll, number keys for weapon
-- slots): weapons come only from the inventory.
local STICKY = GetHashKey('WEAPON_STICKYBOMB')
local DETONATE = 47 -- G
local stickyOut = false -- sticky bombs placed and not yet set off

local SELECT_CONTROLS = { 12, 13, 14, 15, 16, 17, 37, 157, 158, 159, 160, 161, 162, 163, 164, 165, 261, 262 }
local ATTACK_CONTROLS = { 24, 25, 140, 141, 142, 257, 263, 264 }

Citizen.CreateThread(function()
    local sinceReport = 0
    while true do
        local ped = PlayerPedId()
        for _, c in ipairs(SELECT_CONTROLS) do DisableControlAction(0, c, true) end

        local selected = GetSelectedPedWeapon(ped)
        if current then
            if current.broken then
                DisablePlayerFiring(PlayerId(), true)
                for _, c in ipairs(ATTACK_CONTROLS) do DisableControlAction(0, c, true) end
            end
            if not current.melee then
                local now = GetAmmoInPedWeapon(ped, hash)
                if now < lastAmmo then
                    unreported = unreported + (lastAmmo - now)
                    if hash == STICKY then stickyOut = true end
                end
                lastAmmo = now
            end
            if selected ~= hash and selected ~= UNARMED then
                RemoveWeaponFromPed(ped, selected) -- not ours
            end
        elseif selected ~= UNARMED then
            RemoveAllPedWeapons(ped, true) -- picked up or given by something else
        end

        -- G sets off your sticky bombs, also once the last one is thrown
        -- (and the weapon is no longer in your hands).
        if stickyOut and IsControlJustPressed(0, DETONATE) then
            ExplodeProjectiles(ped, STICKY, false)
            stickyOut = false
        end

        sinceReport = sinceReport + GetFrameTime() * 1000
        if sinceReport >= REPORT_MS then
            sinceReport = 0
            report()
        end
        Citizen.Wait(0)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    RemoveAllPedWeapons(PlayerPedId(), true)
end)

-------------------------------------------------------------------------------
-- Attachments with no game part (custom guns: `SCRIPTED`). The suppressor's
-- effect is the server's (shots carry half as far); here: the flashlight
-- (a beam from the gun while aiming) and the scope (zoom while aiming).
-------------------------------------------------------------------------------

local scopeCam = nil
local function scopeOff()
    if scopeCam then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(scopeCam, false)
        scopeCam = nil
    end
end

Citizen.CreateThread(function()
    while true do
        local sc = current and current.scripted
        if not sc or not next(sc) then
            scopeOff()
            Citizen.Wait(300)
        else
            Citizen.Wait(0)
            local ped = PlayerPedId()
            local aiming = IsPlayerFreeAiming(PlayerId()) and GetSelectedPedWeapon(ped) == hash
            if sc.flashlight and aiming then
                local w = GetCurrentPedWeaponEntityIndex(ped)
                local from = (w ~= 0) and GetEntityCoords(w) or GetPedBoneCoords(ped, 0xDEAD, 0.0, 0.0, 0.0)
                local rot = GetGameplayCamRot(2)
                local rx, rz = math.rad(rot.x), math.rad(rot.z)
                local dir = vector3(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx))
                DrawSpotLight(from.x, from.y, from.z, dir.x, dir.y, dir.z, 255, 245, 225, 40.0, 6.0, 0.0, 14.0, 30.0)
            end
            if sc.scope and aiming and GetFollowPedCamViewMode() ~= 4 then
                if not scopeCam then
                    scopeCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
                    RenderScriptCams(true, false, 0, true, false)
                end
                SetCamCoord(scopeCam, GetGameplayCamCoord())
                SetCamRot(scopeCam, GetGameplayCamRot(2), 2)
                SetCamFov(scopeCam, 18.0)
                HideHudComponentThisFrame(14) -- the game's reticle (wrong size zoomed in)
                DrawRect(0.5, 0.5, 0.0015, 0.004, 255, 255, 255, 200)
                DrawRect(0.5, 0.5, 0.002, 0.0015, 255, 255, 255, 200)
            else
                scopeOff()
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then scopeOff() end end)
