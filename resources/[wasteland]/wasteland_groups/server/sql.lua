-- wasteland_groups :: server/sql.lua
-- Groups belong to characters. A character is in at most one group.

WLG = WLG or {}

WLG.MIGRATIONS = {
    {
        version = 1,
        name = 'create_groups',
        up = [[
CREATE TABLE IF NOT EXISTS wl_groups (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(32) NOT NULL,
    leader_id INT UNSIGNED NOT NULL,
    created_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_wl_groups_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
    {
        version = 2,
        name = 'create_group_members',
        up = [[
CREATE TABLE IF NOT EXISTS wl_group_members (
    character_id INT UNSIGNED NOT NULL,
    group_id INT UNSIGNED NOT NULL,
    name VARCHAR(64) NOT NULL,
    joined_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (character_id),
    KEY ix_wl_group_members_group (group_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}

WLG.SQL = {
    selectGroups = 'SELECT id, name, leader_id FROM wl_groups',
    selectMembers = 'SELECT character_id, group_id, name FROM wl_group_members',
    insertGroup = 'INSERT INTO wl_groups (name, leader_id, created_unix) VALUES (?, ?, ?)',
    deleteGroup = 'DELETE FROM wl_groups WHERE id = ?',
    deleteMembers = 'DELETE FROM wl_group_members WHERE group_id = ?',
    insertMember = 'INSERT INTO wl_group_members (character_id, group_id, name, joined_unix) VALUES (?, ?, ?, ?) '
        .. 'ON DUPLICATE KEY UPDATE group_id = VALUES(group_id), name = VALUES(name), joined_unix = VALUES(joined_unix)',
    deleteMember = 'DELETE FROM wl_group_members WHERE character_id = ?',
    setLeader = 'UPDATE wl_groups SET leader_id = ? WHERE id = ?',
    rename = 'UPDATE wl_groups SET name = ? WHERE id = ?',
    memberName = 'UPDATE wl_group_members SET name = ? WHERE character_id = ?',
}

return WLG.SQL
