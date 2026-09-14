# -*- coding: utf-8 -*-
"""059 沙漏【胸口白金光点】8 帧 (2026-09-15)。

★由来 —— 用户 2026-09-14 原话:
  「直接是人物冒战斗特效，能量波几道？**从人物中间爆开，中间是什么颜色特效**，
    然后能量波再从全世界收回人物中心…」
  参考 clip.mp4 10.83~10.97 秒(#025~#029, 30fps 每帧看过):
    #025~#026  DIO **胸口正中亮起一个白金光点**(白芯 + 淡金晕), 周围飘几颗火星
    #027~#028  光点从胸口爆开, 白金光把上半身吞掉
    #029       全身发白金光, 火往上冲 —— 下一帧(11.03)白紫粗环就冲出去了
  ⇒ 「中间」= 这个点: **白芯 + 金晕**。前四版这里是一张涡环贴图(ts-vortex.png, 暖橙→冷紫),
    颜色、形状、时机都不对: 它在释放**之后**才出现, 而参考的光点在释放**之前 0.17 秒**就亮了。

★帧分配(与 timestop_system.gd 的 TS_CORE_* 对应):
  f0~f2  蓄力最后 0.17 秒: 点 → 带四根短芒 → 带八根芒(参考 #025~#026 那个点在长大)
  f3~f4  释放: 爆开, 白芯撑大、锯齿金边、芒拉长(参考 #027~#029)
  f5     掏空: 白芯变成一圈, 中间转暗金(爆开之后中心先空 —— 环已经冲出去了)
  f6~f7  碎成火星散掉(不淡出: 散成碎点, 覆盖自己掉下去)

★尺子: cell 40 texel, 1 texel = 0.0426 m ⇒ 1.70 m, 按 71 码摆(40 × 1.775) = 1:1 不糊。
★像素画: 不做抗锯齿、色数 ≤ 8; 边缘锯齿用确定性噪声(同样输入烤出同样的图)。
"""
import math
import os

from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

CELL = 40
FRAMES = 8
C = CELL / 2.0 - 0.5

W = (255, 253, 240, 255)     # 白芯
Y1 = (255, 238, 164, 255)    # 淡金(晕的内圈)
Y2 = (248, 206, 104, 235)    # 金
G1 = (226, 166, 58, 215)     # 深金(锯齿边)
G2 = (176, 112, 36, 170)     # 暗金(火星)


def _nz(i, k):
    v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
    return v - math.floor(v)


def disc(im, ox, r_in, r_out, col, jag=0.0, seed=0):
    """实心/空心圆, 外缘按 16 个方位各自抖动 jag 格 ⇒ 锯齿边不是规则圆。"""
    for y in range(CELL):
        for x in range(CELL):
            dx, dy = x - C, y - C
            d = math.hypot(dx, dy)
            sec = int(((math.atan2(dy, dx) + math.pi) / (2.0 * math.pi)) * 16) % 16
            ro = r_out + jag * (_nz(sec, seed) - 0.5) * 2.0
            if r_in <= d <= ro:
                im.putpixel((ox + x, y), col)


def rays(im, ox, n, r0, lens, cols, rot=0.0):
    for i in range(n):
        a = rot + 2.0 * math.pi * i / n
        L = lens[i % len(lens)]
        s = r0
        while s <= L:
            c = cols[0] if s < r0 + (L - r0) * 0.5 else cols[1]
            xi, yi = int(round(C + math.cos(a) * s)), int(round(C + math.sin(a) * s))
            if 0 <= xi < CELL and 0 <= yi < CELL:
                im.putpixel((ox + xi, yi), c)
            s += 0.5


def sparks(im, ox, n, r0, r1, cols, seed):
    for i in range(n):
        a = 2.0 * math.pi * _nz(i, seed)
        r = r0 + (r1 - r0) * _nz(i, seed + 1)
        xi, yi = int(round(C + math.cos(a) * r)), int(round(C + math.sin(a) * r))
        c = cols[i % len(cols)]
        if 0 <= xi < CELL and 0 <= yi < CELL:
            im.putpixel((ox + xi, yi), c)
            if _nz(i, seed + 2) > 0.5 and 0 <= yi + 1 < CELL:   # 一半火星拖一格(在动)
                im.putpixel((ox + xi, yi + 1), G2)


