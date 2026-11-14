# -*- coding: utf-8 -*-
"""用户手标中线 → 出手关键姿势(2026-11-13)。读 .out/ref_illaoi/annot_result.json(read_annotation.py 的输出)。

防过拟合(用户:「手抖…需要你来防止这种过拟合」):
  ① 每击按「甩直那一帧」对齐(各击贴地时刻估计差 2–3 帧): 梢端沿出手方向的投影 > 0.6 × 身长的第一帧 = 贴地;
  ② 每击在统一时刻网格上按时间插值(不外推超过 1 帧);
  ③ 每个控制点跨击取【圆周】平均(单位向量平均, 差一整圈不算差), 离其余各击的平均 > 45° 的那一击剔除并列出;
  ④ 沿身长展开成连续角度; ⑤ 时间上 1:2:1 顺一遍(首尾不动)。
用法: python tools/oneoff/annot_poses.py  → 打印 GDScript 可贴的 STRIKE_T / STRIKE_P
"""
import json
import math
import os

import numpy as np

OUTD = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), ".out", "ref_illaoi")
GRID = [0.80, 0.72, 0.60, 0.50, 0.40, 0.33, 0.26, 0.20, 0.15, 0.133, 0.117, 0.100, 0.083, 0.067, 0.050, 0.033, 0.017]
OUT_DEG = 45.0


def unwrap_time(seq):
    out = [list(seq[0])]
    for c in seq[1:]:
        row = []
        for j, v in enumerate(c):
            pv = out[-1][j]
            while v - pv > 180:
                v -= 360
            while pv - v > 180:
                v += 360
            row.append(v)
        out.append(row)
    return out


def main():
    d = json.load(open(os.path.join(OUTD, "annot_result.json"), encoding="utf-8"))["per_strike"]
    per = {}
    for T, s in d.items():
        ks = sorted(s, key=lambda k: -float(k))
        ## 11-13 用户的线显示: 刀光出来时本体多半还盘在根部(45.2 / 62.8 到 0.000 帧还是圈), 晚 1–2 帧才甩直 ⇒
        ##   不按「甩直那一帧」对齐, 直接用刀光时刻(= 我们的伤害时刻)当 0; 0.000 那帧各击有直有圈, 不进网格
        lash = 0.0
        taus = [float(k) - lash for k in ks]
        ch = unwrap_time([s[k]["pitch"] for k in ks])
        per[T] = (taus, ch)
        print("击 %s: 甩直那一帧 τ=%.3f, 标了 %d 帧(对齐后 τ %.3f → %.3f)" % (T, lash, len(ks), taus[0], taus[-1]))
    keys, outl = [], []
    for g in GRID:
        vals = {}
        for T, (taus, ch) in per.items():
            ## 网格点落在已标两帧之间才取(或离最近一帧不超过 1 帧)
            for i in range(len(taus) - 1):
                if taus[i] >= g >= taus[i + 1]:
                    w = (taus[i] - g) / max(taus[i] - taus[i + 1], 1e-6)
                    vals[T] = [ch[i][j] * (1 - w) + ch[i + 1][j] * w for j in range(6)]
                    break
            else:
                k = int(np.argmin([abs(t - g) for t in taus]))
                if abs(taus[k] - g) <= 1.0 / 60.0 + 1e-6:
                    vals[T] = ch[k]
        if not vals:
            continue
        row = []
        for j in range(6):
            angs = {T: math.radians(v[j]) for T, v in vals.items()}
            use = dict(angs)
            if len(angs) >= 3:
                for T, a in angs.items():
                    oth = [b for T2, b in angs.items() if T2 != T]
                    mc = math.atan2(np.mean(np.sin(oth)), np.mean(np.cos(oth)))
                    dev = abs(math.degrees(math.atan2(math.sin(a - mc), math.cos(a - mc))))
                    if dev > OUT_DEG:
                        use.pop(T, None)
                        outl.append((g, T, j, round(dev)))
            if not use:
                use = angs
            mean = math.degrees(math.atan2(np.mean(np.sin(list(use.values()))), np.mean(np.cos(list(use.values())))))
            row.append(mean)
        ## 沿身长展开: 根部取 [-90, 270), 往梢逐个取离上一个最近的
        r0 = row[0] % 360.0
        if r0 >= 270:
            r0 -= 360
        out = [r0]
        for v in row[1:]:
            pv = out[-1]
            while v - pv > 180:
                v -= 360
            while pv - v > 180:
                v += 360
            out.append(v)
        keys.append((g, out, len(vals)))
    ## 时间上展开 + 1:2:1
    chain = unwrap_time([k[1] for k in keys])
    sm = []
    for i in range(len(chain)):
        if i == 0 or i == len(chain) - 1:
            sm.append(chain[i])
            continue
        sm.append([(chain[i - 1][j] + 2 * chain[i][j] + chain[i + 1][j]) / 4 for j in range(6)])
    print("\n剔除的离群(时刻, 击, 控制点, 偏差°):", outl)
    print("\nconst STRIKE_T := [0.86, " + ", ".join("%.3f" % k[0] for k in keys) + ", 0.0]")
    print("const STRIKE_P := [\n\tnull,")
    for (g, _, n), r in zip(keys, sm):
        print("\t[%s],   # %.3f (%d 击)" % (", ".join("%.1f" % v for v in r), g, n))
    json.dump({"keys": [[k[0], r, k[2]] for k, r in zip(keys, sm)], "outliers": outl}, open(os.path.join(OUTD, "annot_poses.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
