"""通用排帧 + 简易特效 + 成片: auto_build.py 龟名
节奏按游戏: 普攻 帧率 = 命中帧 / 前摇; 技能 帧率 = 释放帧 / 0.34; 阵亡 15 帧/秒 + 0.55 秒起淡出。
段名约定: idle walk k_in; 每个动作 <x>_in(8 帧) <x>_out(4 帧) + gen_<姿势>.png"""
import math
import os
import sys

from PIL import Image

sys.path.insert(0, "C:/Users/Louis/AppData/Local/Temp/claude/5a6586b023f62759/a1c0e931-7a92-4ec5-b358-31af224163c8/scratchpad")
from act import L, despeck, onstage, star, shard, ring, PAD, TOP, GROUND, OX
import reel

sys.stdout.reconfigure(encoding="utf-8")
R = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/.out/review/"
INK = [(40, 40, 46), (120, 120, 130), (220, 220, 226), (255, 255, 255)]
CYAN = [(20, 80, 120), (40, 170, 220), (160, 240, 255), (255, 255, 255)]
VIO = [(70, 30, 120), (140, 70, 210), (210, 170, 255), (255, 255, 255)]
GOLD = [(150, 90, 20), (235, 170, 40), (255, 225, 120), (255, 255, 235)]
STAR = [(40, 40, 140), (120, 110, 230), (255, 220, 120), (255, 255, 255)]
LEAF = [(70, 90, 40), (130, 150, 70), (210, 220, 150), (255, 255, 235)]
SOUL = [(50, 20, 80), (120, 50, 170), (200, 130, 240), (255, 240, 255)]
RED = [(120, 20, 34), (220, 56, 60), (255, 190, 170), (255, 255, 255)]
AQUA = [(70, 120, 200), (130, 200, 240), (210, 240, 255), (255, 255, 255)]
CFG = {
    "dice3": dict(title="骰子龟", aspd=0.85, fx=RED, atk=("普攻 · 骰子攻击", "a", "hit"),
                  skills=[("技能 · 孤注一掷", "s", "slash", "游戏里另有红色镰刀贴地弧光"), ("技能 · 命运骰子", "f", "fate", ""), ("技能 · 稳定骰子", "d", "dash", "游戏里掷出 7~11 段连续突刺")]),
    "line": dict(title="线条龟", aspd=0.70, fx=INK, atk=("普攻 · 素描", "a", "hit"),
                 skills=[("技能 · 连笔", "s", "link", ""), ("技能 · 画龙点睛", "f", "dot", ""), ("技能 · 墨水炸弹", "d", "bomb", "")]),
    "cyber": dict(title="赛博龟", aspd=0.75, fx=CYAN, atk=("普攻 · 激光枪", "a", "hit"),
                  skills=[("技能 · 能量大炮", "s", "beam", ""), ("技能 · 侵入", "f", "hack", ""), ("技能 · 智能AI", "d", "ai", "")]),
    "crystal": dict(title="水晶龟", aspd=0.60, fx=VIO, atk=("普攻 · 水晶刺", "a", "hit"),
                    skills=[("技能 · 水晶壁垒", "s", "wall", ""), ("技能 · 碎晶爆破", "f", "burst", ""), ("技能 · 水晶球", "d", "ball", "")]),
    "chest": dict(title="宝箱龟", aspd=0.70, fx=GOLD, atk=("普攻 · 宝箱砸击", "a", "hit"),
                  skills=[("技能 · 清点财宝", "s", "count", ""), ("技能 · 财宝风暴", "f", "storm", ""), ("技能 · 财宝炮击", "d", "cannon", "")]),
    "space": dict(title="星际龟", aspd=0.70, fx=STAR, atk=("普攻 · 星光弹", "a", "hit"),
                  skills=[("技能 · 虫洞", "s", "worm", ""), ("技能 · 星波", "f", "wave", ""), ("技能 · 扭曲空间", "d", "warp", "")]),
    "hiding": dict(title="缩头乌龟", aspd=0.60, fx=LEAF, atk=("普攻 · 攻击", "a", "hit"),
                   skills=[("技能 · 缩头", "s", "shrink", ""), ("技能 · 防御", "f", "defend", ""), ("技能 · 强化随从", "d", "buff", "")]),
    "headless": dict(title="无头龟", aspd=0.80, fx=SOUL, atk=("普攻 · 撕咬", "a", "hit"),
                     skills=[("技能 · 恐吓", "s", "fear", ""), ("技能 · 万千触须", "f", "tendril", ""), ("技能 · 灵魂打击", "d", "soul", "")]),
}
name = sys.argv[1]
C = CFG[name]
D = R + name + "_sample/"
SKIP = set(sys.argv[2:])   # 形如 a_in:6 要跳过的帧


