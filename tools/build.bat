@echo off
rem Exports a standalone build to build\Fragdeck.exe (single file, no engine needed).
cd /d "%~dp0\.."
if not exist build mkdir build
type nul > build\.gdignore
"engine\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" build\Fragdeck.exe
echo.
echo Done: build\Fragdeck.exe
