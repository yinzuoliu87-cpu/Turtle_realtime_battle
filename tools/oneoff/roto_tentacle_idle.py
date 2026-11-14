# -*- coding: utf-8 -*-
"""描帧: LoL 俄洛伊触手待机 → 我们触手的待机姿势表(2026-11-13, 方案书 docs/plans/20261113b-灵物触手最后一版优化.md)。

用户 11-13:「尽量是做到一比一…一比一的完美参考」「我都给你这么多待机动画, 你都没有一比一」。
参考: 用户外服训练营录屏 74.0–88.6 s 中间那根(镜头固定, 一个完整待机循环约 14.5 s)。
做法:
  ① 15 秒逐像素取中位数 = 没有触手的背景; 每帧减背景 ⇒ 连透明的下半身也抠得出来
  ② 掩膜骨架 → 离根部最近的骨架点出发, 沿骨架走到最远点(梢端) → 根部 + 这条路 = 中心线
  ③ 画面坐标 → 触手自己的竖直平面: 水平 = 画面 x, 高 = 画面上移 / cos(俯角)(LoL 镜头约 55° 俯角, 竖直在画面里被压扁)
  ④ 按弧长重采样成 SEG 段 → 每段角度(度, 0 = 朝前水平, 90 = 竖直向上); 时间上高斯平滑(去抠图抖动), 首尾 0.5 秒交叉淡化成无缝循环
输出: .out/ref_illaoi/roto_MID_angles.json(量尺, 不进游戏)  {"fps", "seg", "frames": [[角度×SEG], ...]}
录屏不进仓库(体积 + 版权), 只留这份姿势表与本脚本; 重跑要先按脚本头的路径准备 .out/ref_illaoi/idle_full30.rgb。
跑法: python tools/assetgen/roto_tentacle_idle.py [--sheet]   (--sheet 额外出一张核对图 .out/ref_illaoi/roto_check.png)
"""
import json
import os
import sys

import numpy as np
from scipy import ndimage
from skimage.morphology import skeletonize

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REF = os.path.join(ROOT, ".out", "ref_illaoi")
RAW = os.path.join(REF, "idle_full30.rgb")       # ffmpeg -ss 68.5 -t 25.5 -i illaoi_2.mkv -vf fps=30 -pix_fmt rgb24 -f rawvideo
OUT = os.path.join(REF, "roto_MID_angles.json")   # 量尺, 不进游戏
W, H = 1920, 1080
RAW_T0 = 68.5
CROP = (860, 140, 1240, 580)        # x0 y0 x1 y1(中间那根)
ROOT_PX = (152, 334)                 # 根部(裁剪内坐标; 选中描边的底部)
T0, T1 = 74.0, 88.5                  # 一个完整待机循环
FPS_OUT = 15
SEG = 36
PITCH_DEG = 55.0
XFADE = 0.5


def mask_of(f, bg):
    d = f - bg
    dr, dg, db = d[..., 0], d[..., 1], d[..., 2]
    m = ((dr + db) / 2 - dg > 12) & (db > 8) & (dr > 3)
    m = ndimage.binary_opening(m, iterations=1)
    m = ndimage.binary_closing(m, iterations=3)
    lab, k = ndimage.label(m)
    if not k:
        return m
    sz = ndimage.sum(m, lab, range(1, k + 1))
    keep = [j + 1 for j in range(k) if sz[j] >= max(60, 0.15 * sz.max())]
    return np.isin(lab, keep)


def centerline(m):
    sk = skeletonize(m)
    ys, xs = np.nonzero(sk)
    if len(xs) < 5:
        return None
    pts = np.stack([xs, ys], 1)
    d0 = np.hypot(xs - ROOT_PX[0], ys - ROOT_PX[1])
    start = int(np.argmin(d0))
    idx = {(int(x), int(y)): i for i, (x, y) in enumerate(pts)}
    dist = -np.ones(len(pts), int)
    prev = -np.ones(len(pts), int)
    dist[start] = 0
    q = [start]
    for i in q:
        x, y = pts[i]
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                j = idx.get((int(x + dx), int(y + dy)))
                if j is not None and dist[j] < 0:
                    dist[j] = dist[i] + 1
                    prev[j] = i
                    q.append(j)
    tip = int(np.argmax(dist))
    path = []
    i = tip
    while i >= 0:
        path.append(pts[i])
        i = prev[i]
    path = np.array(path[::-1], float)
    return np.vstack([[ROOT_PX], path])


