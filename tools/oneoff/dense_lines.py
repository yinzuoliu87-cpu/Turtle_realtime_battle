# -*- coding: utf-8 -*-
"""密集抠线(每 0.1 秒一张, 用 my_annotate 的洋红色 + 透明颈部那套抠法), 给待机节奏研究用(2026-11-13)。
用法: python dense_lines.py <名字> <根x> <根y> <裁x> <裁y> <裁w> <裁h> <起> <止> [背景时刻]
输出 .out/ref_illaoi/dense_<名字>.json: [{t, line(画面坐标) | null}]
"""
import json
import os
import subprocess
import sys

import numpy as np
from scipy.interpolate import splev, splprep

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from my_annotate import tent_mask  # noqa: E402
from roto_tentacle import skel_paths  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTD = os.path.join(ROOT, ".out", "ref_illaoi")
FF = "D:/oopz/ffmpeg.exe"


def frames(t0, t1, crop, fps=int(os.environ.get("DENSE_FPS", "10"))):
    x0, y0, w, h = crop
    p = subprocess.Popen([FF, "-loglevel", "error", "-ss", "%.3f" % t0, "-t", "%.3f" % (t1 - t0), "-i", os.path.join(OUTD, "illaoi_2.mkv"),
                          "-vf", "fps=%d,crop=%d:%d:%d:%d" % (fps, w, h, x0, y0), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    k = 0
    while True:
        b = p.stdout.read(w * h * 3)
        if len(b) < w * h * 3:
            break
        yield t0 + k / fps, np.frombuffer(b, np.uint8).reshape(h, w, 3).astype(np.int16)
        k += 1


def main():
    name = sys.argv[1]
    rx, ry, x0, y0, w, h = [int(v) for v in sys.argv[2:8]]
    t0, t1 = float(sys.argv[8]), float(sys.argv[9])
    fr = list(frames(t0, t1, (x0, y0, w, h)))
    if len(sys.argv) > 10:
        bg = next(frames(float(sys.argv[10]), float(sys.argv[10]) + 0.2, (x0, y0, w, h)))[1]
    else:
        bg = np.median(np.stack([f for _, f in fr[::5]]), axis=0)
    rl = (rx - x0, ry - y0)
    out = []
    for t, f in fr:
        m = tent_mask(f, bg, rl)
        line = None
        if m.any():
            raw = skel_paths(m, rl, None)
            if raw is not None and len(raw) > 10:
                keep = np.r_[True, np.hypot(*np.diff(raw, axis=0).T) > 0.5]
                pts = raw[keep]
                tck, _ = splprep([pts[:, 0], pts[:, 1]], s=len(pts) * 9.0, k=3)
                ln = np.stack(splev(np.linspace(0, 1, 60), tck), 1) + np.array([x0, y0])
                line = [[round(float(a), 1), round(float(b), 1)] for a, b in ln]
        out.append({"t": round(t, 2), "line": line})
    json.dump(out, open(os.path.join(OUTD, "dense_%s.json" % name), "w", encoding="utf-8"))
    print(name, len(out), "帧, 有线", sum(1 for o in out if o["line"]))


if __name__ == "__main__":
    main()
