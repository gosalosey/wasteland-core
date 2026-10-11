-- wasteland_emotes :: shared/emotes.lua
-- The emote list. Add or change lines here; the F4 menu and /e use it.
--   name      what players type: /e <name> (lower case, no spaces)
--   label     what the menu shows
--   cat       menu category
--   scenario  a GTA scenario (props come with it), or
--   dict/anim an animation; flag: 1 = loop (whole body), 49 = loop, upper
--             body only (you can walk), 0 = play once, 48 = once, upper body
-- Whole-body emotes stop when you start walking; upper-body ones do not.

WLE = WLE or {}

WLE.CATEGORIES = { 'Gestures', 'Survival', 'Sit & lie', 'Work', 'Moods', 'Fitness' }

WLE.EMOTES = {
    -- Gestures
    { name = 'wave', label = 'Wave', cat = 'Gestures', dict = 'friends@frj@ig_1', anim = 'wave_a', flag = 49 },
    { name = 'point', label = 'Point', cat = 'Gestures', dict = 'gestures@f@standing@casual', anim = 'gesture_point', flag = 48 },
    { name = 'salute', label = 'Salute', cat = 'Gestures', dict = 'mp_player_int_uppersalute', anim = 'mp_player_int_salute', flag = 49 },
    { name = 'thumbsup', label = 'Thumbs up', cat = 'Gestures', dict = 'anim@mp_player_intupperthumbs_up', anim = 'idle_a', flag = 49 },
    { name = 'shrug', label = 'Shrug', cat = 'Gestures', dict = 'gestures@f@standing@casual', anim = 'gesture_shrug_hard', flag = 48 },
    { name = 'facepalm', label = 'Facepalm', cat = 'Gestures', dict = 'anim@mp_player_intcelebrationmale@face_palm', anim = 'face_palm', flag = 48 },
    { name = 'come', label = 'Come here', cat = 'Gestures', dict = 'gestures@f@standing@casual', anim = 'gesture_come_here_soft', flag = 48 },
    { name = 'nod', label = 'Nod yes', cat = 'Gestures', dict = 'gestures@f@standing@casual', anim = 'gesture_pleased', flag = 48 },
    { name = 'no', label = 'Shake head', cat = 'Gestures', dict = 'gestures@f@standing@casual', anim = 'gesture_head_no', flag = 48 },
    { name = 'clap', label = 'Clap', cat = 'Gestures', dict = 'amb@world_human_cheering@male_a', anim = 'base', flag = 1 },
    { name = 'handsup', label = 'Hands up (X)', cat = 'Gestures', dict = 'missminuteman_1ink', anim = 'handsup_base', flag = 49 },
    { name = 'surrender', label = 'Surrender on knees', cat = 'Gestures', dict = 'random@arrests@busted', anim = 'idle_a', flag = 1 },

    -- Survival
    { name = 'binoculars', label = 'Binoculars', cat = 'Survival', scenario = 'WORLD_HUMAN_BINOCULARS' },
    { name = 'flashlight', label = 'Shine flashlight', cat = 'Survival', scenario = 'WORLD_HUMAN_SECURITY_SHINE_TORCH' },
    { name = 'guard', label = 'Stand guard', cat = 'Survival', scenario = 'WORLD_HUMAN_GUARD_STAND' },
    { name = 'warm', label = 'Warm hands by fire', cat = 'Survival', scenario = 'WORLD_HUMAN_STAND_FIRE' },
    { name = 'search', label = 'Search the ground', cat = 'Survival', scenario = 'CODE_HUMAN_MEDIC_TEND_TO_DEAD' },
    { name = 'kneel', label = 'Kneel', cat = 'Survival', dict = 'amb@medic@standing@kneel@base', anim = 'base', flag = 1 },
    { name = 'map', label = 'Read a map', cat = 'Survival', scenario = 'WORLD_HUMAN_TOURIST_MAP' },
    { name = 'radio', label = 'Talk on the radio', cat = 'Survival', scenario = 'WORLD_HUMAN_STAND_MOBILE' },
    { name = 'knock', label = 'Knock', cat = 'Survival', dict = 'timetable@jimmy@doorknock@', anim = 'knockdoor_idle', flag = 1 },
    { name = 'cower', label = 'Cower', cat = 'Survival', dict = 'amb@code_human_cower@male@base', anim = 'base', flag = 1 },

    -- Sit & lie
    { name = 'sit', label = 'Sit on the ground', cat = 'Sit & lie', scenario = 'WORLD_HUMAN_PICNIC' },
    { name = 'lean', label = 'Lean on a wall', cat = 'Sit & lie', scenario = 'WORLD_HUMAN_LEANING' },
    { name = 'sleep', label = 'Sleep (slumped)', cat = 'Sit & lie', scenario = 'WORLD_HUMAN_BUM_SLUMPED' },
    { name = 'liedown', label = 'Lie on your back', cat = 'Sit & lie', scenario = 'WORLD_HUMAN_SUNBATHE_BACK' },
    { name = 'wounded', label = 'Wounded on the ground', cat = 'Sit & lie', dict = 'combat@damage@writhe', anim = 'writhe_loop', flag = 1 },
    { name = 'dead', label = 'Play dead', cat = 'Sit & lie', dict = 'dead', anim = 'dead_a', flag = 1 },

    -- Work
    { name = 'mechanic', label = 'Fix something', cat = 'Work', dict = 'mini@repair', anim = 'fixing_a_player', flag = 1 },
    { name = 'weld', label = 'Weld', cat = 'Work', scenario = 'WORLD_HUMAN_WELDING' },
    { name = 'hammer', label = 'Hammer', cat = 'Work', scenario = 'WORLD_HUMAN_HAMMERING' },
    { name = 'dig', label = 'Dig / plant', cat = 'Work', scenario = 'WORLD_HUMAN_GARDENER_PLANT' },
    { name = 'notes', label = 'Write notes', cat = 'Work', scenario = 'WORLD_HUMAN_CLIPBOARD' },

    -- Moods
    { name = 'smoke', label = 'Smoke', cat = 'Moods', scenario = 'WORLD_HUMAN_SMOKING' },
    { name = 'drink', label = 'Drink', cat = 'Moods', scenario = 'WORLD_HUMAN_DRINKING' },
    { name = 'crossarms', label = 'Cross arms', cat = 'Moods', dict = 'amb@world_human_hang_out_street@female_arms_crossed@base', anim = 'base', flag = 49 },
    { name = 'think', label = 'Think', cat = 'Moods', dict = 'misscarsteal4@aliens', anim = 'rehearsal_base_idle_director', flag = 49 },
    { name = 'tired', label = 'Out of breath', cat = 'Moods', dict = 're@construction', anim = 'out_of_breath', flag = 1 },
    { name = 'cough', label = 'Cough', cat = 'Moods', dict = 'timetable@gardener@smoking_joint', anim = 'idle_cough', flag = 48 },
    { name = 'vomit', label = 'Throw up', cat = 'Moods', dict = 'missheistpaletoscore1leadinout', anim = 'trv_puking_leadout', flag = 0 },
    { name = 'idle', label = 'Hang around', cat = 'Moods', scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },

    -- Fitness
    { name = 'pushups', label = 'Push-ups', cat = 'Fitness', scenario = 'WORLD_HUMAN_PUSH_UPS' },
    { name = 'situps', label = 'Sit-ups', cat = 'Fitness', scenario = 'WORLD_HUMAN_SIT_UPS' },
    { name = 'yoga', label = 'Yoga', cat = 'Fitness', scenario = 'WORLD_HUMAN_YOGA' },
    { name = 'flex', label = 'Flex', cat = 'Fitness', scenario = 'WORLD_HUMAN_MUSCLE_FLEX' },
    { name = 'jog', label = 'Jog on the spot', cat = 'Fitness', scenario = 'WORLD_HUMAN_JOG_STANDING' },
}

WLE.BY_NAME = {}
for _, e in ipairs(WLE.EMOTES) do WLE.BY_NAME[e.name] = e end

return WLE
