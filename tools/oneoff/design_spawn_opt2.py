# -*- coding: utf-8 -*-
"""出土中段(光柱后 0.93–1.68 秒)头的路线重做(2026-11-14 用户「中间可能太快了，中间转太猛了，中间把这个头部往上抽的时候太猛了」)。
量出来: 0.97–1.13 秒头 0.17 秒里从 76 升到 238 像素(一帧最快往上 24 像素), 1.13–1.20 秒在顶上几乎停住, 再往左拱 = 「往上猛抽 + 急停」。
做法: 1.01 / 1.10 / 1.18(对折段)与 1.35 / 1.51(关键姿势)五张一起搜, 锚死 0.85 / 0.93 的「P」和 1.68 的拱:
  · 头走一条连贯的弧: 每帧位移不超过约 13 像素, 速度变化小, 中途不停(1.0–1.6 秒每帧至少约 5 像素)
  · 根要稳(下半截角速度、根部朝向不来回)、身子弯得顺、最高点待机 1.15–1.35 倍
起点 = 上一轮(design_spawn_opt.py 的 _opt_x2)。输出 .out/tent_design/_opt_x3.npy"""
import math
import os
import sys

import numpy as np
from scipy.optimize import differential_evolution, minimize

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spawn_sim as S  # noqa: E402

IDLE_TOP = 182.0
T0 = S.load_tables()
HT = T0["HP_T"]
I101, I110, I118 = HT.index(1.01), HT.index(1.1), HT.index(1.18)
HP_NAMES = ["HP_LP", "HP_R", "HP_DP", "HP_MY", "HP_D", "HP_CU", "HP_B0", "HP_BL"]
EXPOSE = {I101: 0.92 * 0.745, I110: 0.95 * 0.745, I118: 0.98 * 0.745}
NHP = len(HP_NAMES)


def x_from_tables(T):
    x = []
    for idx in (I101, I110, I118):
        x += [T[nm][idx] for nm in HP_NAMES]
    for tk in (1.35, 1.51):
        p6, y6 = [(p, y) for (t, p, y) in T["GROW_KEYS"] if abs(t - tk) < 1e-6][0]
        x += list(p6) + [y6[4]]
    return np.array(x, float)


def apply(x):
    T = {k: (list(v) if isinstance(v, list) else v) for k, v in T0.items()}
    for n, idx in enumerate((I101, I110, I118)):
        for j, nm in enumerate(HP_NAMES):
            T[nm][idx] = float(x[n * NHP + j])
        D = max(T["HP_D"][idx], 0.0)
        T["HP_HN"][idx] = EXPOSE[idx] / ((1.0 + D) * T["HP_HMAX"])
    o = 3 * NHP
    p135 = list(x[o:o + 6]); y135 = float(x[o + 6]); p151 = list(x[o + 7:o + 13]); y151 = float(x[o + 13])
    prof = lambda Y: [0, Y * 0.2, Y * 0.5, Y * 0.8, Y, Y]
    keys = []
    for (tk, p6, y6) in T0["GROW_KEYS"]:
        if abs(tk - 1.35) < 1e-6:
            keys.append((tk, p135, prof(y135)))
        elif abs(tk - 1.51) < 1e-6:
            keys.append((tk, p151, prof(y151)))
        else:
            keys.append((tk, p6, y6))
    T["GROW_KEYS"] = keys
    return T


def metrics(T, t0=0.90, t1=1.90):
    rows = S.simulate(T, t0, t1)
    ts = np.array([r[0] for r in rows])
    Ss = np.array([r[2] for r in rows])
    disp = np.max(np.linalg.norm(Ss[1:] - Ss[:-1], axis=2), axis=1)
    head = Ss[:, -1, :]
    hsp = np.linalg.norm(head[1:] - head[:-1], axis=1)
    base = Ss[:, 0, :]
    top = base[:, 1] - Ss[:, :, 1].min(axis=1)
    Dd = [np.diff(r[1], axis=0) for r in rows]
    Dd = [d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9) for d in Dd]
    roots = np.array([np.degrees(np.arccos(np.clip(np.sum(Dd[k][:8] * Dd[k - 1][:8], axis=1), -1, 1))).mean() * 60.0 for k in range(1, len(rows))])
    head0 = np.array([math.degrees(math.atan2(d[:4].mean(0)[1], d[:4].mean(0)[0])) for d in Dd])
    turn = []
    for r in rows:
        d = np.diff(r[2], axis=0)
        a = np.degrees(np.unwrap(np.arctan2(d[:, 1], d[:, 0])))
        turn.append(np.diff(a))
    return ts, disp, hsp, top, roots, head0, np.array(turn)


