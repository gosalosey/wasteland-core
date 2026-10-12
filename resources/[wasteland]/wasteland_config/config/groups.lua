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
}
