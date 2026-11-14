# -*- coding: utf-8 -*-
"""量尺: 从用户 LoL 录屏里逐帧量俄洛伊触手的中心线(2026-11-13, 方案书 docs/plans/20261113b-灵物触手最后一版优化.md §7)。

★只做量尺, 结果不进游戏(逐帧复制 Riot 动画进商业游戏有风险, 已跟用户讲明; 游戏里用我们自己的关键帧)。
输出 .out/ref_illaoi/roto_<名字>.json: 每帧 {t, root, poly(画面像素, 根→梢), tip}; --sheet 出核对图。

用法:
  python tools/oneoff/roto_tentacle.py --name R --raw .out/ref_illaoi/idle_full30.rgb --raw-t0 68.5 \
      --crop 1500 420 1920 840 --t0 69.0 --t1 94.0 [--root x y] [--sheet]
根部不给就自动找: 触手根部地上那段青色短横线(LoL 的位置标记)的中点往上 6 像素。
"""
import argparse
import json
import os

import numpy as np
from scipy import ndimage
from skimage.morphology import skeletonize

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTD = os.path.join(ROOT, ".out", "ref_illaoi")
W, H = 1920, 1080


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


def find_root(stack):
    f = stack[len(stack) // 2]
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    m = (b > 170) & (g > 120) & (r < 120) & (b - r > 70)
    ys, xs = np.nonzero(m)
    if len(xs) < 4:
        return None
    return (int(np.median(xs)), int(np.median(ys)) - 6)


def skel_paths(m, root, prev_tip):
    sk = skeletonize(m)
    ys, xs = np.nonzero(sk)
    if len(xs) < 5:
        return None
    pts = np.stack([xs, ys], 1)
    idx = {(int(x), int(y)): i for i, (x, y) in enumerate(pts)}
    start = int(np.argmin(np.hypot(xs - root[0], ys - root[1])))
    dist = -np.ones(len(pts), int)
    prev = -np.ones(len(pts), int)
    nb = np.zeros(len(pts), int)
    dist[start] = 0
    q = [start]
    for i in q:
        x, y = pts[i]
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                j = idx.get((int(x + dx), int(y + dy)))
                if j is None:
                    continue
                nb[i] += 1
                if dist[j] < 0:
                    dist[j] = dist[i] + 1
                    prev[j] = i
                    q.append(j)
    ends = [i for i in range(len(pts)) if nb[i] <= 1 and dist[i] > 0]
    if not ends:
        return None
    far = max(ends, key=lambda i: dist[i])
    if prev_tip is not None:
        ## 末端里选「够长(≥ 最长的 60%) 且离上一帧梢端最近」的 —— 不拐进背鳍尖
        cand = [i for i in ends if dist[i] >= 0.6 * dist[far]]
        tip = min(cand, key=lambda i: np.hypot(*(pts[i] - prev_tip)))
    else:
        tip = far
    path = []
    i = tip
    while i >= 0:
        path.append(pts[i])
        i = prev[i]
    return np.vstack([[root], np.array(path[::-1], float)])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--raw", required=True)
    ap.add_argument("--raw-t0", type=float, required=True)
    ap.add_argument("--raw-fps", type=float, default=30.0)
    ap.add_argument("--crop", type=int, nargs=4, required=True)
    ap.add_argument("--t0", type=float, required=True)
    ap.add_argument("--t1", type=float, required=True)
    ap.add_argument("--root", type=int, nargs=2)
    ap.add_argument("--sheet", action="store_true")
    a = ap.parse_args()
    raw = np.memmap(a.raw if os.path.isabs(a.raw) else os.path.join(ROOT, a.raw), dtype=np.uint8, mode="r").reshape(-1, H, W, 3)
    x0, y0, x1, y1 = a.crop
    ts = np.arange(a.t0, a.t1, 1.0 / a.raw_fps)
    idx = [int(round((t - a.raw_t0) * a.raw_fps)) for t in ts]
    idx = [i for i in idx if 0 <= i < raw.shape[0]]
    stack = np.stack([raw[i, y0:y1, x0:x1] for i in idx]).astype(np.int16)
    bg = np.median(stack[::3], axis=0)
    root = tuple(a.root) if a.root else find_root(stack)
    print("root", root)
    frames = []
    prev_tip = None
    for j in range(len(idx)):
        poly = skel_paths(mask_of(stack[j], bg), root, prev_tip)
        if poly is not None and len(poly) > 3:
            prev_tip = poly[-1]
        frames.append({"t": round(float(ts[j]), 4), "poly": None if poly is None else [[round(float(p[0]), 1), round(float(p[1]), 1)] for p in poly]})
    out = os.path.join(OUTD, "roto_%s.json" % a.name)
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"crop": a.crop, "root": root, "frames": frames}, f)
    ok = sum(1 for fr in frames if fr["poly"])
    print("frames", len(frames), "有中心线", ok, "→", out)
    if a.sheet:
        from PIL import Image, ImageDraw
        tiles = []
        for j in range(0, len(idx), 15):
            im = Image.fromarray(np.clip(stack[j], 0, 255).astype(np.uint8)).convert("RGB")
            dd = ImageDraw.Draw(im)
            if frames[j]["poly"]:
                dd.line([tuple(p) for p in frames[j]["poly"]], fill=(0, 255, 0), width=3)
            if root:
                dd.ellipse((root[0] - 4, root[1] - 4, root[0] + 4, root[1] + 4), outline=(255, 0, 0), width=2)
            dd.text((3, 3), "%.1f" % ts[j], fill=(255, 255, 0))
            tiles.append(im.resize((168, int(168 * (y1 - y0) / (x1 - x0)))))
        tw, th = tiles[0].size
        cols = 10
        rows = (len(tiles) + cols - 1) // cols
        sh = Image.new("RGB", (tw * cols, th * rows))
        for k2, tl in enumerate(tiles):
            sh.paste(tl, ((k2 % cols) * tw, (k2 // cols) * th))
        sh.save(os.path.join(OUTD, "roto_%s_check.png" % a.name))


if __name__ == "__main__":
    main()
