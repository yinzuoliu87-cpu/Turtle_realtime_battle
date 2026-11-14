# -*- coding: utf-8 -*-
"""出土 0.6–1.9 秒的离线模拟器 = TentacleRig 里「对折 → 关键姿势轨道」那段原样搬过来(2026-11-13 夜):
  对折参数按时间 Hermite(_hp_at, 末端不停) → _hairpin(画面平面倾斜 b0/bl、往下段回卷 cu) → HP_END 以后 _grow_vec(每节「仰角 / 水平朝向」两条轨道,
  每步挑转得最少的写法, 时间 Hermite) → 露出长度 → 我们镜头的投影(渲染日志标定, SIDE_ZOOM 3.3: 画面 x = 90·x, y = −53·y + 68.6·z)。
  用来在不开游戏的情况下比较设计: 一帧最大位移、头的轨迹、最高点。读 tentacle_rig.gd 里的表; 可用 override 改某几项。
用法: python tools/oneoff/spawn_sim.py <对照的游戏日志(可选)>"""
import math
import os
import re
import sys

import numpy as np

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RIG = os.path.join(ROOT, "scripts", "systems", "equip", "tentacle_rig.gd")
SEG = 36
U6 = [0.05, 0.25, 0.45, 0.65, 0.85, 1.0]
L_FULL = 5.74         # ARC_LEN × IDLE_ARC_K(米), 渲染日志实测
SX, SY, SZ = 90.0, -53.0, 68.6


def load_tables(path=RIG):
    s = open(path, encoding="utf-8").read()
    T = {}
    for m in re.finditer(r"^const (HP_[A-Z0-9]+) := \[(.*)\]$", s, re.M):
        T[m.group(1)] = [float(x) for x in m.group(2).split(",")]
    for m in re.finditer(r"^const (HP_HMAX|HP_END|GROW_HAND) := ([0-9.]+)", s, re.M):
        T[m.group(1)] = float(m.group(2))
    blk = s[s.index("const GROW_KEYS := ["):]
    blk = blk[:blk.index("\n]")]
    keys = []
    for m in re.finditer(r"^\s*\[([0-9.]+),\s*\[([^\]]*)\](?:,\s*\[([^\]]*)\])?\]", blk, re.M):
        p6 = [float(x) for x in m.group(2).split(",")]
        y6 = [float(x) for x in m.group(3).split(",")] if m.group(3) else [0.0] * 6
        keys.append((float(m.group(1)), p6, y6))
    ## 接待机: 2.65 秒 = 待机 A 段 1.0 秒那个姿势(游戏里 _grow_vec 末尾加的那项)
    ik = open(os.path.join(ROOT, "scripts", "systems", "equip", "tentacle_idle_keys.gd"), encoding="utf-8").read()
    m = re.search(r"\[1\.0, \[([^\]]*)\]\]", ik)
    T["JOIN"] = (2.65, [float(x) for x in m.group(1).split(",")], [0.0] * 6)
    T["GROW_KEYS"] = keys
    return T


def hermite(ts, vals, tt, end_moving=False):
    n = len(ts)
    if tt <= ts[0]:
        return vals[0]
    if tt >= ts[-1]:
        return vals[-1]
    i = 0
    for k in range(n - 1):
        if tt >= ts[k]:
            i = k
    t0, t1 = ts[i], ts[i + 1]; h = t1 - t0; x = (tt - t0) / h
    p0, p1 = vals[i], vals[i + 1]
    m0 = 0.0 if i == 0 else (p1 - vals[i - 1]) / (t1 - ts[i - 1])
    m1 = 0.0 if i + 1 == n - 1 else (vals[i + 2] - p0) / (ts[i + 2] - t0)
    if i + 1 == n - 1 and end_moving:
        m1 = (p1 - p0) / h
    x2 = x * x; x3 = x2 * x
    return (2 * x3 - 3 * x2 + 1) * p0 + (x3 - 2 * x2 + x) * h * m0 + (-2 * x3 + 3 * x2) * p1 + (x3 - x2) * h * m1