def cost(x):
    T = apply(x)
    ts, disp, hsp, top, roots, head0, turn = metrics(T)
    t1 = ts[1:]
    c = 0.0
    ## 头匀速、不猛: 每帧不超过 13 像素, 相邻帧速度差小, 1.0–1.6 秒不停
    c += 0.05 * float(np.sum(np.maximum(0.0, hsp - 13.0) ** 2))
    c += 0.02 * float(np.sum(np.diff(hsp) ** 2))
    mid = (t1 >= 1.0) & (t1 <= 1.6)
    c += 0.1 * float(np.sum(np.maximum(0.0, 5.0 - hsp[mid]) ** 2))
    ## 整根也不猛
    c += 0.05 * float(np.sum(np.maximum(0.0, disp - 15.0) ** 2))
    ## 根要稳
    c += 0.002 * float(np.sum(np.maximum(0.0, roots - 45.0) ** 2))
    dh = np.diff(head0)
    c += 0.5 * float(np.sum(np.maximum(0.0, -dh[1:] * dh[:-1])))
    ## 身子弯得顺
    c += 0.002 * float(np.sum(np.maximum(0.0, np.abs(turn) - 14.0) ** 2))
    c += 0.0005 * float(np.sum(np.diff(turn, axis=1) ** 2))
    tip = turn[:, -8:]
    c += 0.002 * float(np.sum(np.maximum(0.0, -tip[:, 1:] * tip[:, :-1])))
    ## 先长高: 1.1–1.45 秒最高点在待机 1.15–1.35 倍
    win = (ts >= 1.1) & (ts <= 1.45)
    pk = float(top[win].max()) / IDLE_TOP
    c += 40.0 * (max(0.0, 1.15 - pk) ** 2 + max(0.0, pk - 1.35) ** 2)
    return c


B_HP = [(85, 105), (0.15, 0.55), (-95, 95), (240, 300), (0.0, 0.8), (0, 160), (-35, 5), (0, 90)]
BOUNDS = B_HP * 3 + [(58, 75), (60, 100), (80, 130), (100, 220), (110, 250), (110, 260), (0, 70),
                     (58, 75), (60, 100), (80, 130), (120, 230), (150, 265), (170, 285), (0, 70)]

if __name__ == "__main__":
    x0 = x_from_tables(T0)
    x0 = np.array([min(max(v, lo), hi) for v, (lo, hi) in zip(x0, BOUNDS)])
    print("现在 cost %.2f" % cost(x0))
    ts, disp, hsp, top, roots, head0, turn = metrics(apply(x0))
    print("现在: 头每帧最快 %.1f @ %.3f  整根一帧最快 %.1f" % (hsp.max(), ts[1 + int(np.argmax(hsp))], disp.max()))
    r = differential_evolution(cost, BOUNDS, x0=x0, seed=5, maxiter=70, popsize=10, tol=1e-7, polish=False)
    r = minimize(cost, r.x, method="Powell", bounds=BOUNDS, options={"maxiter": 4000, "xtol": 0.05, "ftol": 1e-7})
    x = r.x
    np.save(".out/tent_design/_opt_x3.npy", x)
    print("最优 cost %.2f" % r.fun)
    T = apply(x)
    ts, disp, hsp, top, roots, head0, turn = metrics(T)
    print("头每帧最快 %.1f @ %.3f  1.0–1.6 最慢 %.1f  整根一帧最快 %.1f  下半截最快 %.0f°/秒  最高 %.2f × 待机" % (
        hsp.max(), ts[1 + int(np.argmax(hsp))], hsp[(ts[1:] >= 1.0) & (ts[1:] <= 1.6)].min(), disp.max(), roots.max(), top.max() / IDLE_TOP))
    print("头速度(每 2 帧):", " ".join("%.0f" % v for v in hsp[::2]))
    for n, idx in enumerate((I101, I110, I118)):
        print("  %.2f " % HT[idx] + " ".join("%s=%.2f" % (nm, x[n * NHP + j]) for j, nm in enumerate(HP_NAMES)) + " HN=%.3f" % T["HP_HN"][idx])
    o = 3 * NHP
    print("  1.35 p6=%s 侧偏 %.1f" % ([round(v, 1) for v in x[o:o + 6]], x[o + 6]))
    print("  1.51 p6=%s 侧偏 %.1f" % ([round(v, 1) for v in x[o + 7:o + 13]], x[o + 13]))
