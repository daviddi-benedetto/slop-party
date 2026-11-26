#!/usr/bin/env bash
# Linux version of tools/setup_engine.ps1: re-creates the engine/ folder
# (not stored in git: the files are over GitHub's 100 MB limit). Run once
# after cloning. Needs curl and unzip.
#
#   tools/setup_engine.sh              editor only (about 80 MB)
#   tools/setup_engine.sh --templates  also the export templates (1.2 GB download)

set -eu
cd "$(dirname "$0")/.."
VERSION=4.7.2-stable
BASE="https://github.com/godotengine/godot/releases/download/$VERSION"
mkdir -p engine

echo "Downloading Godot $VERSION editor for Linux..."
curl -fSL --progress-bar -o engine/godot.zip "$BASE/Godot_v${VERSION}_linux.x86_64.zip"
unzip -o -q engine/godot.zip -d engine
rm engine/godot.zip
chmod +x "engine/Godot_v${VERSION}_linux.x86_64"

# "_sc_" turns on Godot's self-contained mode: editor settings and export
# templates live in engine/editor_data instead of ~/.local/share, keeping the
# whole project folder portable. ".gdignore" stops Godot scanning this folder.
touch engine/_sc_ engine/.gdignore

if [ "${1:-}" = "--templates" ]; then
	DEST=engine/editor_data/export_templates/4.7.2.stable
	mkdir -p "$DEST"
	echo "Downloading export templates (1.2 GB)..."
	curl -fSL --progress-bar -o engine/templates.tpz "$BASE/Godot_v${VERSION}_export_templates.tpz"
	# Only what tools/build.sh needs: Linux, Windows and macOS.
	unzip -o -q -j engine/templates.tpz -d "$DEST" "templates/version.txt" \
		"templates/linux_*.x86_64" "templates/windows_*_x86_64*.exe" "templates/macos.zip"
	rm engine/templates.tpz
fi
echo "Engine ready. Run ./play.sh to play or ./edit.sh to open the editor."
