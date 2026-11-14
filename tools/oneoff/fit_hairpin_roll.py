# -*- coding: utf-8 -*-
"""出土 0.85–1.18 秒 = 对折往上「滚」开(2026-11-13 用户「第十六针往后应该是全错吧」):
  LoL 这段: 身子越长越高, 头一直卷在顶上的折弯里(0.85 / 1.01 用户的线: 顶在身长 0.58 → 0.71 处), 1.18 秒才完全伸直成 S。
  原来 0.86 秒对折一帧切到关键姿势 ⇒ 顶高一帧 96 → 134 像素、头从垂着翻成朝上。
模型 = 游戏里 TentacleRig._hairpin(整根一条 tanh 弧): 往上段仰角 lp → 折过去后 −dp, 折向水平朝向 my(0 = 正面 / 画面右, 270 = 身后),
  往下段长 D(往上段 = 1); 再整根在「正面 / 上」这个竖直面里(= 画面平面)按身长渐变地倾斜 β = b0 + bl·min(s / sc, 1)(正 = 往后 / 画面左)。
  只在折向那个面里弯的话, 折向朝身后 ⇒ 拟合只能让身子朝镜头倒来凑画面上的高(11-13 第一次拟合就是这样), 画面上的弯要靠 β。
投影 = 我们游戏镜头(渲染日志标定: 画面 x = 60·x, 画面 y = −35.3·y + 45.7·z, 侧向 z 正 = 朝镜头)。不翻转。
输出 .out/ref_illaoi/fit_hairpin_roll.json"""
import json
import math
import os
import sys

import numpy as np
from scipy.optimize import differential_evolution, minimize

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from idle_match import OUTD, resample  # noqa: E402

SEG = 36
ROOT_SCR = np.array([1020.0, 477.0])
## 0.68 秒那一项(游戏里现有的, 用户已看过的前 15 帧到这里为止): lp b0 bl w my dp D
PREV = np.array([100.0, 0.0, 0.0, 0.24, 290.0, 85.0, 1.0, 0.0])
NAMES = ["lp", "b0", "bl", "w", "my", "dp", "D", "cu"]
SCALE = np.array([10, 30, 30, 0.2, 60, 60, 0.5, 60])


def hairpin(lp, b0, bl, w, my, dp, D, cu=0.0):
    w = max(w, 0.04)
    total = 1.0 + max(D, 0.0)
    sc = 1.0 - 0.5 * w
    myr = math.radians(my)
    hdir = np.array([math.cos(myr), 0.0, math.sin(myr)])
    up = np.array([0.0, 1.0, 0.0])
    pts = [np.zeros(3)]
    for i in range(SEG):
        sx = (i + 0.5) / SEG * total
        f = 0.5 * (1.0 + math.tanh((sx - sc) / w))
        ## cu: 往下那段继续往回卷(梢端再转 cu 度; 0.85 秒用户的线是「P」, 头卷回到身子旁边)
        ang = math.radians(lp + (-dp - lp) * f - cu * max(0.0, sx - sc) / max(total - sc, 1e-3))
        d = hdir * math.cos(ang) + up * math.sin(ang)
        b = math.radians(b0 + bl * min(sx / sc, 1.0))
        d = np.array([d[0] * math.cos(b) - d[1] * math.sin(b), d[0] * math.sin(b) + d[1] * math.cos(b), d[2]])
        pts.append(pts[-1] + d / np.linalg.norm(d) * total / SEG)
    return np.array(pts)


def screen(P):
    return np.stack([60.0 * P[:, 0], -35.3 * P[:, 1] + 45.7 * P[:, 2]], 1)


