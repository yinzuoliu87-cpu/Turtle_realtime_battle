# -*- coding: utf-8 -*-
"""出土中段「像硬给它扭的」量尺(2026-11-14 用户「中间部分有点不自然，像是硬给它扭的一样」):
  根部那一节的角速度(°/秒; 真触手根最稳) · 梢 / 根角速度比(动作从根传到梢, 梢应大于根) · 一帧最大位移 ·
  和用户线的形状差(0.85 / 1.68 / 1.88 这几张看得见、手标可信)。比较几种改法。"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spawn_sim as S  # noqa: E402
from idle_match import OUTD, resample  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")
R = np.array([1020.0, 477.0])
_ann = json.load(open(os.path.join(OUTD, "annot_result.json"), encoding="utf-8"))["per_strike"]["spawn_中间"]
USER = {}
for k, v in _ann.items():
    t = round(float(k) - 72.35, 2)
    a = np.array(v["line"], float)
    if np.hypot(*(a[-1] - R)) < np.hypot(*(a[0] - R)):
        a = a[::-1]
    USER[t] = a


def measure(T, overlap=0.0, label=""):
    rows = S.simulate(T, 0.6, 2.7, overlap)
    ts = np.array([r[0] for r in rows])
    D = [np.diff(r[1], axis=0) for r in rows]
    D = [d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9) for d in D]
    rootw, ratio = [], []
    for k in range(1, len(rows)):
        w = np.degrees(np.arccos(np.clip(np.sum(D[k] * D[k - 1], axis=1), -1, 1))) * 60.0
        rootw.append(w[:4].mean()); ratio.append(w[-6:].mean() / max(w[:4].mean(), 1.0))
    rootw = np.array(rootw); ratio = np.array(ratio)
    Ss = np.array([r[2] for r in rows])
    disp = np.max(np.linalg.norm(Ss[1:] - Ss[:-1], axis=2), axis=1)
    mid = (ts[1:] >= 0.9) & (ts[1:] <= 2.6)
    gaps = []
    for tt in (0.85, 1.68, 1.88):
        k = int(round((tt - 0.6) * 60))
        gaps.append(float(np.mean(np.linalg.norm(resample(USER[tt]) - resample(rows[k][2]), axis=1))))
    print("%-16s 根部角速度 最大 %4.0f°/秒 (超过 90 的帧 %2d)  梢/根<1 的帧 %2d  一帧最大位移 %4.1f  形状差 0.85/1.68/1.88 = %s" % (
        label, rootw[mid].max(), int(np.sum(rootw[mid] > 90)), int(np.sum((ratio < 1.0)[mid] & (rootw[mid] > 30))), disp[mid].max(),
        " / ".join("%.3f" % g for g in gaps)))
    return rows


def variant(base, **chg):
    T = {k: (list(v) if isinstance(v, list) else v) for k, v in base.items()}
    for (name, t), v in chg.get("hp", {}).items():
        T[name][T["HP_T"].index(t)] = v
    if "k188" in chg:
        T["GROW_KEYS"] = [(tk, (chg["k188"] if abs(tk - 1.88) < 1e-6 else p6), y6) for (tk, p6, y6) in T["GROW_KEYS"]]
    return T


if __name__ == "__main__":
    T0 = S.load_tables()
    measure(T0, 0.0, "现在")
    measure(T0, 0.06, "加先后0.06")
    root = {("HP_B0", 0.85): -3.0, ("HP_B0", 0.93): -7.0, ("HP_B0", 1.01): -13.0, ("HP_B0", 1.1): -19.5,
            ("HP_MY", 1.01): 275.0, ("HP_MY", 1.1): 269.0}
    k188 = [52.0, 81.9, 103.1, 218.2, 275.5, 328.1]
    Tr = variant(T0, hp=root, k188=k188)
    measure(Tr, 0.0, "理顺根部")
    for ov in (0.05, 0.08, 0.10):
        measure(Tr, ov, "理顺根部+先后%.2f" % ov)
