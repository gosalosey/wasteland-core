-- wasteland_supplydrops :: server/sql.lua
-- The module's table and statements. A module never calls a database
-- driver itself: it uses WDB (@wasteland_database/lib/db.lua).

WLSD = WLSD or {}

-------------------------------------------------------------------------------
-- Database: one table, created by migration 1. Never edit an applied
-- migration; add migration 2, 3 ... instead (docs/MODULE_API.md).
-------------------------------------------------------------------------------

WLSD.MIGRATIONS = {
    {
        version = 1,
        name = 'create_supply_drops',
        up = [[
CREATE TABLE IF NOT EXISTS wl_supply_drops (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    label VARCHAR(64) NOT NULL,
    x FLOAT NOT NULL,
    y FLOAT NOT NULL,
    z FLOAT NOT NULL,
    created_unix INT UNSIGNED NOT NULL,
    opened_by INT UNSIGNED NULL,
    opened_unix INT UNSIGNED NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}

WLSD.SQL = {
    insert = 'INSERT INTO wl_supply_drops (label, x, y, z, created_unix) VALUES (?, ?, ?, ?, ?)',
    opened = 'UPDATE wl_supply_drops SET opened_by = ?, opened_unix = ? WHERE id = ? AND opened_by IS NULL',
}

return WLSD.SQL