def frame(im, f):
    ox = f * CELL
    if f == 0:
        disc(im, ox, 0, 2.2, Y2)
        disc(im, ox, 0, 1.3, Y1)
        disc(im, ox, 0, 0.8, W)
    elif f == 1:
        rays(im, ox, 4, 2.0, [5.0], (Y1, Y2))
        disc(im, ox, 0, 3.0, Y2)
        disc(im, ox, 0, 2.2, Y1)
        disc(im, ox, 0, 1.3, W)
    elif f == 2:
        rays(im, ox, 8, 2.5, [9.0, 5.5], (Y2, G1))
        disc(im, ox, 0, 4.5, Y2, jag=1.0, seed=2)
        disc(im, ox, 0, 3.2, Y1)
        disc(im, ox, 0, 2.0, W)
    elif f == 3:
        rays(im, ox, 12, 5.0, [9 + 5 * _nz(i, 3) for i in range(12)], (Y1, G1), rot=0.13)
        disc(im, ox, 0, 7.0, Y2, jag=2.0, seed=3)
        disc(im, ox, 0, 5.5, Y1, jag=1.5, seed=4)
        disc(im, ox, 0, 3.8, W, jag=1.0, seed=5)
    elif f == 4:
        rays(im, ox, 16, 8.0, [12 + 6 * _nz(i, 6) for i in range(16)], (Y2, G1), rot=0.07)
        disc(im, ox, 0, 11.0, G1, jag=3.0, seed=6)
        disc(im, ox, 0, 9.5, Y2, jag=2.5, seed=7)
        disc(im, ox, 0, 7.5, Y1, jag=2.0, seed=8)
        disc(im, ox, 0, 5.5, W, jag=1.5, seed=9)
    elif f == 5:
        rays(im, ox, 16, 11.0, [14 + 5 * _nz(i, 10) for i in range(16)], (G1, G2), rot=0.19)
        disc(im, ox, 7.0, 13.0, G1, jag=3.0, seed=11)
        disc(im, ox, 8.0, 12.0, Y2, jag=2.0, seed=12)
        disc(im, ox, 9.0, 11.0, W, jag=1.5, seed=13)
        disc(im, ox, 0, 3.5, G1)                       # 掏空: 中心转暗金
    elif f == 6:
        sparks(im, ox, 26, 11.0, 18.0, (Y2, G1, Y1), seed=14)
        for sec in range(16):                          # 断开的弧: 只剩一半方位
            if _nz(sec, 15) > 0.5:
                a = 2.0 * math.pi * sec / 16
                for rr in (12.0, 13.0):
                    im.putpixel((ox + int(round(C + math.cos(a) * rr)), int(round(C + math.sin(a) * rr))), G1)
        disc(im, ox, 0, 1.2, Y2)
    elif f == 7:
        sparks(im, ox, 14, 15.0, 19.0, (G1, G2), seed=16)


def main():
    im = Image.new("RGBA", (CELL * FRAMES, CELL), (0, 0, 0, 0))
    for f in range(FRAMES):
        frame(im, f)
    path = os.path.join(OUT, "ts-core.png")
    im.save(path)

    # ── 自检: 烘完回量(每条判据对着上面那张帧分配表) ──
    px = im.load()
    covs, cols = [], set()
    for f in range(FRAMES):
        n = 0
        for y in range(CELL):
            for x in range(CELL):
                c = px[f * CELL + x, y]
                if c[3]:
                    n += 1
                    cols.add(c)
        covs.append(n)
        print("  f%d 覆盖 %4d px (%.1f%%)" % (f, n, 100.0 * n / (CELL * CELL)))
    print("写出 %s  %dx%d · 色数 %d" % (path, im.width, im.height, len(cols)))
    assert covs[0] < 0.02 * CELL * CELL, "f0 应该只是一个点"
    assert covs[0] < covs[1] < covs[2] < covs[3] < covs[4], "f0~f4 必须一路长大(点 → 爆开)"
    ci = int(C + 0.5)
    assert px[5 * CELL + ci, ci] != W and px[4 * CELL + ci, ci] == W, "f4 白芯满 / f5 中心必须掏空转暗"
    assert covs[7] < 0.03 * CELL * CELL, "f7 应该只剩几颗火星(散掉, 不是淡出)"
    assert covs[7] < covs[6] < covs[4], "f4 → f6 → f7 覆盖一路掉(碎散)"
    assert len(cols) <= 8, "色数 %d 太多" % len(cols)


if __name__ == "__main__":
    main()