def hp_at(T, name, tt):
    return hermite(T["HP_T"], T[name], tt, True)


def hairpin(T, tt):
    hn = hp_at(T, "HP_HN", tt); a0 = hp_at(T, "HP_LP", tt); w = max(hp_at(T, "HP_R", tt), 0.04)
    myr = math.radians(hp_at(T, "HP_MY", tt)); dp = hp_at(T, "HP_DP", tt); dl = max(hp_at(T, "HP_D", tt), 0.0)
    cu = hp_at(T, "HP_CU", tt); b0 = hp_at(T, "HP_B0", tt); bl = hp_at(T, "HP_BL", tt)
    hdir = np.array([math.cos(myr), 0.0, math.sin(myr)])
    total = 1.0 + dl; sc = 1.0 - 0.5 * w
    dirs = np.zeros((SEG, 3))
    for i in range(SEG):
        sx = (i + 0.5) / SEG * total
        f = 0.5 * (1.0 + math.tanh((sx - sc) / w))
        ang = math.radians(a0 + (-dp - a0) * f - cu * max(0.0, sx - sc) / max(total - sc, 0.001))
        dv = hdir * math.cos(ang) + np.array([0, 1.0, 0]) * math.sin(ang)
        bt = math.radians(b0 + bl * min(sx / sc, 1.0))
        d = np.array([dv[0] * math.cos(bt) - dv[1] * math.sin(bt), dv[0] * math.sin(bt) + dv[1] * math.cos(bt), dv[2]])
        dirs[i] = d / np.linalg.norm(d)
    return dirs, total * T["HP_HMAX"] * hn


def ctrl_interp(c, u):
    m = len(c)
    if u <= U6[0]:
        return c[0]
    j = m - 2
    for k in range(m - 1):
        if u <= U6[k + 1]:
            j = k
            break
    s = (u - U6[j]) / (U6[j + 1] - U6[j])
    p0, p1, p2, p3 = c[max(j - 1, 0)], c[j], c[j + 1], c[min(j + 2, m - 1)]
    return 0.5 * (2 * p1 + (p2 - p0) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s * s + (-p0 + 3 * p1 - 3 * p2 + p3) * s ** 3)


def py_vec(p, y):
    p = math.radians(p); y = math.radians(y)
    return np.array([math.cos(y) * math.cos(p), math.sin(p), math.sin(y) * math.cos(p)])


def build_tracks(T):
    tracks = []
    hp_cache = {th: hairpin(T, th)[0] for th in T["HP_T"] if th <= T["HP_END"] + 0.001}
    for i in range(SEG):
        u = (i + 0.5) / SEG
        si = min(max(int(u * SEG), 0), SEG - 1)
        tsa, vs = [], []
        for th in T["HP_T"]:
            if th > T["HP_END"] + 0.001:
                continue
            tsa.append(th); vs.append(hp_cache[th][si])
        for (tk, p6, y6) in T["GROW_KEYS"] + ([T["JOIN"]] if "JOIN" in T else []):
            if tk <= T["HP_END"] + 0.001:
                continue
            tsa.append(tk); vs.append(py_vec(ctrl_interp(p6, u), ctrl_interp(y6, u)))
        ea, aa = [], []
        for k2, v in enumerate(vs):
            v = v / np.linalg.norm(v)
            e0 = math.degrees(math.asin(max(-1, min(1, v[1])))); az0 = math.degrees(math.atan2(v[2], v[0]))
            if k2 == 0:
                ea.append(e0); aa.append(az0); continue
            pe, pa = ea[-1], aa[-1]; best = None
            for fl in range(2):
                ec = (180 - e0) if fl else e0; ac = (az0 + 180) if fl else az0
                ec = pe + ((ec - pe + 180) % 360 - 180); ac = pa + ((ac - pa + 180) % 360 - 180)
                cst = abs(ec - pe) + 0.3 * abs(ac - pa)
                if best is None or cst < best[0]:
                    best = (cst, ec, ac)
            ea.append(best[1]); aa.append(best[2])
        tracks.append((tsa, ea, aa))
    return tracks


