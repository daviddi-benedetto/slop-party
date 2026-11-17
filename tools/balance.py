"""Add up `[balance]` lines from bot-only runs (game.gd --balance) and list
weapons and cards whose kill rate is far from the average.

    python tools/balance.py run1.log run2.log ...

For each weapon and card: minutes held by a living player, kills, deaths,
kills per minute held (KPM) and K/D. Rows with too little play time are
marked, since a handful of kills says nothing.
"""
import json
import sys


def load(paths):
    total = {"time": 0.0, "weapons": {}, "cards": {}}
    for p in paths:
        with open(p, encoding="utf-8", errors="replace") as f:
            for line in f:
                if not line.startswith("[balance] "):
                    continue
                d = json.loads(line[len("[balance] "):])
                total["time"] += d["time"]
                for kind in ("weapons", "cards"):
                    for k, v in d[kind].items():
                        t = total[kind].setdefault(k, [0.0, 0, 0])
                        for i in range(3):
                            t[i] += v[i]
    return total


def report(title, rows, min_minutes):
    rated = []
    for name, (held, kills, deaths) in rows.items():
        mins = held / 60.0
        kpm = kills / mins if mins > 0 else 0.0
        kd = kills / max(deaths, 1)
        rated.append((name, mins, kills, deaths, kpm, kd))
    good = [r for r in rated if r[1] >= min_minutes]
    avg = sum(r[4] for r in good) / max(len(good), 1)
    print(f"\n{title}  (average KPM {avg:.2f} over {len(good)} with >= {min_minutes} min held)")
    print(f"{'name':24} {'min':>6} {'kills':>6} {'deaths':>6} {'KPM':>6} {'K/D':>5}  note")
    for name, mins, kills, deaths, kpm, kd in sorted(rated, key=lambda r: -r[4]):
        note = ""
        if mins < min_minutes:
            note = "too little data"
        elif kpm > avg * 1.6:
            note = "STRONG"
        elif kpm < avg * 0.5:
            note = "WEAK"
        print(f"{name[:24]:24} {mins:6.1f} {int(kills):6d} {int(deaths):6d} {kpm:6.2f} {kd:5.2f}  {note}")


if __name__ == "__main__":
    t = load(sys.argv[1:])
    print(f"total bot play time: {t['time'] / 60.0:.1f} min")
    report("WEAPONS", t["weapons"], 1.5)
    report("CARDS", t["cards"], 3.0)
