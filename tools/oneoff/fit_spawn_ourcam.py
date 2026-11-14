# -*- coding: utf-8 -*-
"""出土 0.85 秒以后的关键姿势: 用【我们游戏的镜头】(俯角 51°, 触手正面朝画面右边)反推, 让我们画面上的样子和用户在 LoL 上标的线一样(2026-11-13)。
不翻转、不换视角(用户「我不知道你为什么要镜像」)。顺时间连续拟合 + 弯得越少越好。输出 .out/ref_illaoi/fit_spawn_ourcam.json"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fit_idle_keys as F  # noqa: E402

F.CAM = math.radians(51.8)
from fit_spawn_keys2 import fit_seq  # noqa: E402
from idle_match import OUTD, resample  # noqa: E402


def main():
    d = json.load(open(os.path.join(OUTD, "annot_result.json"), encoding="utf-8"))["per_strike"]["spawn_中间"]
    L = sorted((float(t) - 72.35, resample(np.array(v["line"]))) for t, v in d.items() if 0.8 <= float(t) - 72.35 <= 1.95)
    m, out = fit_seq(L, 0.0)
    print("平均残差 %.4f" % m)
    for o in out:
        print(o)
    json.dump(out, open(os.path.join(OUTD, "fit_spawn_ourcam.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
