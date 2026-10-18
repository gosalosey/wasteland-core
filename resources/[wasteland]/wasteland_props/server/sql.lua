-- wasteland_props :: server/sql.lua
-- Props placed by admins anywhere in the world (kept for good).

WLPR = WLPR or {}

WLPR.MIGRATIONS = {
    {
        version = 1,
        name = 'create_props',
        up = [[
CREATE TABLE IF NOT EXISTS wl_props (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    model VARCHAR(64) NOT NULL,
    x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL,
    rx DOUBLE NOT NULL DEFAULT 0, ry DOUBLE NOT NULL DEFAULT 0, rz DOUBLE NOT NULL DEFAULT 0,
    collision TINYINT(1) NOT NULL DEFAULT 1,
    placed_by VARCHAR(64) NULL,
    created_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}

WLPR.SQL = {
    select = 'SELECT id, model, x, y, z, rx, ry, rz, collision FROM wl_props',
    insert = 'INSERT INTO wl_props (model, x, y, z, rx, ry, rz, collision, placed_by, created_unix) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    update = 'UPDATE wl_props SET x = ?, y = ?, z = ?, rx = ?, ry = ?, rz = ?, collision = ? WHERE id = ?',
    delete = 'DELETE FROM wl_props WHERE id = ?',
}
