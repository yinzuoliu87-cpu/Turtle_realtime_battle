# -*- coding: utf-8 -*-
"""量尺 → 关键姿势: 用中间那根 74–88 s 每秒一张的干净中心线(用户手标 + 我标好的), 反推每一秒的姿势(2026-11-13)。

假设触手在一个竖直平面里(平面朝向 φ 全段共用, 网格搜), LoL 镜头俯角 56°; 每一帧拟合 6 个控制点的俯仰角(沿身长 Catmull-Rom),
让投影后的形状(按弧长归一)和那条线重合。只输出每秒一个关键姿势(不播描帧), 结果 .out/ref_illaoi/fit_idle_keys.json。
"""
import json
import math
import os
import sys

import numpy as np
from scipy.optimize import minimize

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from idle_match import OUTD, lol_lines, resample  # noqa: E402

CAM = math.radians(56.0)
U6 = np.array([0.05, 0.25, 0.45, 0.65, 0.85, 1.0])
SEG = 36


def chain_pts(p6, phi):
    u = (np.arange(SEG) + 0.5) / SEG
    ## 沿身长 Catmull-Rom(端点外推)
    ang = np.interp(u, U6, p6)
    c = np.array(p6, float)
    out = []
    for uu in u:
        if uu <= U6[0]:
            out.append(c[0]); continue
        j = min(int(np.searchsorted(U6, uu)) - 1, 4)
        s = (uu - U6[j]) / (U6[j + 1] - U6[j])
        p0, p1, p2, p3 = c[max(j - 1, 0)], c[j], c[j + 1], c[min(j + 2, 5)]
        out.append(0.5 * (2 * p1 + (p2 - p0) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s * s + (-p0 + 3 * p1 - 3 * p2 + p3) * s ** 3))
    a = np.radians(out)
    f = np.array([math.cos(phi), 0.0, math.sin(phi)])
    d = np.cos(a)[:, None] * f[None] + np.sin(a)[:, None] * np.array([0, 1.0, 0])[None]
    pts = np.vstack([[0, 0, 0], np.cumsum(d, axis=0)])
    sx = pts[:, 0]
    sy = -(pts[:, 1] * math.cos(CAM)) + (-pts[:, 2]) * math.sin(CAM)
    return np.stack([sx, sy], 1)


def fit_one(q, phi, init):
    def cost(p):
        r = resample(chain_pts(p, phi))
        return float(np.mean(np.linalg.norm(r - q, axis=1))) + 1e-4 * float(np.sum(np.diff(p) ** 2)) / 100.0
    best = None
    for st in init:
        res = minimize(cost, st, method="Powell", options={"maxiter": 4000, "xtol": 0.1, "ftol": 1e-6})
        if best is None or res.fun < best.fun:
            best = res
    return best


def main():
    L = [(t, resample(pl)) for seg, t, pl, src in lol_lines() if seg == "中间" and 74.0 <= t <= 91.0]
    L.sort()
    print("中间那根可用帧:", [t for t, _ in L])
    starts = [np.array(v, float) for v in ([90] * 6, [100, 120, 150, 180, 210, 240], [80, 60, 40, 20, 0, -20], [96, 111, 88, 112, 165, 198], [120, 90, 60, 30, 0, -30])]
    best_phi, best_tot, best_fits = None, 1e9, None
    for phi_deg in ([int(a) for a in sys.argv[1:]] or range(0, 180, 15)):
        phi = math.radians(phi_deg)
        tot, fits = 0.0, []
        prev = None
        for t, q in L:
            init = starts + ([prev] if prev is not None else [])
            r = fit_one(q, phi, init)
            fits.append((t, r.x, r.fun))
            prev = r.x
            tot += r.fun
        print("φ=%3d  平均残差 %.4f" % (phi_deg, tot / len(L)))
        if tot < best_tot:
            best_phi, best_tot, best_fits = phi_deg, tot, fits
    print("取 φ =", best_phi)
    out = [{"t": round(t - 74.0, 2), "pitch": [round(float(v), 1) for v in x], "res": round(float(f), 4)} for t, x, f in best_fits]
    json.dump({"phi": best_phi, "keys": out}, open(os.path.join(OUTD, "fit_idle_keys.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for k in out:
        print(k)


if __name__ == "__main__":
    main()
