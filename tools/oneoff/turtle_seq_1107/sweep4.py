"""普攻第四版: 严格走标注路线 mark_swing。
起点 = 龟的左手边身后低处 -> 命中 = 正前方 -> 终点 = 龟的右手边(身体背后) -> 回肩上。
命中之后的 4 帧手工合成: 无锤身体 + 锤子层垫在身体下面(绕到远离镜头一侧)。"""
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.stdout.reconfigure(encoding="utf-8")
D = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/.out/review/candy_sample/"
FF = "D:/oopz/ffmpeg.exe"
src = open("C:/Users/Louis/AppData/Local/Temp/claude/5a6586b023f62759/a1c0e931-7a92-4ec5-b358-31af224163c8/scratchpad/q_vfx.py", encoding="utf-8").read()
a, b = src.index("def hammer_center"), src.index("def telegraph")
exec(src[a:b])

PAD, TOP = 80, 12
STAGE = (128 + PAD + 50, 128 + TOP + 6)
CX, CY, RX, RY = 72, 94, 72, 20          # 标注椭圆(本体坐标)
A0, A1, A2 = 25, 180, 280


def ell(deg):
    r = math.radians(deg)
    return CX + RX * math.cos(r), CY + RY * math.sin(r)


## 取一个干净锤头 + 调色
W = np.array(Image.open(D + "pose_awind.png").convert("RGBA")).astype(int)
al = W[:, :, 3] > 0
rg = np.where(al[:, 96:].any(1))[0]
ht, hb = int(rg.min()), int(rg.max())
hr = int(np.where(al.any(0))[0].max())
DIA = hb - ht + 1
hl = hr - DIA + 1
hcx, hcy = (hl + hr) / 2, (ht + hb) / 2
DARK, RED, CREAM = (15, 13, 13), (183, 75, 77), (230, 218, 204)