def unred(im):
    """去血迹: 纯红像素先挖掉, 身体内部的洞用周围颜色补"""
    px = im.load()
    W, H = im.size
    holes = set()
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a and r > 150 and g < 70 and b < 70:
                holes.add((x, y))
                px[x, y] = (0, 0, 0, 0)
    for _ in range(6):
        for (x, y) in list(holes):
            if px[x, y][3]:
                continue
            ns = [px[x + dx, y + dy] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)) if 0 <= x + dx < W and 0 <= y + dy < H and px[x + dx, y + dy][3]]
            if len(ns) >= 5:
                px[x, y] = max(set(ns), key=ns.count)
    return im


def f(seg, i):
    im = despeck(L(D, seg, i), 14)
    return unred(im) if seg == "k_in" and "unred" in SKIP else despeck(im, 14)


def gen(n):
    return Image.open(D + "gen_%s.png" % n).convert("RGBA")


def pick(seg, idx):
    out = []
    for i in idx:
        if "%s:%d" % (seg, i) not in SKIP:
            out.append(f(seg, i))
        elif "%s:%d" % (seg, i - 1) not in SKIP and i > 1 and "nofb" not in SKIP:
            out.append(f(seg, i - 1))
    return out


def leftmost(im):
    px = im.load()
    for x in range(128):
        ys = [y for y in range(128) if px[x, y][3]]
        if len(ys) >= 2:
            return x, sum(ys) // len(ys)
    return 10, 90


def hitfx(k, x, y, cols):
    def fr(st):
        if k == 0:
            star(st, PAD + x, TOP + y, 16, cols, 1)
        if k == 1:
            star(st, PAD + x, TOP + y, 9, cols, 2)
    return fr


