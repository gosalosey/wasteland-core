#!/usr/bin/env sh
# Run the Wasteland Core automated tests (Linux / macOS / WSL).
# Requires Lua 5.4 (Debian/Ubuntu: sudo apt install lua5.4).
cd "$(dirname "$0")/.." || exit 1
LUA=$(command -v lua5.4 || command -v lua54 || command -v lua)
if [ -z "$LUA" ]; then echo "Lua 5.4 not found. Install it (e.g. sudo apt install lua5.4)."; exit 2; fi
"$LUA" -v
exec "$LUA" tests/run.lua "$@"
