"""泡泡龟部分动作(待机 / 走路 / 普攻 / 泡泡爆破 / 阵亡)。泡泡盾、泡泡束缚等 11-19 额度重置后补。"""
import math
import os
import sys

from PIL import Image

sys.path.insert(0, "C:/Users/Louis/AppData/Local/Temp/claude/5a6586b023f62759/a1c0e931-7a92-4ec5-b358-31af224163c8/scratchpad")
from act import L, despeck, onstage, puff, star, shard, ring, stage, PAD, TOP, GROUND, OX
import reel

sys.stdout.reconfigure(encoding="utf-8")
D = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/.out/review/bubble_sample/"
BL = [(70, 120, 200), (130, 200, 240), (210, 240, 255), (255, 255, 255)]


def f(seg, i, s=8):
    return despeck(L(D, seg, i), s)


def bubble(st, x, y, r):
    px = st.load()
    for yy in range(int(y - r), int(y + r) + 1):
        for xx in range(int(x - r), int(x + r) + 1):
            if 0 <= xx < st.width and 0 <= yy < st.height:
                d = math.hypot(xx - x, yy - y)
                if d <= r:
                    c = BL[0] if d > r - 1.2 else (BL[3] if math.hypot(xx - x + r * 0.35, yy - y + r * 0.35) < r * 0.28 else (BL[2] if d < r * 0.6 else BL[1]))
                    px[xx, yy] = c + (255,)


clips = []
idle = [onstage(f("idle", i)) for i in range(8)]
clips.append({"name": "待机", "note": "每帧 0.125 秒 · 约 1 秒一轮", "frames": idle, "fps": 8, "ox": OX, "ground": GROUND, "loop": True})
walk = [onstage(f("walk", i)) for i in range(8)]
clips.append({"name": "走路", "note": "每帧 0.083 秒 · 0.67 秒一轮", "frames": walk, "fps": 12, "ox": OX, "ground": GROUND, "loop": True})

## 普攻·泡泡攻击: 攻速 0.65, 前摇 0.40 秒, 命中下标 4, 每帧 0.10 秒; 连击 3 段 = 吹出 3 个泡泡
ao3 = f("a_out", 3)
px = ao3.load()
for y in range(128):
    for x in range(30):
        px[x, y] = (0, 0, 0, 0)
seq = [f("a_in", 2), f("a_in", 4), f("sw", 1), f("sw", 2), f("sw", 3), f("a_in", 8), f("a_in", 8), f("a_in", 8), f("a_out", 1), f("a_out", 2), ao3, f("a_out", 4)]
fr = []
for i, im in enumerate(seq):
    k = i - 5

    def front(st, k=k):
        ## 3 个小泡泡接连飞出
        for b in range(3):
            q = k - b
            if q >= 1:
                x = PAD + 4 - q * 15
                y = TOP + 76 - b * 5 - q * 2
                if x > 2:
                    bubble(st, x, y, 6 + b)
    fr.append(onstage(im, front=front))
clips.append({"name": "普攻 · 泡泡攻击", "note": "攻速 0.65 · 每帧 0.08 秒 · 起手 0.40 秒命中 · 连击 3 段 · 每 1.54 秒打一次", "frames": fr, "fps": 12.5, "ox": OX, "ground": GROUND, "rel": 5, "idle_gap": 0.58})

## 泡泡爆破: 释放帧 4
seq = [f("b_in", i) for i in (1, 2, 3, 4, 5, 6, 7, 8)] + [f("b_out", i) for i in (1, 2, 3, 4)]
FPS = 4 / 0.34
fr = []
for i, im in enumerate(seq):
    k = i - 4

    def back(st, k=k):
        if 0 <= k <= 4:
            ring(st, PAD + 76, GROUND - 2, 26 + k * 16, 7 + k * 4, BL[2 if k < 3 else 1], 3 - min(2, k // 2))

    def front(st, k=k):
        if k == 0:
            star(st, PAD + 62, TOP + 24, 16, BL, 1)
        if 0 <= k <= 4:
            for j in range(9):
                a = j * 0.7 + 0.3
                r = 16 + k * 13
                if k < 4 or j % 2:
                    bubble(st, PAD + 62 + r * math.cos(a), TOP + 24 + r * 0.8 * math.sin(a) + k * k, 4 - k * 0.5)
    fr.append(onstage(im, back=back, front=front))
clips.append({"name": "技能 · 泡泡爆破", "note": "每帧 0.085 秒 · 全程 %.2f 秒 · 起手 0.34 秒释放 · 游戏里目标两侧另有泡沫门和泡沫墙" % (len(seq) / FPS), "frames": fr, "fps": FPS, "ox": OX, "ground": GROUND, "rel": 4})

## 泡泡盾 / 泡泡束缚: 释放帧 4
ho2 = f("h_out", 2)
ho3 = f("h_out", 3)
for im in (ho2, ho3):
    q = im.load()
    for y in range(128):
        for x in range(30):
            q[x, y] = (0, 0, 0, 0)
for title, seqx in (("技能 · 泡泡盾", [f("h_in", i) for i in (1, 3, 5, 6, 7, 8)] + [f("h_out", 1), ho2, ho3, f("h_out", 4)]),
                    ("技能 · 泡泡束缚", [f("n_in", i) for i in (2, 4, 5, 6, 7, 8)] + [f("n_out", i) for i in (1, 2, 3, 4)])):
    rel = 4
    fpsx = rel / 0.34
    fr = []
    for i, im in enumerate(seqx):
        k = i - rel

        def back(st, k=k):
            if 0 <= k <= 3:
                ring(st, PAD + 76, GROUND - 2, 26 + k * 16, 7 + k * 4, BL[2 if k < 3 else 1], 2)
        fr.append(onstage(im, back=back))
    clips.append({"name": title, "note": "每帧 %.3f 秒 · 全程 %.2f 秒 · 起手 0.34 秒释放" % (1 / fpsx, len(seqx) / fpsx), "frames": fr, "fps": fpsx, "ox": OX, "ground": GROUND, "rel": 4})

## 阵亡
seq = [f("k_in", i) for i in (2, 3, 4, 6, 7, 8)]
fr = [onstage(x) for x in seq]
hold = fr[-1]
fr += [hold, hold]
for a in (0.85, 0.7, 0.55, 0.4, 0.25, 0.1):
    c = hold.copy()
    c.putalpha(c.getchannel("A").point(lambda v, a=a: int(v * a)))
    fr.append(c)
clips.append({"name": "阵亡", "note": "6 帧 · 每帧 0.067 秒 · 第 0.55 秒开始淡出，0.4 秒淡完", "frames": fr, "fps": 15, "ox": OX, "ground": GROUND})

os.makedirs(D + "final", exist_ok=True)
for c in clips:
    n = c["name"].replace(" · ", "_")
    os.makedirs(D + "final/" + n, exist_ok=True)
    for i, im in enumerate(c["frames"]):
        im.save(D + "final/%s/f_%02d.png" % (n, i))
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
reel.render(clips, "泡泡龟 · 全部动作（未接入游戏）", D + "泡泡龟_全动作.mp4", idle=idle, idle_ox=OX, idle_ground=GROUND)
