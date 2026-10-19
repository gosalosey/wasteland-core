# Rebuilds resources/[wasteland]/wasteland_buildprops/stream from gen_buildprops.py.
# Needs: Python 3 with Pillow, the .NET 8 SDK, git. GTA V is NOT needed.
#   powershell -ExecutionPolicy Bypass -File tools\buildprops\build.ps1
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$work = Join-Path $env:TEMP 'wl_buildprops'
New-Item -ItemType Directory -Force $work | Out-Null
if (-not (Test-Path "$work\CodeWalker")) { git clone --depth 1 https://github.com/dexyfex/CodeWalker.git "$work\CodeWalker" }
Copy-Item -Recurse -Force "$here\converter" "$work\wlprops"
dotnet build "$work\wlprops\wlprops.csproj" -c Release | Out-Host
python "$here\gen_buildprops.py" "$work\xml"
dotnet "$work\wlprops\bin\Release\net8.0\wlprops.dll" build "$work\xml" "$work\out"
$stream = Join-Path $here '..\..\resources\[wasteland]\wasteland_buildprops\stream'
Copy-Item -Force "$work\out\*" -Destination $stream
Write-Host "Done: $stream"
