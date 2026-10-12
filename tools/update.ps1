# Wasteland Core :: tools/update.ps1
# Updates a Wasteland Core server to the newest version on GitHub.
#
#   1. Stop the server (txAdmin: Stop).
#   2. Double-click update_wasteland.bat in the server folder
#      (or: powershell -ExecutionPolicy Bypass -File update_wasteland.ps1).
#   3. Start the server.
#
# What it does:
#   * shows what is new since the version you have,
#   * backs up the database (if mysqldump / mariadb-dump is found) and the
#     whole resources\[wasteland] folder (server folder\backups\),
#   * replaces resources\[wasteland] with the new version, but KEEPS:
#       - your settings (wasteland_config\config\*.lua); when the new version
#         changed one of them, its new file is saved next to yours as
#         <name>.lua.new so you can compare;
#       - your zombie models (wasteland_zombiemodels\stream and peds.meta),
#   * adds settings files that are new in this version,
#   * checks server.cfg has an "ensure" line for every Wasteland resource
#     (and offers to add missing ones),
#   * updates itself.
#
# Options: -ServerPath <folder with server.cfg>   (default: this script's folder)
#          -Ref <branch or tag>                    (default: main)
#          -Yes                                    (answer yes to every question)
#          -SkipDatabaseBackup

param(
    [string]$ServerPath = '',
    [string]$Ref = 'main',
    [string]$Repo = 'gosalosey/wasteland-core',
    [switch]$Yes,
    [switch]$SkipDatabaseBackup
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Ask($question) {
    if ($Yes) { return $true }
    $a = Read-Host "$question [y/n]"
    return $a -match '^(y|yes)$'
}

# --- the server folder ------------------------------------------------------
if ($ServerPath -eq '') { $ServerPath = $PSScriptRoot }
$ServerPath = (Resolve-Path $ServerPath).Path
$cfgPath = Join-Path $ServerPath 'server.cfg'
$wlPath = Join-Path $ServerPath 'resources\[wasteland]'
if (-not (Test-Path -LiteralPath $cfgPath)) { throw "No server.cfg in $ServerPath. Put this script in the server folder, or pass -ServerPath." }
if (-not (Test-Path -LiteralPath $wlPath)) { throw "No resources\[wasteland] in $ServerPath." }

Say ''
Say '=== Wasteland Core update ===' Green
Say "Server folder: $ServerPath"

$versionFile = Join-Path $wlPath 'VERSION.txt'
$installed = ''
if (Test-Path -LiteralPath $versionFile) { $installed = (Get-Content -LiteralPath $versionFile -TotalCount 1).Trim() }

# --- what is new ------------------------------------------------------------
$headers = @{ 'User-Agent' = 'wasteland-update' }
$commits = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/commits?sha=$Ref&per_page=40" -Headers $headers
$latest = $commits[0].sha
if ($installed -eq $latest) {
    Say "You already have the newest version ($($latest.Substring(0,7)))." Green
    if (-not (Ask 'Reinstall it anyway?')) { exit 0 }
} else {
    Say ''
    Say 'New in this update:' Cyan
    $shown = 0
    foreach ($c in $commits) {
        if ($c.sha -eq $installed) { break }
        $line = ($c.commit.message -split "`n")[0]
        Say ("  * " + $line)
        $shown++
    }
    if ($installed -eq '') { Say "  (your version is unknown: showing the latest $shown changes)" DarkGray }
}

Say ''
Say 'Stop the server before updating (txAdmin: Stop).' Yellow
if (-not (Ask 'Is the server stopped, and do you want to update now?')) { Say 'Nothing changed.'; exit 0 }

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$backupDir = Join-Path $ServerPath "backups\update_$stamp"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

# --- database backup ----------------------------------------------------------
if (-not $SkipDatabaseBackup) {
    $conn = Select-String -LiteralPath $cfgPath -Pattern 'set\s+mysql_connection_string\s+"([^"]+)"' | Select-Object -First 1
    $dump = @(Get-Command mariadb-dump.exe, mysqldump.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    $dump += @(Get-ChildItem 'C:\Program Files\MariaDB*\bin\mariadb-dump.exe', 'C:\Program Files\MariaDB*\bin\mysqldump.exe',
        'C:\Program Files\MySQL\*\bin\mysqldump.exe', 'C:\xampp\mysql\bin\mysqldump.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    if ($conn -and $dump.Count -gt 0 -and $conn.Matches[0].Groups[1].Value -match '^mysql://([^:@/]+)(?::([^@]*))?@([^:/]+)(?::(\d+))?/([^?]+)') {
        $user = [uri]::UnescapeDataString($Matches[1]); $pass = [uri]::UnescapeDataString("$($Matches[2])")
        $dbHost = $Matches[3]; $port = if ($Matches[4]) { $Matches[4] } else { '3306' }; $db = $Matches[5]
        $opt = Join-Path $env:TEMP "wl_update_$stamp.cnf"
        "[client]`nhost=$dbHost`nport=$port`nuser=$user`npassword=`"$pass`"`n" | Set-Content -LiteralPath $opt -Encoding ASCII
        $sql = Join-Path $backupDir "$db.sql"
        try {
            & $dump[0] "--defaults-extra-file=$opt" --single-transaction --quick --routines --triggers --hex-blob --default-character-set=utf8mb4 "--result-file=$sql" $db
            if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
            Compress-Archive -LiteralPath $sql -DestinationPath "$sql.zip" -Force
            Remove-Item -LiteralPath $sql -Force
            Say "Database backed up: $sql.zip" Green
        } catch {
            Say "Database backup failed ($_)." Red
            if (-not (Ask 'Continue without a database backup?')) { Remove-Item -LiteralPath $opt -Force; exit 1 }
        } finally {
            if (Test-Path -LiteralPath $opt) { Remove-Item -LiteralPath $opt -Force }
        }
    } else {
        Say 'Could not back up the database automatically (mysqldump not found, or no mysql:// connection string in server.cfg).' Yellow
        if (-not (Ask 'Continue without a database backup? (back it up yourself first if unsure)')) { exit 1 }
    }
}

# --- download -----------------------------------------------------------------
$tmp = Join-Path $env:TEMP "wl_update_$stamp"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zip = Join-Path $tmp 'wasteland.zip'
Say 'Downloading the new version...'
Invoke-WebRequest -Uri "https://codeload.github.com/$Repo/zip/$Ref" -OutFile $zip -UseBasicParsing -Headers $headers
Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
$root = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
$newWl = Join-Path $root.FullName 'resources\[wasteland]'
if (-not (Test-Path -LiteralPath $newWl)) { throw 'The download does not contain resources\[wasteland].' }

# --- back up the current version -------------------------------------------
Say 'Backing up your current resources\[wasteland]...'
Copy-Item -LiteralPath $wlPath -Destination (Join-Path $backupDir '[wasteland]') -Recurse -Force

# --- keep the server's own files --------------------------------------------
$oldCfg = Join-Path $wlPath 'wasteland_config\config'
$newCfg = Join-Path $newWl 'wasteland_config\config'
$changedSettings = @(); $newSettings = @()
Get-ChildItem -LiteralPath $newCfg -Filter '*.lua' | ForEach-Object {
    $mine = Join-Path $oldCfg $_.Name
    if (Test-Path -LiteralPath $mine) {
        $a = (Get-FileHash -LiteralPath $mine).Hash; $b = (Get-FileHash -LiteralPath $_.FullName).Hash
        if ($a -ne $b) {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $newCfg ($_.Name + '.new')) -Force
            Copy-Item -LiteralPath $mine -Destination $_.FullName -Force
            $changedSettings += $_.Name
        }
    } else {
        $newSettings += $_.Name
    }
}
# Settings files only you have (none in the new version): keep them too.
Get-ChildItem -LiteralPath $oldCfg -Filter '*.lua' | ForEach-Object {
    if (-not (Test-Path -LiteralPath (Join-Path $newCfg $_.Name))) { Copy-Item -LiteralPath $_.FullName -Destination $newCfg -Force }
}
# Your zombie models.
$oldModels = Join-Path $wlPath 'wasteland_zombiemodels'
$newModels = Join-Path $newWl 'wasteland_zombiemodels'
if (Test-Path -LiteralPath (Join-Path $oldModels 'stream')) {
    # -LiteralPath everywhere: the [wasteland] in the path would be read as a wildcard.
    $dest = Join-Path $newModels 'stream'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $oldModels 'stream') | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
    }
}
if (Test-Path -LiteralPath (Join-Path $oldModels 'peds.meta')) {
    Copy-Item -LiteralPath (Join-Path $oldModels 'peds.meta') -Destination (Join-Path $newModels 'peds.meta') -Force
}

