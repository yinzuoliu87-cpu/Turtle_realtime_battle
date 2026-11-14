# -*- coding: utf-8 -*-
"""出土时间线(2026-11-13): 每 1/30 秒量 ① 落点暗影(根部周围变暗多少) ② 光柱(根部上方一列的洋红亮度) ③ 芽身高度(抠出来的线最高点离根部多高, 按最终身长归一)
④ 卷曲(线的总转角)。LoL 两次出土 + 我们的出土, 都按光柱最亮那一帧对齐。只做量尺, 打印各阶段时刻。
用法: python spawn_rules.py
"""
import json
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from my_annotate import tent_mask  # noqa: E402
from roto_tentacle import skel_paths  # noqa: E402
from idle_match import resample  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTD = os.path.join(ROOT, ".out", "ref_illaoi")
FF = "D:/oopz/ffmpeg.exe"


def grab_seq(video, t0, t1, crop, fps=30):
    x0, y0, w, h = crop
    p = subprocess.Popen([FF, "-loglevel", "error", "-ss", "%.3f" % t0, "-t", "%.3f" % (t1 - t0), "-i", video,
                          "-vf", "fps=%d,crop=%d:%d:%d:%d" % (fps, w, h, x0, y0), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    out, k = [], 0
    while True:
        b = p.stdout.read(w * h * 3)
        if len(b) < w * h * 3:
            break
        out.append((t0 + k / fps, np.frombuffer(b, np.uint8).reshape(h, w, 3).astype(np.int16)))
        k += 1
    return out


def measure(name, video, t0, t1, root, crop, bg_t):
    x0, y0, w, h = crop
    rl = (root[0] - x0, root[1] - y0)
    seq = grab_seq(video, t0, t1, crop)
    bg = grab_seq(video, bg_t, bg_t + 0.05, crop)[0][1]
    yy, xx = np.ogrid[:h, :w]
    disk = (xx - rl[0]) ** 2 + ((yy - rl[1]) * 1.6) ** 2 < 45 ** 2
    col = (np.abs(xx - rl[0]) < 14) & (yy < rl[1] - 30) & (yy > rl[1] - 260)
    rows = []
    for t, f in seq:
        lum = f.mean(-1)
        dark = float(bg.mean(-1)[disk].mean() - lum[disk].mean())
        r, g, b = f[..., 0], f[..., 1], f[..., 2]
        mag = float(np.clip((r + b) / 2 - g, 0, None)[col].mean())
        m = tent_mask(f, bg, rl)
        hgt, curl = 0.0, 0.0
        if m.any():
            ys, xs = np.nonzero(m)
            hgt = float(rl[1] - ys.min())
            raw = skel_paths(m, rl, None)
            if raw is not None and len(raw) > 10:
                q = resample(raw)
                d = np.diff(q, axis=0)
                a = np.unwrap(np.arctan2(-d[:, 1], d[:, 0]))
                curl = float(np.degrees(abs(a[-1] - a[0])))
        rows.append((t, dark, mag, hgt, curl))
    R = np.array(rows)
    tb = R[np.argmax(R[:, 2]), 0]
    hmax = np.percentile(R[:, 3], 95)
    def first(cond_idx):
        return None if len(cond_idx) == 0 else round(float(R[cond_idx[0], 0] - tb), 2)
    dk = R[:, 1]
    print("── %s(以光柱最亮那一帧为 0, 最终高 %.0f 像素)" % (name, hmax))
    print("  暗影出现 %s  暗影最深 %s" % (first(np.where(dk > 0.35 * dk.max())[0]), round(float(R[np.argmax(dk), 0] - tb), 2)))
    after = R[:, 0] >= tb
    for frac in (0.3, 0.6, 0.9):
        print("  芽身到 %d%% 高: %s" % (frac * 100, first(np.where(after & (R[:, 3] > frac * hmax))[0])))
    print("  卷曲 > 90°: %s   > 180°: %s" % (first(np.where(after & (R[:, 4] > 90))[0]), first(np.where(after & (R[:, 4] > 180))[0])))
    json.dump({"t_beam": tb, "rows": R.tolist()}, open(os.path.join(OUTD, "spawn_%s.json" % name), "w"))


def main():
    vid = os.path.join(OUTD, "illaoi_2.mkv")
    measure("LoL墙根", vid, 18.0, 22.8, (953, 730), (653, 300, 600, 560), 17.2)
    measure("LoL中间", vid, 70.8, 74.6, (1013, 458), (760, 60, 520, 500), 70.0)


if __name__ == "__main__":
    main()
