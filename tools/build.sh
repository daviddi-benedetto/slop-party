#!/usr/bin/env bash
# Linux version of tools/build.bat. Exports the standalone builds (single
# files, no engine needed) for every platform whose export template is
# installed (tools/setup_engine.sh --templates):
#
#   build/SlopParty.x86_64          Linux / Steam Deck
#   build/SlopParty-Linux.tar.gz    the same, packed with the licences for a release
#   build/SlopParty.exe             Windows
#   build/SlopParty-macOS.zip       macOS (Slop Party.app)

set -eu
cd "$(dirname "$0")/.."
GODOT=engine/Godot_v4.7.2-stable_linux.x86_64
TPL=engine/editor_data/export_templates/4.7.2.stable
mkdir -p build
touch build/.gdignore

"$GODOT" --headless --path . --export-release "Linux" build/SlopParty.x86_64
chmod +x build/SlopParty.x86_64
if [ -f "$TPL/windows_release_x86_64.exe" ]; then
	"$GODOT" --headless --path . --export-release "Windows Desktop" build/SlopParty.exe
fi
if [ -f "$TPL/macos.zip" ]; then
	"$GODOT" --headless --path . --export-release "macOS" build/SlopParty-macOS.zip
fi
cp THIRD_PARTY_LICENSES.txt ASSETS.md build/
python3 tools/pack_linux.py build/SlopParty-Linux.tar.gz

echo
echo "Done: build/SlopParty.x86_64"
echo "      build/SlopParty-Linux.tar.gz"
[ -f build/SlopParty.exe ] && echo "      build/SlopParty.exe"
[ -f build/SlopParty-macOS.zip ] && echo "      build/SlopParty-macOS.zip"
exit 0
