-- wasteland_inventory :: server/sql.lua
-- Migrations and every SQL statement of the inventory module.
-- One row per stack. inventory_id is the Inventory ID contract
-- ('player:42', 'equip:42', 'item:<uid>', 'stash:<name>', 'drop:<id>').
-- Grid stacks have pos_x/pos_y; worn items have slot instead.

WLI = WLI or {}

WLI.MIGRATIONS = {
    {
        version = 1,
        name = 'create_items',
        up = [[
CREATE TABLE IF NOT EXISTS wl_items (
    uid CHAR(16) NOT NULL,
    inventory_id VARCHAR(64) NOT NULL,
    name VARCHAR(48) NOT NULL,
    count INT UNSIGNED NOT NULL,
    pos_x SMALLINT NULL,
    pos_y SMALLINT NULL,
    rotated TINYINT(1) NOT NULL DEFAULT 0,
    slot VARCHAR(16) NULL,
    metadata TEXT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (uid),
    KEY ix_wl_items_inventory (inventory_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
    {
        version = 2,
        name = 'create_drops',
        up = [[
CREATE TABLE IF NOT EXISTS wl_drops (
    id CHAR(16) NOT NULL,
    x DOUBLE NOT NULL,
    y DOUBLE NOT NULL,
    z DOUBLE NOT NULL,
    created_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
    {
        -- Body bags: who died there (map marker), a label, and their own lifetime.
        version = 3,
        name = 'drops_owner_label_expiry',
        up = [[
ALTER TABLE wl_drops
    ADD COLUMN owner_character INT UNSIGNED NULL,
    ADD COLUMN label VARCHAR(64) NULL,
    ADD COLUMN expires_unix INT UNSIGNED NULL]],
    },
}

WLI.SQL = {
    selectItems = 'SELECT uid, name, count, pos_x, pos_y, rotated, slot, metadata FROM wl_items WHERE inventory_id = ?',

    upsertItem = 'INSERT INTO wl_items (uid, inventory_id, name, count, pos_x, pos_y, rotated, slot, metadata) '
        .. 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE inventory_id = VALUES(inventory_id), '
        .. 'name = VALUES(name), count = VALUES(count), pos_x = VALUES(pos_x), pos_y = VALUES(pos_y), '
        .. 'rotated = VALUES(rotated), slot = VALUES(slot), metadata = VALUES(metadata)',

    deleteItem = 'DELETE FROM wl_items WHERE uid = ?',

    deleteInventoryItems = 'DELETE FROM wl_items WHERE inventory_id = ?',

    selectDrops = 'SELECT id, x, y, z, created_unix, owner_character, label, expires_unix FROM wl_drops',

    insertDrop = 'INSERT INTO wl_drops (id, x, y, z, created_unix, owner_character, label, expires_unix) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',

    deleteDrop = 'DELETE FROM wl_drops WHERE id = ?',
}

return WLI.SQL