def main():
    d = json.load(open(os.path.join(OUTD, "annot_result.json"), encoding="utf-8"))["per_strike"]["spawn_中间"]
    lines = {}
    for k in d:
        t = round(float(k) - 72.35, 2)
        a = np.array(d[k]["line"], float)
        if np.hypot(*(a[-1] - ROOT_SCR)) < np.hypot(*(a[0] - ROOT_SCR)):
            a = a[::-1]
        a[:, 1] = a[:, 1]
        lines[t] = a
    out = []
    prev = PREV.copy()
    ## 往下段长 D 由用户的线直接量(顶在身长的比例 f ⇒ D = (1 − f) / f): 2D 线反推 D 不定(11-13 三次拟合都卡在同一个 D)
    ## 1.18 秒已经完全伸直(顶 = 梢端) ⇒ D ≈ 0: 对折一直播到 1.18, 在这里交给后面的关键姿势(同一形状接着变, 不在两套姿势之间切)
    D_FIX = {0.85: 0.72, 1.01: 0.41, 1.18: 0.02}
    ## 露出的身长(× 全长): 0.85 = 游戏里现在的 0.837; 之后按用户的线长涨(195 → 224 → 238 像素)
    EXPOSE = {0.85: 0.837, 1.01: 0.92, 1.18: 0.98}
    ## 画面上的长度要和用户的线同比例(11-13: 只比形状时 1.18 拟合成梢端往身后倒, 画面上反而比 1.01 短)
    L_USER = {t: float(np.hypot(*np.diff(lines[t], axis=0).T).sum()) for t in D_FIX}
    s_ref = None
    for t in (0.85, 1.01, 1.18):
        q = resample(lines[t])

        def scr_len(x):
            S = screen(hairpin(*x))
            return float(np.hypot(*np.diff(S, axis=0).T).sum()) * EXPOSE[t] / (1.0 + x[6])

        def cost(x):
            P = hairpin(*x)
            w = x[3]
            D = x[6]
            c = float(np.mean(np.linalg.norm(resample(screen(P)) - q, axis=1)))
            head = P[-1]
            pen = 0.0
            pen += 0.3 * max(0.0, head[2])                      # 头不在底前面(用户「头是在底的这个后面」)
            pen += 0.3 * max(0.0, 0.05 - head[1])               # 头在地面以上
            pen += 2.0 * max(0.0, 0.18 - w)                     # 折弯是软的(「你身体是柔软的呀」)
            pen += 0.5 * max(0.0, -D)
            ## 和上一项别差太多(顺时间连贯)
            pen += 0.002 * float(np.sum(np.abs(x - prev) / SCALE))
            if s_ref is not None:
                pen += 0.05 * abs((scr_len(x) / s_ref) / (L_USER[t] / L_USER[0.85]) - 1.0)
            return c + pen
        ## 全局搜索(Powell 从几个起点出发会卡在局部: 11-13 第一次跑 1.18 残差 0.017), 再局部细化
        ## lp 只许在 90–105(往上段在折向面里只微微后仰, 主要的弯交给 β); my 限在身后(250–330, 用户「头是在底的这个后面」)
        bounds = [(90, 105), (-50, 25), (-30, 80), (0.18, 0.5), (250, 330), (-60, 95), (D_FIX[t], D_FIX[t] + 1e-4), (0.0, 150.0)]
        best = differential_evolution(cost, bounds, seed=7, maxiter=400, popsize=30, tol=1e-9, polish=False)
        best = minimize(cost, best.x, method="Powell", bounds=bounds, options={"maxiter": 20000, "xtol": 0.005, "ftol": 1e-10})
        x = best.x
        P = hairpin(*x)
        resid = float(np.mean(np.linalg.norm(resample(screen(P)) - q, axis=1)))
        S = screen(P)
        it = int(np.argmin(S[:, 1]))
        L = float(np.hypot(*np.diff(S, axis=0).T).sum())
        o = {"t": t}
        for nm, v in zip(NAMES, x):
            o[nm] = round(float(v), 3 if nm in ("w", "D") else 1)
        o.update({"残差": round(resid, 4), "头高": round(float(P[-1][1]), 2), "头前后": round(float(P[-1][2]), 2),
             "顶在身长": round(it / SEG, 2), "画面长": round(L, 1)})
        a = lines[t]
        La = float(np.hypot(*np.diff(a, axis=0).T).sum())
        ita = int(np.argmin(a[:, 1]))
        o["用户顶在身长"] = round(float(np.hypot(*np.diff(a[:ita + 1], axis=0).T).sum()) / La, 2)
        o["用户线长像素"] = round(La, 0)
        if s_ref is None:
            s_ref = scr_len(x)
        o["画面长比"] = round(scr_len(x) / s_ref, 3)
        o["用户长比"] = round(L_USER[t] / L_USER[0.85], 3)
        o["露出"] = EXPOSE[t]
        print(o)
        out.append(o)
        prev = x
    json.dump(out, open(os.path.join(OUTD, "fit_hairpin_roll.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
