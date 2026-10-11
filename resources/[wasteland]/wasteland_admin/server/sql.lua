-- wasteland_admin :: server/sql.lua
-- Bans and the admin action log.

WLA_ADMIN = WLA_ADMIN or {}

WLA_ADMIN.MIGRATIONS = {
    {
        version = 1,
        name = 'create_bans',
        up = [[
CREATE TABLE IF NOT EXISTS wl_bans (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    license VARCHAR(64) NOT NULL,
    name VARCHAR(64) NOT NULL DEFAULT '',
    reason VARCHAR(255) NOT NULL,
    banned_by VARCHAR(64) NOT NULL,
    created_unix INT UNSIGNED NOT NULL,
    expires_unix INT UNSIGNED NULL,
    revoked_unix INT UNSIGNED NULL,
    revoked_by VARCHAR(64) NULL,
    PRIMARY KEY (id),
    KEY ix_wl_bans_license (license)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
    {
        version = 2,
        name = 'create_admin_log',
        up = [[
CREATE TABLE IF NOT EXISTS wl_admin_log (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    admin VARCHAR(64) NOT NULL,
    action VARCHAR(32) NOT NULL,
    target VARCHAR(128) NULL,
    details VARCHAR(500) NULL,
    created_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}

WLA_ADMIN.SQL = {
    selectActiveBans = 'SELECT id, license, name, reason, banned_by, created_unix, expires_unix FROM wl_bans '
        .. 'WHERE revoked_unix IS NULL AND (expires_unix IS NULL OR expires_unix > ?)',
    selectRecentBans = 'SELECT id, license, name, reason, banned_by, created_unix, expires_unix, revoked_unix, revoked_by '
        .. 'FROM wl_bans ORDER BY id DESC LIMIT 100',
    insertBan = 'INSERT INTO wl_bans (license, name, reason, banned_by, created_unix, expires_unix) VALUES (?, ?, ?, ?, ?, ?)',
    revokeBan = 'UPDATE wl_bans SET revoked_unix = ?, revoked_by = ? WHERE id = ? AND revoked_unix IS NULL',
    insertLog = 'INSERT INTO wl_admin_log (admin, action, target, details, created_unix) VALUES (?, ?, ?, ?, ?)',
    selectLog = 'SELECT id, admin, action, target, details, created_unix FROM wl_admin_log ORDER BY id DESC LIMIT 100',
}

return WLA_ADMIN.SQL
