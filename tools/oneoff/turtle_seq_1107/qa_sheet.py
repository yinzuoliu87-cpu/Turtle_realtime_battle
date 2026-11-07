"""每只龟一张检查表: 每段一行, 帧号写在格子里"""
import glob
import os
import sys

from PIL import Image, ImageDraw

sys.stdout.reconfigure(encoding="utf-8")
R = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/.out/review/"
SEG = ["a_in", "a_out", "s_in", "s_out", "f_in", "f_out", "d_in", "d_out", "k_in", "idle", "walk"]
for t in sys.argv[1:]:
    D = R + t + "_sample/"
    segs = [s for s in SEG + ["h_in", "h_out", "n_in", "n_out"] if os.path.isdir(D + s) and (t != "bubble" or s in ("h_in", "h_out", "n_in", "n_out"))]
    C = 104
    g = Image.new("RGB", (C * 9 + 40, C * len(segs)), (66, 84, 70))
    d = ImageDraw.Draw(g)
    for r, s in enumerate(segs):
        d.text((2, r * C + 4), s, fill=(255, 255, 0))
        for i, p in enumerate(sorted(glob.glob(D + s + "/f_*.png"))[:9]):
            im = Image.open(p).convert("RGBA").resize((C, C), Image.NEAREST)
            g.paste(im, (40 + i * C, r * C), im)
            d.text((42 + i * C, r * C + 2), str(i), fill=(200, 200, 200))
    g.save(R + "qa_%s.png" % t)
    print(t, g.size)
