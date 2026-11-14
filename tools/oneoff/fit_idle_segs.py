# -*- coding: utf-8 -*-
"""其余几根待机(左上 / 墙根 22–28 / 右上 13–17)的关键姿势: 用标注线(用户手标 + 我标好逐张看过的)反推, 同 fit_idle_keys(2026-11-13)。
输出 .out/ref_illaoi/fit_idle_segs.json: {名字: {phi, keys:[(相对秒, 6 控制点俯仰)]}}"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fit_idle_keys import fit_one  # noqa: E402
from idle_match import OUTD, lol_lines, resample  # noqa: E402

SEGS = [("左上", "左上", 73.0, 91.0), ("墙根", "22-30秒_墙根", 22.0, 27.6), ("右上", "12.5-17秒_右上", 13.0, 17.1)]


def main():
    allL = lol_lines()
    out = {}
    for name, seg, t0, t1 in SEGS:
        L = sorted((t, resample(pl)) for s, t, pl, src in allL if s == seg and t0 <= t <= t1)
        L = [(t, q) for t, q in L if q is not None]
        starts = [np.array(v, float) for v in ([90] * 6, [100, 120, 150, 180, 210, 240], [80, 60, 40, 20, 0, -20], [60, 40, 20, 10, 20, 60], [120, 150, 190, 230, 270, 300])]
        best = None
        for phi_deg in range(0, 180, 30):
            phi = math.radians(phi_deg)
            tot, fits, prev = 0.0, [], None
            for t, q in L:
                r = fit_one(q, phi, starts + ([prev] if prev is not None else []))
                fits.append((round(t - t0, 2), [round(float(x), 1) for x in r.x], round(float(r.fun), 4)))
                prev = r.x
                tot += r.fun
            if best is None or tot < best[0]:
                best = (tot, phi_deg, fits)
        out[name] = {"phi": best[1], "t0": t0, "keys": best[2]}
        print("%s: %d 张, φ=%d, 平均残差 %.4f, 最大 %.4f" % (name, len(L), best[1], best[0] / len(L), max(f[2] for f in best[2])))
    json.dump(out, open(os.path.join(OUTD, "fit_idle_segs.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
