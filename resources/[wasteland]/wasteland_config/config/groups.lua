-- Groups (module "groups", resource wasteland_groups).
-- /group (or F6): make a group, name it, invite players (by id or from the
-- players near you). Members see each other on the map (blue; the leader
-- yellow; red when down). Groups are saved and last until the leader
-- disbands them. One group per character.
return {
    maxMembers = 8,
    nameMin = 3,
    nameMax = 24,
    inviteSeconds = 120,    -- an invitation lasts this long
    markerSeconds = 2,      -- how often the map markers move

    -- Group radio (needs pma-voice): members talk to each other anywhere on
    -- the map while holding the radio key (pma-voice convar voice_defaultRadio,
    -- set to Caps Lock in server.cfg). Group N uses channel channelBase + N.
    radio = {
        enabled = true,
        channelBase = 1000,
        keyName = 'Caps Lock',
    },

    -- Calls for help (any player): /help [what is wrong] tells everyone that
    -- this player needs help and roughly where; /accepthelp gives a GPS route
    -- to them (it follows them while the call is open); /cancelhelp ends it.
    -- One call per cooldownMinutes; a call ends after expireMinutes.
    help = { enabled = true, cooldownMinutes = 3, expireMinutes = 10 },
}