def relfx(k, cols):
    def back(st):
        if 0 <= k <= 4:
            ring(st, PAD + 70, GROUND - 2, 26 + k * 15, 7 + k * 4, cols[2 if k < 3 else 1], 3 - min(2, k // 2))

    def front(st):
        if 0 <= k <= 3:
            for j in range(9):
                a = j * 0.7 + k * 0.3
                r = 36 + k * 9
                shard(st, PAD + 70 + r * math.cos(a), TOP + 80 + r * 0.8 * math.sin(a), 3, cols[2 - j % 2], cols[0])
    return back, front


clips = []
idle = [onstage(f("idle", i)) for i in range(8)]
clips.append({"name": "待机", "note": "每帧 0.125 秒 · 约 1 秒一轮", "frames": idle, "fps": 8, "ox": OX, "ground": GROUND, "loop": True})
clips.append({"name": "走路", "note": "每帧 0.083 秒 · 0.67 秒一轮", "frames": [onstage(f("walk", i)) for i in range(8)], "fps": 12, "ox": OX, "ground": GROUND, "loop": True})

## 普攻
title, seg, key = C["atk"]
interval = 1.0 / C["aspd"]
wind = max(0.12, min(0.40, interval * 0.30))
COIL = {"dice3": (5, 7), "line": (5, 7), "cyber": (3, 5), "crystal": (4, 6), "chest": (4, 6), "space": (3, 5), "hiding": (4, 6), "headless": (4, 6)}
hit = gen(key)
if name == "headless":
    sw = [f("sw", i) for i in (1, 2, 3)]
else:
    sw = pick("sw", (1, 2, 3))
pre = [f(seg + "_in", COIL[name][0]), f(seg + "_in", COIL[name][1])] + sw
HIT = len(pre)
post = pick(seg + "_out", (1, 2, 3, 4))
if "atkrev" in SKIP:
    post = pick(seg + "_in", (7, 5, 3, 1))
seq = pre + [hit, hit, hit] + post
fps = HIT / wind
x, y = leftmost(hit)
fr = []
for i, im in enumerate(seq):
    k = i - HIT
    dx = {1: -2, 2: -3}.get(k, 0)
    fr.append(onstage(im, dx=dx, front=hitfx(k, x + dx, y, C["fx"]) if 0 <= k <= 1 else None))
clips.append({"name": title, "note": "攻速 %.2f · 每帧 %.3f 秒 · 起手 %.2f 秒命中 · 动作 %.2f 秒 · 每 %.2f 秒打一次" % (C["aspd"], 1 / fps, wind, len(seq) / fps, interval),
              "frames": fr, "fps": fps, "ox": OX, "ground": GROUND, "rel": HIT, "idle_gap": max(0.1, interval - len(seq) / fps)})

## 技能
for title, seg, key, extra in C["skills"]:
    pre = pick(seg + "_in", (1, 3, 5, 7))[-4:]
    post = pick(seg + "_out", (1, 2, 3, 4))
    if "rev:" + seg in SKIP:
        post = pick(seg + "_in", (7, 3)) + post
    seq = pre + [f(seg + "_in", 8), gen(key)] + post
    if name == "headless" and seg == "d":   # 灵魂打击: 举爪后要砍下去
        seq = pre + [f("d_in", 8), gen("soul"), f("c1", 3), gen("slam")] + pick("c2", (1, 2, 3, 4))
    REL = len(pre)
    fps = REL / 0.34
    fr = []
    for i, im in enumerate(seq):
        back, front = relfx(i - REL, C["fx"])
        fr.append(onstage(im, back=back, front=front))
    note = "每帧 %.3f 秒 · 全程 %.2f 秒 · 起手 0.34 秒释放" % (1 / fps, len(seq) / fps)
    if extra:
        note += " · " + extra
    clips.append({"name": title, "note": note, "frames": fr, "fps": fps, "ox": OX, "ground": GROUND, "rel": REL})

## 阵亡
seq = pick("k_in", (3, 4, 5, 6, 7, 8))
if name == "hiding":   # 翻身要有过程: 第一段到翻倒一半, 第二段翻过来弹一下
    seq = pick("k1", (5, 6, 7, 8)) + pick("k2", (2, 3, 4, 6))
fr = [onstage(x2) for x2 in seq]
hold = fr[-1]
fr += [hold, hold]
for a in (0.85, 0.7, 0.55, 0.4, 0.25, 0.1):
    c = hold.copy()
    c.putalpha(c.getchannel("A").point(lambda v, a=a: int(v * a)))
    fr.append(c)
clips.append({"name": "阵亡", "note": "%d 帧 · 每帧 0.067 秒 · 第 0.55 秒开始淡出，0.4 秒淡完" % len(seq), "frames": fr, "fps": 15, "ox": OX, "ground": GROUND})

os.makedirs(D + "final", exist_ok=True)
for c in clips:
    n = c["name"].replace(" · ", "_")
    os.makedirs(D + "final/" + n, exist_ok=True)
    for i, im in enumerate(c["frames"]):
        im.save(D + "final/%s/f_%02d.png" % (n, i))
rows = len(clips)
cw, ch = 118, 92
g = Image.new("RGB", (cw * 9, ch * rows), (66, 84, 70))
for r, c in enumerate(clips):
    fs = c["frames"]
    for k in range(9):
        im = fs[min(len(fs) - 1, k * len(fs) // 9)].resize((cw, ch), Image.NEAREST)
        g.paste(im, (k * cw, r * ch), im)
g.save(D + "overview.png")
print("总览", g.size)
if "noreel" not in SKIP:
    reel.render(clips, "%s · 全部动作（未接入游戏）" % C["title"], D + "%s_全动作.mp4" % C["title"], idle=idle, idle_ox=OX, idle_ground=GROUND)
