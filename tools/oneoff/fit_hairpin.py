# -*- coding: utf-8 -*-
"""出土前段(光柱后 0–0.68 秒)= 对折的发卡(2026-11-13 用户逐张讲解):
  从底往上一条腿 → 顶上折过去 → 另一条腿往下, 头在底的后面; 前几张头还扎在地里(只露出往上那条腿)。
  模型参数(以往上那条腿的长度为 1): 往上腿的仰角与弯 (lp, lc) · 折弯半径 r · 往下腿的水平朝向 dy(0 = 正面 / 画面右, −90 = 身后 / 远离镜头)
  与往下的角度 dp · 往下腿露出的长度 D。
  投影 = 我们游戏的镜头(俯角 51.8°, 正面朝画面右, 侧向 +z 朝镜头): 画面 x = x, 画面 y(向下)= −y·cos + z·sin。不翻转。
  用户的线按「起点离真正的根部标记最近」定方向(根部标记 = 中间那根地上的青条, 画面 (1020, 477))。
输出 .out/ref_illaoi/fit_hairpin.json: 每张 {t, 参数, 残差, 头的世界高度 / 前后}"""
import json
import math
import os
import sys

import numpy as np
from scipy.optimize import minimize

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from idle_match import OUTD, resample  # noqa: E402

CAM = math.radians(51.8)
ROOT_SCR = np.array([1020.0, 477.0])


def hairpin(lp, lc, r, dy, dp, D, n_up=20, n_fold=14, n_dn=14):
    pts = [np.zeros(3)]
    for i in range(n_up):
        p = math.radians(lp + lc * (i + 0.5) / n_up)
        pts.append(pts[-1] + np.array([math.cos(p), math.sin(p), 0.0]) / n_up)
    p_end = math.radians(lp + lc)
    d0 = np.array([math.cos(p_end), math.sin(p_end), 0.0])
    dyr, dpr = math.radians(dy), math.radians(dp)
    d1 = np.array([math.cos(dpr) * math.cos(dyr), -math.sin(dpr), math.cos(dpr) * math.sin(dyr)])
    ang = math.acos(float(np.clip(d0 @ d1, -1, 1)))
    if ang > 1e-4:
        for i in range(n_fold):
            s = (i + 1) / n_fold
            dd = (math.sin((1 - s) * ang) * d0 + math.sin(s * ang) * d1) / math.sin(ang)
            pts.append(pts[-1] + dd * r * ang / n_fold)
    for i in range(n_dn):
        pts.append(pts[-1] + d1 * D / n_dn)
    return np.array(pts)


def screen(P):
    return np.stack([P[:, 0], -P[:, 1] * math.cos(CAM) + P[:, 2] * math.sin(CAM)], 1)


def main():
    d = json.load(open(os.path.join(OUTD, "annot_result.json"), encoding="utf-8"))["per_strike"]["spawn_中间"]
    ## 第 5、6 张用我重标、用户认可的线(从底上去、顶在尖角下面、再下到右下的头); 第 7 张用户说他标的对, 不替换
    rel = json.load(open(os.path.join(OUTD, "my_relabel_spawn.json"), encoding="utf-8"))
    keys = sorted(d, key=float)
    ## 第 5 张用户 11-13 晚说他原来标的对(头在半腰、抵着往上那条腿的后背), 只第 6 张用重标
    for idx in (5,):
        if keys[idx] in rel:
            d[keys[idx]] = {"line": rel[keys[idx]]}
    out = []
    prev = np.array([88.0, 0.0, 0.15, -60.0, 70.0, 0.6])
    for k in sorted(d, key=float):
        t = float(k) - 72.35
        if t > 0.7:
            continue
        a = np.array(d[k]["line"], float)
        if np.hypot(*(a[-1] - ROOT_SCR)) < np.hypot(*(a[0] - ROOT_SCR)):
            a = a[::-1]
        q = resample(a)
        only_up = t < 0.25          # 头还在地里: 用户只标到顶

        def cost(x):
            lp, lc, r, dy, dp, D = x
            P = hairpin(lp, lc, max(r, 0.02), dy, dp, max(D, 0.0))
            if only_up:
                P = P[:21]
            c = float(np.mean(np.linalg.norm(resample(screen(P)) - q, axis=1)))
            head = P[-1]
            pen = 0.0
            if not only_up:
                pen += 0.3 * max(0.0, head[2])               # 头不在底前面(用户: 头在底的后面)
                if t < 0.6:
                    pen += 0.3 * max(0.0, -head[1])          # 0.6 秒前头在地面以上
            pen += 0.02 * float(np.sum(np.abs(x - prev) / np.array([30, 30, 0.2, 60, 40, 0.5])))   # 和上一张别差太多
            ## 身子是软的, 折弯是圆的(用户「不能直接扯折成两半吧？你身体是柔软的呀」): 折弯半径不小于往上腿的 0.22
            pen += 2.0 * max(0.0, 0.22 - r)
            return c + pen
        best = None
        for st in (prev, np.array([88, 0, 0.12, -90, 70, 0.7]), np.array([85, 5, 0.15, -30, 60, 0.6]), np.array([90, -5, 0.1, -120, 80, 0.8])):
            res = minimize(cost, st, method="Powell", options={"maxiter": 6000, "xtol": 0.05, "ftol": 1e-7})
            if best is None or res.fun < best.fun:
                best = res
        x = best.x
        P = hairpin(x[0], x[1], max(x[2], 0.02), x[3], x[4], max(x[5], 0.0))
        resid = float(np.mean(np.linalg.norm(resample(screen(P[:21] if only_up else P)) - q, axis=1)))
        prev = x
        out.append({"t": round(t, 2), "lp": round(x[0], 1), "lc": round(x[1], 1), "r": round(max(x[2], 0.02), 3), "dy": round(x[3], 1), "dp": round(x[4], 1),
                    "D": round(max(x[5], 0.0), 3), "残差": round(resid, 4), "头高": round(float(P[-1][1]), 2), "头前后": round(float(P[-1][2]), 2), "只看往上那条腿": only_up})
        print(out[-1])
    json.dump(out, open(os.path.join(OUTD, "fit_hairpin.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
