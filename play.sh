#!/usr/bin/env bash
# Launches Slop Party on Linux (Steam Deck included). Uses the exported build
# if present, otherwise runs the project straight from source with the
# bundled Godot engine (tools/setup_engine.sh downloads it).
cd "$(dirname "$(readlink -f "$0")")" || exit 1
if [ -x "build/SlopParty.x86_64" ]; then
	exec "build/SlopParty.x86_64" "$@"
elif [ -x "engine/Godot_v4.7.2-stable_linux.x86_64" ]; then
	exec "engine/Godot_v4.7.2-stable_linux.x86_64" --path . "$@"
else
	echo "No build and no engine found. Run tools/setup_engine.sh first." >&2
	exit 1
fi
