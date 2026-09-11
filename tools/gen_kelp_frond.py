# -*- coding: utf-8 -*-
"""gen_kelp_frond.py —— 012【海藻】的海藻叶片(6 帧生长+摇摆像素动画)。

跑法(本文件自己锁板, 直接按最终分辨率画 —— 理由同 gen_shield_shell.py):
  python tools/gen_kelp_frond.py -o assets/sprites/vfx/kelp-frond.png

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-11)
════════════════════════════════════════════════════════════════════════
用户看 012 的演出后:

    「我觉得特效完全不够商业游戏，**名称也不好，改为海藻，重做图标**」

⇒ 012 从「龟苓膏块」改名【海藻】; 它每 4 秒给自己一次护盾, 演出就该是
**海藻从脚下长起来缠住龟** —— 演出即效果本身([[fb-effect-text-is-the-spec]])。

★通用的六棱护罩(`shield-shell.png`)仍然照常罩上去 —— 那是全游戏"我有盾了"的
  统一语言; 海藻是**这件装备的来源标识**, 两层各司其职, 不是二选一。
  (所以 012 **不**置 `_own_grant_vfx`。)

════════════════════════════════════════════════════════════════════════
 ★怎么画的
════════════════════════════════════════════════════════════════════════
一格里两片叶子从底边长出来: 中线是正弦波(海藻在水里的自然弯曲), 宽度从根部
向尖端收细, 外面留一圈暗描边。两片相位差半个周期 ⇒ 读起来是"一丛"不是"一根"。

6 帧讲的是: 长出来(f0 f1 f2) → 长足后左右各摇一下(f3 f4) → 尖端卷起收势(f5)。
**没有 alpha 渐变** —— 收势靠形状变化与明度档位, 不靠淡出(防【淡出病】)。

★颜色是**带色相的**(不像护罩那张是纯灰) —— 海藻就该是海藻的颜色, 调用点不 modulate。
"""
import argparse
import math
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

from PIL import Image

CW, CH = 32, 48        # 每帧宽×高(最终像素)
FRAMES = 6

## kelp 板(与 tools/pixelize_sheet.PALETTES["kelp"] 逐字一致, 索引 0 最亮)
P = [
    (214, 240, 186),   # 叶尖受光
    (150, 200, 110),   # 亮叶面
    ( 92, 152,  76),   # 主叶色
    ( 48, 104,  60),   # 暗面
    ( 24,  58,  40),   # 描边
]

## 每帧: 长到多高(占格高) / 整丛的摆动相位 / 尖端是否卷起
GROW = [0.32, 0.62, 0.86, 0.94, 0.94, 0.90]   # ★封顶 0.94: 长到 1.00 会正好顶到格顶, 尖看着像被切平
SWAY = [0.00, 0.18, -0.10, 0.30, -0.30, 0.14]
CURL = [0.0, 0.0, 0.0, 0.0, 0.0, 0.55]

BLADES = [
    ## (根部 x 偏移, 波长, 振幅, 根部半宽, 相位)
    ## ★宽度是重做过的: 第一版 hw=0.10~0.175, 渲出来只有 2px 宽 —— 读成"铁丝"不是海藻,
    ##   而且 2px 宽里根本塞不下"受光面/主色/暗面/描边"四档。海藻是**带状叶片**, 得宽。
    (-0.34, 1.15, 0.22, 0.40, 0.00),
    ( 0.30, 0.95, 0.18, 0.32, 2.35),
    ( 0.02, 1.45, 0.13, 0.22, 4.30),
]


def _blade_px(u, t, b, sway, curl):
    """点 (u, t) 在这片叶子上的**带符号**横向位置 s ∈ [-1, 1]; 不在叶上返回 None。

    ★为什么要带符号: 第一版返回的是 |距离|, 于是只能做"中线亮边缘暗",
      那是管子不是叶片。带符号才能把光放在**左上方那一侧**, 叶片才有正反面。
    u: 横向 -1..1(格宽的一半为 1) ／ t: 纵向 0=根 1=尖
    """
    x0, wl, amp, hw, ph = b
    ## 中线: 正弦弯曲 + 本帧的整体摆动(越靠尖摆得越多 —— 根是扎住的)
    cx = x0 + amp * math.sin(t * math.tau / wl + ph) + sway * (t ** 1.6)
    ## 尖端卷起(收势帧): 最上面那段额外往一侧拐
    if curl > 0.0 and t > 0.62:
        cx += curl * ((t - 0.62) / 0.38) ** 2
    ## 宽度: 根宽尖窄, 但收得慢(海藻是带子, 不是锥子)
    w = hw * (1.0 - t) ** 0.34 + 0.030
    s = (u - cx) / max(1e-6, w)
    if abs(s) > 1.0:
        return None
    return s


def frame(k):
    img = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    ld = img.load()
    grow, sway, curl = GROW[k], SWAY[k], CURL[k]
    for py in range(CH):
        for px in range(CW):
            u = (px + 0.5 - CW * 0.5) / (CW * 0.5)
            t = (CH - 1 - py) / float(CH - 1)          # 0 = 格底(根) … 1 = 格顶(尖)
            if t > grow:
                continue                                # 还没长到这么高
            ## 每片叶子按自己的"实际长度"归一 —— 否则长到一半时波形会被拉伸
            tt = t / max(1e-6, grow)
            best = None
            for b in BLADES:
                s = _blade_px(u, tt, b, sway, curl)
                if s is not None and (best is None or abs(s) < abs(best)):
                    best = s
            if best is None:
                continue
            ## 光从**左上**来: 左半边是受光面, 右半边是背光面, 最外一圈是描边。
            if abs(best) > 0.70:
                col = P[4]                              # 描边
            elif best < -0.34:
                col = P[1]                              # 受光面
            elif best < 0.30:
                col = P[2]                              # 主叶色
            else:
                col = P[3]                              # 背光面
            ## 受光边的一道细高光: 只在叶片中段偏上, 不满片撒
            ## (第一版把最亮那档放在**尖端**, 渲出来是一截白线头, 像被剪断的铁丝)
            if -0.78 < best < -0.52 and 0.22 < tt < 0.86:
                col = P[0]
            ld[px, py] = col + (255,)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", required=True)
    a = ap.parse_args()
    sheet = Image.new("RGBA", (CW * FRAMES, CH), (0, 0, 0, 0))
    for k in range(FRAMES):
        sheet.paste(frame(k), (k * CW, 0))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)) or ".", exist_ok=True)
    sheet.save(a.out)

    px = sheet.load()
    cols, semi, op = set(), 0, 0
    per = [0] * FRAMES
    for y in range(CH):
        for x in range(CW * FRAMES):
            r, g, b, al = px[x, y]
            if al == 0:
                continue
            if al < 255:
                semi += 1
            else:
                op += 1
                per[x // CW] += 1
            cols.add((r, g, b))
    print("  %s  %dx%d (%d 帧)  色数 %d  半透 %d  不透明 %d"
          % (a.out, CW * FRAMES, CH, FRAMES, len(cols), semi, op))
    print("  每帧不透明像素: %s" % per)
    return 0


if __name__ == "__main__":
    sys.exit(main())
