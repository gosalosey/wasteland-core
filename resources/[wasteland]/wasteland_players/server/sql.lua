-- wasteland_players :: server/sql.lua
-- Schema migrations and every SQL statement the players module runs
-- (MariaDB / MySQL). Timestamps are read with UNIX_TIMESTAMP() so callers
-- always get numbers, whatever the driver does with DATETIME values.

WLP = WLP or {}

WLP.MIGRATIONS = {
    {
        version = 1,
        name = 'create_accounts',
        up = [[
CREATE TABLE IF NOT EXISTS wl_accounts (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    license VARCHAR(64) NOT NULL,
    name VARCHAR(64) NOT NULL DEFAULT '',
    identifiers TEXT NULL,
    first_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_wl_accounts_license (license)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
    {
        version = 2,
        name = 'create_characters',
        up = [[
CREATE TABLE IF NOT EXISTS wl_characters (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    account_id INT UNSIGNED NOT NULL,
    slot TINYINT UNSIGNED NULL,
    first_name VARCHAR(32) NOT NULL,
    last_name VARCHAR(32) NOT NULL,
    pos_x DOUBLE NULL,
    pos_y DOUBLE NULL,
    pos_z DOUBLE NULL,
    heading DOUBLE NULL,
    play_seconds INT UNSIGNED NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_played DATETIME NULL,
    deleted_at DATETIME NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_wl_characters_slot (account_id, slot),
    CONSTRAINT fk_wl_characters_account FOREIGN KEY (account_id) REFERENCES wl_accounts (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
    {
        version = 3,
        name = 'create_character_data',
        up = [[
CREATE TABLE IF NOT EXISTS wl_character_data (
    character_id INT UNSIGNED NOT NULL,
    data_key VARCHAR(64) NOT NULL,
    data LONGTEXT NOT NULL,
    revision INT UNSIGNED NOT NULL DEFAULT 1,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (character_id, data_key),
    CONSTRAINT fk_wl_character_data_character FOREIGN KEY (character_id) REFERENCES wl_characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}

WLP.SQL = {
    upsertAccount = 'INSERT INTO wl_accounts (license, name, identifiers) VALUES (?, ?, ?) '
        .. 'ON DUPLICATE KEY UPDATE name = VALUES(name), identifiers = VALUES(identifiers), last_seen = CURRENT_TIMESTAMP',

    accountIdByLicense = 'SELECT id FROM wl_accounts WHERE license = ?',

    listCharacters = 'SELECT id, slot, first_name, last_name, play_seconds, '
        .. 'UNIX_TIMESTAMP(created_at) AS created_at, UNIX_TIMESTAMP(last_played) AS last_played '
        .. 'FROM wl_characters WHERE account_id = ? AND deleted_at IS NULL ORDER BY slot',

    insertCharacter = 'INSERT INTO wl_characters (account_id, slot, first_name, last_name, pos_x, pos_y, pos_z, heading) '
        .. 'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',

    loadCharacter = 'SELECT id, account_id, slot, first_name, last_name, pos_x, pos_y, pos_z, heading, play_seconds '
        .. 'FROM wl_characters WHERE id = ? AND account_id = ? AND deleted_at IS NULL',

    loadCharacterData = 'SELECT data_key, data, revision FROM wl_character_data WHERE character_id = ?',

    touchCharacter = 'UPDATE wl_characters SET last_played = CURRENT_TIMESTAMP WHERE id = ?',

    saveCharacter = 'UPDATE wl_characters SET pos_x = ?, pos_y = ?, pos_z = ?, heading = ?, play_seconds = ?, '
        .. 'last_played = CURRENT_TIMESTAMP WHERE id = ?',

    upsertCharacterData = 'INSERT INTO wl_character_data (character_id, data_key, data) VALUES (?, ?, ?) '
        .. 'ON DUPLICATE KEY UPDATE data = VALUES(data), revision = revision + 1',

    deleteCharacterData = 'DELETE FROM wl_character_data WHERE character_id = ? AND data_key = ?',

    softDeleteCharacter = 'UPDATE wl_characters SET deleted_at = CURRENT_TIMESTAMP, slot = NULL '
        .. 'WHERE id = ? AND account_id = ? AND deleted_at IS NULL',
}

return WLP.SQL
