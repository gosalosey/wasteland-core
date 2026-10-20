-- wasteland_farming :: server/sql.lua
-- Farm plots and what grows in them (slots as JSON).

WLF = WLF or {}

WLF.MIGRATIONS = {
    {
        version = 1,
        name = 'create_plots',
        up = [[
CREATE TABLE IF NOT EXISTS wl_farm_plots (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    owner_id INT UNSIGNED NOT NULL,
    size VARCHAR(16) NOT NULL,
    x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL,
    heading DOUBLE NOT NULL DEFAULT 0,
    water DOUBLE NOT NULL DEFAULT 0,
    slots TEXT NOT NULL,
    created_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    KEY ix_wl_farm_plots_owner (owner_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}

WLF.SQL = {
    select = 'SELECT id, owner_id, size, x, y, z, heading, water, slots FROM wl_farm_plots',
    insert = 'INSERT INTO wl_farm_plots (owner_id, size, x, y, z, heading, water, slots, created_unix) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)',
    update = 'UPDATE wl_farm_plots SET water = ?, slots = ? WHERE id = ?',
    delete = 'DELETE FROM wl_farm_plots WHERE id = ?',
}
