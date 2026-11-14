# -*- coding: utf-8 -*-
"""待机 A 段关键姿势改用【我们游戏的镜头】(俯角 51.8°)从标注反推, 和出土那段同一个镜头 —— 交接处同一个姿势(2026-11-13)。
11-13 用户「出土那后面几帧怎么回事」: 出土用我们的镜头算、待机用 LoL 镜头(56°)算 ⇒ 交接处本该是同一个圈, 算出两个姿势, 多出一个「松开再抬头」。"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fit_idle_keys as F  # noqa: E402

F.CAM = math.radians(51.8)
from fit_spawn_keys2 import fit_seq  # noqa: E402
from idle_match import OUTD, lol_lines, resample  # noqa: E402

ROOT = np.array([1013.0, 458.0])


def main():
    L = []
    for seg, t, pl, src in lol_lines():
        if seg == "中间" and 74.0 <= t <= 91.0:
            a = np.array(pl, float)
            if np.hypot(*(a[-1] - ROOT)) < np.hypot(*(a[0] - ROOT)):
                a = a[::-1]
            L.append((t - 74.0, resample(a)))
    L.sort(key=lambda x: x[0])
    m, out = fit_seq(L, 0.0)
    print("平均残差 %.4f" % m)
    for o in out:
        print(o)
    json.dump(out, open(os.path.join(OUTD, "fit_idle_ourcam.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
