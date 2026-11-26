#!/usr/bin/env bash
# Opens the project in the bundled Godot editor (Linux).
cd "$(dirname "$(readlink -f "$0")")" || exit 1
exec "engine/Godot_v4.7.2-stable_linux.x86_64" --path . --editor "$@"
