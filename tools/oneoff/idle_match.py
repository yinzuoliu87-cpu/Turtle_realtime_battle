# -*- coding: utf-8 -*-
"""待机逐段对照(2026-11-13): LoL 9 段待机的每一张中心线(用户手标 + 我标好的), 在我们待机循环里找最像的那一刻。

公平起见: 我们的 3D 中心线(调试场 SIDE_IDLE=1 打出的 [LINE])按 LoL 镜头俯角 56° 重新投影, 并从 12 个朝向 × 左右镜像各看一次;
  形状描述 = 从根部起按弧长重采样 20 点、平移到根部、按总弧长归一 ⇒ 只比形状不比大小。
尺子: 同一张 LoL 线和【别的 LoL 触手】最像的那张差多少(LoL 自己的多样性)。我们的差距 ≤ 这把尺子 = 对上了。
输出 .out/ref_illaoi/idle_match.json + idle_match_worst.png(对不上的那几张: LoL 线 | 我们最像的那一刻)。
"""
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTD = os.path.join(ROOT, ".out", "ref_illaoi")
N = 20
CAM = math.radians(56.0)


def resample(pl):
    pl = np.asarray(pl, float)
    seg = np.hypot(*np.diff(pl, axis=0).T)
    s = np.concatenate([[0], np.cumsum(seg)])
    if s[-1] < 1e-6:
        return None
    t = np.linspace(0, s[-1], N)
    out = np.stack([np.interp(t, s, pl[:, 0]), np.interp(t, s, pl[:, 1])], 1)
    out -= out[0]
    return out / s[-1]


def ours():
    log = open(os.path.join(OUTD, "idle_ours_lines.log"), encoding="utf-8", errors="ignore").read().splitlines()
    roto = None
    res = []
    for ln in log:
        m = re.match(r"\[ROTO\] f=\d+ st=(\d+) tl=([0-9.]+)", ln)
        if m:
            roto = (int(m.group(1)), float(m.group(2)))
            continue
        if ln.startswith("[LINE]") and roto and roto[0] == 1:
            pts = np.array([[float(v) for v in q.split(",")] for q in ln.split(" ", 2)[2].split(";")])
            res.append((roto[1], pts))
    ## 跳过长出那 2 秒: 只取第一次出现之后 2 秒以后的
    t0 = None
    out = []
    for k, (tl, pts) in enumerate(res):
        if k < 130:
            continue
        if k % 3:
            continue
        out.append((tl, pts))
    return out


def project(pts, yaw):
    ## 世界坐标(y 向上) → 俯角 CAM 的镜头画面(x 右, y 下); 镜头绕竖轴转 yaw
    c, s = math.cos(yaw), math.sin(yaw)
    x = pts[:, 0] * c + pts[:, 2] * s
    z = -pts[:, 0] * s + pts[:, 2] * c          # 往镜头外(远处)为负
    sx = x
    sy = -(pts[:, 1] * math.cos(CAM)) + z * math.sin(CAM)
    return np.stack([sx, sy], 1)


def lol_lines():
    res = []
    ar = json.load(open(os.path.join(OUTD, "annot_result.json"), encoding="utf-8"))["per_strike"]
    for k, frames in ar.items():
        if not k.startswith("idle_"):
            continue
        for t, v in frames.items():
            if "line" in v:
                res.append((k[5:].replace("那根", ""), float(t), np.array(v["line"]), "你标的"))
    have = {(a, b) for a, b, _, _ in res}
    my = json.load(open(os.path.join(OUTD, "my_annot.json"), encoding="utf-8"))
    for f, v in my.items():
        if not isinstance(v, list):
            continue
        seg = f.split(os.sep)[0].replace("待机_", "").replace("那根", "")
        t = float(f.split("录屏")[1].replace("秒.png", ""))
        if (seg, t) in have:
            continue
        res.append((seg, t, np.array(v), "我标的"))
    return res


def main():
    oc = ours()
    variants = []
    for tl, pts in oc:
        for yi in range(12):
            q = resample(project(pts, yi * math.pi / 6))
            if q is None:
                continue
            variants.append((tl, yi, False, q))
            variants.append((tl, yi, True, q * np.array([-1, 1])))
    V = np.stack([v[3] for v in variants])
    lol = lol_lines()
    L = [(seg, t, resample(pl), src, pl) for seg, t, pl, src in lol]
    L = [x for x in L if x[2] is not None]
    rows = []
    for i, (seg, t, q, src, pl) in enumerate(L):
        d = np.mean(np.linalg.norm(V - q[None], axis=2), axis=1)
        j = int(np.argmin(d))
        others = [np.mean(np.linalg.norm(x[2] - q, axis=1)) for x in L if x[0] != seg]
        others += [np.mean(np.linalg.norm(x[2] * np.array([-1, 1]) - q, axis=1)) for x in L if x[0] != seg]
        rows.append({"seg": seg, "t": t, "src": src, "d_ours": round(float(d[j]), 4), "d_lol": round(float(min(others)), 4),
                     "best_tl": variants[j][0], "best_yaw": variants[j][1] * 30, "mirror": variants[j][2], "_vi": j, "_i": i})
    json.dump([{k: v for k, v in r.items() if not k.startswith("_")} for r in rows], open(os.path.join(OUTD, "idle_match.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    segs = sorted({r["seg"] for r in rows})
    print("段 | 张数 | 我们差距中位 | LoL 自身差距中位 | 对上(我们≤LoL×1.2)")
    for sg in segs:
        rr = [r for r in rows if r["seg"] == sg]
        ok = sum(1 for r in rr if r["d_ours"] <= 1.2 * r["d_lol"])
        print("%s | %d | %.3f | %.3f | %d/%d" % (sg, len(rr), np.median([r["d_ours"] for r in rr]), np.median([r["d_lol"] for r in rr]), ok, len(rr)))
    allok = sum(1 for r in rows if r["d_ours"] <= 1.2 * r["d_lol"])
    print("合计 对上 %d / %d" % (allok, len(rows)))
    ## 对不上的那几张画出来
    bad = sorted([r for r in rows if r["d_ours"] > 1.2 * r["d_lol"]], key=lambda r: -r["d_ours"] / max(r["d_lol"], 1e-6))[:12]
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 16)
    W = 220
    sh = Image.new("RGB", (W * 2 * 4, W * 3), (20, 20, 30))
    for k, r in enumerate(bad):
        x0, y0 = (k % 4) * 2 * W, (k // 4) * W
        for side, qq, col in ((0, L[r["_i"]][2], (255, 80, 80)), (1, variants[r["_vi"]][3], (80, 255, 120))):
            im = Image.new("RGB", (W, W), (20, 20, 30))
            d = ImageDraw.Draw(im)
            pts = [(W / 2 + p[0] * W * 0.8, W * 0.85 + p[1] * W * 0.8) for p in qq]
            d.line(pts, fill=col, width=3)
            d.ellipse((pts[0][0] - 4, pts[0][1] - 4, pts[0][0] + 4, pts[0][1] + 4), outline=(255, 255, 255))
            d.text((4, 2), ("LoL %s %.1fs" % (r["seg"][:8], r["t"])) if side == 0 else ("我们 tl=%.1f" % r["best_tl"]), fill=(255, 255, 0), font=font)
            sh.paste(im, (x0 + side * W, y0))
    sh.save(os.path.join(OUTD, "idle_match_worst.png"))


if __name__ == "__main__":
    main()
