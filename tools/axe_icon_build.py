# -*- coding: utf-8 -*-
"""axe_icon_build.py — 照【原版 Minecraft 的五条做法】把九档斧头图标铺出来。

════════════════════════════════════════════════════════════════════════
 ★五条做法(从 430 张参考里逐格拆出来的, 见方案书 §1b)
════════════════════════════════════════════════════════════════════════
 ① 木柄在各档【逐字节相同】, 只换刃 —— 原版木柄 27 格(45%)/刃 33 格(55%)
 ② 刃只有 6 个色阶, 且【同一色相严格对齐】(钻石斧全部 H≈169.6°, 偏差<1°)
 ③ 亮部 hue-shift: 金斧 39°→44°→61°, 越亮越偏黄
 ④ 描边用【材质自己的暗色】, 不是统一黑(木斧深棕 H38°/钻石深青 H169°)
 ⑤ 每档 10 色左右, 色频很平

★★还推翻了我一个前提: 原版六档的蒙版【逐字节完全相同】——
  人家就是"同一形状换配色", 所以九档共用一个母版是**对的**, 不是偷懒。

跑法: python tools/axe_icon_build.py            # 写到 docs/plans/ref/gen9f/
"""
import colorsys
import io
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASTER = os.path.join(ROOT, "docs", "plans", "ref", "定稿", "wood.png")
OUT = os.path.join(ROOT, "docs", "plans", "ref", "gen9f")

## 每档刃部的【基色相 / 饱和 / 亮部色相偏移】—— 照 ③ 做 hue-shift。
## hue_end 是最亮那一档的色相; 中间按亮度线性插值(原版金斧就是 39→44→61)。
MAT = {
    "wood":    dict(h=31.0, h_end=25.0, s=0.55, s_end=0.63, l=(0.12, 0.76)),
    "stone":   dict(h=30.0, h_end=30.0, s=0.06, s_end=0.04, l=(0.14, 0.72)),
    "iron":    dict(h=210.0, h_end=210.0, s=0.04, s_end=0.02, l=(0.10, 0.97)),
    "gold":    dict(h=39.0, h_end=61.0, s=0.70, s_end=1.00, l=(0.13, 0.80)),
    "diamond": dict(h=170.0, h_end=172.0, s=0.64, s_end=0.82, l=(0.11, 0.72)),
    "undead":  dict(h=120.0, h_end=96.0, s=0.60, s_end=0.75, l=(0.12, 0.78)),
    "seraph":  dict(h=45.0, h_end=52.0, s=0.72, s_end=0.35, l=(0.16, 0.95)),
    "holo":    dict(h=190.0, h_end=186.0, s=0.72, s_end=0.55, l=(0.15, 0.92)),
    "ember":   dict(h=14.0, h_end=38.0, s=0.85, s_end=0.90, l=(0.12, 0.82)),
}
BLADE_STEPS = 6          # ② 刃只有 6 个色阶


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def ramp(m):
    """按 ②③ 生成 6 档刃色: 色相从 h 线性走到 h_end, 亮度从 l0 到 l1。"""
    out = []
    for i in range(BLADE_STEPS):
        f = i / float(BLADE_STEPS - 1)
        h = (m["h"] + (m["h_end"] - m["h"]) * f) / 360.0
        s = m["s"] + (m["s_end"] - m["s"]) * f
        l = m["l"][0] + (m["l"][1] - m["l"][0]) * f
        r, g, b = colorsys.hls_to_rgb(h % 1.0, l, s)
        out.append((int(round(r * 255)), int(round(g * 255)), int(round(b * 255))))
    return out


def split_blade(im):
    """把母版切成【刃】与【柄】。

    ★母版的结构(实测打印过每一格): 斧头是右上那一团, 木柄是左下→右上的斜带。
      判据用【到柄轴的横向距离】+【是否在右上】, 不用连通域 ——
      连通域会把刃与柄的接缝一起吃掉(实测刃会涨到 84%, 而原版是 55%)。
    """
    px = im.load()
    pts = [(x, y) for y in range(32) for x in range(32) if px[x, y][3] > 8]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    blade, handle = [], []
    for (x, y) in pts:
        # 归一化到内容框
        u = (x - x0) / float(max(1, x1 - x0))
        v = (y - y0) / float(max(1, y1 - y0))
        # 斧头 = 右上角那一团: u 偏右 且 v 偏上
        if u > 0.46 and v < 0.52:
            blade.append((x, y))
        else:
            handle.append((x, y))
    return blade, handle


