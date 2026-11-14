# -*- coding: utf-8 -*-
"""待机: 三根触手(左上 / 中间 / 右边)在 LoL 录屏 69–94 s(镜头固定)的中心线自动抠线 + 画回原图(2026-11-13)。
只做量尺, 输出 .out/ref_illaoi/idle_lines_<名>.json + idle_lines_<名>_check.png。
抠图同 line_overlay「lol」那套(低阈值 + 填平鳍和缺口 + 磨圆), 背景 = 整段 25 秒逐像素中位数(镜头不动)。
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from line_overlay import mask  # noqa: E402
from roto_tentacle import skel_paths  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTD = os.path.join(ROOT, ".out", "ref_illaoi")
W, H = 1920, 1080
RAW_T0, FPS = 68.5, 30.0
## 名字, 裁切(x0,y0,x1,y1), 根部(画面坐标)
TENTS = [("左上", (240, 0, 760, 420), (458, 194)),
         ("中间", (800, 100, 1300, 600), (973, 425)),
         ("右边", (1400, 380, 1920, 880), (1696, 821))]


def main():
    a = np.memmap(os.path.join(OUTD, "idle_full30.rgb"), dtype=np.uint8, mode="r").reshape(-1, H, W, 3)
    n = a.shape[0]
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
    step = float(sys.argv[1]) if len(sys.argv) > 1 else 0.25
    for name, (x0, y0, x1, y1), (rx, ry) in TENTS:
        idx_bg = list(range(0, n, 15))
        bg = np.median(np.stack([a[i, y0:y1, x0:x1] for i in idx_bg]).astype(np.int16), axis=0)
        lr = (rx - x0, ry - y0)
        frames, tiles = [], []
        for t in np.arange(69.0, 94.0, step):
            i = int(round((t - RAW_T0) * FPS))
            if i >= n:
                break
            f = a[i, y0:y1, x0:x1].astype(np.int16)
            m = mask("lol", f, bg)
            lab, k = ndimage.label(m)
            if k:
                yy, xx = np.ogrid[: m.shape[0], : m.shape[1]]
                near = (xx - lr[0]) ** 2 + (yy - lr[1]) ** 2 < 70 ** 2
                cand = sorted(set(np.unique(lab[near & m])) - {0})
                m = (lab == cand[int(np.argmax(ndimage.sum(m, lab, cand)))]) if cand else np.zeros_like(m)
            poly = skel_paths(m, lr, None) if m.any() else None
            frames.append({"t": round(float(t), 3), "poly": None if poly is None else [[round(float(p[0]) + x0, 1), round(float(p[1]) + y0, 1)] for p in poly]})
            if abs((t - 69.0) % 1.0) < 1e-6 or abs((t - 69.0) % 1.0 - 1.0) < 1e-6:
                im = Image.fromarray(np.clip(f, 0, 255).astype(np.uint8))
                dd = ImageDraw.Draw(im)
                if poly is not None and len(poly) > 3:
                    dd.line([tuple(p) for p in poly], fill=(0, 255, 60), width=3)
                dd.ellipse((lr[0] - 6, lr[1] - 6, lr[0] + 6, lr[1] + 6), outline=(255, 40, 40), width=2)
                dd.text((5, 3), "%s %.0f 秒" % (name, t), fill=(255, 255, 0), font=font)
                tiles.append(im.resize((260, int(260 * (y1 - y0) / (x1 - x0)))))
        json.dump({"name": name, "root": [rx, ry], "frames": frames}, open(os.path.join(OUTD, "idle_lines_%s.json" % name), "w", encoding="utf-8"))
        tw, th = tiles[0].size
        cols = 9
        rows = (len(tiles) + cols - 1) // cols
        sh = Image.new("RGB", (tw * cols, th * rows))
        for j, im in enumerate(tiles):
            sh.paste(im, ((j % cols) * tw, (j // cols) * th))
        sh.save(os.path.join(OUTD, "idle_lines_%s_check.png" % name))
        ok = sum(1 for fr in frames if fr["poly"])
        print(name, "帧", len(frames), "有线", ok)


if __name__ == "__main__":
    main()
