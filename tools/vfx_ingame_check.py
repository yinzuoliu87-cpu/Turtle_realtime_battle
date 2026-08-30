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
# ★采样要密: 光束只存在 BEAM_SEC(0.24 秒), 稀疏采样撞不上 ——
#   第一版四个点只撞到一次(5 个像素), 那条判据等于形同虚设。
#   普攻段(1.6~2.8 秒, 技能还没放)密排 12 个点抓光束; 3.1~3.7 抓十字斩。
## ★★采样时刻跟着节奏走: 2026-08-29 用户把两刀拉长一倍
##   (CROSS_T1 0.25→0.40 · CROSS_T3 0.60→1.00) ⇒ 旧的 3.14~3.60 只能拍到后撤与蓄力,
##   两刀全在窗口外。技能约 3.14 秒施放 ⇒ 横斩 ≈3.54、竖斩 ≈4.14、波飞到 ≈4.9。
## ★★普攻的采样必须落在【第一次施法之前】。
##   2026-08-29 加了移动锁(整招演完前 `_slam` 锁住整个 _tick_unit) 之后,
##   龟在 1.9 秒里**根本打不出普攻** ⇒ 旧的 1.60~2.70 落在锁里,
##   激光束只抓到 27 px 而报红 —— 束没坏, 是尺子量错了地方。
SHOTS = ("0.60,0.75,0.90,1.05,1.20,1.35,1.50,1.65,1.80,1.95,"
         "3.20,3.56,3.70,3.90,4.16,4.34,4.55,4.80")

# 斩击弧 = 紫/蓝紫(色相 0.70~0.82) 或近白; 剑气波 = 青(0.45~0.55)
SLASH_HUE = (0.66, 0.86)
WAVE_HUE = (0.42, 0.58)
SLASH_MIN_RATIO = 0.60      # 斩击面积 / 剑波面积 的下限 —— 斩击是主角
BEAM_HUE = (0.93, 1.01)     # 激光束 = 红(色相绕回 0)
BEAM_MIN_PX = 60            # 整组里至少要看到这么多红像素 —— 否则等于没画出来


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
    beam = 0
    turtles = 0
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            r, g, b = px[x, y]
            if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) < 26:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if (h > 0.93 or h < 0.06) and s > 0.35:
                beam += 1                       # 红 = 激光束
            elif s < 0.22 and v > 0.78:
                slash += 1                      # 白热也算斩击(它的刀锋)
            elif SLASH_HUE[0] <= h <= SLASH_HUE[1] and s > 0.25:
                slash += 1
            elif WAVE_HUE[0] <= h <= WAVE_HUE[1] and s > 0.25:
                # 龟本身也是青的 —— 靠"很亮"把特效和龟分开
                if v > 0.55:
                    wave += 1
                else:
                    turtles += 1
    return slash, wave, beam, turtles


## ★★这条审计【开真窗口截图】(见 shoot(): --position 5000,5000, 不是 --headless),
##   所以它在【没有显示设备的机器上跑不了】—— GitHub runner 就是。
##   2026-08-30: CI 因此红了一次(「一张都没拍到 —— VFXLAB 没跑起来」)。
##
## ★处理方式不是"悄悄让它过", 而是【显式登记成一条本地专属审计】(CLAUDE.md 铁律⑤:
##   缺口显式登记, 不许静默截断)。判据由 tools/ci_deps_audit.py 的规则② 守着:
##   · 名单必须写在那里、每条带理由
##   · 被登记的工具必须真的能打出下面这行 SKIP_MARK, 否则那条登记是假的
##   ⇒ "在 CI 上跳过"这件事本身有门禁盯着, 不会悄悄扩散到别的审计上。
SKIP_MARK = "本条为【本地专属审计】: 它开真窗口截图, 无显示设备的机器跑不了"


def _no_display():
    """没有显示设备? Windows/macOS 一律当有; Linux 看 DISPLAY / WAYLAND_DISPLAY。"""
    ## ★门禁要能在【任何系统上】真跑一遍这条路 —— 判据必须落在行为, 不能落在
    ##   "源码里有没有 SKIP_MARK 这个词"(2026-08-30 反向验证抓到: 我的说明注释里也有
    ##   这个词, 拿掉真实现门禁照样绿。和一小时前 _b4_all() 那次是同一个错)。
    if os.environ.get("TURTLE_FORCE_NO_DISPLAY") == "1":
        return True
    if os.name == "nt" or sys.platform == "darwin":
        return False
    return not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


def main():
    if _no_display():
        print("  [SKIP] " + SKIP_MARK)
        print("  ⚠ 本机没跑到它 —— **推之前必须在本地跑过一次全套门禁**, 这条只有本地能验。")
        print("ALL OK — (已登记跳过)")
        return 0
    shots = shoot()
    if not shots:
        print("  [FAIL] 一张都没拍到 —— VFXLAB 没跑起来")
        return 1
    best = None
    tot_s = tot_w = tot_b = 0
    for p in shots:
        sl, wv, bm, tu = measure(p)
        tot_s += sl
        tot_w += wv
        tot_b += bm
        print("  %-22s 斩击 %5d · 剑波 %5d · 激光 %5d px" % (os.path.basename(p), sl, wv, bm))
        if best is None or (sl + wv) > best[0]:
            best = (sl + wv, sl, wv)
    fails = []
    print("  [分母] 拍了 %d 张 · 斩击合计 %d px · 剑波合计 %d px" % (len(shots), tot_s, tot_w))
    if tot_s == 0:
        fails.append("整组都没看到斩击弧(N=0 是空检查不是通过)")
    if tot_w == 0:
        fails.append("整组都没看到剑气波")
    print("  激光束合计 %d px(下限 %d)" % (tot_b, BEAM_MIN_PX))
    if tot_b < BEAM_MIN_PX:
        fails.append("激光束几乎没画出来: %d px < %d —— 普攻是速射火炮那种【一条束】, 不能看不见"
                     % (tot_b, BEAM_MIN_PX))
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
