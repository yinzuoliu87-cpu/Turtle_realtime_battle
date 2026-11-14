# -*- coding: utf-8 -*-
"""出土关键姿势(第二版, 2026-11-13): 顺着时间一张接一张拟合, 加「和上一张不要差太多」的约束 ⇒ 梢端小钩不会一张往前一张往后乱翻。
平面朝向 φ 全段共用(网格搜)。只拟合中间那根(墙根那根作核对)。"""
import json
import math
import os
import sys

import numpy as np
from scipy.optimize import minimize

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fit_idle_keys import chain_pts  # noqa: E402
from idle_match import OUTD, resample  # noqa: E402

LAM = 0.02   # 每差 100° 加的代价(身长比)
BEND = 0.004  # 整根每弯 100° 加的代价


def fit_seq(L, phi):
    prev = np.array([95.0] * 6)
    out, tot = [], 0.0
    for t, q in L:
        def cost(p):
            r = resample(chain_pts(p, phi))
            ## 第三项: 弯得越少越好(同一条 2D 线, 弯折少的那种 3D 姿势优先) —— 11-13 用户看出尖芽「头是微微往下」, 之前的反推挑了大折
            return (float(np.mean(np.linalg.norm(r - q, axis=1))) + LAM * float(np.mean(np.abs(p - prev))) / 100.0
                    + BEND * float(np.sum(np.abs(np.diff(p)))) / 100.0)
        best = None
        for st in (prev, np.array([95.0] * 6), prev + np.array([0, 0, 0, 0, 60, 90]), prev - np.array([0, 0, 0, 0, 60, 90])):
            r = minimize(cost, st, method="Powell", options={"maxiter": 4000, "xtol": 0.1, "ftol": 1e-7})
            if best is None or r.fun < best.fun:
                best = r
        prev = best.x
        res = float(np.mean(np.linalg.norm(resample(chain_pts(best.x, phi)) - q, axis=1)))
        out.append((round(t, 2), [round(float(v), 1) for v in best.x], round(res, 4)))
        tot += res
    return tot / len(L), out


def main():
    ar = json.load(open(os.path.join(OUTD, "annot_result.json"), encoding="utf-8"))["per_strike"]
    res = {}
    for nm, t0 in (("中间", 72.35), ("墙根", 19.95)):
        d = ar["spawn_" + nm]
        L = sorted((float(t) - t0, resample(np.array(v["line"]))) for t, v in d.items() if "line" in v)
        best = None
        for phi_deg in ([int(a) for a in sys.argv[1:]] or range(0, 180, 30)):
            m, out = fit_seq(L, math.radians(phi_deg))
            if best is None or m < best[0]:
                best = (m, phi_deg, out)
        res[nm] = {"phi": best[1], "keys": best[2]}
        print(nm, "φ", best[1], "平均残差 %.4f" % best[0])
        for k in best[2]:
            print("   ", k)
    json.dump(res, open(os.path.join(OUTD, "fit_spawn_keys2.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
