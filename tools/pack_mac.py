"""Make the Mac release zip: Godot's exported .app zip plus ASSETS.md and
THIRD_PARTY_LICENSES.txt. Done in Python (not Compress-Archive) so the app's
Unix permissions (the executable flag) and its ad-hoc signature survive.
Usage: python tools/pack_mac.py <output.zip>"""
import shutil, sys, zipfile

out = sys.argv[1]
shutil.copyfile("build/SlopParty-macOS.zip", out)
with zipfile.ZipFile(out, "a", zipfile.ZIP_DEFLATED) as z:
    for f in ("ASSETS.md", "THIRD_PARTY_LICENSES.txt"):
        z.write(f, f)
print("Done:", out)
