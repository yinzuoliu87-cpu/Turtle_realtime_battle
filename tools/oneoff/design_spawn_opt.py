# -*- coding: utf-8 -*-
"""出土第 20–22 帧(光柱后 1.18 / 1.35 / 1.51 秒)三个姿势自己设计(2026-11-13 夜用户「二十、二十一、二十二针…在墙里面看不到…你得设计这三针，好接到二十三针」)。
两头锚死: 第 19 帧(1.10, 对折段) 与 第 23 帧(1.68, 手标反推); 中间三个姿势让离线模拟器(spawn_sim.py, 和游戏逐帧对过)搜:
  · 动得匀: 每帧位移的变化(加速度)小, 一帧最大位移不超过约 15 像素(SIDE_ZOOM 3.3)
  · 先长高: 1.15–1.35 秒最高点在待机高的 1.2–1.35 倍(LoL 1.15 秒露在墙外那截已有 1.2 倍)
  · 一路走: 头 1.18 → 1.51 一直往左、1.35 以后一直往下, 顶高过了最高点就不再回升(不来回、不停一下又走)
  · 1.18 那张是对折段的末项(钩全部打开); 1.35 / 1.51 是关键姿势(画面平面角 6 个 + 往身后偏的侧偏 1 个)
输出: 打印最优参数(直接抄进 tentacle_rig.gd) + 模拟量"""
import math
import sys

import numpy as np
from scipy.optimize import differential_evolution, minimize

sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import spawn_sim as S  # noqa: E402

IDLE_TOP = 182.0
T0 = S.load_tables()
## 第 16–19 帧用户这一轮没说有问题: 1.01 / 1.10 的折向用上一版(用户看过的)
iT = T0["HP_T"].index(1.01); T0["HP_MY"][iT] = 268.0; T0["HP_MY"][iT + 1] = 255.0
## 11-14 用户「中间部分有点不自然，像是硬给它扭的一样」: 量出来根部来回摆(75 → 51 → 65 → 54 → 67°)、1.01–1.10 根部 0.17 秒倾 27°
##   ⇒ 根部倾斜 b0 放到 0.85–1.18 慢慢转, 折向不来回; 1.88 那张根部 38.4 → 64(手标反推的根部偏得太多, 其余不动)
for (nm, tt, v) in (("HP_B0", 0.85, -3.0), ("HP_B0", 0.93, -7.0), ("HP_B0", 1.01, -13.0), ("HP_B0", 1.1, -19.5),
                    ("HP_MY", 1.01, 275.0), ("HP_MY", 1.1, 269.0)):
    T0[nm][T0["HP_T"].index(tt)] = v
T0["GROW_KEYS"] = [(tk, ([64.0] + list(p6[1:]) if abs(tk - 1.88) < 1e-6 else p6), y6) for (tk, p6, y6) in T0["GROW_KEYS"]]
I118 = T0["HP_T"].index(1.18)
HP_NAMES = ["HP_LP", "HP_R", "HP_DP", "HP_MY", "HP_D", "HP_CU", "HP_B0", "HP_BL"]
EXPOSE_118 = 0.98 * 0.745     # 1.18 露出身长(× 全长)


def apply(x):
    T = {k: (list(v) if isinstance(v, list) else v) for k, v in T0.items()}
    for j, nm in enumerate(HP_NAMES):
        T[nm][I118] = float(x[j])
    D = max(float(x[4]), 0.0)
    T["HP_HN"][I118] = EXPOSE_118 / ((1.0 + D) * T["HP_HMAX"])
    p135 = list(x[8:14]); y135 = float(x[14]); p151 = list(x[15:21]); y151 = float(x[21])
    keys = []
    for (tk, p6, y6) in T0["GROW_KEYS"]:
        if abs(tk - 1.35) < 1e-6:
            keys.append((tk, p135, [0, y135 * 0.2, y135 * 0.5, y135 * 0.8, y135, y135]))
        elif abs(tk - 1.51) < 1e-6:
            keys.append((tk, p151, [0, y151 * 0.2, y151 * 0.5, y151 * 0.8, y151, y151]))
        else:
            keys.append((tk, p6, y6))
    T["GROW_KEYS"] = keys
    return T


def metrics(T, t0=1.06, t1=2.0):
    rows = S.simulate(T, t0, t1)
    Ss = np.array([r[2] for r in rows])
    disp = np.max(np.linalg.norm(Ss[1:] - Ss[:-1], axis=2), axis=1)
    acc = np.mean(np.linalg.norm(Ss[2:] - 2 * Ss[1:-1] + Ss[:-2], axis=2) ** 2, axis=1)
    base = Ss[:, 0, :]
    top = base[:, 1] - Ss[:, :, 1].min(axis=1)
    hx = Ss[:, -1, 0] - base[:, 0]; hy = base[:, 1] - Ss[:, -1, 1]
    ts = np.array([r[0] for r in rows])
    ## 下半截(前 8 节)的方向角速度(°/秒) —— 根要稳
    Dd = [np.diff(r[1], axis=0) for r in rows]
    Dd = [d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9) for d in Dd]
    roots = np.array([np.degrees(np.arccos(np.clip(np.sum(Dd[k][:8] * Dd[k - 1][:8], axis=1), -1, 1))).mean() * 60.0 for k in range(1, len(rows))])
    head0 = np.array([math.degrees(math.atan2(d[:4].mean(0)[1], d[:4].mean(0)[0])) for d in Dd])
    ## 画面上沿身长每节的转角(度): 折角 = 某一节转得特别多; 梢端 S = 最后几节转向来回变号
    turn = []
    for r in rows:
        d = np.diff(r[2], axis=0)
        a = np.degrees(np.unwrap(np.arctan2(d[:, 1], d[:, 0])))
        turn.append(np.diff(a))
    return ts, disp, acc, top, hx, hy, np.array(turn), roots, head0


