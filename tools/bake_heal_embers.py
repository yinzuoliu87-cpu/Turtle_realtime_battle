# -*- coding: utf-8 -*-
"""045 地狱护盾【持续回复】期间的余烬内收 6 帧循环 (2026-09-14)。

用户 2026-09-14:「045 也需要做个回复 buff 持续特效, 你想想怎么办, **不要和之前上一个重复**」。

★先说清背景: 045 **已经在放 044 那套气泡了** —— 持续演出接在共享字段 `eq_hot_until` 上,
  044 深海项链 / 045 地狱护盾 / 037 蜡烛三件自动都有。所以这不是"045 缺特效",
  是"045 跟 044 撞了"。正确做法是保留共享机制、**按持有者换素材**
  (memory [[fb-fix-the-shared-primitive-not-one-instance]]: 单件花样是第二层, 不是替代品)。

★怎么保证"不重复"能被**量出来**而不是我说了算 —— 判据落在**运动方向**上:
    044 气泡: 亮点逐帧**向上**走(y 递减), 到顶破掉        —— 水
    045 余烬: 亮点逐帧**向内**收(到中心的距离递减), 沉进身体 —— 火 / 护盾吸收
  两者的位移方向正交, 门禁逐帧量得出来(见 tests/verify_heal_hot_readout.gd 判据④)。

★为什么是"向内收"而不是随便换个颜色: 045 是【地狱护盾】, 它的效果是把自己烧回满血。
  火星往身体里沉 = "在吸收", 与 044 的"水从脚下往上漫"是两件事, 不只是配色不同。
  ⚠ 没有把"敌人身上的灼烧飞回来"画进去 —— 文案里没有那条因果, 画了就是凭空发明
  (memory [[fb-effect-text-is-the-spec]] / [[fb-telegraph-needs-a-cause-not-a-flash]])。

★尺子: 1 texel = 0.0426 m = 1 屏幕像素(zoom 1.0) = 1.775 码。
  cell 40×40 texel ⇒ 与 044 同样按 71 码摆, 正好 1:1。
"""
import os
import math

from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

CELL = 40
FRAMES = 6
CX = CY = CELL / 2.0 - 0.5

CLR = (0, 0, 0, 0)
# 地狱火色阶(暗→亮)。与 045 自己的火球/灼烧同色系, 形状是新画的。
EMBER_D = (92, 24, 16, 170)    # 余烬暗部
EMBER_M = (186, 62, 24, 200)   # 余烬中段
EMBER_L = (246, 136, 42, 230)  # 余烬亮部
SPARK = (255, 226, 150, 245)   # 火星尖端(最亮)
RING = (168, 52, 28, 168)      # 沉入身体那一圈暗红余温(半透, 不挡龟)

# 八颗火星: (起始角度, 起始半径)。半径不一 ⇒ 不会读成一圈规则的点。
## ★第一版只有 8 颗, 烘完实测每帧只覆盖 37~42 px(2~3%), 而 044 的气泡是 188~309 px
##   (12~19%) —— 盖在龟身上等于看不见。加到 15 颗并给核心加粗。
EMBERS = [
    (0.00, 19.0), (0.42, 17.2), (0.79, 16.5), (1.15, 18.8), (1.57, 18.0),
    (1.98, 15.8), (2.36, 15.0), (2.75, 19.2), (3.14, 19.5), (3.52, 17.0),
    (3.93, 16.0), (4.32, 18.6), (4.71, 17.5), (5.10, 15.4), (5.50, 14.5),
]
R_IN = 4.0            # 收到这个半径就算"沉进去了"
R_STEP = (19.5 - R_IN) / float(FRAMES)   # 每帧往里收多少 ⇒ 六帧走完一个周期, 循环闭合


def _px(im, ox, x, y, c):
    xi, yi = int(round(x)), int(round(y))
    if 0 <= xi < CELL and 0 <= yi < CELL:
        im.putpixel((ox + xi, yi), c)


def _draw_frame(im, f):
    ox = f * CELL
    ## 身体外缘那一圈暗红余温: 断续的弧(不是闭合圆环 —— 闭合亮环是禁区形状),
    ## 逐帧换相位 ⇒ 看得出它在转。
    for k in range(34):
        a = k * (2.0 * math.pi / 34.0) + f * 0.26
        if (k + f) % 3 == 0:
            continue                      # 断口: 让它是"一串余温"不是一个环
        r = 17.5 + 1.2 * math.sin(a * 3.0 + f)
        _px(im, ox, CX + math.cos(a) * r, CY + math.sin(a) * r * 0.72, RING)

    for (a0, r0) in EMBERS:
        ## 向内收: 半径随帧递减, 到底了就回到外圈(循环闭合)
        r = r0 - f * R_STEP
        while r < R_IN:
            r += (19.5 - R_IN)
        ang = a0 + f * 0.14                     # 一边内收一边略微旋转, 像被吸进去
        x = CX + math.cos(ang) * r
        y = CY + math.sin(ang) * r * 0.72       # 0.72: 俯视角下圆压成椭圆
        t = 1.0 - (r - R_IN) / (19.5 - R_IN)    # 0 外 → 1 内
        core = SPARK if t > 0.62 else (EMBER_L if t > 0.3 else EMBER_M)
        _px(im, ox, x, y, core)
        ## 核心加粗成 2 格(越往里越粗) —— 单像素火星在 1:1 下看不见
        if t > 0.34:
            _px(im, ox, x + 1, y, core)
            if t > 0.62:
                _px(im, ox, x, y + 1, EMBER_L)
        ## 拖尾: 朝外拖两格(它是往里走的, 尾巴在外面)
        for s in (1, 2):
            rr = r + s * 1.6
            c = EMBER_M if s == 1 else EMBER_D
            _px(im, ox, CX + math.cos(ang) * rr, CY + math.sin(ang) * rr * 0.72, c)


def main():
    im = Image.new("RGBA", (CELL * FRAMES, CELL), CLR)
    for f in range(FRAMES):
        _draw_frame(im, f)
    path = os.path.join(OUT, "heal-hot-embers.png")
    im.save(path)

    # ── 自检: 烘完回量 —— 重点是【火星到中心的距离逐帧递减】 ──
    px = im.load()
    print("写出 %s  %dx%d  %d 帧, cell %d" % (path, im.width, im.height, FRAMES, CELL))
    cols = set()
    mean_r = []
    for f in range(FRAMES):
        n = 0
        rs = []
        for y in range(CELL):
            for x in range(CELL):
                c = px[f * CELL + x, y]
                if c[3] == 0:
                    continue
                n += 1
                cols.add(c)
                ## 只统计**火星**(亮档), 不统计外缘那圈余温 —— 要量的是它们在内收
                if c[3] >= 200 and c[0] > 180:
                    rs.append(math.hypot(x - CX, (y - CY) / 0.72))
        r = sum(rs) / max(1, len(rs))
        mean_r.append(r)
        print("  f%d 覆盖 %3d px (%.0f%%), 火星 %2d 颗, 平均半径 %.1f texel"
              % (f, n, 100.0 * n / (CELL * CELL), len(rs), r))
    print("  色数 %d" % len(cols))
    print("  ★六帧平均半径 %s" % ["%.1f" % v for v in mean_r])
    drops = sum(1 for i in range(FRAMES - 1) if mean_r[i + 1] < mean_r[i])
    print("  ★逐帧递减的次数 %d / %d(最后一帧回到外圈是循环闭合, 不计)" % (drops, FRAMES - 1))
    assert drops >= FRAMES - 2, "火星没有在向内收 —— 那就和 044 的气泡没区别了"


if __name__ == "__main__":
    main()
