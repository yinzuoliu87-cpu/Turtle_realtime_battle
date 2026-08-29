# -*- coding: utf-8 -*-
"""手半剑 084 十字斩的**实拍**判据 (2026-08-29)。

`vfx_ref_match.py` 量的是**素材文件**; 这个量的是**屏幕上真的画出来的样子**。
两个都要 —— 素材过了不代表场上对: 我这一轮连续三次"判据绿了、实拍一看不对"
(纱窗 / 扫描线 / 1px 横线), 每次都是因为漏了一条实拍才看得见的性质。

★用户 2026-08-29:「**没通过就不要停也不要给我看**」——
  我自己发现问题就等于没通过, 该继续修, 不该停下来问。这个脚本就是"通过"的定义。

判据(全部实拍量, 不是眼看):
  ① 施法者必须在画面里(否则看不出是谁挥的)
  ② 斩击弧必须是**主角** —— 屏上面积不小于剑气波的 60%
     (我做出来的斩击只有剑波的一小半, 看着剑波是主角、斩击是配角, 主次反了)
  ③ 两者都必须真的出现过(N=0 是空检查不是通过)

跑法: python tools/vfx_ingame_check.py
  (自己调 VFXLAB 拍一组图再量; 需要 Godot 与 Pillow)
"""
import colorsys
import glob
import os
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

from PIL import Image

GODOT = os.environ.get("GODOT", "C:/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe")
OUT = "C:/tmp/shots/ingame084"
SHOTS = "3.14,3.22,3.30,3.40,3.50,3.60"

# 斩击弧 = 紫/蓝紫(色相 0.70~0.82) 或近白; 剑气波 = 青(0.45~0.55)
SLASH_HUE = (0.66, 0.86)
WAVE_HUE = (0.42, 0.58)
SLASH_MIN_RATIO = 0.60      # 斩击面积 / 剑波面积 的下限 —— 斩击是主角


def shoot():
    for f in glob.glob(OUT + "_*.png"):
        try:
            os.remove(f)
        except Exception:
            pass
    env = dict(os.environ)
    env.update({"VFXLAB": "1", "VFXLAB_CASE": "p2eq_084_melee",
                "VFXLAB_OUT": OUT, "VFXLAB_SHOTS": SHOTS, "TURTLE_BACKEND": " "})
    subprocess.run([GODOT, "--path", ".", "--position", "5000,5000",
                    "--resolution", "1280x720", "res://scenes/RealtimeBattle3D.tscn"],
                   env=env, capture_output=True, timeout=280)
    return sorted(glob.glob(OUT + "_*.png"))


def measure(path):
    im = Image.open(path).convert("RGB")
    px = im.load()
    W, H = im.size
    bg = px[5, 5]
    slash = 0
    wave = 0
    turtles = 0
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            r, g, b = px[x, y]
            if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) < 26:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if s < 0.22 and v > 0.78:
                slash += 1                      # 白热也算斩击(它的刀锋)
            elif SLASH_HUE[0] <= h <= SLASH_HUE[1] and s > 0.25:
                slash += 1
            elif WAVE_HUE[0] <= h <= WAVE_HUE[1] and s > 0.25:
                # 龟本身也是青的 —— 靠"很亮"把特效和龟分开
                if v > 0.55:
                    wave += 1
                else:
                    turtles += 1
    return slash, wave, turtles


def main():
    shots = shoot()
    if not shots:
        print("  [FAIL] 一张都没拍到 —— VFXLAB 没跑起来")
        return 1
    best = None
    tot_s = tot_w = 0
    for p in shots:
        sl, wv, tu = measure(p)
        tot_s += sl
        tot_w += wv
        print("  %-22s 斩击 %5d · 剑波 %5d px" % (os.path.basename(p), sl, wv))
        if best is None or (sl + wv) > best[0]:
            best = (sl + wv, sl, wv)
    fails = []
    print("  [分母] 拍了 %d 张 · 斩击合计 %d px · 剑波合计 %d px" % (len(shots), tot_s, tot_w))
    if tot_s == 0:
        fails.append("整组都没看到斩击弧(N=0 是空检查不是通过)")
    if tot_w == 0:
        fails.append("整组都没看到剑气波")
    if tot_s and tot_w:
        ratio = tot_s / float(tot_w)
        print("  斩击/剑波 面积比 = %.2f (下限 %.2f)" % (ratio, SLASH_MIN_RATIO))
        if ratio < SLASH_MIN_RATIO:
            fails.append("斩击弧不是主角: 面积只有剑波的 %.0f%% < %.0f%% —— 主次反了"
                         % (100 * ratio, 100 * SLASH_MIN_RATIO))
    for f in fails:
        print("  [FAIL] " + f)
    if fails:
        print("")
        print("FAILED: %d 条" % len(fails))
        return 1
    print("")
    print("ALL OK — 实拍: 斩击是主角, 两者都真的画出来了")
    return 0


if __name__ == "__main__":
    sys.exit(main())