def seg_dir(T, tracks, i, tt):
    ## 第 i 节在 tt 时刻的方向(对折段 / 关键姿势轨道)
    if tt < T["HP_END"]:
        return hairpin(T, tt)[0][i]
    tsa, ea, aa = tracks[i]
    e = math.radians(hermite(tsa, ea, tt)); az = math.radians(hermite(tsa, aa, tt))
    return np.array([math.cos(e) * math.cos(az), math.sin(e), math.cos(e) * math.sin(az)])


def frame(T, tracks, tg, overlap=0.0):
    hp_end = T["HP_END"]
    if overlap > 0.0:
        ## 从根到梢的先后: 第 i 节取 tg − overlap·u 时刻的方向(梢端晚 overlap 秒跟上)
        dirs = np.array([seg_dir(T, tracks, i, tg - overlap * (i + 0.5) / SEG) for i in range(SEG)])
        ex = hairpin(T, tg)[1] if tg < hp_end else None
        if ex is None:
            l_end = hairpin(T, hp_end)[1]
            k = min(max((tg - hp_end) / T["GROW_HAND"], 0), 1); k = k * k * (3 - 2 * k)
            ex = l_end + (1.0 - l_end) * k
        P = np.vstack([[0, 0, 0], np.cumsum(dirs * (L_FULL * ex / SEG), 0)])
        S = np.stack([SX * P[:, 0], SY * P[:, 1] + SZ * P[:, 2]], 1)
        return P, S
    if tg < hp_end:
        dirs, ln = hairpin(T, tg)
        ex = ln
    else:
        dirs = np.zeros((SEG, 3))
        for i in range(SEG):
            tsa, ea, aa = tracks[i]
            e = math.radians(hermite(tsa, ea, tg)); az = math.radians(hermite(tsa, aa, tg))
            dirs[i] = [math.cos(e) * math.cos(az), math.sin(e), math.cos(e) * math.sin(az)]
        l_end = hairpin(T, hp_end)[1]
        k = min(max((tg - hp_end) / T["GROW_HAND"], 0), 1); k = k * k * (3 - 2 * k)
        ex = l_end + (1.0 - l_end) * k
    P = np.vstack([[0, 0, 0], np.cumsum(dirs * (L_FULL * ex / SEG), 0)])
    S = np.stack([SX * P[:, 0], SY * P[:, 1] + SZ * P[:, 2]], 1)
    return P, S


def simulate(T, t0=0.6, t1=1.9, overlap=0.0):
    tracks = build_tracks(T)
    out = []
    for k in range(int(round((t1 - t0) * 60)) + 1):
        tg = t0 + k / 60.0
        P, S = frame(T, tracks, tg, overlap)
        out.append((tg, P, S))
    return out


def report(rows, label=""):
    steps = [(float(np.max(np.linalg.norm(rows[i][2] - rows[i - 1][2], axis=1))), rows[i][0]) for i in range(1, len(rows))]
    mx = max(steps)
    print("%s 一帧最大位移 %.1f 像素 @ %.3f 秒" % (label, mx[0], mx[1]))
    for tg, P, S in rows:
        if abs(tg * 20 - round(tg * 20)) < 1e-6:
            b = S[0]; it = int(np.argmin(S[:, 1]))
            print("  %.3f 顶高 %4.0f 顶偏x %+4.0f 头高 %+4.0f 头偏x %+4.0f" % (tg, b[1] - S[it, 1], S[it, 0] - b[0], b[1] - S[-1, 1], S[-1, 0] - b[0]))
    return mx


if __name__ == "__main__":
    T = load_tables()
    rows = simulate(T)
    report(rows, "模拟(当前表)")
