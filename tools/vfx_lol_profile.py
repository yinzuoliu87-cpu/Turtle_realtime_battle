# -*- coding: utf-8 -*-
"""vfx_lol_profile.py — 用【从真 LoL 画面量出来的剖面】审我们的特效素材。

★由来(2026-09-06)：用户「我最在意的就是对齐 lol，但你就是不会去抄，学都学不明白」。
  他说对了。我为 001 做了 7 轮素材，**每一轮都是照我脑子里"LoL 剑气应该长什么样"写 prompt,
  从头到尾没有真的看过一帧 LoL 的画面**。而 memory fb-pixel-1to1-video-reference 早就写着
  「参考」的正确五步是: 拿到画面 → 逐帧 → 量 → 照量做 → 并排比 —— 我五步全跳了。

★参考来源(已存档, 可复量): docs/specs/refs/lol-riven-windslash-f22.png
  Riven「狂风绝息斩」(Wild Rift 英雄演示 iux0KbkIHOE 的 t≈2.0+22帧), 640x296。
  它和本项目 001 的形态完全对应: 一道飞出去的新月剑气。

★实测剖面(帧#22, 横截面由内侧到外缘):
      内侧尾wash  RGB(45,140,116) 深绿   亮度 65~142
      中段        RGB(80,255,123) 亮绿   亮度 189
      近缘        RGB(109,255,253) 转青  亮度 210
      最外缘      RGB(194,255,255) 近白  亮度 237
  ⇒ 四条可量的硬指标(下面 REF)。我第一版素材对照结果:
      白占比 37.8% vs 5.5%(差 7 倍·我做成了肥白芯而 LoL 是凸缘一条细线)
      主体亮度四分位跨度 30 vs 121(我的太平·没有层次)
      半透明像素 0.0% vs 主体半透(LoL 能看见地板)
      长宽比 1.20 vs >2.35(我的太胖)

只读。跑法: python tools/vfx_lol_profile.py <png> [--cell WxH+col+row]
"""
import argparse
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

try:
    import numpy as np
    from PIL import Image
except ImportError:
    print("[SKIP] 没装 Pillow/numpy")
    sys.exit(0)

## 从 docs/specs/refs/lol-riven-windslash-f22.png 量出来的。改这些数之前先重量参考图。
REF = {
    ## ★★这四个区间**由本工具自己量 …-f22-cut.png 得出**, 不是我手量的那组数。
    ##   第一版我沿用了手量口径(白 = r>185&g>195&b>175 ⇒ 5.5 百分点), 而工具里"白"是 亮度>215
    ##   ⇒ 12.4 百分点 —— 两个"白"不是一个东西, 结果**拿参考图自证当场红**。
    ##   ⇒ 改这些数之前: 先跑本工具量一遍参考抠图, 按【它的输出】定区间, 再跑自证。
    ##   参考实测: white_pct 12.42 / white_ratio 2.58 / body_iqr 55.00 / aspect 2.37
    "white_pct": (0.0, 19.9),
    "white_ratio": (1.60, 3.74),
    "body_iqr": (44.0, 999.0),
    "aspect": (1.71, 99.0),
}


def profile(img):
    """一帧 RGBA → 四个可比的量。

    ★掩膜怎么取, 决定了这把尺子量的是不是【那个效果】:
      · 我们自己的素材是透明底 ⇒ alpha>0 就是效果本体。
      · 参考图是**没有 alpha 的游戏截图** ⇒ alpha 全 255, "不透明像素"= 整幅地板和人物,
        量出来白/主体比 3.34、四分位跨度 36.7 —— 拿参考图自证当场红。
        这不是尺子的结论错, 是**被测对象根本不是那个效果**
        (memory fb-gate-subject-never-constructed 那一类)。
      ⇒ 没有 alpha 的图, 用【彩色且亮】把特效从背景里分出来。
    """
    c = np.asarray(img.convert("RGBA")).astype(float)
    r, g, b, a = c[:, :, 0], c[:, :, 1], c[:, :, 2], c[:, :, 3]
    ## ★参考图存档成**带 alpha 的抠图**(…-f22-cut.png), 所以这里只走 alpha 一条路。
    ##   我一开始想在工具里"自动把特效从截图背景里分出来", 连试两个阈值都把参考图自己判红
    ##   —— 那是在【拍阈值】(memory fb-my-thresholds-degrade-good-assets)。
    ##   没有通用分割法; 参考的掩膜是手工逐像素核实过的, 就该固化成存档, 不该每次现算。
    if True:
        m = a > 0
    if m.sum() < 20:
        return None
    lum = .3 * r + .6 * g + .1 * b
    white = m & (lum > 215)
    body = m & ~white
    ys, xs = np.nonzero(m)
    wl = float(np.median(lum[white])) if white.sum() else 0.0
    bl = float(np.median(lum[body])) if body.sum() else 1.0
    return {
        "n": int(m.sum()),
        "white_pct": 100.0 * white.sum() / m.sum(),
        "white_ratio": (wl / bl) if body.sum() else 0.0,
        "body_iqr": float(np.percentile(lum[body], 75) - np.percentile(lum[body], 25)) if body.sum() else 0.0,
        ## ★是【长边/短边】不是【宽/高】—— 这个量必须与朝向无关。
        ##   写成 宽/高 的话, 同一道剑气转 90° 装进"向东"格就从 2.67 变成 0.35, 门禁当场误报。
        ##   "剑气是长而扁的一扫, 不是一团"这个概念本身跟它朝哪边没关系。
        "aspect": (max(xs.max() - xs.min(), ys.max() - ys.min()) + 1)
                  / float(min(xs.max() - xs.min(), ys.max() - ys.min()) + 1),
        "translucent_pct": 100.0 * float((a[m] < 250).sum()) / m.sum(),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("png")
    ap.add_argument("--grid", default=None, help="精灵表格数 CxR, 只量第 0 格")
    a = ap.parse_args()
    if not os.path.exists(a.png):
        print("[FAIL] 文件不在: %s" % a.png)
        return 1
    im = Image.open(a.png).convert("RGBA")
    if a.grid:
        gc, gr = (int(v) for v in a.grid.lower().split("x"))
        im = im.crop((0, 0, im.width // gc, im.height // gr))
    p = profile(im)
    if p is None:
        print("[FAIL] 这一帧几乎是空的 —— 空检查不是通过")
        return 1
    print("=== %s ===  (分母: %d 个不透明像素)" % (os.path.basename(a.png), p["n"]))
    bad = 0
    for k, (lo, hi) in REF.items():
        v = p[k]
        ok = lo <= v <= hi
        bad += 0 if ok else 1
        print("  [%s] %-12s %7.2f   参考区间 %.2f~%.2f" % ("OK" if ok else "FAIL", k, v, lo, hi))
    print("  [info] 半透明像素 %.1f%%（LoL 主体是半透的；像素风可以不透，只作参考）" % p["translucent_pct"])
    if bad:
        print("FAILED: %d 项与 LoL 实测剖面不符" % bad)
        return 1
    print("ALL OK — 结构剖面对得上 LoL 参考")
    return 0


if __name__ == "__main__":
    sys.exit(main())
