"""下载一批姿势: poses.py 龟 名=job [名=job ...]; 对齐地面线存 gen_名.png, 拼总表 look_poses.png"""
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.stdout.reconfigure(encoding="utf-8")
R = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/.out/review/"
t = sys.argv[1]
D = R + t + "_sample/"
AIR = {"dash"}   # 空中姿势不贴地
names = []
for a in sys.argv[2:]:
    n, job = a.split("=")
    p = D + "pose_%s.png" % n
    r = subprocess.run(["curl", "-sS", "--noproxy", "*", "-m", "40", "-o", p, "-w", "%{http_code}", "https://api.pixellab.ai/mcp/images/%s/download" % job], capture_output=True, text=True)
    if r.stdout.strip() != "200":
        print("失败", n, r.stdout)
        continue
    im = Image.open(p).convert("RGBA")
    a2 = np.array(im)[:, :, 3] > 0
    ys, xs = np.where(a2)
    dy = 0 if n in AIR else 123 - int(ys.max())
    c = Image.new("RGBA", im.size, (0, 0, 0, 0))
    c.paste(im, (0, dy))
    c.save(D + "gen_%s.png" % n)
    names.append(n)
    print(n, "bbox", int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()), "下移", dy)
S = 3
cols = 3
rows = (len(names) + cols - 1) // cols
g = Image.new("RGB", (128 * S * cols, 128 * S * rows), (66, 84, 70))
d = ImageDraw.Draw(g)
for k, n in enumerate(names):
    z = Image.open(D + "gen_%s.png" % n).convert("RGBA").resize((128 * S, 128 * S), Image.NEAREST)
    x, y = (k % cols) * 128 * S, (k // cols) * 128 * S
    g.paste(z, (x, y), z)
    d.text((x + 4, y + 4), n, fill=(255, 255, 0))
g.save(D + "look_poses.png")
