# -*- coding: utf-8 -*-
"""icon_art_audit.py — 装备/物品图标的【像素画硬闸】(2026-09-13)

════════════════════════════════════════════════════════════════════════
 ★由来
════════════════════════════════════════════════════════════════════════
用户 2026-09-13:「我对赤烤海胆，守护贝母，月之刃，守护贝壳的图标不是很满意，
  这虽然像素风，但**看的很丑**，为什么，**跟我的世界模组里那些武器或事物的图标差远了**啊，
  我记得让你学习过 mod 的 400 个图片啊」

★★上一轮(v0.19.320 斧头)那五条尺子**量不到这次的「丑」**:
  色阶数/色相对齐/亮部 hue-shift/描边用材质暗色/色频平坦 —— 这四张在那五条上
  和斧头没差(颜色数 6 甚至比参考的 10 还少)。**量了不等于量对了。**

⇒ 重新抓了 Minecraft/模组物品图标当分布, 从中量出**真正分得开**的三条。
  (抓法: curl + GitHub tree API 免 token; 只做研究, 一张不进游戏。)

════════════════════════════════════════════════════════════════════════
 判据(阈值全部来自参考分布, 不是我拍的)
════════════════════════════════════════════════════════════════════════
参考 405 张的分布:
    描边闭合度  中位 0.562   (轮廓上的格子里有多少是本图最暗那 25%)
    高光占比    中位 0.151   (亮度 ≥ p88 的格子占内容的比例)
    颜色数      中位 12

 A 描边闭合度 ≥ 0.45   不满足 = 没有深色骨架, 形状散(013 实测 0.23, 第 5 分位)
 B 高光占比   ≤ 0.20   不满足 = 一条横贯全图的斜向亮带(021 实测 0.31, 第 95 分位)
 C 颜色数     ≥ 9      不满足 = 32×32 的画布只有几档 ⇒ 大片纯色, 读成海报
 D 尺寸       ≤ 64×64  不满足 = 拿照片/大图当图标(用户明令禁止)

★★三条都是**只减不增**的棘轮: 存量冻进台账, 新增当场红; 还了债要销账
  (照 vfx_discipline_audit / shield_duration_audit 的规矩)。

跑法:
    python tools/icon_art_audit.py
    ICON_ART_UPDATE=1 python tools/icon_art_audit.py    # 还债后重写台账
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(ROOT, "tools", "icon_art_debt.json")
SCAN = [os.path.join(ROOT, "assets", "sprites", "equip", "*.png")]

## 阈值 —— 来自 405 张 mod 参考的分布(中位 0.562 / 0.151 / 12), 取中位与 p25 之间
EDGE_MIN = 0.45
HI_MAX = 0.20
COLORS_MIN = 9
SIZE_MAX = 64
## ★分母哨兵: 扫到的图标数不许突然变少(正则/路径写坏时会静默扫到 0 张)
MIN_FILES = 100


def measure(p):
    """返回 (尺寸, 描边闭合度, 高光占比, 颜色数); 读不出返回 None。"""
    try:
        im = Image.open(p).convert("RGBA")
    except Exception:
        return None
    a = np.asarray(im, dtype=np.float32)
    al = a[..., 3] >= 128
    if al.sum() < 24:
        return None
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    L = lum[al]
    hi = float((lum[al] >= np.percentile(L, 88)).mean())
    pad = np.zeros((a.shape[0] + 2, a.shape[1] + 2), bool)
    pad[1:-1, 1:-1] = al
    inner = (pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    edge = al & ~inner
    ed = float((lum[edge] <= np.percentile(L, 25)).mean()) if edge.sum() else 0.0
    cols = len(set(map(tuple, a[..., :3][al].astype(int).tolist())))
    return im.size, ed, hi, cols


def violations(p):
    m = measure(p)
    if m is None:
        return None, []
    sz, ed, hi, cols = m
    v = []
    if max(sz) > SIZE_MAX:
        v.append("size")
    if ed < EDGE_MIN:
        v.append("edge")
    if hi > HI_MAX:
        v.append("hi")
    if cols < COLORS_MIN:
        v.append("colors")
    return (sz, ed, hi, cols), v


def main():
    files = []
    for g in SCAN:
        files += sorted(glob.glob(g))
    print("=== 图标像素画纪律审计 ===")
    print("  阈值(来自 405 张 mod 参考): 描边闭合 ≥%.2f · 高光占比 ≤%.2f · 颜色数 ≥%d · 尺寸 ≤%d"
          % (EDGE_MIN, HI_MAX, COLORS_MIN, SIZE_MAX))
    print("  ★分母: 扫到 %d 张图标" % len(files))
    if len(files) < MIN_FILES:
        print("  [FAIL] ★只扫到 %d 张(<%d) —— 路径写坏了, 这不是通过" % (len(files), MIN_FILES))
        return 1

    cur = {}
    for p in files:
        m, v = violations(p)
        if v:
            cur[os.path.relpath(p, ROOT).replace("\\", "/")] = sorted(v)

    if os.environ.get("ICON_ART_UPDATE"):
        json.dump(cur, open(LEDGER, "w", encoding="utf-8"), ensure_ascii=False,
                  indent=1, sort_keys=True)
        print("  台账已重写: %d 张在册" % len(cur))
        return 0

    old = {}
    if os.path.exists(LEDGER):
        old = json.load(open(LEDGER, encoding="utf-8"))

    bad = 0
    ## ① 新增违规 = 当场红
    for k, v in sorted(cur.items()):
        was = set(old.get(k, []))
        new = set(v) - was
        if new:
            m, _ = violations(os.path.join(ROOT, k))
            print("  [FAIL] ★新增违规 %s: %s  (尺寸%s 描边%.2f 高光%.2f 色数%d)"
                  % (k, "/".join(sorted(new)), m[0], m[1], m[2], m[3]))
            bad += 1
    ## ② 还了债要销账(台账停在历史最大值就没意义了)
    for k, v in sorted(old.items()):
        still = set(cur.get(k, []))
        fixed = set(v) - still
        if fixed:
            print("  [FAIL] ★%s 的 %s 已修好, 但台账还记着 —— 跑 ICON_ART_UPDATE=1 销账"
                  % (k, "/".join(sorted(fixed))))
            bad += 1

    print("  [存量] 台账 %d 张在册(只减不增)" % len(old))
    print("")
    print("ALL OK — 图标纪律没有新增欠债" if bad == 0 else "FAILED: %d 处" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