def cost(x):
    T = apply(x)
    ts, disp, acc, top, hx, hy, turn, roots, head0 = metrics(T)
    c = float(np.sum(acc)) / 200.0
    ## 根要稳: 下半截角速度超过 45°/秒罚; 根部朝向不来回(角速度变号)
    c += 0.002 * float(np.sum(np.maximum(0.0, roots - 45.0) ** 2))
    dh = np.diff(head0)
    c += 0.5 * float(np.sum(np.maximum(0.0, -dh[1:] * dh[:-1])))
    ## 身子弯得顺: 每节转角不超过 14°(36 节), 相邻两节转角差不大(没有折角)
    c += 0.002 * float(np.sum(np.maximum(0.0, np.abs(turn) - 14.0) ** 2))
    c += 0.0005 * float(np.sum(np.diff(turn, axis=1) ** 2))
    ## 梢端最后 8 节不来回弯(转角变号)
    tip = turn[:, -8:]
    c += 0.002 * float(np.sum(np.maximum(0.0, -tip[:, 1:] * tip[:, :-1])))
    c += 0.05 * float(np.sum(np.maximum(0.0, disp - 14.0) ** 2))
    ## 速度不要忽快忽慢(停一下又走): 相邻帧位移比
    c += 0.5 * float(np.sum(np.maximum(0.0, np.abs(np.diff(disp)) - 3.0) ** 2)) / 50.0
    win = (ts >= 1.15) & (ts <= 1.35)
    pk = float(top[win].max()) / IDLE_TOP
    c += 40.0 * (max(0.0, 1.2 - pk) ** 2 + max(0.0, pk - 1.35) ** 2)
    ## 过了最高点顶高不再回升
    ip = int(np.argmax(top))
    c += 0.01 * float(np.sum(np.maximum(0.0, np.diff(top[ip:])) ** 2))
    ## 头: 1.18 → 1.51 一直往左; 1.35 → 1.68 一直往下
    a = (ts >= 1.18) & (ts <= 1.51)
    c += 0.01 * float(np.sum(np.maximum(0.0, np.diff(hx[a])) ** 2))
    b = (ts >= 1.35) & (ts <= 1.68)
    c += 0.01 * float(np.sum(np.maximum(0.0, np.diff(hy[b])) ** 2))
    return c


X0 = [92.3, 0.2, -80.0, 255.0, 0.0, 0.0, -30.0, 60.0,
      63, 79, 103, 145, 178, 198, 0.0,
      64, 78, 105, 182, 230, 245, 0.0]
BOUNDS = [(85, 100), (0.15, 0.5), (-95, 60), (170, 300), (0.0, 0.3), (0, 80), (-50, 0), (0, 90),
          (58, 72), (65, 95), (85, 125), (100, 200), (110, 240), (110, 250), (0, 60),
          (58, 72), (65, 95), (85, 125), (120, 210), (150, 260), (170, 280), (0, 60)]

if __name__ == "__main__":
    print("起点 cost %.3f" % cost(X0))
    import os
    x_start = list(np.load(".out/tent_design/_opt_x.npy")) if os.path.exists(".out/tent_design/_opt_x.npy") else X0
    x_start[8] = min(max(x_start[8], 58), 72); x_start[15] = min(max(x_start[15], 58), 72)
    print("上一轮结果在新目标下 cost %.3f" % cost(x_start))
    r = differential_evolution(cost, BOUNDS, x0=x_start, seed=3, maxiter=60, popsize=12, tol=1e-6, polish=False, workers=1)
    r = minimize(cost, r.x, method="Powell", bounds=BOUNDS, options={"maxiter": 3000, "xtol": 0.05, "ftol": 1e-6})
    x = r.x
    print("最优 cost %.3f" % r.fun)
    for j, nm in enumerate(HP_NAMES):
        print("  1.18 %s = %.2f" % (nm, x[j]))
    T = apply(x)
    print("  1.18 HP_HN = %.3f" % T["HP_HN"][I118])
    print("  1.35 p6 = %s  侧偏 %.1f" % ([round(v, 1) for v in x[8:14]], x[14]))
    print("  1.51 p6 = %s  侧偏 %.1f" % ([round(v, 1) for v in x[15:21]], x[21]))
    ts, disp, acc, top, hx, hy, turn, roots, head0 = metrics(T, 0.9, 2.6)
    print("下半截角速度 最大 %.0f°/秒  根部朝向 %s" % (roots.max(), " ".join("%.0f" % head0[int(round((tt - 0.9) * 60))] for tt in (1.0, 1.1, 1.2, 1.35, 1.5, 1.68, 1.88, 2.2, 2.6))))
    print("一帧最大位移 %.1f @ %.3f   最高 %.2f × 待机 @ %.2f" % (disp.max(), ts[1 + int(np.argmax(disp))], top.max() / IDLE_TOP, ts[int(np.argmax(top))]))
    for tt in (1.10, 1.18, 1.27, 1.35, 1.43, 1.51, 1.60, 1.68):
        k = int(round((tt - 0.9) * 60))
        print("  %.2f 顶高 %4.0f 头 (%+4.0f, %+4.0f)" % (tt, top[k], hx[k], hy[k]))
    np.save(".out/tent_design/_opt_x2.npy", x)
