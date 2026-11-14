# -*- coding: utf-8 -*-
"""待机动画规律研究(2026-11-13 用户「从中学习他的动画，去自创」)。只做量尺, 输出 .out/ref_illaoi/idle_study.json + 图。

数据: 三根(左上 / 中间 / 右边)69–94 s 每 0.25 s 的自动中心线(idle_lines.py), 先拿同一时刻的手标 / 我核过的线校准,
  偏差大的帧剔掉。全部在画面坐标里量, 每根按自己的平均身长归一(只比形状和节奏, 不比大小)。
量: ① 动的快慢(相邻帧形状变化 / 秒)与停顿占比 ② 动一阵停一阵的节奏 ③ 弯曲沿身体传递: 根部方向与梢部方向变化的时间差
    ④ 卷曲程度(总转角)的分布与变化 ⑤ 姿势种类(按形状聚类)与占比、相互之间怎么转。
"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from idle_match import OUTD, lol_lines, resample  # noqa: E402

DT = 0.25


def load_dense(name):
    d = json.load(open(os.path.join(OUTD, "idle_lines_%s.json" % name), encoding="utf-8"))
    out = {}
    for fr in d["frames"]:
        if fr["poly"] and len(fr["poly"]) > 8:
            out[round(fr["t"], 2)] = np.array(fr["poly"])
    return out


def shape(pl):
    """按弧长取 20 点; 返回 (归一形状, 弧长, 各段方向角(度, 沿身长展开), 总转角)。"""
    pl = np.asarray(pl, float)
    seg = np.hypot(*np.diff(pl, axis=0).T)
    L = float(seg.sum())
    q = resample(pl)
    d = np.diff(q, axis=0)
    a = np.degrees(np.arctan2(-d[:, 1], d[:, 0]))
    a = np.degrees(np.unwrap(np.radians(a)))
    return q, L, a, float(a[-1] - a[0])


def main():
    ann = {}
    for seg, t, pl, src in lol_lines():
        ann[(seg, round(t, 2))] = pl
    res = {}
    for name in ("左上", "中间", "右边"):
        dense = load_dense(name)
        ## 校准: 同一时刻手标 vs 自动
        errs = []
        for (seg, t), pl in ann.items():
            if seg == name and t in dense:
                errs.append(float(np.mean(np.linalg.norm(resample(dense[t]) - resample(pl), axis=1))))
        thr = max(0.06, float(np.percentile(errs, 75)) * 1.5) if errs else 0.06
        ## 剔掉: 和前后两帧都差很多的(抠错的孤立帧)
        ts = sorted(dense)
        Q = {t: resample(dense[t]) for t in ts}
        keep = []
        for i, t in enumerate(ts):
            nb = [Q[ts[j]] for j in (i - 1, i + 1) if 0 <= j < len(ts) and abs(ts[j] - t - (ts[j] - t)) < 1e-6]
            dmin = min([float(np.mean(np.linalg.norm(Q[t] - x, axis=1))) for x in nb] or [0.0])
            if dmin < 0.25:
                keep.append(t)
        res[name] = {"n_dense": len(ts), "n_keep": len(keep), "calib_err_median": float(np.median(errs)) if errs else None,
                     "calib_n": len(errs), "keep": keep}
        print("%s: 自动线 %d 帧, 留 %d; 和手标比的偏差(身长比) 中位 %.3f (n=%d)" % (name, len(ts), len(keep), np.median(errs) if errs else -1, len(errs)))
    json.dump(res, open(os.path.join(OUTD, "idle_study_calib.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
