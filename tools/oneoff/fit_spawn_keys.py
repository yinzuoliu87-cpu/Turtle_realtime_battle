# -*- coding: utf-8 -*-
"""出土卷开的关键姿势: 用户手标两次出土(中间 / 墙根)光柱后 0.7–1.9 秒的中心线, 照 fit_idle_keys 的办法反推每一刻的姿势(2026-11-13)。"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fit_idle_keys import fit_one  # noqa: E402
from idle_match import OUTD, resample  # noqa: E402


def main():
    ar = json.load(open(os.path.join(OUTD, "annot_result.json"), encoding="utf-8"))["per_strike"]
    out = {}
    for nm in ("中间", "墙根"):
        d = ar.get("spawn_" + nm, {})
        T0 = 72.35 if nm == "中间" else 19.95
        L = sorted((float(t) - T0, resample(np.array(v["line"]))) for t, v in d.items() if "line" in v)
        starts = [np.array(v, float) for v in ([90] * 6, [90, 95, 110, 160, 230, 290], [70, 60, 40, 10, -40, -100], [100, 120, 150, 200, 260, 320])]
        best = None
        for phi_deg in range(0, 180, 30):
            phi = math.radians(phi_deg)
            tot, fits, prev = 0.0, [], None
            for t, q in L:
                r = fit_one(q, phi, starts + ([prev] if prev is not None else []))
                fits.append((round(t, 2), [round(float(x), 1) for x in r.x], round(float(r.fun), 4)))
                prev = r.x
                tot += r.fun
            if best is None or tot < best[0]:
                best = (tot, phi_deg, fits)
        out[nm] = {"phi": best[1], "keys": best[2]}
        print(nm, "φ", best[1], "平均残差 %.4f" % (best[0] / max(len(L), 1)))
        for k in best[2]:
            print("   ", k)
    json.dump(out, open(os.path.join(OUTD, "fit_spawn_keys.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