def draw_hammer(st, hand, head):
    """舞台像素坐标: 手 -> 锤头"""
    sp = st.load()
    L = math.hypot(head[0] - hand[0], head[1] - hand[1])
    ux, uy = (head[0] - hand[0]) / L, (head[1] - hand[1]) / L
    x0, x1 = int(min(hand[0], head[0])) - 5, int(max(hand[0], head[0])) + 6
    y0, y1 = int(min(hand[1], head[1])) - 5, int(max(hand[1], head[1])) + 6
    for y in range(max(0, y0), min(st.height, y1)):
        for x in range(max(0, x0), min(st.width, x1)):
            rx, ry = x - hand[0], y - hand[1]
            t = rx * ux + ry * uy
            d = -rx * uy + ry * ux
            if -2 <= t <= L:
                if abs(d) <= 3.1:
                    sp[x, y] = DARK + (255,)
                if abs(d) <= 2.1:
                    c = RED if int((t + d * 1.2) // 4) % 2 == 0 else CREAM
                    if d > 1.1:
                        c = tuple(int(v * 0.82) for v in c)
                    sp[x, y] = c + (255,)
    ox, oy = int(head[0]) - int(hcx), int(head[1]) - int(hcy)
    for y in range(ht, hb + 1):
        for x in range(hl, hr + 1):
            if al[y, x] and math.hypot(x - hcx, y - hcy) <= DIA / 2 + 0.6:
                X, Y = x + ox, y + oy
                if 0 <= X < st.width and 0 <= Y < st.height:
                    sp[X, Y] = tuple(int(v) for v in W[y, x])


## 无锤身体 ①: 命中身体
b = Image.open(D + "pose_mid3b.png").convert("RGBA")
px = b.load()
mask = set()
for y in range(128):
    for x in range(128):
        if (x >= 99) or (x >= 96 and y <= 106) or (x >= 87 and 90 <= y <= 100):
            if px[x, y][3]:
                mask.add((x, y))
            px[x, y] = (0, 0, 0, 0)
for (x, y) in list(mask):
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        p = (x + dx, y + dy)
        if p not in mask and 0 <= p[0] < 128 and 0 <= p[1] < 128 and px[p][3]:
            px[p] = DARK + (255,)
BODY_HIT = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
BODY_HIT.paste(b.crop((0, 0, 104, 128)), (12, 0))

## 无锤身体 ②: 拉回身体(取 AI 帧 r_01, 擦锤)
BODY_R1 = Image.open(D + "a_back/r_01.png").convert("RGBA")
px = BODY_R1.load()
for y in range(128):
    for x in range(128):
        if x < 52 or (x < 56 and y >= 91):
            px[x, y] = (0, 0, 0, 0)

## 无锤身体 ③: 站立身体(擦肩上的锤, 龟壳顶用 r_01 的壳补)
BODY_BASE = Image.open(D + "base128_k4.png").convert("RGBA")
donor = Image.open(D + "a_back/r_01.png").convert("RGBA").load()
px = BODY_BASE.load()
for y in range(128):
    for x in range(128):
        inhead = math.hypot(x - 108, y - 58) <= 15.5
        inhandle = x >= 87 and y <= 70 and abs((y - 64) + (x - 86) * 0.5) <= 6
        if (inhead or inhandle) and px[x, y][3]:
            sx = x - 2
            px[x, y] = donor[sx, y] if (y >= 62 and 0 <= sx < 128 and donor[sx, y][3] and x >= 88) else (0, 0, 0, 0)

## 蓄力帧: 身体用 gen_wind, 锤子重摆到标注起点
WIND = Image.open(D + "gen_wind.png").convert("RGBA")
px = WIND.load()
for y in range(128):
    for x in range(128):
        r, g, bb, aa = px[x, y]
        if not aa:
            continue
        pink = r > 170 and g < 175 and bb > g and r - g > 50
        if (x >= 101 and y <= 107) or (x >= 90 and 84 <= y <= 95 and not pink):
            px[x, y] = (0, 0, 0, 0)

## (图, 身体偏移, 手(本体坐标), 锤头(本体坐标), 锤子在身体 下/上, 能量, 锤头显示点)
F = [
    (Image.open(D + "a_back/r_03.png").convert("RGBA"), 2, None, None, None, 0.1, (116, 66)),
    (Image.open(D + "a_back/r_02.png").convert("RGBA"), 5, None, None, None, 0.25, (114, 85)),
    (Image.open(D + "a_wind/r_07.png").convert("RGBA"), 9, None, None, None, 0.45, (123, 100)),
    (WIND, 14, (84 + 14, 85), (132, 100), "over", 0.7, (132, 100)),
    (Image.open(D + "gen_hit.png").convert("RGBA"), -15, None, None, None, 1.0, (0, 96)),
    (Image.open(D + "gen_hit2.png").convert("RGBA"), -18, None, None, None, 1.0, (-4, 90)),
    (BODY_HIT, -15, (37, 88), (13, 82), "under", 0.6, (13, 82)),
    (BODY_R1, -11, (44, 88), (36, 77), "under", 0.35, (36, 77)),
    (BODY_BASE, -5, (52, 79), (74, 75), "under", 0.0, (74, 75)),
    (BODY_BASE, -2, (55, 79), (92, 60), "under", 0.0, (92, 60)),
]
HIT = 4
## 拖尾: (尾巴角度, 头角度, 最大半厚, 碎)
TRAIL = {4: (A0, 180, 9, False), 5: (70, 190, 7, False), 6: (140, 215, 4, False), 7: (190, 240, 2, True)}


def trail(st, spec, shift_unused, front):
    a0, a1, T, broken = spec
    px = st.load()
    n = 900
    for k in range(n + 1):
        t = k / n
        ang = a0 + (a1 - a0) * t
        if (ang <= 180) != front:
            continue
        x, y = ell(ang)
        X = int(round(x + PAD))
        w = T * t ** 1.3
        lo, hi = -w * 0.3, w * 0.7
        sign = 1 if math.sin(math.radians(ang)) >= 0 else -1
        iy = lo
        while iy <= hi:
            Y = int(round(y + TOP + sign * iy))
            if 0 <= X < st.width and 0 <= Y < st.height and not (broken and (X + Y * 3) % 5 < 3):
                f = (iy - lo) / max(0.001, hi - lo)
                idx = 4 if f > 0.68 else (3 if f > 0.36 else 2)
                if broken:
                    idx = 2
                px[X, Y] = RAMP[idx] + (255,)
            iy += 0.5


frames, bare = [], []
for i, (im, shift, hand, head, layer, power, show) in enumerate(F):
    ox = PAD + shift
    plain = Image.new("RGBA", STAGE, (0, 0, 0, 0))
    if layer == "under":
        draw_hammer(plain, (hand[0] + PAD, hand[1] + TOP), (head[0] + PAD, head[1] + TOP))
    plain.alpha_composite(im, (ox, TOP))
    if layer == "over":
        draw_hammer(plain, (hand[0] + PAD, hand[1] + TOP), (head[0] + PAD, head[1] + TOP))
    bare.append(plain)
    st = Image.new("RGBA", STAGE, (0, 0, 0, 0))
    if i in TRAIL:
        trail(st, TRAIL[i], 0, False)
    cx, cy = show[0] + PAD, show[1] + TOP
    swirl(st, cx, cy, i, power, False)
    st.alpha_composite(plain, (0, 0))
    if layer != "under":
        swirl(st, cx, cy, i, power, True)
    if i in TRAIL:
        trail(st, TRAIL[i], 0, True)
    frames.append(st)
os.makedirs(D + "sweep4", exist_ok=True)
os.makedirs(D + "sweep4_vfx", exist_ok=True)
for i, (p1, p2) in enumerate(zip(bare, frames)):
    p1.save(D + "sweep4/f_%02d.png" % i)
    p2.save(D + "sweep4_vfx/f_%02d.png" % i)

## 核对: 实测锤头 vs 标注路线。被身体挡住的帧不测
print("帧 | 实测锤头 | 离路线")
ANGS = [a0 + 0.5 * k for a0 in [A0] for k in range(int((A2 - A0) * 2) + 1)]
curve = [ell(v) for v in ANGS]
check = []
for i in range(3, 9):
    c = hammer_center(bare[i])
    mx, my = c[0] - PAD, c[1] - TOP
    dist = min(math.hypot(mx - u, my - v) for u, v in curve)
    check.append((i + 1, (mx, my), round(dist, 1), c[2]))
    print(i + 1, (mx, my), round(dist, 1), "锤头像素", c[2])

## 逐帧表 + 轨迹核对图
S = 2
cols = 5
tw, th = STAGE[0] * S, STAGE[1] * S
rows = (len(frames) + cols - 1) // cols
g = Image.new("RGB", (cols * (tw + 4), rows * (th + 4)), (66, 84, 70))
dr = ImageDraw.Draw(g)
for i, st in enumerate(frames):
    x, y = (i % cols) * (tw + 4), (i // cols) * (th + 4)
    a2 = st.resize((tw, th), Image.NEAREST)
    g.paste(a2, (x, y), a2)
    dr.rectangle((x, y, x + 34, y + 13), fill=(200, 40, 40) if i == HIT else (0, 0, 0))
    dr.text((x + 3, y + 1), "%d" % (i + 1), fill=(255, 255, 0))
g.save(D + "sweep4_sheet.png")
