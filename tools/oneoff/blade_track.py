# -*- coding: utf-8 -*-
"""blade_track.py —— 逐帧标出刀尖 / 刀柄位置, 画出整段动作里刀的活动路径(2026-11-25)。

由来: 用户 11-25「你自己把这个刀刀头和刀尾这里自己去标点，然后你看一下整个刀的活动路径…有没有绕着人这样的走动的，就是横扫的」。
做法: 刀身 = 亮、低饱和的钢色像素(R,G,B 都 ≥ 150 且 max-min ≤ 45); 取最大的一团连通块;
  刀尖 = 这团里离身体中心(非透明像素重心)最远的点; 刀柄 = 这团里离刀尖最远的点(刀身另一头, 靠手)。
  输出: 每帧放大 3 倍, 刀尖红点 / 刀柄蓝点 + 刀身连线; 最后一格把所有帧的刀尖路径(红)与刀柄路径(蓝)叠在第一帧上。
  python tools/oneoff/blade_track.py <输出.png> <帧1.png> <帧2.png> ...
"""
import sys

from PIL import Image, ImageDraw


def blade_pixels(im):
    px = im.load()
    pts = set()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a > 128 and min(r, g, b) >= 150 and max(r, g, b) - min(r, g, b) <= 45:
                pts.add((x, y))
    ## 最大连通块(8 邻接)
    best = []
    seen = set()
    for p in pts:
        if p in seen:
            continue
        comp, st = [], [p]
        seen.add(p)
        while st:
            q = st.pop()
            comp.append(q)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (q[0] + dx, q[1] + dy)
                    if n in pts and n not in seen:
                        seen.add(n)
                        st.append(n)
        if len(comp) > len(best):
            best = comp
    return best


def body_center(im):
    px = im.load()
    sx = sy = n = 0
    for y in range(im.height):
        for x in range(im.width):
            if px[x, y][3] > 128:
                sx += x; sy += y; n += 1
    return (sx / max(1, n), sy / max(1, n))


def track(im):
    bl = blade_pixels(im)
    if len(bl) < 6:
        return None, None, len(bl)
    ## 刀身两头 = 这团里相距最远的两点; 靠金色护手(鍔)的那头是刀柄, 另一头是刀尖(11-25: 原来按离身体中心远近分, 刀横过身前时会标反)
    a = max(bl, key=lambda p: p[0] + p[1] * 0.001)
    e1 = max(bl, key=lambda p: (p[0] - a[0]) ** 2 + (p[1] - a[1]) ** 2)
    e2 = max(bl, key=lambda p: (p[0] - e1[0]) ** 2 + (p[1] - e1[1]) ** 2)
    gold = gold_pixels(im)
    def near_gold(e):
        return min([(g[0] - e[0]) ** 2 + (g[1] - e[1]) ** 2 for g in gold] or [1e9])
    hilt, tip = (e1, e2) if near_gold(e1) <= near_gold(e2) else (e2, e1)
    return tip, hilt, len(bl)


def gold_pixels(im):
    px = im.load()
    return [(x, y) for y in range(im.height) for x in range(im.width)
            if px[x, y][3] > 128 and px[x, y][0] > 170 and px[x, y][1] > 120 and px[x, y][2] < 90]


def main():
    out = sys.argv[1]
    paths = sys.argv[2:]
    ims = [Image.open(p).convert("RGBA") for p in paths]
    K = 3
    W, H = ims[0].size
    sheet = Image.new("RGBA", (W * K * (len(ims) + 1), H * K), (70, 80, 50, 255))
    d = ImageDraw.Draw(sheet)
    tips, hilts = [], []
    for i, im in enumerate(ims):
        sheet.alpha_composite(im.resize((W * K, H * K), Image.NEAREST), (i * W * K, 0))
        tip, hilt, n = track(im)
        tips.append(tip); hilts.append(hilt)
        ox = i * W * K
        d.text((ox + 4, 4), "%d" % i, fill=(255, 255, 0, 255))
        if tip:
            d.line([(ox + tip[0] * K, tip[1] * K), (ox + hilt[0] * K, hilt[1] * K)], fill=(255, 255, 0, 200), width=1)
            d.ellipse([ox + tip[0] * K - 5, tip[1] * K - 5, ox + tip[0] * K + 5, tip[1] * K + 5], fill=(255, 40, 40, 255))
            d.ellipse([ox + hilt[0] * K - 5, hilt[1] * K - 5, ox + hilt[0] * K + 5, hilt[1] * K + 5], fill=(60, 120, 255, 255))
        print("帧 %d: 刀尖 %s 刀柄 %s (刀身 %d 像素)" % (i, tip, hilt, n))
    ox = len(ims) * W * K
    sheet.alpha_composite(ims[0].resize((W * K, H * K), Image.NEAREST), (ox, 0))
    for seq, col in ((tips, (255, 40, 40, 255)), (hilts, (60, 120, 255, 255))):
        pts = [(ox + p[0] * K, p[1] * K) for p in seq if p]
        if len(pts) > 1:
            d.line(pts, fill=col, width=2)
        for j, p in enumerate(pts):
            d.ellipse([p[0] - 3, p[1] - 3, p[0] + 3, p[1] + 3], fill=col)
            d.text((p[0] + 4, p[1] - 10), str(j), fill=col)
    sheet.save(out)


if __name__ == "__main__":
    main()
