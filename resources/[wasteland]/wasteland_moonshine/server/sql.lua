-- wasteland_moonshine :: server/sql.lua
-- Moonshine stills (the run in progress and jars waiting, as JSON).

WLM = WLM or {}

WLM.SQL = {
    select = 'SELECT id, owner_id, x, y, z, heading, brew FROM wl_moonshine_stills',
    insert = 'INSERT INTO wl_moonshine_stills (owner_id, x, y, z, heading, brew, created_unix) VALUES (?, ?, ?, ?, ?, ?, ?)',
    update = 'UPDATE wl_moonshine_stills SET brew = ? WHERE id = ?',
    delete = 'DELETE FROM wl_moonshine_stills WHERE id = ?',
}
WLM.MIGRATIONS = {
    {
        version = 1,
        name = 'create_stills',
        up = [[
CREATE TABLE IF NOT EXISTS wl_moonshine_stills (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    owner_id INT UNSIGNED NOT NULL,
    x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL,
    heading DOUBLE NOT NULL DEFAULT 0,
    brew TEXT NOT NULL,
    created_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    KEY ix_wl_moonshine_stills_owner (owner_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}

