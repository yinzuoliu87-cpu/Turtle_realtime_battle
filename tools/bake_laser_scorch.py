# -*- coding: utf-8 -*-
"""051 激光手枪【地面灼痕】4 帧 (2026-09-14)。

为什么要这张图 —— 见 docs/plans/20260914-046至051第五批与判定带三件.md §方案A 第④段:
  051 的判定是「中线两侧各 50 码」, 而 `_laser_beam` 画的带子是**立起来的**
  (`up = Vector3(0, half_w, 0)`), 四个角在地面上完全重合 ⇒ 地面横向宽度**恒为 0**。
  第③段的顶点色地面带负责把那 100 码画出来(边缘亮/内侧暗),
  这张图负责给那条带子**材质** —— 光扫过的地面被烧出来的坑。

★为什么不复用 `lava-crack.png` / `eq006-groundslit.png`:
  素材不复用铁律(用户 2026-08-03 定·08-04 重申)。那两张是岩浆/剑痕, 是别人的东西。

★形状必须【径向不规则】不能是长条:
  精灵贴地后**不许自由旋转**(像素风三条硬约束), 而激光的方向是任意的。
  画成沿某个方向的长条, 只有激光正好水平时才对 —— 034 那次踩过同一个坑,
  当时的解法是"对称就不需要旋转"。这里同理: 一团不规则的**圆形**烧斑,
  转到任何角度都说得通。

★尺子: 1 texel = 0.0426 m = 1 屏幕像素(zoom 1.0) = 1.775 码。
  cell 20×20 texel ⇒ 贴进游戏按 SCORCH_YARDS = 34 码摆, 34/20 = 1.7 码/texel,
  与 1.775 只差 4% ⇒ 接近 1:1, 不糊。

★四帧在说四件事(不是同一张图淡出 —— 淡出病):
  f0 白热击中(最小最亮) / f1 烧穿最大(焦黑边 + 橙裂缝) / f2 余烬冷却 / f3 灰烬将散
"""
import os
import math
import random

from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

CELL = 20
FRAMES = 4

# 锁定调色板(暗→亮)。红系跟 051 自己的激光同色系(#ff5a72 / #ff8aa0),
# 但形状是新画的 —— 铁律管的是"别拿别人的图顶替", 不是"不许同色系"。
CLR = (0, 0, 0, 0)
CHAR = (46, 26, 24, 255)     # 焦黑(最外圈轮廓)
CHR2 = (86, 46, 40, 255)     # 焦褐
RED = (176, 54, 46, 255)     # 暗红余温
ORNG = (246, 132, 58, 255)   # 橙热
HOT = (255, 214, 150, 255)   # 白热边
WHT = (255, 248, 226, 255)   # 命中瞬间的白核
ASH = (118, 102, 96, 255)    # 灰烬


def _blob(rng, n, base_r, jitter):
    """一圈每个角度的半径 —— 径向不规则(不是正圆, 也不是长条)。"""
    ring = []
    for k in range(n):
        ring.append(base_r * (1.0 + rng.uniform(-jitter, jitter)))
    # 平滑一遍, 免得锯成刺猬
    out = []
    for k in range(n):
        out.append((ring[k - 1] + ring[k] * 2.0 + ring[(k + 1) % n]) / 4.0)
    return out


def _radius_at(ring, ang):
    n = len(ring)
    f = (ang % (2.0 * math.pi)) / (2.0 * math.pi) * n
    i = int(f) % n
    j = (i + 1) % n
    t = f - int(f)
    return ring[i] * (1.0 - t) + ring[j] * t


def _draw(im, ox, ring_out, ring_in, cols, rng, ember_n, ember_col):
    """cols = (最外轮廓, 环带, 内芯)。内芯用 ring_in 划出来。"""
    cx = cy = CELL / 2.0 - 0.5
    for y in range(CELL):
        for x in range(CELL):
            dx = x - cx
            dy = y - cy
            d = math.hypot(dx, dy)
            if d < 0.001:
                ang = 0.0
            else:
                ang = math.atan2(dy, dx)
            ro = _radius_at(ring_out, ang)
            ri = _radius_at(ring_in, ang)
            if d > ro:
                continue
            if d > ro - 1.15:
                c = cols[0]
            elif d > ri:
                c = cols[1]
            else:
                c = cols[2]
            im.putpixel((ox + x, y), c)
    # 余烬/裂缝: 在环带上点几颗更亮的
    for _ in range(ember_n):
        ang = rng.uniform(0.0, 2.0 * math.pi)
        ro = _radius_at(ring_out, ang)
        ri = _radius_at(ring_in, ang)
        r = rng.uniform(min(ri, ro) * 0.25, max(ro - 1.6, 0.6))
        x = int(round(cx + math.cos(ang) * r))
        y = int(round(cy + math.sin(ang) * r))
        if 0 <= x < CELL and 0 <= y < CELL:
            im.putpixel((ox + x, y), ember_col)


def main():
    rng = random.Random(51051)          # 定死种子: 同一份脚本永远烘出同一张图
    im = Image.new("RGBA", (CELL * FRAMES, CELL), CLR)

    # f0 白热击中 —— 最小、最亮, 说的是"光刚打到这儿"
    r0 = _blob(rng, 24, 4.6, 0.20)
    _draw(im, 0 * CELL, r0, _blob(rng, 24, 2.3, 0.22),
          (ORNG, HOT, WHT), rng, 5, WHT)

    # f1 烧穿最大 —— 焦黑外圈 + 橙裂缝, 这一帧是主帧
    r1 = _blob(rng, 24, 8.4, 0.22)
    _draw(im, 1 * CELL, r1, _blob(rng, 24, 4.0, 0.26),
          (CHAR, CHR2, ORNG), rng, 9, HOT)

    # f2 余烬冷却 —— 同样大, 但内芯从橙退到暗红, 亮点少一半
    r2 = _blob(rng, 24, 8.0, 0.24)
    _draw(im, 2 * CELL, r2, _blob(rng, 24, 4.4, 0.26),
          (CHAR, CHR2, RED), rng, 4, ORNG)

    # f3 灰烬将散 —— 只剩焦褐/灰, 面积开始收, 没有一点热色
    r3 = _blob(rng, 24, 6.4, 0.26)
    _draw(im, 3 * CELL, r3, _blob(rng, 24, 3.2, 0.28),
          (CHR2, ASH, CHR2), rng, 3, ASH)

    path = os.path.join(OUT, "laser-scorch.png")
    im.save(path)

    # ── 自检: 烘完回量, 打印实测 vs 目标(别只相信脚本说它画了什么) ──
    px = im.load()
    print("写出 %s  %dx%d  %d 帧, cell %d" % (path, im.width, im.height, FRAMES, CELL))
    cols = set()
    for f in range(FRAMES):
        n = 0
        lum_hi = 0
        for y in range(CELL):
            for x in range(CELL):
                c = px[f * CELL + x, y]
                if c[3] == 0:
                    continue
                n += 1
                cols.add(c)
                if (c[0] * 299 + c[1] * 587 + c[2] * 114) // 1000 >= 150:
                    lum_hi += 1
        print("  f%d 覆盖 %3d px (%.0f%%), 其中亮度≥150 的 %2d px (%.0f%%)"
              % (f, n, 100.0 * n / (CELL * CELL), lum_hi, 100.0 * lum_hi / max(1, n)))
    print("  色数 %d (NEAREST 像素风, 不许出现插值过渡色)" % len(cols))
    assert len(cols) <= 8, "色数超了 —— 说明哪里混了插值"


if __name__ == "__main__":
    main()
