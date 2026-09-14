# -*- coding: utf-8 -*-
"""【持续回复】期间挂在身上的治疗气泡 6 帧循环 (2026-09-14)。

用户 2026-09-14 看 044 深海项链时:「特效有做么, 就是这 6 秒的持续回复特效」。

现状(查过代码不是猜的): 摊付的结算在 `RealtimeBattle3DScene.gd:2430` 就两行 ——
`if _t < eq_hot_until: _heal(rate * delta)`, **纯数字零演出**。
`_heal_body_glow` 是触发那一下的一次性脉动(约 0.8 秒), 之后 5 秒多只有血条在悄悄涨。

★接在**共享字段 `eq_hot_until`** 上, 不接在 044 上 —— 044 深海项链 / 045 珍珠耳环 /
  037 蜡烛都走这个字段, 做成【演出是状态的函数】则三件自动都有
  (memory [[fb-zero-caller-is-a-whole-class]]: 写了没人读是一整类)。

★分段表见方案书; 这张图只负责第②段【持续】:
  气泡从脚下往上升 → 到顶破掉 → 循环。**整体亮度六帧几乎不变** ——
  持续态一旦明暗在跳就读成「要结束了」或「在闪」(淡出病, [[fb-vfx-defect-families]])。

★循环必须闭合: 第 5 帧接回第 0 帧不许跳。做法是气泡位置按 `(y0 - f*step) % cell`
  整体平移一格周期, 六帧正好走完一个 step 周期。

★尺子: 1 texel = 0.0426 m = 1 屏幕像素(zoom 1.0) = 1.775 码。
  cell 40×40 texel ⇒ 按 HHOT_YARDS = 71 码摆, 40×1.775 = 71 ⇒ **正好 1:1**, 不糊。
"""
import os
import math

from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

CELL = 40
FRAMES = 6
STEP = CELL // FRAMES        # 每帧上移几格 ⇒ 六帧走完一个周期, 循环闭合

CLR = (0, 0, 0, 0)
# 治疗绿(与 044 现有的全身绿光同色系, 形状是新画的)
RIM = (168, 255, 196, 236)   # 气泡亮边
BODY = (64, 196, 120, 150)   # 气泡体(半透: 龟要从里面透出来)
CORE = (222, 255, 232, 210)  # 高光点
POP = (140, 245, 180, 190)   # 破掉那一下的碎点

# 气泡: (x, 初始 y, 半径)。x 错开、半径不一, 免得读成一串规则圆点。
BUBBLES = [
    (9, 34, 4),
    (20, 27, 5),
    (30, 36, 3),
    (14, 18, 3),
    (26, 10, 4),
]


def _ring(im, ox, cx, cy, r, alpha_scale=1.0):
    """画一个空心气泡: 亮边 + 半透体 + 一个高光点。空心=读成气泡不是实心球。"""
    for y in range(cy - r - 1, cy + r + 2):
        for x in range(cx - r - 1, cx + r + 2):
            if not (0 <= x < CELL and 0 <= y < CELL):
                continue
            d = math.hypot(x - cx, y - cy)
            if d > r + 0.5:
                continue
            c = RIM if d > r - 1.0 else BODY
            c = (c[0], c[1], c[2], max(0, min(255, int(c[3] * alpha_scale))))
            if c[3] <= 0:
                continue
            im.putpixel((ox + x, y), c)
    hx, hy = cx - max(1, r // 2), cy - max(1, r // 2)
    if 0 <= hx < CELL and 0 <= hy < CELL and alpha_scale > 0.4:
        im.putpixel((ox + hx, hy), CORE)


def _draw_frame(im, f):
    ox = f * CELL
    for (bx, by0, r) in BUBBLES:
        y = (by0 - f * STEP) % CELL
        ## 越往上越淡 + 快到顶时破掉(半径收、亮度降) —— 这就是"它在升"这件事的证据。
        t = 1.0 - (y / float(CELL))          # 0 底 → 1 顶
        if t > 0.82:
            # 破掉: 三个碎点散开, 不再画整颗
            for k in range(3):
                a = k * 2.1 + f * 0.7
                px = int(bx + math.cos(a) * (r + 1))
                py = int(y + math.sin(a) * (r + 1))
                if 0 <= px < CELL and 0 <= py < CELL:
                    im.putpixel((ox + px, py), POP)
            continue
        _ring(im, ox, bx, int(y), r, 1.0 - 0.25 * t)


def main():
    im = Image.new("RGBA", (CELL * FRAMES, CELL), CLR)
    for f in range(FRAMES):
        _draw_frame(im, f)
    path = os.path.join(OUT, "heal-hot-bubbles.png")
    im.save(path)

    # ── 自检: 烘完回量, 打印实测 vs 目标 ──
    px = im.load()
    print("写出 %s  %dx%d  %d 帧, cell %d (HHOT_YARDS 应配 %.0f 码)"
          % (path, im.width, im.height, FRAMES, CELL, CELL * 1.775))
    cols = set()
    covs = []
    tops = []
    for f in range(FRAMES):
        n = 0
        top = CELL
        for y in range(CELL):
            for x in range(CELL):
                c = px[f * CELL + x, y]
                if c[3] == 0:
                    continue
                n += 1
                cols.add(c)
                top = min(top, y)
        covs.append(n)
        tops.append(top)
        print("  f%d 覆盖 %3d px (%.0f%%), 最高点 y=%d" % (f, n, 100.0 * n / (CELL * CELL), top))
    print("  色数 %d" % len(cols))
    spread = max(covs) - min(covs)
    print("  ★六帧覆盖量 %s —— 极差 %d px (%.0f%%), 不该大起大落(持续态不许整体明暗跳)"
          % (covs, spread, 100.0 * spread / max(1, max(covs))))
    assert spread < max(covs) * 0.55, "六帧覆盖量起落太大, 会读成在闪"
    assert len(set(tops)) > 1, "最高点六帧一样 —— 气泡没在动, 这就是一张贴纸"


if __name__ == "__main__":
    main()
