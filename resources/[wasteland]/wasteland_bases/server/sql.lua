-- wasteland_bases :: server/sql.lua
-- A base belongs to a character (its owner's group shares it). Pieces are
-- stored with their world position; grid pieces also with their edge
-- (slot_key), one piece per edge.

WLB = WLB or {}

WLB.MIGRATIONS = {
    {
        version = 1,
        name = 'create_bases',
        up = [[
CREATE TABLE IF NOT EXISTS wl_bases (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    owner_id INT UNSIGNED NOT NULL,
    x DOUBLE NOT NULL,
    y DOUBLE NOT NULL,
    z DOUBLE NOT NULL,
    heading DOUBLE NOT NULL,
    paid_until INT UNSIGNED NOT NULL,
    created_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    KEY ix_wl_bases_owner (owner_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
    {
        version = 2,
        name = 'create_base_pieces',
        up = [[
CREATE TABLE IF NOT EXISTS wl_base_pieces (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    base_id INT UNSIGNED NOT NULL,
    kind VARCHAR(32) NOT NULL,
    x DOUBLE NOT NULL,
    y DOUBLE NOT NULL,
    z DOUBLE NOT NULL,
    heading DOUBLE NOT NULL,
    slot_key VARCHAR(32) NULL,
    builder_id INT UNSIGNED NOT NULL,
    created_unix INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    KEY ix_wl_base_pieces_base (base_id),
    UNIQUE KEY uq_wl_base_pieces_slot (base_id, slot_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}

WLB.SQL = {
    selectBases = 'SELECT id, owner_id, x, y, z, heading, paid_until FROM wl_bases',
    selectPieces = 'SELECT id, base_id, kind, x, y, z, heading, slot_key, builder_id FROM wl_base_pieces',
    insertBase = 'INSERT INTO wl_bases (owner_id, x, y, z, heading, paid_until, created_unix) VALUES (?, ?, ?, ?, ?, ?, ?)',
    deleteBase = 'DELETE FROM wl_bases WHERE id = ?',
    paidUntil = 'UPDATE wl_bases SET paid_until = ? WHERE id = ?',
    insertPiece = 'INSERT INTO wl_base_pieces (base_id, kind, x, y, z, heading, slot_key, builder_id, created_unix) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    deletePiece = 'DELETE FROM wl_base_pieces WHERE id = ?',
    deletePieces = 'DELETE FROM wl_base_pieces WHERE base_id = ?',
    upgradePiece = 'UPDATE wl_base_pieces SET kind = ?, heading = ? WHERE id = ?',
}
