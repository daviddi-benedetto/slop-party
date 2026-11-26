"""Make the Linux / Steam Deck release archive: the exported
build/SlopParty.x86_64 plus ASSETS.md and THIRD_PARTY_LICENSES.txt, in a
SlopParty/ folder. Done with tarfile so the game keeps its executable flag
even when packed on Windows (tools/build.bat).
Usage: python tools/pack_linux.py <output.tar.gz>"""
import sys, tarfile

out = sys.argv[1]


def mode(m):
    def f(info):
        info.mode = m
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        return info
    return f


with tarfile.open(out, "w:gz") as t:
    t.add("build/SlopParty.x86_64", "SlopParty/SlopParty.x86_64", filter=mode(0o755))
    for f in ("ASSETS.md", "THIRD_PARTY_LICENSES.txt"):
        t.add(f, "SlopParty/" + f, filter=mode(0o644))
print("Done:", out)
