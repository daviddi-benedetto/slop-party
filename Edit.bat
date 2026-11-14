@echo off
rem Opens the project in the bundled Godot editor.
cd /d "%~dp0"
start "" "engine\Godot_v4.7.2-stable_win64.exe" --path . --editor
