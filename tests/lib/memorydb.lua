-- tests/lib/memorydb.lua
-- In-memory stand-in for MariaDB used by the simulated tests. It does not
-- parse SQL: it knows the exact statements the framework runs (loaded from
-- the resources' own sql.lua files) and implements each one. Any other
-- statement is an error and is recorded in `unhandled`, so a test fails if
-- code and statement list drift apart. The real SQL is exercised against
-- MariaDB by the db/ suite (see docs/TESTING.md).
--
-- Result shapes follow oxmysql: query -> rows | { affectedRows, insertId },
-- single -> first row, scalar -> first column, insert -> insertId,
-- update -> affectedRows.

local MemoryDB = {}
MemoryDB.__index = MemoryDB

local function normalise(sql)
    return (tostring(sql):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', ''))
end

local function deepCopy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = deepCopy(val) end
    return out
end

local function loadSqlFile(path, namespace)
    local f = assert(io.open(path, 'rb'))
    local src = f:read('a')
    f:close()
    local env = { [namespace] = {} }
    assert(load(src, '@' .. path, 't', env))()
    return env[namespace]
end

function MemoryDB.new(resourcesDir)
    local self = setmetatable({}, MemoryDB)
    self.data = {
        wl_migrations = {}, -- list of { module_name, version, name, checksum }
        wl_accounts = {},   -- [id] = row
        wl_characters = {}, -- [id] = row
        wl_character_data = {}, -- ["cid|key"] = row
        wl_items = {},      -- [uid] = row
        wl_drops = {},      -- [id] = row
        wl_bans = {},       -- [id] = row
        wl_admin_log = {},  -- list
        wl_vehicles = {},   -- [id] = row
        autoinc = { wl_accounts = 0, wl_characters = 0, wl_bans = 0 },
    }
    self.ddl = {}          -- DDL statements seen
    self.unhandled = {}    -- statements this backend does not know
    self.log = {}          -- { kind, sql, params }
    self.failPattern = nil -- statements containing this substring fail
    self.failMessage = 'simulated database error'
    self.clock = 1700000000
    self.handlers = {}
    local wld = loadSqlFile(resourcesDir .. '/wasteland_database/server/sql.lua', 'WLD')
    local wlp = loadSqlFile(resourcesDir .. '/wasteland_players/server/sql.lua', 'WLP')
    local wli = loadSqlFile(resourcesDir .. '/wasteland_inventory/server/sql.lua', 'WLI')
    local wla = loadSqlFile(resourcesDir .. '/wasteland_admin/server/sql.lua', 'WLA_ADMIN')
    local wlv = loadSqlFile(resourcesDir .. '/wasteland_vehicles/server/sql.lua', 'WLV')
    local wlg = loadSqlFile(resourcesDir .. '/wasteland_groups/server/sql.lua', 'WLG')
    local wlb = loadSqlFile(resourcesDir .. '/wasteland_bases/server/sql.lua', 'WLB')
    local wlbb = loadSqlFile(resourcesDir .. '/wasteland_basebuilding/server/sql.lua', 'WLBB')
    self:installDatabase(wld.SQL)
    self:installPlayers(wlp.SQL)
    self:installInventory(wli.SQL)
    self:installAdmin(wla.SQL)
    self:installVehicles(wlv.SQL)
    self:installGroups(wlg.SQL)
    self:installBases(wlb.SQL)
    self:installBasebuilding(wlbb.SQL)
    return self
end

function MemoryDB:now()
    self.clock = self.clock + 1
    return self.clock
end

local function header(affected, insertId)
    return { affectedRows = affected or 0, insertId = insertId or 0 }
end

function MemoryDB:on(sql, fn)
    self.handlers[normalise(sql)] = fn
end

-------------------------------------------------------------------------------
-- wasteland_database statements
-------------------------------------------------------------------------------

function MemoryDB:installDatabase(SQL)
    self:on(SQL.ping, function() return { { ['1'] = 1 } } end)
    self:on(SQL.selectMigrations, function(db, p)
        local rows = {}
        for _, r in ipairs(db.data.wl_migrations) do
            if r.module_name == p[1] then rows[#rows + 1] = { version = r.version, name = r.name, checksum = r.checksum } end
        end
        table.sort(rows, function(a, b) return a.version < b.version end)
        return rows
    end)
    self:on(SQL.insertMigration, function(db, p)
        for _, r in ipairs(db.data.wl_migrations) do
            if r.module_name == p[1] and r.version == p[2] then
                error(string.format("Duplicate entry '%s-%s' for key 'PRIMARY'", p[1], p[2]), 0)
            end
        end
        table.insert(db.data.wl_migrations, { module_name = p[1], version = p[2], name = p[3], checksum = p[4] })
        return header(1)
    end)
end

-------------------------------------------------------------------------------
-- wasteland_players statements
-------------------------------------------------------------------------------

function MemoryDB:installPlayers(SQL)
    local function accountByLicense(db, license)
        for _, a in pairs(db.data.wl_accounts) do if a.license == license then return a end end
    end

    self:on(SQL.upsertAccount, function(db, p)
        local a = accountByLicense(db, p[1])
        if a then
            a.name, a.identifiers, a.last_seen = p[2], p[3], db:now()
            return header(2, 0)
        end
        db.data.autoinc.wl_accounts = db.data.autoinc.wl_accounts + 1
        local id = db.data.autoinc.wl_accounts
        db.data.wl_accounts[id] = { id = id, license = p[1], name = p[2], identifiers = p[3], first_seen = db:now(), last_seen = db:now() }
        return header(1, id)
    end)
    self:on(SQL.accountIdByLicense, function(db, p)
        local a = accountByLicense(db, p[1])
        return a and { { id = a.id } } or {}
    end)
    self:on(SQL.listCharacters, function(db, p)
        local rows = {}
        for _, c in pairs(db.data.wl_characters) do
            if c.account_id == p[1] and c.deleted_at == nil then
                rows[#rows + 1] = { id = c.id, slot = c.slot, first_name = c.first_name, last_name = c.last_name,
                    play_seconds = c.play_seconds, created_at = c.created_at, last_played = c.last_played }
            end
        end
        table.sort(rows, function(a, b) return a.slot < b.slot end)
        return rows
    end)
    self:on(SQL.insertCharacter, function(db, p)
        if not db.data.wl_accounts[p[1]] then
            error('Cannot add or update a child row: a foreign key constraint fails (fk_wl_characters_account)', 0)
        end
        for _, c in pairs(db.data.wl_characters) do
            if c.account_id == p[1] and c.slot ~= nil and c.slot == p[2] then
                error(string.format("Duplicate entry '%s-%s' for key 'uq_wl_characters_slot'", p[1], p[2]), 0)
            end
        end
        db.data.autoinc.wl_characters = db.data.autoinc.wl_characters + 1
        local id = db.data.autoinc.wl_characters
        db.data.wl_characters[id] = {
            id = id, account_id = p[1], slot = p[2], first_name = p[3], last_name = p[4],
            pos_x = p[5], pos_y = p[6], pos_z = p[7], heading = p[8],
            play_seconds = 0, created_at = db:now(), last_played = nil, deleted_at = nil,
        }
        return header(1, id)
    end)
    self:on(SQL.loadCharacter, function(db, p)
        local c = db.data.wl_characters[p[1]]
        if not c or c.account_id ~= p[2] or c.deleted_at ~= nil then return {} end
        return { { id = c.id, account_id = c.account_id, slot = c.slot, first_name = c.first_name, last_name = c.last_name,
            pos_x = c.pos_x, pos_y = c.pos_y, pos_z = c.pos_z, heading = c.heading, play_seconds = c.play_seconds } }
    end)
    self:on(SQL.loadCharacterData, function(db, p)
        local rows = {}
        for _, d in pairs(db.data.wl_character_data) do
            if d.character_id == p[1] then rows[#rows + 1] = { data_key = d.data_key, data = d.data, revision = d.revision } end
        end
        table.sort(rows, function(a, b) return a.data_key < b.data_key end)
        return rows
    end)
    self:on(SQL.touchCharacter, function(db, p)
        local c = db.data.wl_characters[p[1]]
        if not c then return header(0) end
        c.last_played = db:now()
        return header(1)
    end)
    self:on(SQL.saveCharacter, function(db, p)
        local c = db.data.wl_characters[p[6]]
        if not c then return header(0) end
        c.pos_x, c.pos_y, c.pos_z, c.heading, c.play_seconds = p[1], p[2], p[3], p[4], p[5]
        c.last_played = db:now()
        return header(1)
    end)
    self:on(SQL.upsertCharacterData, function(db, p)
        if not db.data.wl_characters[p[1]] then
            error('Cannot add or update a child row: a foreign key constraint fails (fk_wl_character_data_character)', 0)
        end
        local key = p[1] .. '|' .. p[2]
        local d = db.data.wl_character_data[key]
        if d then
            d.data, d.revision = p[3], d.revision + 1
            return header(2)
        end
        db.data.wl_character_data[key] = { character_id = p[1], data_key = p[2], data = p[3], revision = 1 }
        return header(1)
    end)
    self:on(SQL.deleteCharacterData, function(db, p)
        local key = p[1] .. '|' .. p[2]
        if db.data.wl_character_data[key] then
            db.data.wl_character_data[key] = nil
            return header(1)
        end
        return header(0)
    end)
    self:on(SQL.softDeleteCharacter, function(db, p)
        local c = db.data.wl_characters[p[1]]
        if not c or c.account_id ~= p[2] or c.deleted_at ~= nil then return header(0) end
        c.deleted_at, c.slot = db:now(), nil
        return header(1)
    end)
end

-------------------------------------------------------------------------------
-- wasteland_inventory statements
-------------------------------------------------------------------------------

function MemoryDB:installInventory(SQL)
    self:on(SQL.selectItems, function(db, p)
        local rows = {}
        for _, r in pairs(db.data.wl_items) do
            if r.inventory_id == p[1] then rows[#rows + 1] = deepCopy(r) end
        end
        table.sort(rows, function(a, b) return a.uid < b.uid end)
        return rows
    end)
    self:on(SQL.upsertItem, function(db, p)
        local existed = db.data.wl_items[p[1]] ~= nil
        db.data.wl_items[p[1]] = { uid = p[1], inventory_id = p[2], name = p[3], count = p[4],
            pos_x = p[5], pos_y = p[6], rotated = p[7] == 1, slot = p[8], metadata = p[9] }
        return header(existed and 2 or 1)
    end)
    self:on(SQL.deleteItem, function(db, p)
        local existed = db.data.wl_items[p[1]] ~= nil
        db.data.wl_items[p[1]] = nil
        return header(existed and 1 or 0)
    end)
    self:on(SQL.deleteInventoryItems, function(db, p)
        local n = 0
        for uid, r in pairs(db.data.wl_items) do
            if r.inventory_id == p[1] then db.data.wl_items[uid] = nil; n = n + 1 end
        end
        return header(n)
    end)
    self:on(SQL.selectDrops, function(db)
        local rows = {}
        for _, r in pairs(db.data.wl_drops) do rows[#rows + 1] = deepCopy(r) end
        table.sort(rows, function(a, b) return a.id < b.id end)
        return rows
    end)
    self:on(SQL.insertDrop, function(db, p)
        if db.data.wl_drops[p[1]] then error("Duplicate entry '" .. p[1] .. "' for key 'PRIMARY'", 0) end
        db.data.wl_drops[p[1]] = { id = p[1], x = p[2], y = p[3], z = p[4], created_unix = p[5],
            owner_character = p[6], label = p[7], expires_unix = p[8] }
        return header(1)
    end)
    self:on(SQL.deleteDrop, function(db, p)
        local existed = db.data.wl_drops[p[1]] ~= nil
        db.data.wl_drops[p[1]] = nil
        return header(existed and 1 or 0)
    end)
end

-------------------------------------------------------------------------------
-- wasteland_admin statements
-------------------------------------------------------------------------------

function MemoryDB:installVehicles(SQL)
    local cols = { 'x', 'y', 'z', 'heading', 'fuel', 'engine', 'body', 'parts', 'lock_code', 'lock_owner', 'locked', 'spot_checked', 'updated_unix' }
    self:on(SQL.selectAll, function(db)
        local rows = {}
        for _, v in pairs(db.data.wl_vehicles) do rows[#rows + 1] = deepCopy(v) end
        table.sort(rows, function(a, b) return a.id < b.id end)
        return rows
    end)
    self:on(SQL.insert, function(db, p)
        if db.data.wl_vehicles[p[1]] then error("Duplicate entry '" .. p[1] .. "' for key 'PRIMARY'", 0) end
        db.data.wl_vehicles[p[1]] = { id = p[1], model = p[2], x = p[3], y = p[4], z = p[5], heading = p[6], fuel = p[7],
            engine = p[8], body = p[9], parts = p[10], lock_code = p[11], lock_owner = p[12], locked = p[13], spot_checked = p[14], updated_unix = p[15] }
        return header(1)
    end)
    self:on(SQL.update, function(db, p)
        local v = db.data.wl_vehicles[p[14]]
        if not v then return header(0) end
        for i, c in ipairs(cols) do v[c] = p[i] end
        return header(1)
    end)
    self:on(SQL.delete, function(db, p)
        if not db.data.wl_vehicles[p[1]] then return header(0) end
        db.data.wl_vehicles[p[1]] = nil
        return header(1)
    end)
end

function MemoryDB:installBasebuilding(SQL)
    local d = self.data
    d.wl_bb_cupboards, d.wl_bb_auth, d.wl_bb_props, d.wl_bb_notices = d.wl_bb_cupboards or {}, d.wl_bb_auth or {}, d.wl_bb_props or {}, d.wl_bb_notices or {}
    local nextC, nextP, nextN = 0, 0, 0
    local function rows(t) local out = {} for _, r in pairs(t) do out[#out + 1] = deepCopy(r) end return out end
    local function ins(id) local h = header(1); h.insertId = id; return h end
    self:on(SQL.selectCupboards, function(db) return rows(db.data.wl_bb_cupboards) end)
    self:on(SQL.selectAuth, function(db) return rows(db.data.wl_bb_auth) end)
    self:on(SQL.selectProps, function(db) return rows(db.data.wl_bb_props) end)
    self:on(SQL.insertCupboard, function(db, p)
        nextC = nextC + 1
        db.data.wl_bb_cupboards[nextC] = { id = nextC, owner_id = p[1], x = p[2], y = p[3], z = p[4], heading = p[5], radius = p[6],
            health = p[7], max_health = p[8], created_unix = p[9] }
        return ins(nextC)
    end)
    self:on(SQL.deleteCupboard, function(db, p) db.data.wl_bb_cupboards[p[1]] = nil; return header(1) end)
    self:on(SQL.cupboardHealth, function(db, p) local r = db.data.wl_bb_cupboards[p[2]]; if r then r.health = p[1] end; return header(1) end)
    self:on(SQL.insertAuth, function(db, p) db.data.wl_bb_auth[p[1] .. ':' .. p[2]] = { cupboard_id = p[1], character_id = p[2], name = p[3] }; return header(1) end)
    self:on(SQL.deleteAuth, function(db, p) db.data.wl_bb_auth[p[1] .. ':' .. p[2]] = nil; return header(1) end)
    self:on(SQL.deleteAuthAll, function(db, p)
        for k, r in pairs(db.data.wl_bb_auth) do if r.cupboard_id == p[1] then db.data.wl_bb_auth[k] = nil end end
        return header(1)
    end)
    self:on(SQL.insertProp, function(db, p)
        nextP = nextP + 1
        db.data.wl_bb_props[nextP] = { id = nextP, cupboard_id = p[1], category = p[2], piece = p[3], model = p[4], x = p[5], y = p[6], z = p[7],
            heading = p[8], is_open = 0, health = p[9], max_health = p[10], material = p[11], created_unix = p[12] }
        return ins(nextP)
    end)
    self:on(SQL.deleteProp, function(db, p) db.data.wl_bb_props[p[1]] = nil; return header(1) end)
    self:on(SQL.propOpen, function(db, p) local r = db.data.wl_bb_props[p[2]]; if r then r.is_open = p[1] end; return header(1) end)
    self:on(SQL.propHealth, function(db, p) local r = db.data.wl_bb_props[p[2]]; if r then r.health = p[1] end; return header(1) end)
    self:on(SQL.propUpgrade, function(db, p)
        local r = db.data.wl_bb_props[p[6]]
        if r then r.piece, r.model, r.health, r.max_health, r.material = p[1], p[2], p[3], p[4], p[5] end
        return header(1)
    end)
    self:on(SQL.detachProps, function(db, p)
        for _, r in pairs(db.data.wl_bb_props) do if r.cupboard_id == p[1] then r.cupboard_id = nil end end
        return header(1)
    end)
    self:on(SQL.attachProp, function(db, p) local r = db.data.wl_bb_props[p[2]]; if r then r.cupboard_id = p[1] end; return header(1) end)
    self:on(SQL.insertNotice, function(db, p)
        nextN = nextN + 1
        db.data.wl_bb_notices[nextN] = { id = nextN, character_id = p[1], message = p[2], created_unix = p[3] }
        return ins(nextN)
    end)
    self:on(SQL.selectNotices, function(db, p)
        local out = {}
        for _, r in pairs(db.data.wl_bb_notices) do if r.character_id == p[1] then out[#out + 1] = deepCopy(r) end end
        return out
    end)
    self:on(SQL.deleteNotices, function(db, p)
        for k, r in pairs(db.data.wl_bb_notices) do if r.character_id == p[1] then db.data.wl_bb_notices[k] = nil end end
        return header(1)
    end)
end

function MemoryDB:installBases(SQL)
    self.data.wl_bases, self.data.wl_base_pieces = self.data.wl_bases or {}, self.data.wl_base_pieces or {}
    local nextBase, nextPiece = 0, 0
    local function rows(t) local out = {} for _, r in pairs(t) do out[#out + 1] = deepCopy(r) end return out end
    self:on(SQL.selectBases, function(db) return rows(db.data.wl_bases) end)
    self:on(SQL.selectPieces, function(db) return rows(db.data.wl_base_pieces) end)
    self:on(SQL.insertBase, function(db, p)
        nextBase = nextBase + 1
        db.data.wl_bases[nextBase] = { id = nextBase, owner_id = p[1], x = p[2], y = p[3], z = p[4], heading = p[5], paid_until = p[6], created_unix = p[7] }
        local h = header(1)
        h.insertId = nextBase
        return h
    end)
    self:on(SQL.deleteBase, function(db, p) db.data.wl_bases[p[1]] = nil; return header(1) end)
    self:on(SQL.paidUntil, function(db, p) if db.data.wl_bases[p[2]] then db.data.wl_bases[p[2]].paid_until = p[1] end; return header(1) end)
    self:on(SQL.insertPiece, function(db, p)
        if p[7] ~= nil then
            for _, r in pairs(db.data.wl_base_pieces) do
                if r.base_id == p[1] and r.slot_key == p[7] then error("Duplicate entry for key 'uq_wl_base_pieces_slot'", 0) end
            end
        end
        nextPiece = nextPiece + 1
        db.data.wl_base_pieces[nextPiece] = { id = nextPiece, base_id = p[1], kind = p[2], x = p[3], y = p[4], z = p[5], heading = p[6],
            slot_key = p[7], builder_id = p[8], created_unix = p[9] }
        local h = header(1)
        h.insertId = nextPiece
        return h
    end)
    self:on(SQL.deletePiece, function(db, p) db.data.wl_base_pieces[p[1]] = nil; return header(1) end)
    self:on(SQL.deletePieces, function(db, p)
        for k, r in pairs(db.data.wl_base_pieces) do if r.base_id == p[1] then db.data.wl_base_pieces[k] = nil end end
        return header(1)
    end)
    self:on(SQL.upgradePiece, function(db, p)
        local r = db.data.wl_base_pieces[p[3]]
        if r then r.kind, r.heading = p[1], p[2] end
        return header(1)
    end)
end

function MemoryDB:installGroups(SQL)
    self.data.wl_groups, self.data.wl_group_members = self.data.wl_groups or {}, self.data.wl_group_members or {}
    local nextId = 0
    local function rows(t) local out = {} for _, r in pairs(t) do out[#out + 1] = deepCopy(r) end return out end
    self:on(SQL.selectGroups, function(db) return rows(db.data.wl_groups) end)
    self:on(SQL.selectMembers, function(db) return rows(db.data.wl_group_members) end)
    self:on(SQL.insertGroup, function(db, p)
        for _, g in pairs(db.data.wl_groups) do
            if g.name:lower() == p[1]:lower() then error("Duplicate entry '" .. p[1] .. "' for key 'uq_wl_groups_name'", 0) end
        end
        nextId = nextId + 1
        db.data.wl_groups[nextId] = { id = nextId, name = p[1], leader_id = p[2], created_unix = p[3] }
        local h = header(1)
        h.insertId = nextId
        return h
    end)
    self:on(SQL.deleteGroup, function(db, p) db.data.wl_groups[p[1]] = nil; return header(1) end)
    self:on(SQL.deleteMembers, function(db, p)
        for k, m in pairs(db.data.wl_group_members) do if m.group_id == p[1] then db.data.wl_group_members[k] = nil end end
        return header(1)
    end)
    self:on(SQL.insertMember, function(db, p)
        db.data.wl_group_members[p[1]] = { character_id = p[1], group_id = p[2], name = p[3], joined_unix = p[4] }
        return header(1)
    end)
    self:on(SQL.deleteMember, function(db, p) db.data.wl_group_members[p[1]] = nil; return header(1) end)
    self:on(SQL.setLeader, function(db, p) if db.data.wl_groups[p[2]] then db.data.wl_groups[p[2]].leader_id = p[1] end; return header(1) end)
    self:on(SQL.rename, function(db, p) if db.data.wl_groups[p[2]] then db.data.wl_groups[p[2]].name = p[1] end; return header(1) end)
    self:on(SQL.memberName, function(db, p)
        if db.data.wl_group_members[p[2]] then db.data.wl_group_members[p[2]].name = p[1] end
        return header(1)
    end)
end

function MemoryDB:installAdmin(SQL)
    self:on(SQL.selectActiveBans, function(db, p)
        local rows = {}
        for _, b in pairs(db.data.wl_bans) do
            if b.revoked_unix == nil and (b.expires_unix == nil or b.expires_unix > p[1]) then rows[#rows + 1] = deepCopy(b) end
        end
        return rows
    end)
    self:on(SQL.selectRecentBans, function(db)
        local rows = {}
        for _, b in pairs(db.data.wl_bans) do rows[#rows + 1] = deepCopy(b) end
        table.sort(rows, function(a, b) return a.id > b.id end)
        return rows
    end)
    self:on(SQL.insertBan, function(db, p)
        db.data.autoinc.wl_bans = db.data.autoinc.wl_bans + 1
        local id = db.data.autoinc.wl_bans
        db.data.wl_bans[id] = { id = id, license = p[1], name = p[2], reason = p[3], banned_by = p[4],
            created_unix = p[5], expires_unix = p[6] }
        return header(1, id)
    end)
    self:on(SQL.revokeBan, function(db, p)
        local b = db.data.wl_bans[p[3]]
        if not b or b.revoked_unix then return header(0) end
        b.revoked_unix, b.revoked_by = p[1], p[2]
        return header(1)
    end)
    self:on(SQL.insertLog, function(db, p)
        local id = #db.data.wl_admin_log + 1
        db.data.wl_admin_log[id] = { id = id, admin = p[1], action = p[2], target = p[3], details = p[4], created_unix = p[5] }
        return header(1, id)
    end)
    self:on(SQL.selectLog, function(db)
        local rows = {}
        for i = #db.data.wl_admin_log, 1, -1 do rows[#rows + 1] = deepCopy(db.data.wl_admin_log[i]) end
        return rows
    end)
end

-------------------------------------------------------------------------------
-- Execution
-------------------------------------------------------------------------------

-- Returns the raw result (rows or header) or raises.
function MemoryDB:run(sql, params)
    local key = normalise(sql)
    self.log[#self.log + 1] = { sql = key, params = deepCopy(params) }
    if self.failPattern and key:find(self.failPattern, 1, true) then
        error(self.failMessage, 0)
    end
    if key:find('SIMULATE_ERROR', 1, true) then
        error('You have an error in your SQL syntax near SIMULATE_ERROR', 0)
    end
    local fn = self.handlers[key]
    if fn then return fn(self, params or {}) end
    if key:match('^CREATE TABLE') or key:match('^ALTER TABLE') or key:match('^CREATE INDEX') then
        self.ddl[#self.ddl + 1] = key
        return header(0)
    end
    self.unhandled[#self.unhandled + 1] = key
    error('memorydb: unhandled SQL: ' .. key, 0)
end

--- Execute one statement the way oxmysql shapes results.
--- Returns result or nil, errorMessage.
function MemoryDB:execute(kind, sql, params)
    local ok, raw = pcall(self.run, self, sql, params)
    if not ok then return nil, tostring(raw) end
    if kind == 'insert' then return raw.insertId end
    if kind == 'update' then return raw.affectedRows end
    if kind == 'single' then return raw[1] end
    if kind == 'scalar' then
        local row = raw[1]
        if not row then return nil end
        local _, v = next(row)
        return v
    end
    return raw
end

--- Run statements { { sql, params }, ... } atomically. Returns ok, err.
function MemoryDB:transaction(statements)
    local snapshot = deepCopy(self.data)
    for _, st in ipairs(statements) do
        local ok, err = pcall(self.run, self, st[1], st[2])
        if not ok then
            self.data = snapshot
            return false, tostring(err)
        end
    end
    return true
end

--- Statements executed so far whose SQL contains `needle`.
function MemoryDB:calls(needle)
    local out = {}
    for _, l in ipairs(self.log) do
        if not needle or l.sql:find(needle, 1, true) then out[#out + 1] = l end
    end
    return out
end

return MemoryDB
