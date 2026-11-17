#!/usr/bin/env bash
# Balance check: runs bot-only matches with --balance (Gun Game on every
# arena, so every weapon gets used; Rounds with a high kill target, so cards
# pile up), three at a time, then prints tools/balance.py's report.
#
#   tools/balance.sh [seconds per match, default 150]
#
# Logs go to $TMPDIR/slop_balance. Takes about 4 x the match length.

set -u
cd "$(dirname "$0")/.."
GODOT=./engine/Godot_v4.7.2-stable_win64_console.exe
OUT="${TMPDIR:-/tmp}/slop_balance"
LEN="${1:-150}"
mkdir -p "$OUT"
rm -f "$OUT"/*.log

RUNS=(
	"--mode=gungame --map=0" "--mode=gungame --map=1" "--mode=gungame --map=2"
	"--mode=gungame --map=3" "--mode=gungame --map=4" "--mode=gungame --map=5"
	"--map=0 --target=999" "--map=2 --target=999" "--map=4 --target=999"
	"--map=5 --target=999" "--map=8 --target=999" "--map=1 --target=999"
)
n=0
for r in "${RUNS[@]}"; do
	n=$((n + 1))
	# shellcheck disable=SC2086
	"$GODOT" --path . -w --resolution 480x270 -- --autotest --views=0 --balance --seed=$n $r \
		--shot="$OUT/run$n.png" --shot-time="$LEN" >"$OUT/run$n.log" 2>&1 &
	if [ $((n % 3)) -eq 0 ]; then wait; fi
done
wait
grep -l "SCRIPT ERROR" "$OUT"/*.log && echo "(script errors in the logs above)"
python -I tools/balance.py "$OUT"/*.log
