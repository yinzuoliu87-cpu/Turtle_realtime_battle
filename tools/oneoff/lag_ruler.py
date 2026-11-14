# -*- coding: utf-8 -*-
"""量尺(只量规律, 不取姿势): LoL 中间那根待机每秒 60 帧的中心线 → 身长各处方向角随时间的变化,
量 ① 弯曲从根传到梢要多久(各段方向变化的互相关时差) ② 动作停下时梢端甩过头多少(梢端角速度过零前后的回摆) ③ 角速度分布。
用法: python lag_ruler.py <dense json 名> ; 也可量我们的: python lag_ruler.py --ours <demo 日志>"""
import json
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from idle_match import OUTD, resample, project  # noqa: E402

US = [0.15, 0.35, 0.55, 0.75, 0.92]


def angles_from_lines(lines):
    A = []
    for q in lines:
        r = resample(q)
        d = np.diff(r, axis=0)
        a = np.degrees(np.unwrap(np.arctan2(-d[:, 1], d[:, 0])))
        A.append([np.interp(u, np.linspace(0, 1, len(a)), a) for u in US])
    A = np.array(A)
    for j in range(A.shape[1]):          # 时间方向展开
        A[:, j] = np.degrees(np.unwrap(np.radians(A[:, j])))
    return A


def smooth(x, n=5):
    k = np.ones(n) / n
    return np.convolve(np.pad(x, n // 2, mode="edge"), k, "valid")


def stats(A, fps):
    W = np.array([smooth(A[:, j]) for j in range(A.shape[1])]).T
    V = np.diff(W, axis=0) * fps
    out = {}
    base = V[:, 0]
    for j in range(1, len(US)):
        best, lag = -9, 0
        for k in range(0, int(0.5 * fps)):
            a = base[: len(base) - k]
            b = V[k:, j]
            c = float(np.corrcoef(a, b)[0, 1])
            if c > best:
                best, lag = c, k
        out["身长%.2f比根部晚(秒)" % US[j]] = round(lag / fps, 3)
        out["身长%.2f相关" % US[j]] = round(best, 2)
    tip = V[:, -1]
    out["梢端角速度中位(°/秒)"] = round(float(np.median(np.abs(tip))))
    out["梢端角速度90分位"] = round(float(np.percentile(np.abs(tip), 90)))
    ## 甩过头: 梢端角速度换向前后, 换向后那一段转回的角度 / 换向前那一段转过的角度
    sg = np.sign(tip)
    ch = np.where(np.diff(sg) != 0)[0]
    ratios = []
    for i in range(1, len(ch) - 1):
        a0, a1, a2 = ch[i - 1], ch[i], ch[i + 1]
        fwd = abs(W[a1, -1] - W[a0, -1])
        back = abs(W[a2, -1] - W[a1, -1])
        if fwd > 15:
            ratios.append(back / fwd)
    out["梢端回摆比(中位)"] = round(float(np.median(ratios)), 2) if ratios else None
    return out


def main():
    if sys.argv[1] == "--ours":
        lines = []
        for ln in open(sys.argv[2], encoding="utf-8", errors="ignore"):
            if ln.startswith("[LINE]"):
                p = np.array([[float(v) for v in q.split(",")] for q in ln.split(" ", 2)[2].strip().split(";")])
                lines.append(project(p, 0.0))
        lines = lines[int(sys.argv[3]) if len(sys.argv) > 3 else 0:]
        print(json.dumps(stats(angles_from_lines(lines), 60.0), ensure_ascii=False, indent=1))
        return
    d = json.load(open(os.path.join(OUTD, "dense_%s.json" % sys.argv[1]), encoding="utf-8"))
    lines = [np.array(o["line"]) for o in d if o["line"]]
    print(json.dumps(stats(angles_from_lines(lines), 60.0), ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
