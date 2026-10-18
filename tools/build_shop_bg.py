# -*- coding: utf-8 -*-
"""商店整页背景: 在 PixelLab 原图(assets/sprites/shop/src/shop-bg-raw.png, 384×216)左半画两层木台。

用户 2026-10-18「整个页面就应该重做啊，没有任何游戏搞的这种浏览器网页感」。
原图左半是开阔水体 + 底部一小条沙地, 两排龟站上去是浮在水里的。
⇒ 在原生像素上画两层木台(后排高、前排低), 台面高度 = 两排龟的脚(ShopLineup.LANE_Y + 脚底偏移):
    上战场: 屏幕 y≈228 → 原生 68     下战场: 屏幕 y≈432 → 原生 130
颜色全部从原图右侧货架木板上取色, 不另调色 —— 同一张图里两种木头才是违和。
跑法: python tools/build_shop_bg.py   → 写 assets/sprites/shop/shop-bg.png
"""
import os
import sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'assets/sprites/shop/src/shop-bg-raw.png')
OUT = os.path.join(ROOT, 'assets/sprites/shop/shop-bg.png')

# 从货架板上取的木色(原图 x 216..373, y 74..80 是上层板)
TOP_HI = (180, 128, 74)
TOP = (155, 99, 61)
FRONT = (112, 70, 41)
FRONT_DK = (84, 52, 31)
SEAM = (62, 38, 22)
OUTLINE = (28, 17, 9)
POST = (92, 58, 34)
POST_DK = (64, 40, 24)
SHADOW = (0, 0, 0, 70)

## 两级阶梯台(后排高、前排低, 前排压住后排的下半截): (左, 右, 台面顶 y, 台面深, 正面落到 y)
##   台面看得见一条深度(略俯视) = 龟站的地方; 正面是竖木板, 落到沙地 ⇒ 读起来是「台子」。
DECKS = [
    (14, 206, 52, 18, 140),   # 后排 = 上战场(台面 52..70, 龟脚 ≈68)
    (8, 212, 114, 18, 160),   # 前排 = 下战场(台面 114..132, 龟脚 ≈130)
]
## 原图实测色(货架板 / 吊绳)
PLANK = [(179, 111, 67), (167, 104, 63), (155, 96, 58), (141, 85, 55)]
ROPE = (179, 140, 90)
ROPE_DK = (120, 88, 56)
NAIL = (50, 40, 34)


def deck(im, x0, x1, ty, td, bottom):
    import random
    rnd = random.Random(ty * 1000 + x0)     # 固定种子: 每次生成逐字节相同
    px = im.load()
    W, H = im.size

    def put(x, y, c):
        if 0 <= x < W and 0 <= y < H:
            px[x, y] = c

    # ── 台面: 横向木板, 每块一个随机深浅; 板缝暗线; 越往里越暗(远处)
    rows = []
    y = ty
    while y < ty + td:
        h = rnd.choice([3, 4, 4, 5])
        rows.append((y, min(y + h, ty + td), rnd.choice(PLANK)))
        y += h
    for (ya, yb, col) in rows:
        for yy in range(ya, yb):
            far = (ty + td - yy) / td * 0.18           # 里侧压暗一点
            c = tuple(int(v * (1.0 - far)) for v in col)
            for x in range(x0, x1):
                put(x, yy, c)
        for x in range(x0, x1):
            put(x, yb - 1, (110, 66, 40))               # 板缝
        # 端头接缝: 每块板随机一处竖缝
        sx = rnd.randrange(x0 + 20, x1 - 20)
        for yy in range(ya, yb):
            put(sx, yy, (110, 66, 40))
    for x in range(x0, x1):
        put(x, ty - 1, OUTLINE)
        put(x, ty, TOP_HI)
    # ── 台沿: 一条麻绳(两色交替成股) + 每隔一段一个贝壳色小点
    ry = ty + td
    for x in range(x0, x1):
        put(x, ry, ROPE if (x // 2) % 2 == 0 else ROPE_DK)
        put(x, ry + 1, ROPE_DK if (x // 2) % 2 == 0 else ROPE)
    for x in range(x0 + 16, x1 - 8, 46):
        for dx, dy, c in [(0, 0, (230, 214, 190)), (1, 0, (210, 188, 160)), (-1, 0, (210, 188, 160)),
                          (0, 1, (190, 160, 130)), (0, -1, (240, 228, 210))]:
            put(x + dx, ry + 1 + dy, c)
    # ── 正面: 竖木板, 每块随机深浅; 往下渐暗(抖动过渡, 沉进水里); 钉子
    fy0 = ry + 2
    for bx in range(x0, x1, 9):
        col = rnd.choice(PLANK[1:])
        for y in range(fy0, bottom):
            k = (y - fy0) / max(1, bottom - fy0)
            dark = 0.45 + 0.35 * k
            if ((bx + y) % 2 == 0) and abs(k - 0.5) < 0.12:
                dark += 0.08                                # 交界处抖动, 不出硬色带
            c = tuple(int(v * (1.0 - dark)) for v in col)
            for x in range(bx, min(bx + 9, x1)):
                put(x, y, c)
            put(bx, y, SEAM)
        put(bx + 4, fy0 + 2, NAIL)
        put(bx + 4, bottom - 3, NAIL)
    # ── 两侧描边 + 底下沙地上的一条阴影
    for y in range(ty - 1, bottom):
        put(x0 - 1, y, OUTLINE)
        put(x1, y, OUTLINE)
    for x in range(x0 - 2, x1 + 3):
        for dy in range(0, 3):
            yy = bottom + dy
            if 0 <= yy < H and 0 <= x < W:
                r, g, b = px[x, yy]
                f = 0.55 + 0.15 * dy
                px[x, yy] = (int(r * f), int(g * f), int(b * f))


def main() -> int:
    im = Image.open(SRC).convert('RGB')
    assert im.size == (384, 216), im.size
    for d in DECKS:
        deck(im, *d)
    im.save(OUT)
    print('写出', OUT, im.size)
    return 0


if __name__ == '__main__':
    sys.exit(main())
