@echo off
rem Exports a standalone build to build\SlopGame.exe (single file, no engine needed).
cd /d "%~dp0\.."
if not exist build mkdir build
type nul > build\.gdignore
"engine\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" build\SlopGame.exe
copy /y THIRD_PARTY_LICENSES.txt build\ >nul
copy /y ASSETS.md build\ >nul
echo.
echo Done: build\SlopGame.exe
