# Pictures of how full each page is (v0.61), from a load test run with WOLF_SHOTS=<dir>: every text where it lands,
# on the window's dark background. Not the game's look - its density. python3 tools/test/shots.py <dir> <out dir>
import os, sys
from PIL import Image, ImageDraw, ImageFont
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
for name in sorted(os.listdir(src)):
    if not name.endswith(".txt"):
        continue
    lines = open(os.path.join(src, name), encoding="utf-8", errors="replace").read().splitlines()
    win = None
    texts = []
    for ln in lines:
        p = ln.split(" ", 6)
        if p[0] == "WIN":
            win = list(map(float, p[1:5]))
        elif p[0] == "T" and len(p) >= 7:
            texts.append((float(p[1]), float(p[2]), float(p[3]), float(p[4]), int(p[5]), p[6]))
    if not win:
        continue
    l, r, t, b = win
    W, H = int(r - l), int(t - b)
    img = Image.new("RGB", (W, H), (24, 20, 16))
    d = ImageDraw.Draw(img)
    for (x1, x2, y1, y2, size, text) in texts:
        X1, X2 = x1 - l, x2 - l
        Y1, Y2 = t - y1, t - y2
        if X2 < 0 or X1 > W or Y2 < 0 or Y1 > H:
            continue
        d.rectangle([X1, Y1, X2, Y2], outline=(70, 60, 44))
        f = ImageFont.truetype(FONT, max(7, int(size * 0.82)))
        d.text((X1, Y1), text, font=f, fill=(225, 214, 190))
    img.save(os.path.join(out, name.replace(".txt", ".png")))
print("pictures in", out)