def to_angles(poly):
    k = 1.0 / np.cos(np.radians(PITCH_DEG))
    X = poly[:, 0] - ROOT_PX[0]
    Hh = (ROOT_PX[1] - poly[:, 1]) * k
    P = np.stack([X, Hh], 1)
    # 空间平滑(抠图毛刺)
    if len(P) >= 7:
        P = ndimage.uniform_filter1d(P, size=5, axis=0, mode="nearest")
    seg = np.hypot(*np.diff(P, axis=0).T)
    s = np.concatenate([[0], np.cumsum(seg)])
    if s[-1] < 1e-6:
        return None
    u = np.linspace(0, s[-1], SEG + 1)
    Q = np.stack([np.interp(u, s, P[:, 0]), np.interp(u, s, P[:, 1])], 1)
    d = np.diff(Q, axis=0)
    return np.degrees(np.arctan2(d[:, 1], d[:, 0]))


def main():
    a = np.memmap(RAW, dtype=np.uint8, mode="r").reshape(-1, H, W, 3)
    x0, y0, x1, y1 = CROP
    ts = np.arange(T0, T1, 1.0 / 30.0)
    idx = [int(round((t - RAW_T0) * 30)) for t in ts]
    stack = np.stack([a[i, y0:y1, x0:x1] for i in idx]).astype(np.int16)
    bg = np.median(stack[::3], axis=0)
    angs = []
    polys = []
    for j in range(len(idx)):
        poly = centerline(mask_of(stack[j], bg))
        polys.append(poly)
        angs.append(to_angles(poly) if poly is not None else None)
    # 缺帧用前后补
    last = None
    for j in range(len(angs)):
        if angs[j] is None:
            angs[j] = last
        last = angs[j]
    A = np.array(angs, float)
    A = np.unwrap(np.radians(A), axis=0)
    A = np.degrees(ndimage.gaussian_filter1d(A, sigma=2.5, axis=0, mode="wrap"))
    # 降到 FPS_OUT, 首尾交叉淡化成无缝循环
    step = 30 // FPS_OUT
    A = A[::step]
    n = len(A)
    nx = int(XFADE * FPS_OUT)
    for i in range(nx):
        w = (i + 1) / (nx + 1)
        A[n - nx + i] = A[n - nx + i] * (1 - w) + A[i] * w
    out = {"src": "LoL 俄洛伊 待机 74.0–88.5 s(用户外服训练营录屏) · 描帧 tools/assetgen/roto_tentacle_idle.py",
           "fps": FPS_OUT, "seg": SEG, "pitch_deg": PITCH_DEG,
           "frames": [[round(float(v), 1) for v in row] for row in A]}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print("frames", n, "seg", SEG, "→", OUT)
    if "--sheet" in sys.argv:
        from PIL import Image, ImageDraw
        tiles = []
        for j in range(0, len(idx), 15):
            im = Image.fromarray(np.clip(stack[j], 0, 255).astype(np.uint8)).convert("RGB")
            dd = ImageDraw.Draw(im)
            if polys[j] is not None:
                dd.line([tuple(p) for p in polys[j]], fill=(0, 255, 0), width=3)
            dd.ellipse((ROOT_PX[0] - 4, ROOT_PX[1] - 4, ROOT_PX[0] + 4, ROOT_PX[1] + 4), outline=(255, 0, 0), width=2)
            dd.text((3, 3), "%.1f" % ts[j], fill=(255, 255, 0))
            tiles.append(im.resize((190, 220)))
        cols = 10
        rows = (len(tiles) + cols - 1) // cols
        sh = Image.new("RGB", (190 * cols, 220 * rows))
        for k2, tl in enumerate(tiles):
            sh.paste(tl, ((k2 % cols) * 190, (k2 // cols) * 220))
        sh.save(os.path.join(REF, "roto_check.png"))


if __name__ == "__main__":
    main()
