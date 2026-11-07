"""钻石龟全套排帧 + 特效 + 成片"""
import math
import os
import sys

from PIL import Image

sys.path.insert(0, "C:/Users/Louis/AppData/Local/Temp/claude/5a6586b023f62759/a1c0e931-7a92-4ec5-b358-31af224163c8/scratchpad")
from act import L, despeck, onstage, puff, star, shard, ring, lines, stage, PAD, TOP, GROUND, OX
import reel

sys.stdout.reconfigure(encoding="utf-8")
R = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/.out/review/"
D = R + "diamond_sample/"
BL = [(30, 70, 170), (70, 140, 235), (170, 225, 255), (255, 255, 255)]
base = Image.open(D + "base128.png").convert("RGBA")


def f(seg, i):
    return despeck(L(D, seg, i))


clips = []
idle = [onstage(f("idle", i)) for i in range(8)]
clips.append({"name": "待机", "note": "每帧 0.125 秒 · 约 1 秒一轮", "frames": idle, "fps": 8, "ox": OX, "ground": GROUND, "loop": True})
walk = [onstage(f("walk", i)) for i in range(8)]
clips.append({"name": "走路", "note": "每帧 0.083 秒 · 0.67 秒一轮", "frames": walk, "fps": 12, "ox": OX, "ground": GROUND, "loop": True})

## 普攻·钻石切割: 攻速 0.6, 前摇封顶 0.40 秒, 命中下标 4, 每帧 0.10 秒
sw = [f("sw", i) for i in (1, 2, 3)]
hit = Image.open(D + "gen_hit.png").convert("RGBA")
seq = [f("a_in", 3), f("a_in", 4)] + sw + [hit, hit, hit] + [f("a_out", i) for i in (1, 3, 5, 6)]
H = 5
fps_a = H / 0.40
fx = 34 + 0
fy = 112