def build(key, master, blade, handle):
    m = MAT[key]
    rp = ramp(m)
    px = master.load()
    out = master.copy()
    o = out.load()
    ls = [lum(px[x, y]) for (x, y) in blade]
    lo, hi = min(ls), max(ls)
    for (x, y) in blade:
        c = px[x, y]
        f = (lum(c) - lo) / max(1e-6, (hi - lo))
        i = min(BLADE_STEPS - 1, max(0, int(round(f * (BLADE_STEPS - 1)))))
        r, g, b = rp[i]
        o[x, y] = (r, g, b, c[3])
    ## ④ 描边用材质自己的暗色: 刃的最暗那一档已经是 rp[0](材质暗色), 无需再动
    return out


## ══════════════════════════════════════════════════════════════
##  四个最终造物的【特效像素】(用户 2026-09-02:「应该要有额外特殊的特效」)
## ══════════════════════════════════════════════════════════════
## ★特效必须**长在轮廓之外** —— 那正是造物与五个材质档的区别所在:
##   材质档共用母版蒙版(原版就是这么做的), 造物则要突破它。
## ★位置是【相对内容包围盒】算的, 不写死坐标 —— 母版换了也不会飘。
##   (memory fb-vfx-defect-families: 高度/坐标写死是特效八毛病之一)
FX = {
    ## (u, v, 色阶idx) —— u/v 是内容框内的归一化坐标, 可超出 [0,1] 表示在轮廓外
    "undead": [(0.30, -0.08, 5), (0.44, -0.14, 4), (0.58, -0.06, 5),   # 刃上方三簇鬼火
               (0.72, 0.02, 3), (0.20, 0.04, 3), (0.86, 0.16, 4)],
    "seraph": [(0.36, -0.10, 5), (0.50, -0.16, 5), (0.64, -0.10, 5),   # 顶上一排光羽
               (0.28, -0.02, 4), (0.72, -0.02, 4), (0.90, 0.10, 5)],
    "holo":   [(1.06, 0.20, 5), (1.06, 0.44, 4), (1.06, 0.66, 5),      # 右侧扫描线光点
               (0.52, -0.10, 4), (0.20, -0.06, 3)],
    "ember":  [(0.34, -0.12, 5), (0.48, -0.20, 4), (0.62, -0.10, 5),   # 刃上方飘散火星
               (0.78, -0.04, 4), (0.24, -0.04, 3), (0.90, 0.08, 5)],
}


def add_fx(key, im, rp):
    """把特效像素点上去。返回真正落笔的格数(0 = 特效没长出来, 调用方要能发现)。"""
    if key not in FX:
        return 0
    px = im.load()
    pts = [(x, y) for y in range(32) for x in range(32) if px[x, y][3] > 8]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    w = max(1, x1 - x0)
    h = max(1, y1 - y0)
    n = 0
    for (u, v, ci) in FX[key]:
        x = int(round(x0 + u * w))
        y = int(round(y0 + v * h))
        if not (0 <= x < 32 and 0 <= y < 32):
            continue
        if px[x, y][3] > 8:          # 已经有斧头了就不盖(特效不许吃掉本体)
            continue
        r, g, b = rp[min(len(rp) - 1, ci)]
        px[x, y] = (r, g, b, 255)
        n += 1
    return n


def main():
    os.makedirs(OUT, exist_ok=True)
    master = Image.open(MASTER).convert("RGBA")
    blade, handle = split_blade(master)
    print("  母版切分: 刃 %d 格 (%.0f%%) · 柄 %d 格 (%.0f%%)   [原版是 55%%/45%%]"
          % (len(blade), 100.0 * len(blade) / (len(blade) + len(handle)),
             len(handle), 100.0 * len(handle) / (len(blade) + len(handle))))
    for k in MAT:
        im = master.copy() if k == "wood" else build(k, master, blade, handle)
        nfx = add_fx(k, im, ramp(MAT[k]))
        if k in FX and nfx == 0:
            print("  [FAIL] %s 的特效一格都没落上 —— 位置全被本体挡住了" % k)
        elif nfx:
            print("     %-8s 特效 %d 格" % (k, nfx))
        im.save(os.path.join(OUT, k + ".png"))
    ## ① 自证: 九张的【柄】必须逐字节相同
    ref = Image.open(os.path.join(OUT, "wood.png")).convert("RGBA").load()
    bad = []
    for k in MAT:
        p = Image.open(os.path.join(OUT, k + ".png")).convert("RGBA").load()
        if any(p[x, y] != ref[x, y] for (x, y) in handle):
            bad.append(k)
    print("  ① 自证: 木柄在九档里逐字节相同 —— %s" % ("全部一致 OK" if not bad else "★不一致: %s" % bad))
    print("  → %s" % OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
