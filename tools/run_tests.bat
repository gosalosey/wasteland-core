@echo off
rem Run the Wasteland Core automated tests on Windows.
rem Requires a Lua 5.4 interpreter on PATH (lua54.exe or lua.exe), e.g. from
rem https://luabinaries.sourceforge.net/ or `scoop install lua`.
cd /d "%~dp0\.."
where lua54 >nul 2>nul && (lua54 tests\run.lua %* & exit /b %ERRORLEVEL%)
where lua >nul 2>nul && (lua tests\run.lua %* & exit /b %ERRORLEVEL%)
echo Lua 5.4 not found on PATH. See docs\TESTING.md.
exit /b 2
