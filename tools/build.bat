@echo off
rem Exports a standalone build to build\SlopParty.exe (single file, no engine needed)
rem and, when the macOS export template is installed, build\SlopParty-macOS.zip (Slop Party.app).
cd /d "%~dp0\.."
if not exist build mkdir build
type nul > build\.gdignore
"engine\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" build\SlopParty.exe
if exist "engine\editor_data\export_templates\4.7.2.stable\macos.zip" (
	"engine\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "macOS" build\SlopParty-macOS.zip
)
copy /y THIRD_PARTY_LICENSES.txt build\ >nul
copy /y ASSETS.md build\ >nul
echo.
echo Done: build\SlopParty.exe
if exist build\SlopParty-macOS.zip echo       build\SlopParty-macOS.zip
