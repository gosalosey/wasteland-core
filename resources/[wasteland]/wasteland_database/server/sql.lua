-- wasteland_database :: server/sql.lua
-- Every SQL statement the database module itself runs (MariaDB / MySQL).

WLD = WLD or {}

WLD.SQL = {
    ping = 'SELECT 1',

    createMigrationsTable = [[
CREATE TABLE IF NOT EXISTS wl_migrations (
    module_name VARCHAR(32) NOT NULL,
    version INT UNSIGNED NOT NULL,
    name VARCHAR(128) NOT NULL,
    checksum CHAR(8) NOT NULL,
    applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (module_name, version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    selectMigrations = 'SELECT version, name, checksum FROM wl_migrations WHERE module_name = ? ORDER BY version',

    insertMigration = 'INSERT INTO wl_migrations (module_name, version, name, checksum) VALUES (?, ?, ?, ?)',
}

return WLD.SQL
