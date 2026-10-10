# Database: setup, backup and restore

Wasteland Core stores persistent data (accounts, characters and module data) in MariaDB or MySQL. It reaches the database through the **oxmysql** driver resource. Only `wasteland_database` talks to the driver.

## 1. Setup

### 1.1 Database server

MariaDB 10.6 or newer (or MySQL 8) on the same machine as FXServer or reachable from it. Create a database and a user that has rights **only on that database**. In the `mariadb` client, as root:

```sql
CREATE DATABASE wasteland CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'wasteland'@'127.0.0.1' IDENTIFIED BY 'choose-a-long-random-password';
GRANT ALL PRIVILEGES ON wasteland.* TO 'wasteland'@'127.0.0.1';
FLUSH PRIVILEGES;
```

Never let FXServer connect as `root`.

### 1.2 oxmysql

1. Download `oxmysql.zip` from https://github.com/overextended/oxmysql/releases (tested with **v2.14.3**, which needs server build 12913 or newer) and extract it so you have `resources/[standalone]/oxmysql/fxmanifest.lua`.
2. In `server.cfg`, set the connection string and start order:

```
set mysql_connection_string "mysql://wasteland:PASSWORD@127.0.0.1/wasteland?charset=utf8mb4"

ensure oxmysql
ensure wasteland_config
ensure wasteland_core
ensure wasteland_database
ensure wasteland_players
```

If the password contains `@`, `:`, `/` or `?`, URL-encode it (for example `@` becomes `%40`). The password is a secret. Do not paste `server.cfg` into chats or tickets, and do not commit it.

### 1.3 Tables

You do not create tables by hand. Each module creates and upgrades its own tables through **migrations** when it starts, and records them in `wl_migrations`. All framework tables start with `wl_`.

| Table | Owner | Contents |
|---|---|---|
| `wl_migrations` | database | applied migrations per module (version, name, checksum) |
| `wl_accounts` | players | one row per Rockstar license: name, identifiers (no IPs), first/last seen |
| `wl_characters` | players | characters: slot, name, position, play time; soft-deleted rows keep `deleted_at` |
| `wl_character_data` | players | per-character module data (JSON per key, with a revision counter) |

### 1.4 Checking it works

After a restart, run `wasteland status` in the console. `database` and `players` should be `running` with no `DEGRADED` note. If `database` is `failed`, its reason says what is wrong (driver missing, not started, or no connection). oxmysql prints the exact connection error just above it.

## 2. How data is kept safe

* **No in-memory fallback.** If the database is down, actions that need it (joining, creating and loading characters) are refused with a clear message, and `wasteland status` shows the module as `DEGRADED`.
* **Saves:** characters are saved every `players.saveIntervalSeconds` (60 s by default), when they unload, when a player leaves, when the server shuts down through txAdmin, and immediately when a module requests it after a valuable change.
* **Account lock:** a player cannot reconnect until the final save of their previous session has succeeded. If that save fails, it is retried until the database is back, so a reconnect can never load stale data.
* **What can be lost:** if the FXServer process is killed (crash, closed window, `taskkill`), no shutdown runs. Changes since the last periodic save are lost, which is at most `saveIntervalSeconds` of play.

## 3. Backups

Use `tools/backup_database.ps1`. It runs `mysqldump --single-transaction`, which gives a consistent snapshot without stopping the server, zips the dump, and deletes backups older than `-KeepDays`.

1. Create `tools/backup.cnf` (it is in `.gitignore`; keep it private):

   ```ini
   [client]
   host=127.0.0.1
   user=wasteland
   password="the-wasteland-user-password"
   ```

2. Run it once by hand to check it works:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\backup_database.ps1 -OutDir D:\wasteland-backups
   ```

3. Schedule it (for example every 6 hours) with Windows Task Scheduler: *Create Basic Task* → trigger *Daily*, repeat every 6 hours → action *Start a program*: `powershell.exe`, arguments `-ExecutionPolicy Bypass -File "F:\...\tools\backup_database.ps1" -OutDir "D:\wasteland-backups"`.

Keep at least one copy on a different disk or machine. A backup that sits on the same disk as the database does not survive a disk failure.

## 4. Restore

Restoring replaces **all** framework data with the backup. Everything since the backup is lost.

1. Stop the game server (txAdmin → *Stop*) so nothing writes while you restore.
2. Unzip the backup you want, for example `wasteland-2026-10-10_1800.sql`.
3. Restore into the database:

   ```powershell
   & "C:\Program Files\MariaDB 11.6\bin\mariadb.exe" --defaults-extra-file=tools\backup.cnf wasteland < wasteland-2026-10-10_1800.sql
   ```

   (In PowerShell, `<` does not work; run it from `cmd.exe`, or use `Get-Content file.sql -Raw | & mariadb.exe ...`.)
4. Start the server and check `wasteland status`.

**Test your backups.** Restoring into a scratch database once a month proves they work:

```sql
CREATE DATABASE wasteland_restore_test;  -- as root
```

```
mariadb --defaults-extra-file=tools\backup.cnf wasteland_restore_test < backup.sql
```

Then check the row counts (`SELECT COUNT(*) FROM wl_characters;`) and drop the scratch database.

## 5. Upgrades and downgrades

* Framework updates add migrations. They run automatically on the next start. Take a backup before updating.
* **Downgrades are refused:** if the database has migrations that the installed module does not know, the module fails with a message that says so. To go back to an older version, restore the backup you took before the update.
* An applied migration that was edited is refused, because its checksum no longer matches. This protects you from half-applied schema changes.
