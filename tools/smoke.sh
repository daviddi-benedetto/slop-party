#!/usr/bin/env bash
# Smoke test: runs a short bot match on every arena and in every mode, each
# in a different visual theme, plus the lobby, and fails if Godot printed any
# script error or a run fell below 50 FPS. Run it from the repo root (Git
# Bash on Windows, or any Linux shell) after pulling anyone's changes and before every release:
#
#   tools/smoke.sh            all 13 runs (about 4 minutes)
#   tools/smoke.sh quick      lobby + 3 matches (about 1 minute)
#
# Screenshots and logs go to $TMPDIR/slop_smoke (or /tmp/slop_smoke); each
# run's last log line is printed. Exit code 0 = all passed.

set -u
cd "$(dirname "$0")/.."
GODOT=./engine/Godot_v4.7.2-stable_win64.exe
# Linux / Steam Deck: the Linux editor (tools/setup_engine.sh).
[ "$(uname -s)" = "Linux" ] && GODOT=./engine/Godot_v4.7.2-stable_linux.x86_64
OUT="${TMPDIR:-/tmp}/slop_smoke"
mkdir -p "$OUT"

RUNS=(
	"lobby|--lobby-demo=3,2 --theme=cyberpunk"
	"neon-yard|--autotest --views=4 --map=0 --theme=classic"
	"ember-pit|--autotest --views=4 --map=1 --theme=toy"
	"frost-line|--autotest --views=4 --map=2 --theme=warm"
	"museum|--autotest --views=4 --map=3 --theme=cyberpunk"
	"stadium|--autotest --views=4 --map=4 --theme=synthwave"
	"suburb|--autotest --views=6 --map=5 --theme=spooky"
	"castle|--autotest --views=4 --map=8 --theme=moonlit"
	"zombies|--autotest --views=4 --mode=zombies --theme=random"
	"frontline|--autotest --views=4 --mode=frontline --theme=random"
	"gungame|--autotest --views=4 --mode=gungame --theme=random"
	"medieval|--autotest --views=4 --mode=medieval --theme=random"
	"results|--autotest --views=1 --target=1 --theme=toy"
)
if [ "${1:-}" = "quick" ]; then
	RUNS=("${RUNS[0]}" "${RUNS[1]}" "${RUNS[4]}" "${RUNS[9]}")
fi

fail=0
for r in "${RUNS[@]}"; do
	name="${r%%|*}"
	args="${r#*|}"
	t=12
	[ "$name" = "lobby" ] && t=7
	[ "$name" = "results" ] && t=30
	# Hightown (Frontline) takes longest to load.
	[ "$name" = "frontline" ] && t=18
	log="$OUT/$name.log"
	# shellcheck disable=SC2086
	"$GODOT" --path . -w --resolution 1280x720 -- $args --shot="$OUT/$name.png" --shot-time=$t >"$log" 2>&1
	errs=$(grep -ciE "script error|^error:|parse error" "$log")
	fps=$(grep -oE "fps=[0-9]+" "$log" | tail -1 | cut -d= -f2)
	status="ok"
	if [ "$errs" -gt 0 ]; then status="ERRORS ($errs)"; fail=1; fi
	if [ -z "$fps" ]; then status="NO SHOT"; fail=1
	elif [ "$fps" -lt 50 ]; then status="$status, LOW FPS"; fail=1; fi
	printf "%-12s fps=%-4s %s\n" "$name" "${fps:-?}" "$status"
	if [ "$errs" -gt 0 ]; then grep -iE "script error|^error:|parse error" -A2 "$log" | head -12; fi
done
echo "screenshots and logs: $OUT"
exit $fail
