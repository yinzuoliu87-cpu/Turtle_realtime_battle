"""三只普攻新节奏对比: 骰子龟 / 宝箱龟 / 糖果龟。命中时刻不变, 只改帧分配"""
import glob
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, "C:/Users/Louis/AppData/Local/Temp/claude/5a6586b023f62759/a1c0e931-7a92-4ec5-b358-31af224163c8/scratchpad")
from act import L, despeck, onstage, star, PAD, TOP, GROUND

sys.stdout.reconfigure(encoding="utf-8")
R = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/.out/review/"
FF = "D:/oopz/ffmpeg.exe"
RED = [(120, 20, 34), (220, 56, 60), (255, 190, 170), (255, 255, 255)]
GOLD = [(150, 90, 20), (235, 170, 40), (255, 225, 120), (255, 255, 235)]


def seq(d):
    return [Image.open(p).convert("RGBA") for p in sorted(glob.glob(d + "/f_*.png"))]


def leftmost(im):
    px = im.load()
    for x in range(128):
        ys = [y for y in range(128) if px[x, y][3]]
        if len(ys) >= 2:
            return x, sum(ys) // len(ys)
    return 10, 90


def std(name, title, aspd, oldname, coil, cols, rev=False):
    D = R + name + "_sample/"
    f = lambda s, i: despeck(L(D, s, i), 14)
    hit = Image.open(D + "gen_hit.png").convert("RGBA")
    interval = 1 / aspd
    wind = min(0.4, max(0.12, interval * 0.3))
    pre = [f("a_in", coil[0]), f("a_in", coil[1]), f("sw", 1), f("sw", 2), f("sw", 3)]
    H = len(pre)
    x, y = leftmost(hit)
    new = [onstage(p) for p in pre]
    new.append(onstage(hit, front=lambda st: star(st, PAD + x, TOP + y, 16, cols, 1)))
    new.append(onstage(hit, dx=-2, front=lambda st: star(st, PAD + x - 2, TOP + y, 9, cols, 2)))
    new.append(onstage(hit, dx=-3))
    post = [f("a_in", i) for i in (7, 5, 3, 1)] if rev else [f("a_out", i) for i in (1, 2, 3, 4)]
    new += [onstage(p) for p in post]
    dt = wind / H
    old = seq(D + "final/" + oldname)
    odt = wind / 4
    idle = seq(D + "final/待机")
    os.makedirs(D + "swing_new", exist_ok=True)
    for i, im in enumerate(new):
        im.save(D + "swing_new/f_%02d.png" % i)
    print(title, "新版", len(new), "帧 每帧", round(dt, 3), "全程", round(dt * len(new), 2), "命中", round(wind, 3), "命中后停", round(dt * 3, 2))
    return dict(title=title, aspd=aspd, interval=interval, old=old, odt=odt, new=new, dt=dt, idle=idle, ox=PAD, ground=GROUND)


D = R + "candy_sample/"
bare = seq(D + "sweep4")
vfx = seq(D + "sweep4_vfx")
CP, CT = 80, 12


def cstage(im, dx):
    st = Image.new("RGBA", vfx[0].size, (0, 0, 0, 0))
    st.alpha_composite(im, (CP + dx, CT))
    return st


s1 = despeck(L(D, "sw", 1), 14)
s3 = despeck(L(D, "sw", 3), 14)
wind = 0.40
new = [vfx[1], vfx[3], cstage(s1, 6), cstage(s3, -9), vfx[4], vfx[5]]
hold = Image.new("RGBA", vfx[0].size, (0, 0, 0, 0))
hold.alpha_composite(vfx[5], (0, 0))
new.append(hold)
new += vfx[6:]
os.makedirs(D + "swing_new", exist_ok=True)
for i, im in enumerate(new):
    im.save(D + "swing_new/f_%02d.png" % i)
dt = wind / 4
print("糖果龟 新版", len(new), "帧 每帧", round(dt, 3), "全程", round(dt * len(new), 2), "命中", wind, "命中后停", round(dt * 3, 2))
candy = dict(title="糖果龟 · 横扫大锤", aspd=0.65, interval=1 / 0.65, old=vfx, odt=wind / 4, new=new, dt=dt, idle=[cstage(i, 0) for i in seq(D + "idle_final")], ox=CP, ground=135)
items = [std("dice3", "骰子龟 · 快刀", 0.85, "普攻_骰子攻击", (5, 7), RED, True),
         std("chest", "宝箱龟 · 重砸", 0.70, "普攻_宝箱砸击", (4, 6), GOLD), candy]

FONT = "C:/Windows/Fonts/msyh.ttc"
f_t, f_s = ImageFont.truetype(FONT, 36), ImageFont.truetype(FONT, 26)
W, H, Z, GY = 1280, 720, 3, 640
out = R + "普攻新节奏对比_三只.mp4"
p = subprocess.Popen([FF, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H), "-r", "30", "-i", "-",
                      "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p", out], stdin=subprocess.PIPE)
for it in items:
    bg = Image.new("RGB", (W, H), (66, 84, 70))
    d = ImageDraw.Draw(bg)
    d.text((30, 14), "%s · 攻速 %.2f" % (it["title"], it["aspd"]), font=f_t, fill=(255, 244, 214))
    d.text((230, 80), "现在", font=f_s, fill=(205, 222, 208))
    d.text((860, 80), "新版", font=f_s, fill=(255, 225, 120))
    d.line((0, GY, W, GY), fill=(46, 60, 50), width=4)
    for k in range(30 * 11):
        t = k / 30.0
        tt = t if t < 5 else 5 + (t - 5) * 0.33
        q = tt % it["interval"]
        im = bg.copy()
        idl = it["idle"][int(tt * 8) % len(it["idle"])]
        a = it["old"][int(q / it["odt"])] if q < it["odt"] * len(it["old"]) else idl
        b = it["new"][int(q / it["dt"])] if q < it["dt"] * len(it["new"]) else idl
        for fr, cx in ((a, 300), (b, 930)):
            z = fr.resize((fr.width * Z, fr.height * Z), Image.NEAREST)
            im.paste(z, (cx - (it["ox"] + 64) * Z, GY - it["ground"] * Z), z)
        ImageDraw.Draw(im).text((W - 30, 22), "原速" if t < 5 else "1/3 倍慢放", font=f_s, fill=(255, 225, 120), anchor="ra")
        p.stdin.write(im.tobytes())
p.stdin.close()
p.wait()
print("视频", round(os.path.getsize(out) / 1048576, 2), "MiB", p.returncode)
