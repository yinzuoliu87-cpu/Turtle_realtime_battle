# -*- coding: utf-8 -*-
"""量尺: LoL 录屏里每一击出手的姿势 → 沿身长 6 个控制点的俯仰角 + 身长(2026-11-13, 方案书 20261113b §7)。

★只做量尺, 输出 .out/ref_illaoi/strike_ruler.json + 核对图; 游戏里的姿势是参考这些数自己定的关键姿势(不播描帧数据)。
做法: 抠中心线(line_overlay 同一套) → 假设触手在「过根部、沿出手方向的竖直平面」里(录屏里蓄力到躺平都是这样) →
  LoL 镜头 ≈ 俯角 56°(竖直 1 米在画面上 × cos56, 地面朝远处 1 米 × sin56) ⇒ 画面上每一小段反算出平面里的方向和长度 →
  按身长重采样到 U6 = [0.05, 0.25, 0.45, 0.65, 0.85, 1.0] 取俯仰角(0 = 朝目标水平, 90 = 竖直, 180 = 朝身后水平)。
出手方向: 取贴地后 0.05 秒(本体沿出手方向躺平)那一帧中心线「根部 → 最远点」。
用法: python tools/oneoff/strike_ruler.py   (击次与根部写在 STRIKES 里)
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from line_overlay import grab, mask  # noqa: E402
from roto_tentacle import skel_paths  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTD = os.path.join(ROOT, ".out", "ref_illaoi")
VID = os.path.join(OUTD, "illaoi_2.mkv")
CAM = math.radians(56.0)
U6 = [0.05, 0.25, 0.45, 0.65, 0.85, 1.0]
TAUS = [0.80, 0.72, 0.60, 0.50, 0.40, 0.33, 0.26, 0.20, 0.15]
## 贴地时刻, 根部估计(画面像素, 自动在附近找青色根部标记修正)
STRIKES = [(31.11, (953, 732)), (45.20, (640, 748)), (48.50, (700, 640)), (62.80, (1020, 742))]


def find_bar(f, est):
    x0, y0 = max(est[0] - 120, 0), max(est[1] - 80, 0)
    sub = f[y0:est[1] + 80, x0:est[0] + 120]
    r, g, b = sub[..., 0], sub[..., 1], sub[..., 2]
    m = (b > 170) & (g > 120) & (r < 120) & (b - r > 70)
    ys, xs = np.nonzero(m)
    if len(xs) < 4:
        return None
    return (int(np.median(xs)) + x0, int(np.median(ys)) + y0 - 6)


def centerline(t, root, box):
    cx, cy, cw, ch = box
    bgs = [grab(VID, t + dt, (1920, 1080))[cy:cy + ch, cx:cx + cw] for dt in (-1.2, -1.0, -0.8, 0.8, 1.0, 1.2, 1.4)]
    bg = np.median(np.stack(bgs), axis=0)
    f = grab(VID, t, (1920, 1080))[cy:cy + ch, cx:cx + cw]
    m = mask("lol", f, bg)
    lr = (root[0] - cx, root[1] - cy)
    lab, k = ndimage.label(m)
    if k:
        yy, xx = np.ogrid[: m.shape[0], : m.shape[1]]
        near = (xx - lr[0]) ** 2 + (yy - lr[1]) ** 2 < 90 ** 2
        cand = sorted(set(np.unique(lab[near & m])) - {0})
        if cand:
            sz = ndimage.sum(m, lab, cand)
            m = lab == cand[int(np.argmax(sz))]
    poly = skel_paths(m, lr, None)
    return f, (None if poly is None else poly + np.array([cx, cy]))


def smooth(poly, n=9):
    if len(poly) < n:
        return poly
    k = np.ones(n) / n
    xs = np.convolve(np.pad(poly[:, 0], n // 2, mode="edge"), k, "valid")
    ys = np.convolve(np.pad(poly[:, 1], n // 2, mode="edge"), k, "valid")
    out = np.stack([xs, ys], 1)
    out[0] = poly[0]
    return out


def to_plane(poly, fwd_g, upos=None):
    """画面折线 → 竖直平面里的 (俯仰角数组, 总长)。fwd_g = 出手方向在地面上的单位向量 (x 向右, a 向远处)。"""
    fs = np.array([fwd_g[0], -fwd_g[1] * math.sin(CAM)])     # 朝目标 1 米 → 画面
    us = np.array([0.0, -math.cos(CAM)])                       # 竖直向上 1 米 → 画面
    A = np.stack([fs, us], 1)
    inv = np.linalg.inv(A)
    p = smooth(np.asarray(poly, float))
    segs = np.diff(p, axis=0)
    ab = segs @ inv.T                                          # 每段 (朝目标分量, 向上分量)
    ln = np.hypot(ab[:, 0], ab[:, 1])
    keep = ln > 1e-6
    ab, ln = ab[keep], ln[keep]
    ang = np.degrees(np.arctan2(ab[:, 1], ab[:, 0]))
    ## 沿身长展开(相邻不绕整圈), 根部取 [−90, 270) 里离 90 最近的
    for i in range(len(ang)):
        ref = 90.0 if i == 0 else ang[i - 1]
        while ang[i] - ref > 180:
            ang[i] -= 360
        while ref - ang[i] > 180:
            ang[i] += 360
    s = np.concatenate([[0], np.cumsum(ln)])
    L = s[-1]
    mid = (s[:-1] + s[1:]) / 2 / L
    out = []
    for u in (upos or U6):
        w = np.exp(-((mid - u) / 0.06) ** 2) * ln             # 每个控制点取附近一段的加权平均方向
        out.append(float(np.sum(w * ang) / max(np.sum(w), 1e-9)))
    return out, float(L)


def main():
    res = {}
    sheet = []
    for T, est in STRIKES:
        f0 = grab(VID, T - 0.5, (1920, 1080))
        root = find_bar(f0, est) or est
        box = (max(root[0] - 520, 0), max(root[1] - 430, 0), 1000, 560)
        box = (box[0], box[1], min(1000, 1920 - box[0]), min(560, 1080 - box[1]))
        ## 出手方向: 贴地后 0.05 秒那一帧, 根部 → 最远点
        _, pl = centerline(T + 0.05, root, box)
        if pl is None:
            print(T, "贴地帧抠不出线"); continue
        far = pl[np.argmax(np.hypot(pl[:, 0] - root[0], pl[:, 1] - root[1]))]
        sx, sy = far[0] - root[0], far[1] - root[1]
        g = np.array([sx, -sy / math.sin(CAM)]); g /= np.linalg.norm(g)
        print("%.2f 根部 %s 出手方向(画面) %.0f,%.0f → 地面 %.2f,%.2f" % (T, root, sx, sy, g[0], g[1]))
        rows = {}
        for tau in TAUS:
            f, pl = centerline(T - tau, root, box)
            im = Image.fromarray(np.clip(f, 0, 255).astype(np.uint8))
            dd = ImageDraw.Draw(im)
            if pl is not None and len(pl) > 8:
                q = [(x - box[0], y - box[1]) for x, y in pl]
                dd.line(q, fill=(0, 255, 60), width=4)
                ang, L = to_plane(pl, g)
                rows["%.2f" % tau] = {"pitch": [round(a, 1) for a in ang], "len_px": round(L, 1)}
            dd.ellipse((root[0] - box[0] - 6, root[1] - box[1] - 6, root[0] - box[0] + 6, root[1] - box[1] + 6), outline=(255, 40, 40), width=3)
            dd.text((6, 6), "%.2f  tau %.2f" % (T, tau), fill=(255, 255, 0))
            sheet.append(im.resize((300, 168)))
        res["%.2f" % T] = {"root": root, "fwd_ground": [round(float(g[0]), 3), round(float(g[1]), 3)], "poses": rows}
    json.dump(res, open(os.path.join(OUTD, "strike_ruler.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    cols = len(TAUS)
    rows_n = (len(sheet) + cols - 1) // cols
    sh = Image.new("RGB", (300 * cols, 168 * rows_n))
    for i, im in enumerate(sheet):
        sh.paste(im, ((i % cols) * 300, (i // cols) * 168))
    sh.save(os.path.join(OUTD, "strike_ruler_check.png"))
    print("ok")


if __name__ == "__main__":
    main()
