-- wasteland_vehicles :: server/sql.lua
-- Persistent world vehicles. Trunks are inventory stashes "veh_<id>".

WLV = WLV or {}

WLV.MIGRATIONS = {
    {
        version = 1,
        name = 'create_vehicles',
        up = [[
CREATE TABLE IF NOT EXISTS wl_vehicles (
    id VARCHAR(16) NOT NULL,
    model VARCHAR(32) NOT NULL,
    x FLOAT NOT NULL,
    y FLOAT NOT NULL,
    z FLOAT NOT NULL,
    heading FLOAT NOT NULL DEFAULT 0,
    fuel FLOAT NOT NULL DEFAULT 0,
    engine FLOAT NOT NULL DEFAULT 1000,
    body FLOAT NOT NULL DEFAULT 1000,
    parts VARCHAR(255) NOT NULL DEFAULT '{}',
    lock_code VARCHAR(16) NULL,
    locked TINYINT(1) NOT NULL DEFAULT 0,
    updated_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
    {
        version = 2,
        name = 'lock_owner',
        -- The character that fitted the lock (only they can take it off).
        up = [[ALTER TABLE wl_vehicles ADD COLUMN lock_owner INT UNSIGNED NULL AFTER lock_code]],
    },
}

WLV.SQL = {
    selectAll = 'SELECT id, model, x, y, z, heading, fuel, engine, body, parts, lock_code, lock_owner, locked FROM wl_vehicles',
    insert = 'INSERT INTO wl_vehicles (id, model, x, y, z, heading, fuel, engine, body, parts, lock_code, lock_owner, locked, updated_unix) '
        .. 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    update = 'UPDATE wl_vehicles SET x = ?, y = ?, z = ?, heading = ?, fuel = ?, engine = ?, body = ?, parts = ?, '
        .. 'lock_code = ?, lock_owner = ?, locked = ?, updated_unix = ? WHERE id = ?',
    delete = 'DELETE FROM wl_vehicles WHERE id = ?',
}

return WLV.SQL
