@echo off
rem Launches Fragdeck. Uses the exported build if present, otherwise runs the
rem project straight from source with the bundled Godot engine.
cd /d "%~dp0"
if exist "build\Fragdeck.exe" (
    start "" "build\Fragdeck.exe"
) else if exist "engine\Godot_v4.7.2-stable_win64.exe" (
    start "" "engine\Godot_v4.7.2-stable_win64.exe" --path .
) else (
    echo No build and no engine found. Run tools\setup_engine.ps1 first.
    pause
)
