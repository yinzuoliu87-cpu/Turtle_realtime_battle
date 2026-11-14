# -*- coding: utf-8 -*-
"""同一把尺子量两边: 在 LoL 录屏帧和我们的录像帧上抠出触手、求中心线, 画回原图(2026-11-13, 方案书 20261113b §7)。

★只做量尺 / 对照图, 结果不进游戏。输出到 .out/ref_illaoi/。
抠图: 背景 = 前后 ±1 秒逐帧中位数(触手在动 ⇒ 被中位数去掉); 触手像素 = 与背景差得多 + 颜色偏紫(LoL 洋红 / 我们淡紫两套阈值);
只留与根部连通的那一块; 骨架化后从根部走到最远的端点 = 中心线(同 roto_tentacle.py)。
用法: python tools/oneoff/line_overlay.py <视频> <lol|ours> <根x> <根y> <裁x> <裁y> <裁w> <裁h> <输出前缀> <时刻1> [时刻2 ...]
"""
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roto_tentacle import skel_paths  # noqa: E402

FF = "D:/oopz/ffmpeg.exe"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTD = os.path.join(ROOT, ".out", "ref_illaoi")


def grab(video, t, size):
    w, h = size
    r = subprocess.run([FF, "-loglevel", "error", "-ss", "%.3f" % t, "-i", video, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                       capture_output=True)
    return np.frombuffer(r.stdout, np.uint8)[: w * h * 3].reshape(h, w, 3).astype(np.int16)


def mask(kind, f, bg):
    d = f - bg
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    if kind == "lol":
        ## 11-13 用户画红线指出: 阈值 12 只抠到半透明颈部的下沿 ⇒ 中心线贴着下边走。降到 6, 再把鳍 / 缺口填平
        dr, dg, db = d[..., 0], d[..., 1], d[..., 2]
        m = ((dr + db) / 2 - dg > 6) & (db > 3)
        m = ndimage.binary_opening(m, iterations=2)
        m = ndimage.binary_closing(m, iterations=8)
        m = ndimage.binary_fill_holes(m)
        ## 磨圆: 先腐蚀再膨胀(半径 6) ⇒ 鳍尖 / 锯齿去掉, 中线不往鳍里拐
        m = ndimage.binary_dilation(ndimage.binary_erosion(m, iterations=6), iterations=6)
        return m
    else:
        m = (np.abs(d).sum(-1) > 45) & (b - g > 12) & (r > g)
    m = ndimage.binary_opening(m, iterations=1)
    m = ndimage.binary_closing(m, iterations=6)
    return m


def main():
    video, kind = sys.argv[1], sys.argv[2]
    rx, ry, cx, cy, cw, ch = [int(v) for v in sys.argv[3:9]]
    pre = sys.argv[9]
    times = [float(v) for v in sys.argv[10:]]
    size = (1920, 1080) if kind == "lol" else (1280, 720)
    vp = video if os.path.isabs(video) else os.path.join(OUTD, video)
    scr = {}
    if kind == "scr":
        import re
        for ln in open(os.path.join(OUTD, pre.split(":")[1]), encoding="utf-8", errors="ignore"):
            mm = re.match(r"\[SCR\] t=([0-9.]+) st=\d+ (.*)", ln)
            if mm:
                scr[float(mm.group(1))] = [tuple(float(v) for v in q.split(",")) for q in mm.group(2).strip().split(";")]
        pre = pre.split(":")[0]
        size = (1280, 720)
    tiles = []
    for t in times:
        if kind == "scr":
            f = grab(vp, t, size)[cy:cy + ch, cx:cx + cw]
            k0 = min(scr, key=lambda q: abs(q - t))
            im = Image.fromarray(np.clip(f, 0, 255).astype(np.uint8))
            dd = ImageDraw.Draw(im)
            pl = [(x - cx, y - cy) for x, y in scr[k0]]
            dd.line(pl, fill=(0, 255, 60), width=4)
            dd.ellipse((pl[-1][0] - 6, pl[-1][1] - 6, pl[-1][0] + 6, pl[-1][1] + 6), outline=(255, 255, 0), width=3)
            dd.ellipse((pl[0][0] - 6, pl[0][1] - 6, pl[0][0] + 6, pl[0][1] + 6), outline=(255, 40, 40), width=3)
            im.save(os.path.join(OUTD, "%s_%.3f.png" % (pre, t)))
            continue
        bgs = [grab(vp, t + dt, size)[cy:cy + ch, cx:cx + cw] for dt in (-1.0, -0.8, -0.6, 0.6, 0.8, 1.0, -1.2, 1.2, 1.4)]
        bg = np.median(np.stack(bgs), axis=0)
        f = grab(vp, t, size)[cy:cy + ch, cx:cx + cw]
        m = mask(kind, f, bg)
        root = (rx - cx, ry - cy)
        lab, k = ndimage.label(m)
        if k:
            ## 只留一块: 伸到根部 90 像素以内的那些里面面积最大的(触手本体; 半透明的颈部常和根部隔一点)
            yy, xx = np.ogrid[: m.shape[0], : m.shape[1]]
            near = (xx - root[0]) ** 2 + (yy - root[1]) ** 2 < 90 ** 2
            cand = sorted(set(np.unique(lab[near & m])) - {0})
            if cand:
                sz = ndimage.sum(m, lab, cand)
                m = lab == cand[int(np.argmax(sz))]
        poly = skel_paths(m, root, None)
        im = Image.fromarray(np.clip(f, 0, 255).astype(np.uint8))
        dd = ImageDraw.Draw(im)
        if poly is not None and len(poly) > 3:
            dd.line([tuple(p) for p in poly], fill=(0, 255, 60), width=4)
            dd.ellipse((poly[-1][0] - 6, poly[-1][1] - 6, poly[-1][0] + 6, poly[-1][1] + 6), outline=(255, 255, 0), width=3)
        dd.ellipse((root[0] - 6, root[1] - 6, root[0] + 6, root[1] + 6), outline=(255, 40, 40), width=3)
        tiles.append(im)
        im.save(os.path.join(OUTD, "%s_%.3f.png" % (pre, t)))
    print("ok", len(tiles))


if __name__ == "__main__":
    main()
