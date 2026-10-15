-- wasteland_zombies :: client/sounds.lua
-- Zombie sounds (zombies.lua `sounds`). Every game plays them for the
-- zombies near its player (not only the game running a zombie), so all
-- players hear the same zombie: groans (calm / chasing), the swing, being
-- hurt, dying, a screamer's or howler's call. The files are in a separate
-- resource (`sounds.pack`, default wasteland_zombiesounds) kept on the server;
-- without it zombies are silent as before.

local AI = WLZ.AI

local DEFAULTS = {
    enabled = true,
    pack = 'wasteland_zombiesounds',
    volume = 0.7,            -- 0 - 1, at point-blank range
    range = 35,              -- metres: heard no further than this
    callRange = 90,          -- screams and howls carry further
    idleEvery = { 7, 18 },   -- seconds between groans for a calm zombie
    chaseEvery = { 3, 7 },   -- ... and for one coming at you
    groups = {
        idle = { 'Zombie001_Idle_A_001.ogg', 'Zombie001_Idle_A_002.ogg', 'Zombie001_Idle_A_003.ogg',
            'Zombie003_Idle_A_001.ogg', 'Zombie003_Idle_A_002.ogg', 'Zombie003_Idle_A_003.ogg' },
        chase = { '01_zombey.mp3', '02_zombey.mp3', '03_zombey.mp3', '04_zombey.mp3', '06_zombey.mp3', '07_zombey.mp3' },
        attack = { 'Zombie001_Attack_A_001.ogg', 'Zombie001_Attack_A_002.ogg', 'Zombie001_Attack_A_003.ogg',
            'Zombie003_Attack_A_001.ogg', 'Zombie003_Attack_A_002.ogg', 'Zombie003_Attack_A_003.ogg',
            'Zombie_Attack_Bite_001.ogg', 'Zombie_Attack_Bite_002.ogg' },
        hurt = { 'Zombie001_Hurt_A_001.ogg', 'Zombie001_Hurt_A_002.ogg', 'Zombie001_Hurt_A_003.ogg',
            'Zombie003_Hurt_A_001.ogg', 'Zombie003_Hurt_A_002.ogg', 'Zombie003_Hurt_A_003.ogg' },
        impact = { 'Impact_Flesh_001.ogg', 'Impact_Flesh_002.ogg', 'Impact_Flesh_003.ogg',
            'Impact_Flesh_Gory_Light_001.ogg', 'Impact_Flesh_Gory_Light_002.ogg' },
        death = { 'Foley_BodyFall_001.ogg', 'Foley_BodyFall_002.ogg', 'Foley_BodyFall_003.ogg' },
        call = { '01_zombey.mp3', '03_zombey.mp3', '07_zombey.mp3' },   -- screamer / howler (played lower and longer)
    },
}

local ATTACK_DICT, ATTACK_ANIM = 'melee@unarmed@streamed_variations', 'plyr_takedown_front_slap'
local CALL_DICT, CALL_ANIM = 'anim@mp_player_intcelebrationmale@freakout', 'freakout'
local SLEEP_DICT, SLEEP_ANIM = 'dead', 'dead_a'

local voices = {}   -- ped -> { nextGroan, attacking, calling, health, dead, nextHurt }

local cache = { src = false, merged = DEFAULTS }
local function settings()
    local cfg = WLZ.Client and WLZ.Client.cfg()
    local user = cfg and cfg.sounds
    if cache.src ~= user then cache.src, cache.merged = user, AI.merge(DEFAULTS, user) end
    return cache.merged
end

local function pick(list) return list[math.random(1, #list)] end

-- How loud and from which side, for a sound at `at`.
local function place(at, range)
    local cam = GetFinalRenderedCamCoord()
    local d = #(at - cam)
    if d > range then return nil end
    local loud = (1.0 - d / range) ^ 1.5
    local rot = GetFinalRenderedCamRot(2)
    local yaw = math.rad(rot.z)
    local rx, ry = math.cos(yaw), math.sin(yaw)   -- the camera's right
    local dx, dy = at.x - cam.x, at.y - cam.y
    local len = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    return loud, (rx * dx + ry * dy) / len
end

local function play(s, group, at, opts)
    local list = s.groups[group]
    if type(list) ~= 'table' or #list == 0 then return end
    opts = opts or {}
    local loud, pan = place(at, opts.range or s.range)
    if not loud then return end
    SendNUIMessage({ type = 'wlz:sound', pack = s.pack, file = pick(list),
        volume = s.volume * loud * (opts.volume or 1), pan = pan * 0.8, rate = opts.rate or (0.92 + math.random() * 0.16) })
end

local function between(pair) return (pair[1] + math.random() * (pair[2] - pair[1])) * 1000 end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(200)
        local s = settings()
        if s.enabled and GetResourceState(s.pack) == 'started' then
            local t = GetGameTimer()
            local me = GetEntityCoords(PlayerPedId())
            local seen = {}
            for _, ped in ipairs(GetGamePool('CPed')) do
                if not IsPedAPlayer(ped) then
                    local at = GetEntityCoords(ped)
                    if #(at - me) <= s.callRange then
                        local ok, state = pcall(function() return Entity(ped).state end)
                        if ok and state and state.wlZombie then
                            seen[ped] = true
                            local v = voices[ped]
                            if not v then
                                v = { nextGroan = t + between(s.idleEvery), health = GetEntityHealth(ped) }
                                voices[ped] = v
                            end
                            local dead = IsPedDeadOrDying(ped, true)
                            local health = GetEntityHealth(ped)
                            if dead then
                                if not v.dead then
                                    v.dead = true
                                    play(s, 'hurt', at, { volume = 0.9 })
                                    play(s, 'death', at)
                                end
                            else
                                -- hurt (with the thud of the hit)
                                if health < v.health - 2 and t >= (v.nextHurt or 0) then
                                    v.nextHurt = t + 900
                                    play(s, 'impact', at, { volume = 0.8 })
                                    play(s, 'hurt', at)
                                end
                                -- the swing
                                local swinging = IsEntityPlayingAnim(ped, ATTACK_DICT, ATTACK_ANIM, 3)
                                if swinging and not v.attacking then play(s, 'attack', at) end
                                v.attacking = swinging
                                -- a screamer's / howler's call
                                local calling = IsEntityPlayingAnim(ped, CALL_DICT, CALL_ANIM, 3)
                                if calling and not v.calling then
                                    play(s, 'call', at, { range = s.callRange, volume = 1.3, rate = 0.8 })
                                end
                                v.calling = calling
                                -- groans: calm ones now and then, ones running at you more often; sleepers are quiet
                                if t >= v.nextGroan and not IsEntityPlayingAnim(ped, SLEEP_DICT, SLEEP_ANIM, 3) then
                                    local hurrying = GetEntitySpeed(ped) > 1.8
                                    play(s, hurrying and 'chase' or 'idle', at)
                                    v.nextGroan = t + between(hurrying and s.chaseEvery or s.idleEvery)
                                end
                            end
                            v.health = health
                        end
                    end
                end
            end
            for ped in pairs(voices) do if not seen[ped] then voices[ped] = nil end end
        end
    end
end)
