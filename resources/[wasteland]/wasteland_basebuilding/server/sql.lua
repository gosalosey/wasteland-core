-- wasteland_basebuilding :: server/sql.lua
-- Tool cupboards (claims), who may use them, placed pieces, and messages for
-- owners who were offline when their base was raided.

WLBB = WLBB or {}

WLBB.MIGRATIONS = {
    {
        version = 1,
        name = 'create_cupboards',
        up = [[
CREATE TABLE IF NOT EXISTS wl_bb_cupboards (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    owner_id INT UNSIGNED NOT NULL,
    x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL,
    heading DOUBLE NOT NULL DEFAULT 0,
    radius DOUBLE NOT NULL DEFAULT 40,
    health INT NOT NULL DEFAULT 500,
    max_health INT NOT NULL DEFAULT 500,
    created_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    KEY ix_wl_bb_cupboards_owner (owner_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
    {
        version = 2,
        name = 'create_auth',
        up = [[
CREATE TABLE IF NOT EXISTS wl_bb_auth (
    cupboard_id INT UNSIGNED NOT NULL,
    character_id INT UNSIGNED NOT NULL,
    name VARCHAR(64) NOT NULL,
    PRIMARY KEY (cupboard_id, character_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
    {
        version = 3,
        name = 'create_props',
        up = [[
CREATE TABLE IF NOT EXISTS wl_bb_props (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    cupboard_id INT UNSIGNED NULL,
    category VARCHAR(16) NOT NULL,
    piece VARCHAR(40) NOT NULL,
    model VARCHAR(64) NOT NULL,
    x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL,
    heading DOUBLE NOT NULL DEFAULT 0,
    is_open TINYINT(1) NOT NULL DEFAULT 0,
    health INT NOT NULL DEFAULT 500,
    max_health INT NOT NULL DEFAULT 500,
    material VARCHAR(16) NOT NULL DEFAULT 'wood',
    created_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    KEY ix_wl_bb_props_cupboard (cupboard_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
    {
        version = 4,
        name = 'create_notices',
        up = [[
CREATE TABLE IF NOT EXISTS wl_bb_notices (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    character_id INT UNSIGNED NOT NULL,
    message VARCHAR(255) NOT NULL,
    created_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    KEY ix_wl_bb_notices_character (character_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
    {
        version = 5,
        name = 'props_owner',
        up = [[ALTER TABLE wl_bb_props ADD COLUMN owner_id INT UNSIGNED NULL AFTER cupboard_id]],
    },
    {
        version = 6,
        name = 'props_fuel',
        up = [[ALTER TABLE wl_bb_props ADD COLUMN fuel DOUBLE NOT NULL DEFAULT 0 AFTER is_open]],
    },
}

WLBB.SQL = {
    selectCupboards = 'SELECT id, owner_id, x, y, z, heading, radius, health, max_health, created_unix FROM wl_bb_cupboards',
    cupboardMove = 'UPDATE wl_bb_cupboards SET x = ?, y = ?, z = ?, heading = ? WHERE id = ?',
    selectAuth = 'SELECT cupboard_id, character_id, name FROM wl_bb_auth',
    selectProps = 'SELECT id, cupboard_id, owner_id, category, piece, model, x, y, z, heading, is_open, fuel, health, max_health, material, created_unix FROM wl_bb_props',
    insertCupboard = 'INSERT INTO wl_bb_cupboards (owner_id, x, y, z, heading, radius, health, max_health, created_unix) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    deleteCupboard = 'DELETE FROM wl_bb_cupboards WHERE id = ?',
    cupboardHealth = 'UPDATE wl_bb_cupboards SET health = ? WHERE id = ?',
    insertAuth = 'INSERT INTO wl_bb_auth (cupboard_id, character_id, name) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name)',
    deleteAuth = 'DELETE FROM wl_bb_auth WHERE cupboard_id = ? AND character_id = ?',
    deleteAuthAll = 'DELETE FROM wl_bb_auth WHERE cupboard_id = ?',
    insertProp = 'INSERT INTO wl_bb_props (cupboard_id, owner_id, category, piece, model, x, y, z, heading, is_open, health, max_health, material, created_unix) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)',
    deleteProp = 'DELETE FROM wl_bb_props WHERE id = ?',
    propOpen = 'UPDATE wl_bb_props SET is_open = ? WHERE id = ?',
    propPower = 'UPDATE wl_bb_props SET fuel = ?, is_open = ? WHERE id = ?',
    propHealth = 'UPDATE wl_bb_props SET health = ? WHERE id = ?',
    propUpgrade = 'UPDATE wl_bb_props SET piece = ?, model = ?, health = ?, max_health = ?, material = ? WHERE id = ?',
    propMove = 'UPDATE wl_bb_props SET x = ?, y = ?, z = ?, heading = ?, cupboard_id = ?, is_open = 0 WHERE id = ?',
    detachProps = 'UPDATE wl_bb_props SET cupboard_id = NULL WHERE cupboard_id = ?',
    attachProp = 'UPDATE wl_bb_props SET cupboard_id = ? WHERE id = ?',
    insertNotice = 'INSERT INTO wl_bb_notices (character_id, message, created_unix) VALUES (?, ?, ?)',
    selectNotices = 'SELECT id, message FROM wl_bb_notices WHERE character_id = ?',
    deleteNotices = 'DELETE FROM wl_bb_notices WHERE character_id = ?',
}
