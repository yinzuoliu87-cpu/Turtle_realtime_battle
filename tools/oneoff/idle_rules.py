# -*- coding: utf-8 -*-
"""待机动画规律(2026-11-13): LoL 三根(中间 / 左上 / 墙根)每 0.1 秒的准线 vs 我们的待机, 同一把尺子量。只做量尺。
指标(都按身长归一, 画面坐标):
  速度 = 相邻帧形状(20 点)平均位移 / 秒; 停顿占比 = 速度 < 0.15 身长/秒 的时间比例
  动停节奏 = 速度时间序列里「动一阵」(连续高于中位数)的平均时长
  根→梢传递 = 根部段(身长 15%)与梢部段(85%)方向角变化的互相关峰值时差(正 = 梢比根晚)
  卷曲 = 总转角(根到梢方向变化之和, 度)的分布; 卷曲最强处在身长哪里
输出 .out/ref_illaoi/idle_rules.json, 打印对照表。
"""
import json
import math
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from idle_match import OUTD, resample, project  # noqa: E402


def seq_from_dense(name):
    d = json.load(open(os.path.join(OUTD, "dense_%s.json" % name), encoding="utf-8"))
    return [(o["t"], np.array(o["line"])) for o in d if o["line"]]


def seq_ours(step=6):
    log = open(os.path.join(OUTD, "idle_ours_lines.log"), encoding="utf-8", errors="ignore").read().splitlines()
    roto = None
    out = []
    n = 0
    for ln in log:
        m = re.match(r"\[ROTO\] f=\d+ st=(\d+) tl=([0-9.]+)", ln)
        if m:
            roto = int(m.group(1)); n += 1
            continue
        if ln.startswith("[LINE]") and roto == 1 and n > 260 and n % step == 0:
            pts = np.array([[float(v) for v in q.split(",")] for q in ln.split(" ", 2)[2].split(";")])
            out.append((n / 60.0, project(pts, 0.0)))
    return out


def dirs(q):
    d = np.diff(q, axis=0)
    a = np.degrees(np.arctan2(-d[:, 1], d[:, 0]))
    return np.degrees(np.unwrap(np.radians(a)))


def metrics(seq):
    ts = np.array([t for t, _ in seq])
    Q = [resample(p) for _, p in seq]
    ok = [i for i, q in enumerate(Q) if q is not None]
    ts = ts[ok]
    Q = [Q[i] for i in ok]
    ## 抠线每帧有 ~1.5% 身长的随机误差 ⇒ 0.1 秒采样时速度会多出 ~0.15 身长/秒的「噪声速度」。两边都做同样的时间平滑(3 帧滑动平均)再量
    Qa = np.array(Q)
    Qs = Qa.copy()
    for i in range(1, len(Q) - 1):
        Qs[i] = (Qa[i - 1] + Qa[i] + Qa[i + 1]) / 3.0
    Q = list(Qs)
    A = np.array([dirs(q) for q in Q])            # 每帧 19 段方向角
    sp = []
    for i in range(1, len(Q)):
        dt = ts[i] - ts[i - 1]
        if 0 < dt < 0.25:
            sp.append(float(np.mean(np.linalg.norm(Q[i] - Q[i - 1], axis=1))) / dt)
    sp = np.array(sp)
    still = float(np.mean(sp < 0.15))
    ## 动一阵的时长
    hi = sp > np.median(sp)
    runs, cur = [], 0
    for h in hi:
        if h:
            cur += 1
        elif cur:
            runs.append(cur); cur = 0
    dt0 = float(np.median(np.diff(ts)))
    move_len = float(np.mean(runs)) * dt0 if runs else 0.0
    ## 根→梢传递: 根部段 / 梢部段方向角的变化率互相关
    r = np.diff(A[:, 3]); tp = np.diff(A[:, 16])
    r = (r - r.mean()) / (r.std() + 1e-9); tp = (tp - tp.mean()) / (tp.std() + 1e-9)
    best, lag = -9, 0
    for k in range(-8, 9):
        if k >= 0:
            c = float(np.mean(r[:len(r) - k] * tp[k:])) if k < len(r) else -9
        else:
            c = float(np.mean(r[-k:] * tp[:len(tp) + k]))
        if c > best:
            best, lag = c, k
    ## 每一段在画面上转得多快(度/秒): 「非正常扭动」那种瞬间甩动看这一项的 99 分位和最大值
    dA = np.abs(np.diff(A, axis=0)) / np.maximum(np.diff(ts)[:, None], 1e-6)
    seg_p99 = float(np.percentile(dA.max(1), 99))
    seg_max = float(dA.max())
    curl = A[:, -1] - A[:, 0]
    kpos = np.argmax(np.abs(np.diff(A, axis=1)), axis=1) / 18.0
    root_rng = float(np.percentile(A[:, 1], 95) - np.percentile(A[:, 1], 5))
    return {"帧": len(Q), "采样间隔": round(dt0, 3), "速度中位": round(float(np.median(sp)), 3), "速度90分位": round(float(np.percentile(sp, 90)), 3),
            "停顿占比": round(still, 3), "动一阵平均秒": round(move_len, 2), "梢比根晚(秒)": round(lag * dt0, 2), "传递相关": round(best, 2),
            "卷曲中位(度)": round(float(np.median(np.abs(curl))), 1), "卷曲90分位(度)": round(float(np.percentile(np.abs(curl), 90)), 1),
            "最弯处身长位置中位": round(float(np.median(kpos)), 2), "根部摆幅(度)": round(root_rng, 1),
            "段转速99分位(度/秒)": round(seg_p99), "段转速最大(度/秒)": round(seg_max)}


def main():
    res = {}
    for nm in ("中间", "左上", "墙根"):
        res["LoL " + nm] = metrics(seq_from_dense(nm))
    res["我们(现在)"] = metrics(seq_ours())
    json.dump(res, open(os.path.join(OUTD, "idle_rules.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    keys = list(next(iter(res.values())).keys())
    print("指标".ljust(14) + "".join(k.ljust(12) for k in res))
    for k in keys:
        print(k.ljust(14) + "".join(str(res[n][k]).ljust(12) for n in res))


if __name__ == "__main__":
    main()
