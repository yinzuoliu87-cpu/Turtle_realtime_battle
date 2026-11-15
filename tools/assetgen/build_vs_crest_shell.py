# -*- coding: utf-8 -*-
"""对阵 / 三路开场的盾徽 · 龟甲纹(2026-11-15)。确定性生成, 重跑逐字节相同。

用户 11-15:「这个盾面一定要说这两种颜色吗？还是说你可以设计一种什么图标呢？这个盾里面的这个红蓝，你觉得呢？」
我的看法(已回复用户): 背景两条斜带已经在说「蓝方对红方」, 盾面再分红蓝是重复、还和背景抢色;
  中间这枚应当是这个游戏自己的标志 ⇒ 盾面画成琥珀色龟甲(斗龟场的「龟」), 中性金铜色, 不偏任何一方。
以决赛日那枚 `assets/sprites/finals/vs-crest.png` 为底: 铜边 / 铆钉 / 交叉剑原样(同一家族), 只重画盾面。
做法(如实): 盾面范围 = 从盾心出发只走蓝 / 红像素的连通块(原图正中那条竖分界线单独认);
  龟甲分块 = 预设 7 个甲片中心(中间一列 3 片脊甲 + 两侧各 2 片肋甲), 每格归最近的那片(Voronoi);
  到最近两片中心的距离差 < 1.1 格 ⇒ 甲缝; 片内按「到甲缝多远」分: 贴缝一圈左上亮 / 右下暗(斜面), 再往里一圈生长纹, 其余中间色。规则算的, 不是逐格手点。

  python tools/assetgen/build_vs_crest_shell.py            写 assets/sprites/finals/vs-crest-shell.png
  python tools/assetgen/build_vs_crest_shell.py <路径>     写到别处(出对照图用)
"""
import math
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "sprites", "finals", "vs-crest.png")
OUT = os.path.join(ROOT, "assets", "sprites", "finals", "vs-crest-shell.png")

HI = (232, 182, 92)
MID = (190, 128, 54)
LO = (132, 80, 36)
SEAM = (58, 32, 18)
SPEC = (255, 226, 150)


def _is_field_color(c):
    r, g, b, a = c
    if a < 200:
        return False
    blue = b > r + 25 and b > g + 15 and b > 60
    red = r > g + 40 and r > b + 10 and r > 50 and g < 70
    return blue or red


def _field(px, w, h):
    field = [[False] * w for _ in range(h)]
    seed = None
    for d in range(0, 12):
        for x in (w // 2 - 3 - d, w // 2 + 2 + d):
            if _is_field_color(px[x, h // 2]):
                seed = (x, h // 2)
                break
        if seed:
            break
    stack = [seed]
    while stack:
        x, y = stack.pop()
        if not (0 <= x < w and 0 <= y < h) or field[y][x]:
            continue
        ok = _is_field_color(px[x, y])
        if not ok:
            lft = any(_is_field_color(px[x - k, y]) for k in (1, 2) if x - k >= 0)
            rgt = any(_is_field_color(px[x + k, y]) for k in (1, 2) if x + k < w)
            ok = lft and rgt
        if not ok:
            continue
        field[y][x] = True
        stack.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return field


def build():
    im = Image.open(SRC).convert("RGBA")
    w, h = im.size
    px = im.load()
    field = _field(px, w, h)
    rows = [y for y in range(h) if any(field[y])]
    y0, y1 = min(rows), max(rows)
    xs = [x for y in rows for x in range(w) if field[y][x]]
    x0, x1 = min(xs), max(xs)
    cx = (x0 + x1 + 1) / 2.0
    H = float(y1 - y0 + 1)
    W = float(x1 - x0 + 1)
    ## 甲片中心: 中间一列 3 片脊甲(上大下小), 两侧各 2 片肋甲
    centers = [
        (cx, y0 + H * 0.20), (cx, y0 + H * 0.50), (cx, y0 + H * 0.78),
        (cx - W * 0.30, y0 + H * 0.33), (cx + W * 0.30, y0 + H * 0.33),
        (cx - W * 0.26, y0 + H * 0.64), (cx + W * 0.26, y0 + H * 0.64),
    ]
    out = im.copy()
    op = out.load()
    for y in rows:
        for x in range(w):
            if not field[y][x]:
                continue
            p = (x + 0.5, y + 0.5)
            ds = sorted((math.hypot(p[0] - c[0], (p[1] - c[1]) * 0.9), i) for i, c in enumerate(centers))
            d0, i0 = ds[0]
            d1 = ds[1][0]
            if d1 - d0 < 1.1:
                op[x, y] = SEAM + (255,)
                continue
            c = centers[i0]
            ## 多边形甲片的斜面: 离甲缝近(e 小)的那一圈, 朝左上的一侧亮、朝右下的一侧暗; 片里一圈生长纹; 其余中间色
            dx, dy = p[0] - c[0], p[1] - c[1]
            e = d1 - d0
            if e < 2.4:
                col = HI if (dx + dy) < 0 else LO
            elif abs(e - 4.6) < 0.7:
                col = LO
            else:
                col = MID
            if abs(dx + 2.0) < 0.6 and abs(dy + 2.0) < 0.6 and e > 3.0:
                col = SPEC
            op[x, y] = col + (255,)
    return out


if __name__ == "__main__":
    dst = sys.argv[1] if len(sys.argv) > 1 else OUT
    build().save(dst)
    print("ok", dst)
