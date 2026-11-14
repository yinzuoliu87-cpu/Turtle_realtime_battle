# -*- coding: utf-8 -*-
"""我先替用户标待机中线(2026-11-13 用户:「你先尝试标一下，不好的话再让我来」)。
触手下半身几乎透明, 只有头部是实心洋红 ⇒ 两种一起抠:
  头部 = 洋红色(r−g、b−g 都大, r 不比 b 小太多 —— 地上的紫裂纹偏蓝);
  透明的颈 = 与「这根还没长出来时」那一帧(或整段中位数)逐像素比, 被染上一层淡紫的地方。
→ 只留伸到根部的那一块 → 填平 / 磨圆 → 骨架上根部到最远端 → 平滑样条。
画成红线存到 桌面/触手中线标注/我先标的/<子文件夹>/<同名>.png, 线另存 .out/ref_illaoi/my_annot.json。
用法: python tools/oneoff/my_annotate.py <子文件夹> [背景时刻(秒), 不给 = 整段中位数]
"""
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.interpolate import splev, splprep

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roto_tentacle import skel_paths  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTD = os.path.join(ROOT, ".out", "ref_illaoi")
SRC = os.path.join(OUTD, "annot_src")
DESK = os.path.join(os.path.expanduser("~"), "Desktop", "触手中线标注", "我先标的")
FF = "D:/oopz/ffmpeg.exe"


def grab(t):
    r = subprocess.run([FF, "-loglevel", "error", "-ss", "%.3f" % t, "-i", os.path.join(OUTD, "illaoi_2.mkv"), "-frames:v", "1",
                        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True)
    return np.frombuffer(r.stdout, np.uint8)[: 1920 * 1080 * 3].reshape(1080, 1920, 3).astype(np.int16)


def tent_mask(f, bg, root):
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    head = (r - g > 35) & (b - g > 35) & (r > 0.62 * b)
    d = f - bg
    neck = ((d[..., 0] + d[..., 2]) / 2 - d[..., 1] > 6) & (d[..., 2] > 3)
    m = head | neck
    m = ndimage.binary_opening(m, iterations=2)
    m = ndimage.binary_closing(m, iterations=6)
    m = ndimage.binary_fill_holes(m)
    m = ndimage.binary_dilation(ndimage.binary_erosion(m, iterations=5), iterations=5)
    lab, k = ndimage.label(m)
    if not k:
        return m
    yy, xx = np.ogrid[: m.shape[0], : m.shape[1]]
    near = (xx - root[0]) ** 2 + (yy - root[1]) ** 2 < 60 ** 2
    cand = sorted(set(np.unique(lab[near & m])) - {0})
    if not cand:
        return np.zeros_like(m)
    return lab == cand[int(np.argmax(ndimage.sum(m, lab, cand)))]


def main():
    sub = sys.argv[1]
    bg_t = float(sys.argv[2]) if len(sys.argv) > 2 else None
    man = []
    for mf in ("manifest_idle.json", "manifest_idle2.json"):
        if os.path.isfile(os.path.join(SRC, mf)):
            man += [e for e in json.load(open(os.path.join(SRC, mf), encoding="utf-8")) if e["file"].startswith(sub + os.sep)]
    if not man:
        print("没找到", sub); return
    x0, y0, w, h = man[0]["box"]
    if bg_t is not None:
        bg = grab(bg_t)[y0:y0 + h, x0:x0 + w]
    else:
        bg = np.median(np.stack([grab(e["t"])[y0:y0 + h, x0:x0 + w] for e in man]), axis=0)
    os.makedirs(os.path.join(DESK, sub), exist_ok=True)
    allp = json.load(open(os.path.join(OUTD, "my_annot.json"), encoding="utf-8")) if os.path.isfile(os.path.join(OUTD, "my_annot.json")) else {}
    ok = 0
    for e in man:
        f = grab(e["t"])[y0:y0 + h, x0:x0 + w]
        rl = (e["root"][0] - x0, e["root"][1] - y0)
        m = tent_mask(f, bg, rl)
        line = None
        if m.any():
            raw = skel_paths(m, rl, None)
            if raw is not None and len(raw) > 10:
                keep = np.r_[True, np.hypot(*np.diff(raw, axis=0).T) > 0.5]
                pts = raw[keep]
                tck, _ = splprep([pts[:, 0], pts[:, 1]], s=len(pts) * 9.0, k=3)
                line = np.stack(splev(np.linspace(0, 1, 120), tck), 1)
        im = Image.open(os.path.join(SRC, e["file"])).convert("RGB")
        dd = ImageDraw.Draw(im)
        if line is not None:
            dd.line([tuple(p) for p in line], fill=(255, 0, 0), width=4)
            ok += 1
        im.save(os.path.join(DESK, e["file"].replace(sub, sub, 1)))
        allp[e["file"]] = None if line is None else [[round(float(p[0]) + x0, 1), round(float(p[1]) + y0, 1)] for p in line]
    json.dump(allp, open(os.path.join(OUTD, "my_annot.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print(sub, "标了", ok, "/", len(man))


if __name__ == "__main__":
    main()
