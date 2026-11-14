# -*- coding: utf-8 -*-
"""读回用户手标的触手中线(2026-11-13), 抹掉手抖, 换算姿势, 4 击取中位数。

用户 11-13:「我标注可能会因为手抖有些歪, 需要你来防止这种过拟合」⇒
  ① 读线: 用户图 vs 我留的原图逐像素比, 改过的像素 = 线(不挑颜色; 尺寸变了按比例缩回); 少于 40 像素 = 这张没标。
  ② 抹抖: 线细化成骨架 → 从根部走到最远端排好序 → 平滑样条拟合(平滑量按点数定, 抹掉几个像素的抖动, 保留大弯) → 按弧长重采样。
  ③ 换算: 同 strike_ruler.to_plane(出手竖直平面 + 镜头俯角)→ 沿身长 6 个控制点的角度。
  ④ 跨击: 同一时刻 4 击取中位数; 某一击某个控制点离中位数 > 35° 记为「离群」, 列出来给用户看, 不进平均。
  ⑤ 跨时: 中位数按时间再顺一遍(相邻三帧加权), 单帧跳变被压下去。
输出 .out/ref_illaoi/annot_result.json + annot_check/<击>/<图>.png(原图 + 读到的线(红) + 平滑后的线(绿))。
用法: python tools/oneoff/read_annotation.py [标注文件夹(默认桌面/触手中线标注)]
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.interpolate import splev, splprep
from skimage.morphology import skeletonize

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roto_tentacle import skel_paths  # noqa: E402
from strike_ruler import OUTD, to_plane  # noqa: E402

SRC = os.path.join(OUTD, "annot_src")
OUTLIER_DEG = 35.0


def walk_stroke(mc, start):
    """顺着笔画走: 从 start(这一笔离根部最近的骨架点)出发, 每步挑和当前方向夹角最小的未走过邻点;
    到交叉口(邻点都走过了)就在前方 3 像素内找未走过的点跳过去 ⇒ 画圈 / 交叉也能整条读出来(用户 11-13 有几帧画的是闭合圈)。"""
    sk = skeletonize(mc)
    ys, xs = np.nonzero(sk)
    if len(xs) < 6:
        return None
    pix = set(zip(xs.tolist(), ys.tolist()))
    i0 = int(np.argmin(np.hypot(xs - start[0], ys - start[1])))
    cur = (int(xs[i0]), int(ys[i0]))
    path = [cur]
    seen = {cur}
    while True:
        dvec = None
        if len(path) >= 6:
            dvec = np.array(cur, float) - np.array(path[-6], float)
            n = np.linalg.norm(dvec)
            dvec = dvec / n if n > 0 else None
        best, bc = None, 1e9
        for rad in (1, 2, 3):
            for dx in range(-rad, rad + 1):
                for dy in range(-rad, rad + 1):
                    if max(abs(dx), abs(dy)) != rad:
                        continue
                    q = (cur[0] + dx, cur[1] + dy)
                    if q not in pix or q in seen:
                        continue
                    v = np.array([dx, dy], float) / math.hypot(dx, dy)
                    cost = (1.0 - float(v @ dvec)) if dvec is not None else 0.0
                    if rad > 1 and dvec is not None and float(v @ dvec) < 0.5:
                        continue                      # 跳过交叉口只往前跳
                    cost += 0.3 * (rad - 1)
                    if cost < bc:
                        best, bc = q, cost
            if best is not None:
                break
        if best is None:
            break
        ## 把这一步周围紧贴的骨架点也记成走过(粗线骨架常有并排两像素)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                seen.add((cur[0] + dx, cur[1] + dy)) if (cur[0] + dx, cur[1] + dy) != best and dvec is not None and np.array([dx, dy]) @ dvec <= 0 else None
        cur = best
        path.append(cur)
        seen.add(cur)
    return np.array(path, float) if len(path) >= 6 else None


def read_line(ann_path, src_path, root_local):
    if not os.path.isfile(ann_path):
        return None, None
    a = Image.open(ann_path).convert("RGB")
    b = Image.open(src_path).convert("RGB")
    if a.size != b.size:
        a = a.resize(b.size, Image.LANCZOS)
    d = np.abs(np.asarray(a, np.int16) - np.asarray(b, np.int16)).sum(-1)
    m = d > 60
    m = ndimage.binary_opening(m, iterations=1)
    if m.sum() < 40:
        return None, None
    m = ndimage.binary_closing(m, iterations=3)
    m = ndimage.binary_dilation(m, iterations=2)
    ## 用户的线常断成几笔(11-13 第一批里 5 张): 每一笔各自求骨架最长路径, 再从根部起按「首尾最近」一笔一笔接起来
    lab, k = ndimage.label(m)
    pieces = []
    for c in range(1, k + 1):
        mc = lab == c
        if mc.sum() < 30:
            continue
        ys, xs = np.nonzero(mc)
        ## 两头都试着走一遍, 取走得更长的(笔画端点 = 骨架上离其余点最远的那两个)
        start = (xs[np.argmin(np.hypot(xs - root_local[0], ys - root_local[1]))], ys[np.argmin(np.hypot(xs - root_local[0], ys - root_local[1]))])
        path = walk_stroke(mc, start)
        if path is None:
            ## 顺笔画走一开头就拐进小毛刺、走不下去(11-13 第二批 11 号): 退回「骨架上离起点最远的那条路」
            sp = skel_paths(mc, start, None)
            path = np.asarray(sp[1:], float) if sp is not None and len(sp) > 6 else None
        if path is None:
            continue
        p2 = walk_stroke(mc, tuple(path[-1]))
        if p2 is not None and len(p2) > len(path) * 1.15:
            path = p2[::-1]
        pieces.append(np.asarray(path, float))
    if not pieces:
        return None, None
    cur = np.array(root_local, float)
    chain = [cur[None, :]]
    ## 用户的线起点离白圈超过 40 像素(根部被挡住、从露出来的地方画起)⇒ 不硬连到白圈
    near0 = min(min(np.hypot(*(pc[0] - cur)), np.hypot(*(pc[-1] - cur))) for pc in pieces)
    if near0 > 40:
        chain = []
    while pieces:
        best, bi, rev = 1e18, -1, False
        for i, pc in enumerate(pieces):
            d0 = np.hypot(*(pc[0] - cur))
            d1 = np.hypot(*(pc[-1] - cur))
            if d0 < best:
                best, bi, rev = d0, i, False
            if d1 < best:
                best, bi, rev = d1, i, True
        pc = pieces.pop(bi)
        if rev:
            pc = pc[::-1]
        chain.append(pc)
        cur = pc[-1]
    raw = np.vstack(chain)
    root_local = tuple(raw[0])
    ## 平滑样条: 每个点允许偏 ~3 像素(手抖量级), 大弯保留
    keep = np.r_[True, np.hypot(*np.diff(raw, axis=0).T) > 0.5]
    pts = raw[keep]
    s = len(pts) * 3.0 ** 2
    tck, _ = splprep([pts[:, 0], pts[:, 1]], s=s, k=3)
    uu = np.linspace(0, 1, 200)
    sm = np.stack(splev(uu, tck), 1)
    return raw, sm


def main():
    ann_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.expanduser("~"), "Desktop", "触手中线标注")
    man = json.load(open(os.path.join(SRC, "manifest.json"), encoding="utf-8"))
    for extra in ("manifest_after.json", "manifest_idle.json", "manifest_idle2.json", "manifest_spawn.json", "manifest_lift.json"):
        if os.path.isfile(os.path.join(SRC, extra)):
            man += json.load(open(os.path.join(SRC, extra), encoding="utf-8"))
    res = {}
    n_ok = 0
    pick_rev = {}
    if os.path.isfile(os.path.join(SRC, "pick_map.json")):
        for k, v in json.load(open(os.path.join(SRC, "pick_map.json"), encoding="utf-8")).items():
            pick_rev.setdefault(v, []).append(k if "/" in k else "请标这些_26张/" + k)
    for e in man:
        x0, y0, w, h = e["box"]
        rl = (e["root"][0] - x0, e["root"][1] - y0)
        ## 11-13 用户嫌文件夹太多 ⇒ 把要标的 26 张集中到「请标这些_26张」(pick_map.json 记着每张对应哪个原文件); 那里标过就用那里的
        ann_p = os.path.join(ann_dir, e["file"])
        for pk in pick_rev.get(e["file"], []):
            pp = os.path.join(ann_dir, *pk.split("/"))
            if os.path.isfile(pp):
                r0, _s0 = read_line(pp, os.path.join(SRC, e["file"]), rl)
                if r0 is not None:
                    ann_p = pp
        raw, sm = read_line(ann_p, os.path.join(SRC, e["file"]), rl)
        key = "%.3f" % e["tau"]
        if sm is None:
            continue
        n_ok += 1
        if e.get("fwd_ground") is None:
            ## 待机: 先只存画面上的线(换算方法另定 —— 待机的竖直平面朝向不固定)
            res.setdefault(e["strike"], {})["%.3f" % e["t"]] = {"line": [[round(float(x) + x0, 1), round(float(y) + y0, 1)] for x, y in sm[::4]]}
            im = Image.open(os.path.join(SRC, e["file"])).convert("RGB")
            dd = ImageDraw.Draw(im)
            dd.line([tuple(p) for p in raw], fill=(255, 40, 40), width=2)
            dd.line([tuple(p) for p in sm], fill=(0, 255, 60), width=3)
            op = os.path.join(OUTD, "annot_check", e["file"])
            os.makedirs(os.path.dirname(op), exist_ok=True)
            im.save(op)
            continue
        ## 梢端那个控制点取 95% 身长处的方向(手画收笔常带小勾, 最末几像素方向不稳)
        ang, L = to_plane(sm + np.array([x0, y0]), e["fwd_ground"], upos=[0.05, 0.25, 0.45, 0.65, 0.85, 0.95])
        g = e["fwd_ground"]
        fs = np.array([g[0], -g[1] * 0.829]); fs /= np.linalg.norm(fs)
        tip_fwd = float(((sm[-1] - np.array(rl)) @ fs) / max(L, 1.0))
        res.setdefault(e["strike"], {})[key] = {"pitch": [round(v, 1) for v in ang], "len_px": round(L, 1), "tip_fwd": round(tip_fwd, 3)}
        im = Image.open(os.path.join(SRC, e["file"])).convert("RGB")
        dd = ImageDraw.Draw(im)
        dd.line([tuple(p) for p in raw], fill=(255, 40, 40), width=2)
        dd.line([tuple(p) for p in sm], fill=(0, 255, 60), width=3)
        op = os.path.join(OUTD, "annot_check", e["file"])
        os.makedirs(os.path.dirname(op), exist_ok=True)
        im.save(op)
    ## 跨击中位数 + 离群
    res_p = {T: v for T, v in res.items() if not T.startswith(("idle_", "spawn_"))}
    taus = sorted({k for s in res_p.values() for k in s}, key=lambda x: -float(x))
    med, outl = {}, []
    for k in taus:
        rows = {T: s[k]["pitch"] for T, s in res_p.items() if k in s}
        a = np.array(list(rows.values()))
        m0 = np.median(a, 0)
        good = []
        for T, p in rows.items():
            dev = np.abs(np.array(p) - m0)
            if np.any(dev > OUTLIER_DEG) and len(rows) >= 3:
                outl.append({"tau": k, "strike": T, "max_dev": round(float(dev.max()), 1), "ctrl": int(dev.argmax())})
            else:
                good.append(p)
        med[k] = {"n": len(good), "pitch": [round(float(v), 1) for v in (np.median(np.array(good), 0) if good else m0)]}
    ## 跨时顺一遍(相邻 1:2:1)
    sm_t = {}
    for i, k in enumerate(taus):
        acc, wsum = np.zeros(6), 0.0
        for j, w in ((i - 1, 1.0), (i, 2.0), (i + 1, 1.0)):
            if 0 <= j < len(taus):
                acc += w * np.array(med[taus[j]]["pitch"])
                wsum += w
        sm_t[k] = [round(float(v), 1) for v in acc / wsum]
    out = {"标注张数": n_ok, "per_strike": res, "median": med, "median_smoothed": sm_t, "outliers": outl}
    json.dump(out, open(os.path.join(OUTD, "annot_result.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("读到标注", n_ok, "张 / 共", len(man), "· 离群", len(outl))
    for o in outl:
        print("  离群:", o)


if __name__ == "__main__":
    main()
