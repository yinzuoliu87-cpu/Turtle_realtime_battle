# -*- coding: utf-8 -*-
"""043 海浪护符【浪墙扫到谁】那一下的水花 (2026-09-13)。

原状(实拍 16 帧看过): `_water_splash` = `_skill_ring` 一圈**程序生成的椭圆环** +
4 颗 `VfxTex._make_glow_texture()` 程序光点上飘。圆环与光球都在禁区里,
实拍读成"地上多了两个蓝圈"。⇒ 换成真正的水花: 王冠状的水冠 + 往外崩的水滴。

★左右对称 ⇒ 不 flip 不旋转(像素风不许自由旋转)。
★尺子: 1 texel = 0.0426 m = 1.775 码。24×16 texel = 42.6 × 28.4 码。
"""
import os, math
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

D = (12, 58, 82, 255)
M = (46, 160, 200, 255)
L = (128, 226, 246, 255)
W = (232, 252, 255, 255)
CLR = (0, 0, 0, 0)

CW, CH, CN = 24, 16, 6
GROUND = CH - 1
CX = CW // 2
# 水冠高度 / 张开半径(相对) —— 先窜起再摊开落下
CROWN = [0.35, 0.80, 1.00, 0.78, 0.46, 0.18]
SPREAD = [0.25, 0.55, 0.80, 1.00, 1.00, 1.00]


def _px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c)


def bake():
    im = Image.new("RGBA", (CW * CN, CH), CLR)
    hmax = CH - 4
    rmax = CW / 2.0 - 1.5
    for f in range(CN):
        ox = f * CW
        h = hmax * CROWN[f]
        r = rmax * SPREAD[f]
        ## 水冠: 两片向外张开的"墙", 中间空 —— 空心才像水冠, 实心就是个土包
        for sgn in (-1, 1):
            for k in range(int(round(r))):
                t = k / max(1.0, r)
                wall = h * (1.0 - t * t) * (0.55 + 0.45 * (1.0 - t))
                if wall < 0.8:
                    continue
                x = CX + sgn * k
                top = int(round(GROUND - wall))
                for y in range(top, GROUND + 1):
                    d = y - top
                    c = W if d == 0 else (L if d <= 1 else M)
                    if d > 2 and (x + y + f) % 3 == 0:
                        c = D                       # 冠内挖空一点, 不做实心
                    _px(im, ox + x, y, c)
                _px(im, ox + x, top - 1, D)
        ## 冠口: 中间那一圈压低(水被推开留下的坑)
        for x in range(CX - 1, CX + 2):
            _px(im, ox + x, GROUND, D)
            _px(im, ox + x, GROUND - 1, CLR)
        ## 崩出去的水滴: 逐帧越飞越远越低(抛物线)
        for k in range(6):
            sgn = 1 if k % 2 else -1
            age = f / float(CN - 1)
            dx = CX + sgn * int(round(2 + k * 1.4 + age * 8))
            dy = int(round(GROUND - h - 1 - math.sin(min(1.0, age + k * 0.06) * math.pi) * 6 + k * 0.4))
            _px(im, ox + dx, dy, W if k % 2 else L)
            _px(im, ox + dx, dy + 1, D)
    p = os.path.join(OUT, "wave-splash.png")
    im.save(p)
    return p, im


if __name__ == "__main__":
    p, im = bake()
    print("  wave-splash.png  %dx%d = %d 帧 × %dx%d" % (im.width, im.height, CN, CW, CH))
    for f in range(CN):
        cell = im.crop((f * CW, 0, (f + 1) * CW, CH))
        px = list(cell.getdata())
        op = [q for q in px if q[3] > 0]
        br = [q for q in op if (q[0] + q[1] + q[2]) / 3.0 >= 110]
        print("    f%d 不透明 %3d (%.0f%%)  亮/不透明 = %.2f"
              % (f, len(op), 100.0 * len(op) / len(px), (len(br) / len(op)) if op else 0.0))
    print("→", p)
