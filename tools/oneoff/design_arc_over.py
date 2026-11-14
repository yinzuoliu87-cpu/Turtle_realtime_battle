# -*- coding: utf-8 -*-
"""出土 1.18 / 1.35 / 1.51 三个关键姿势自己设计(2026-11-13 夜用户「二十、二十一、二十二针…在墙里面，我们看不到…你得设计这三针，好接到二十三针」)。
LoL 1.01–1.51 秒上半截插进石墙看不见; 能确定的: 1.15 秒露在墙外那截已经有待机的 1.2 倍高, 1.60 秒头从墙左下钻出来朝下, 1.68 秒拱形(第 23 帧, 锚点)。
做法: 每个控制点的角度从 1.10(对折末尾, 游戏里实测)到 1.68(锚点)按时间顺滑走, 再加「先长高再往左拱过去」的形状约束,
  量: 最高点(× 待机高)、头在画面上的位置、头每帧走多远(匀不匀)。投影 = 我们游戏镜头(画面 x = 60·x, y = −35.3·y)。
用法: python tools/oneoff/design_arc_over.py  —— 打印候选的量 + 画 .out/tent_design/_arc_design.png"""
import math
import sys

import numpy as np

sys.stdout.reconfigure(encoding="utf-8")
U6 = np.array([0.05, 0.25, 0.45, 0.65, 0.85, 1.0])
SEG = 36
L_FULL = 5.74          # 全长(米), 游戏日志实测
IDLE_H = 3.4           # 待机最高点(米)的中位, 游戏日志实测(画面顶高 182 像素 ÷ 53.6 像素/米)


def chain(p6, length=L_FULL):
    u = (np.arange(SEG) + 0.5) / SEG
    c = np.array(p6, float)
    out = []
    for uu in u:
        if uu <= U6[0]:
            out.append(c[0]); continue
        j = min(int(np.searchsorted(U6, uu)) - 1, 4)
        s = (uu - U6[j]) / (U6[j + 1] - U6[j])
        p0, p1, p2, p3 = c[max(j - 1, 0)], c[j], c[j + 1], c[min(j + 2, 5)]
        out.append(0.5 * (2 * p1 + (p2 - p0) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s * s + (-p0 + 3 * p1 - 3 * p2 + p3) * s ** 3))
    a = np.radians(out)
    d = np.stack([np.cos(a), np.sin(a)], 1) * length / SEG
    return np.vstack([[0, 0], np.cumsum(d, 0)])


def cr_time(ts, vals, t):
    ## 时间上 Catmull-Rom(和游戏 _hermite 一样的切线)
    n = len(ts)
    if t <= ts[0]:
        return vals[0]
    if t >= ts[-1]:
        return vals[-1]
    i = max(k for k in range(n - 1) if t >= ts[k])
    t0, t1 = ts[i], ts[i + 1]; h = t1 - t0; x = (t - t0) / h
    p0, p1 = vals[i], vals[i + 1]
    m0 = 0 if i == 0 else (p1 - vals[i - 1]) / (t1 - ts[i - 1])
    m1 = 0 if i + 1 == n - 1 else (vals[i + 2] - p0) / (ts[i + 2] - t0)
    return (2 * x ** 3 - 3 * x ** 2 + 1) * p0 + (x ** 3 - 2 * x ** 2 + x) * h * m0 + (-2 * x ** 3 + 3 * x ** 2) * p1 + (x ** 3 - x ** 2) * h * m1


## 锚点: 1.01 / 1.10 = 对折段在游戏里实测的画面平面角(上半截朝身后, 画面上看着朝上 ⇒ 按画面上的样子折成平面角); 1.68 / 1.88 = 现有关键姿势
ANCH = {1.01: [66, 88, 112, 150, 250, 275], 1.10: [65, 86, 109, 120, 112, 105],
        1.68: [64.7, 76.6, 106.3, 220.5, 278.8, 278.8], 1.88: [38.4, 81.9, 103.1, 218.2, 275.5, 328.1]}
CANDS = {
    "原来": {1.18: [55, 75, 100, 126, 158, 195], 1.35: [62.8, 81.8, 95.2, 108.4, 125.2, 144.4], 1.51: [57.0, 75.5, 90.3, 109.5, 145.4, 186.5]},
    "设计A": {1.18: [62, 80, 100, 118, 128, 135], 1.35: [63, 79, 103, 145, 178, 198], 1.51: [64, 78, 105, 182, 230, 245]},
    "设计B": {1.18: [62, 80, 98, 112, 122, 128], 1.35: [63, 79, 102, 138, 170, 190], 1.51: [64, 78, 105, 178, 228, 248]},
}


def run(name, keys):
    K = dict(ANCH); K.update(keys)
    ts = sorted(K)
    rows = []
    for t in np.arange(1.10, 1.881, 1 / 60):
        p6 = [cr_time(ts, [K[k][j] for k in ts], t) for j in range(6)]
        P = chain(p6)
        S = np.stack([60 * P[:, 0], -35.3 * P[:, 1]], 1)
        rows.append((t, P, S))
    hs = [P[:, 1].max() / IDLE_H for _, P, _ in rows]
    steps = [float(np.max(np.linalg.norm(rows[i][2] - rows[i - 1][2], axis=1))) for i in range(1, len(rows))]
    head = [S[-1] for _, _, S in rows]
    print("%s: 最高 %.2f × 待机高(在 %.2f 秒)  一帧最大位移 %.1f 像素(在 %.2f 秒)  中位 %.1f" % (
        name, max(hs), rows[int(np.argmax(hs))][0], max(steps), rows[1 + int(np.argmax(steps))][0], np.median(steps)))
    for tt in (1.10, 1.18, 1.35, 1.51, 1.60, 1.68):
        k = int(round((tt - 1.10) * 60)); S = rows[k][2]
        print("   %.2f 头 (%+4.0f, %+4.0f)  最高 %.2f" % (tt, S[-1, 0], -S[-1, 1], hs[k]))
    return rows


if __name__ == "__main__":
    from PIL import Image, ImageDraw, ImageFont
    f = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 15)
    allr = {n: run(n, k) for n, k in CANDS.items()}
    show = [1.10, 1.18, 1.27, 1.35, 1.43, 1.51, 1.60, 1.68]
    W, H = 150, 200
    img = Image.new("RGB", (W * len(show), H * len(allr)), (20, 20, 28)); d = ImageDraw.Draw(img)
    for r, (n, rows) in enumerate(allr.items()):
        for c, tt in enumerate(show):
            S = rows[int(round((tt - 1.10) * 60))][2] * 0.4
            ox, oy = c * W + 75, r * H + 185
            d.line([(ox + x, oy + y) for x, y in S], fill=(80, 220, 255), width=3)
            d.ellipse((ox + S[-1, 0] - 4, oy + S[-1, 1] - 4, ox + S[-1, 0] + 4, oy + S[-1, 1] + 4), outline=(255, 90, 90), width=2)
            d.text((c * W + 4, r * H + 2), "%s %.2f秒" % (n, tt), fill=(255, 255, 0), font=f)
    img.save(".out/tent_design/_arc_design.png")
