# Wasteland Core :: tools/backup_database.ps1
# Consistent online backup of the Wasteland database with mysqldump
# (--single-transaction: no need to stop the server), zipped, with rotation.
# See docs/DATABASE.md section 3.
#
#   powershell -ExecutionPolicy Bypass -File tools\backup_database.ps1 -OutDir D:\wasteland-backups

param(
    [string]$Database = 'wasteland',
    [string]$OutDir = (Join-Path $PSScriptRoot '..\backups'),
    [string]$OptionFile = (Join-Path $PSScriptRoot 'backup.cnf'),
    [string]$Dump = '',
    [int]$KeepDays = 14
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $OptionFile)) {
    throw "Option file not found: $OptionFile. Create it with [client] host, user and password (see docs/DATABASE.md)."
}
if ($Dump -eq '') {
    $candidates = @(Get-ChildItem 'C:\Program Files\MariaDB*\bin\mysqldump.exe', 'C:\Program Files\MySQL\*\bin\mysqldump.exe' -ErrorAction SilentlyContinue)
    if ($candidates.Count -eq 0) { throw 'mysqldump.exe not found; pass -Dump "C:\path\to\mysqldump.exe".' }
    $Dump = $candidates[0].FullName
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$sqlFile = Join-Path $OutDir "$Database-$stamp.sql"
$zipFile = "$sqlFile.zip"

$dumpArgs = @(
    "--defaults-extra-file=$OptionFile",
    '--single-transaction', '--quick', '--routines', '--triggers', '--events',
    '--hex-blob', '--default-character-set=utf8mb4',
    "--result-file=$sqlFile",
    $Database
)
& $Dump @dumpArgs
if ($LASTEXITCODE -ne 0) {
    if (Test-Path $sqlFile) { Remove-Item $sqlFile -Force }
    throw "mysqldump failed with exit code $LASTEXITCODE"
}
if ((Get-Item $sqlFile).Length -lt 100) { throw "Backup file is suspiciously small: $sqlFile" }

Compress-Archive -Path $sqlFile -DestinationPath $zipFile -Force
Remove-Item $sqlFile -Force
Write-Output "Backup written: $zipFile ($([math]::Round((Get-Item $zipFile).Length / 1KB)) KB)"

$cutoff = (Get-Date).AddDays(-$KeepDays)
Get-ChildItem $OutDir -Filter "$Database-*.sql.zip" | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
    Remove-Item $_.FullName -Force
    Write-Output "Removed old backup: $($_.Name)"
}
