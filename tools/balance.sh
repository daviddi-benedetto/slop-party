#!/usr/bin/env bash
# Balance check: runs bot-only Rounds matches with --balance (every bot
# respawns with the least-used weapon, so all 31 get similar play time; a
# high kill target so nobody wins), three at a time, then prints
# tools/balance.py's report.
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

MAPS=(0 1 2 3 4 5 8 0 2 4 5 8)
n=0
for m in "${MAPS[@]}"; do
	n=$((n + 1))
	"$GODOT" --path . -w --resolution 480x270 -- --autotest --views=0 --balance --target=999 --seed=$n --map=$m \
		--shot="$OUT/run$n.png" --shot-time="$LEN" >"$OUT/run$n.log" 2>&1 &
	if [ $((n % 3)) -eq 0 ]; then wait; fi
done
wait
grep -l "SCRIPT ERROR" "$OUT"/*.log && echo "(script errors in the logs above)"
python -I tools/balance.py "$OUT"/*.log