# --- swap -----------------------------------------------------------------------
Remove-Item -LiteralPath $wlPath -Recurse -Force
Move-Item -LiteralPath $newWl -Destination $wlPath
Set-Content -LiteralPath (Join-Path $wlPath 'VERSION.txt') -Value $latest -Encoding ASCII
Say 'resources\[wasteland] updated.' Green

# --- server.cfg -------------------------------------------------------------------
$template = Get-Content -LiteralPath (Join-Path $root.FullName 'txadmin\server.cfg')
$cfg = Get-Content -LiteralPath $cfgPath
$wanted = $template | Where-Object { $_ -match '^ensure\s+(wasteland_\w+)' } | ForEach-Object { ($_ -split '\s+')[1] }
$missing = @($wanted | Where-Object { $name = $_; -not ($cfg | Where-Object { $_ -match ('^\s*ensure\s+' + [regex]::Escape($name) + '\s*(#.*)?$') }) })
if ($missing.Count -gt 0) {
    Say ''
    Say ('server.cfg has no "ensure" line for: ' + ($missing -join ', ')) Yellow
    if (Ask 'Add them after the other Wasteland resources?') {
        $last = -1
        for ($i = 0; $i -lt $cfg.Count; $i++) { if ($cfg[$i] -match '^\s*ensure\s+wasteland_') { $last = $i } }
        $add = $missing | ForEach-Object { "ensure $_" }
        if ($last -ge 0 -and $last -lt $cfg.Count - 1) { $cfg = @($cfg[0..$last]) + $add + @($cfg[($last + 1)..($cfg.Count - 1)]) }
        else { $cfg = @($cfg) + $add }   # (a reversed range would repeat the last line)
        Copy-Item -LiteralPath $cfgPath -Destination (Join-Path $backupDir 'server.cfg') -Force
        Set-Content -LiteralPath $cfgPath -Value $cfg -Encoding UTF8
        Say 'server.cfg updated (old copy in the backup folder).' Green
    }
}

# --- update this script -----------------------------------------------------------
$newScript = Join-Path $root.FullName 'tools\update.ps1'
if ((Test-Path -LiteralPath $newScript) -and $PSCommandPath) { Copy-Item -LiteralPath $newScript -Destination $PSCommandPath -Force }
Remove-Item -LiteralPath $tmp -Recurse -Force

# --- summary --------------------------------------------------------------------------
Say ''
Say "=== Done: version $($latest.Substring(0,7)) ===" Green
if ($newSettings.Count -gt 0) { Say ('New settings files (defaults): ' + ($newSettings -join ', ')) Cyan }
if ($changedSettings.Count -gt 0) {
    Say ('Your settings were kept. These differ from the new version: ' + ($changedSettings -join ', ')) Cyan
    Say '  The new version of each is saved next to yours as <name>.lua.new (wasteland_config\config): compare them for new options.' DarkGray
}
Say "Backup of the old version: $backupDir" DarkGray
Say 'Start the server now. Its console should show every Wasteland module as "running".' Yellow