def hitfx(k):
    def fr(st):
        cx, cy = PAD + 22, TOP + 103
        if k == 0:
            star(st, cx, cy, 20, BL, 1)
        for j in range(7):
            a = -0.2 - j * 0.42
            r = 8 + k * 11
            if k <= 3:
                shard(st, cx + r * math.cos(a) * 1.2, cy + r * math.sin(a) + k * k * 1.6, 4 - min(2, k // 2), BL[1 + j % 2], BL[0])
    return fr


fr = []
for i, im in enumerate(seq):
    k = i - H
    dx = {1: -2, 2: -3}.get(k, 0)
    fr.append(onstage(im, dx=dx, front=hitfx(k) if 0 <= k <= 3 else None))
clips.append({"name": "普攻 · 钻石切割", "note": "攻速 0.6 · 每帧 0.08 秒 · 起手 0.40 秒命中 · 动作 %.2f 秒 · 每 1.67 秒打一次" % (len(seq) / fps_a), "frames": fr, "fps": fps_a, "ox": OX, "ground": GROUND, "rel": 5, "idle_gap": 1.667 - len(seq) / fps_a})

## 坚不可摧: 释放帧 4, 11.8 帧/秒
seq = [f("g_in", 1), f("g_in", 2), f("g_in", 3), f("g_in", 4), f("g_in", 5), f("g_in", 6), f("g_in", 7), f("g_in", 8), f("g_in", 7), f("g_in", 8), f("g_out", 1), f("g_out", 2), f("g_out", 3)]
FPS = 4 / 0.34


def shieldfx(k):
    def fr(st):
        cx, cy = PAD + 64, TOP + 84
        if k == 0:
            star(st, cx - 4, cy - 2, 18, BL, 2)
        for j in range(10):
            a = j * 0.628 + k * 0.28
            r = 44 + (2 if k % 2 else 0)
            x, y = cx + r * math.cos(a), cy + (r - 2) * math.sin(a)
            if k >= 0:
                shard(st, x, y, 5 if k < 5 else 3, BL[2 - j % 2], BL[0])
    return fr


fr = []
for i, im in enumerate(seq):
    k = i - 4
    fr.append(onstage(im, front=shieldfx(k) if 0 <= k <= 5 else None))
clips.append({"name": "技能 · 坚不可摧", "note": "每帧 0.085 秒 · 全程 %.2f 秒 · 起手 0.34 秒生效" % (len(seq) / FPS), "frames": fr, "fps": FPS, "ox": OX, "ground": GROUND, "rel": 4})

## 钻石滚球: 释放帧 4; 滚动 8 帧/圈(游戏 15 帧/秒)
ball = Image.open(D + "gen_ball.png").convert("RGBA")
bb = ball.getbbox()
cx0, cy0 = (bb[0] + bb[2]) // 2, (bb[1] + bb[3]) // 2
fr = [onstage(f("b_in", i)) for i in (4, 5, 6, 7, 8)]
for n in range(16):
    r = ball.rotate(45 * (n % 8) if False else (n % 8) * 45, resample=Image.NEAREST, center=(cx0, cy0))

    def back(st, n=n):
        for j in range(5):
            puff(st, PAD + cx0 + 26 + j * 13 + (n % 3), TOP + 119 - (j % 2) * 3, 5 - j * 0.7, BL[2], 1.0 - j * 0.17)
    fr.append(onstage(r, dx=(-1 if n % 2 else 1), back=back, front=lambda st, n=n: lines(st, PAD + cx0 + 30, TOP + 80, PAD + cx0 + 68, 4, BL[2], n)))
fr += [onstage(f("b_out", i)) for i in (1, 2, 3)]
clips.append({"name": "技能 · 钻石滚球", "note": "缩成球后按滚动时长持续滚动 · 这里演示 16 帧 · 收招舒展 3 帧", "frames": fr, "fps": 15, "ox": OX, "ground": GROUND})

## 钻石冲撞: 释放帧 4; 蓄力到撞击约 0.84 秒
seq = [(f("c_in", 2), 0), (f("c_in", 3), 0), (f("c_in", 4), 0), (f("c_in", 5), 0), (f("c_in", 6), 1), (f("c_in", 6), -1), (f("c_in", 7), 1), (f("c_in", 7), -1), (f("c_in", 8), -4), (f("c_in", 8), -10), (f("c_out", 1), -8), (f("c_out", 2), -5), (f("c_out", 3), -2)]
fr = []
for i, (im, dx) in enumerate(seq):
    k = i - 9

    def front(st, k=k, i=i):
        if 4 <= i <= 7:
            for j in range(6):
                a = j * 1.05 + i * 0.6
                r = 40 - (i - 4) * 7
                shard(st, PAD + 64 + r * math.cos(a), TOP + 84 + r * 0.9 * math.sin(a), 3, BL[2], BL[0])
        if i in (8, 9):
            lines(st, PAD + 96, TOP + 70, PAD + 150, 7, BL[2], i)
        if 0 <= k <= 2:
            star(st, PAD + 6 - k * 2, TOP + 92, 20 - k * 5, BL, k)
            for j in range(6):
                a = 2.2 + j * 0.42
                shard(st, PAD + 6 + (10 + k * 12) * math.cos(a), TOP + 92 + (10 + k * 12) * math.sin(a), 3, BL[1], BL[0])
    fr.append(onstage(im, dx=dx, front=front))
FPS = 4 / 0.34
clips.append({"name": "技能 · 钻石冲撞", "note": "每帧 0.085 秒 · 全程 %.2f 秒 · 蓄力 0.84 秒后撞击" % (len(seq) / FPS), "frames": fr, "fps": FPS, "ox": OX, "ground": GROUND, "rel": 4})

## 被动·钻石结构: 登场怒吼
HAS_R = os.path.exists(D + "r_out/f_01.png")
seq = [f("r_in", i) for i in (2, 3, 4, 5, 6, 7, 8)] + [f("r_in", 7)]
seq += [f("r_out", i) for i in (1, 2, 3)] if HAS_R else [f("r_in", 3), f("r_in", 2)]
fr = []
for i, im in enumerate(seq):
    k = i - 3

    def back(st, k=k):
        if 0 <= k <= 4:
            ring(st, PAD + 64, GROUND - 2, 24 + k * 18, 6 + k * 4, BL[2 if k < 3 else 1], 3 - min(2, k // 2))
    fr.append(onstage(im, back=back))
clips.append({"name": "被动 · 钻石结构（登场）", "note": "每帧 0.083 秒 · 全程 %.2f 秒 · 登场时全队加双抗" % (len(seq) / 12.0), "frames": fr, "fps": 12, "ox": OX, "ground": GROUND})

## 阵亡: 6 帧 15 帧/秒, 0.55 秒起淡出
seq = [f("d_in", i) for i in (3, 4, 5, 6, 7, 8)]
fr = []
for i, im in enumerate(seq):
    k = i - 4

    def front(st, k=k):
        if k >= 0:
            for j in range(9):
                x = PAD + 20 + j * 11
                shard(st, x, GROUND - 6 - (j % 3) * (5 - k * 2), 4 - k, BL[1 + j % 2], BL[0])
    fr.append(onstage(im, front=front))
hold = fr[-1]
fr += [hold, hold]
for a in (0.85, 0.7, 0.55, 0.4, 0.25, 0.1):
    c = hold.copy()
    c.putalpha(c.getchannel("A").point(lambda v, a=a: int(v * a)))
    fr.append(c)
clips.append({"name": "阵亡", "note": "6 帧 · 每帧 0.067 秒 · 第 0.55 秒开始淡出，0.4 秒淡完", "frames": fr, "fps": 15, "ox": OX, "ground": GROUND})

os.makedirs(D + "final", exist_ok=True)
for c in clips:
    n = c["name"].replace(" · ", "_").replace("（登场）", "")
    os.makedirs(D + "final/" + n, exist_ok=True)
    for i, im in enumerate(c["frames"]):
        im.save(D + "final/%s/f_%02d.png" % (n, i))
## 总览表: 每段抽 5 帧
rows = len(clips)
cw, ch = 118, 92
g = Image.new("RGB", (cw * 6, ch * rows), (66, 84, 70))
for r, c in enumerate(clips):
    fs = c["frames"]
    for k in range(6):
        im = fs[min(len(fs) - 1, k * len(fs) // 6)].resize((cw, ch), Image.NEAREST)
        g.paste(im, (k * cw, r * ch), im)
g.save(D + "overview.png")
print("总览", g.size)
reel.render(clips, "钻石龟 · 全部动作（未接入游戏）", D + "钻石龟_全动作.mp4", idle=idle, idle_ox=OX, idle_ground=GROUND)
