"""cent_cape_clean_1127.py —— 百夫长新画的待机 / 走路帧里 PixelLab 凭空长出的红披风清掉(底图 centB_0 没有披风; 三次生成都长)
按底图每一行最左的像素(= 盾左缘)当界: 界外 2 像素以上的一律清(盾牌下沿以下只清偏红的布, 不碰往前迈的脚);
界内贴边 1 像素、底图那里本来透明的偏红像素也清。输入 cBidle3_* / cBwalk3_*, 输出 cBidle3c_* / cBwalk3c_*。重跑逐字节相同。
    python tools/oneoff/cent_cape_clean_1127.py
"""
import os
from PIL import Image

D = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools", "assetgen", "ai_src", "spear")
base = Image.open(os.path.join(D, "centB_0.png")).convert("RGBA")
bp = base.load()
W, H = base.size
L0 = {}
for y in range(H):
    xs = [x for x in range(W) if bp[x, y][3] > 0]
    if xs:
        L0[y] = xs[0]


def red(p):
    return p[0] > 40 and p[0] > p[1] * 2


def clean(src, dst):
    im = Image.open(src).convert("RGBA")
    px = im.load()
    n = 0
    for y in range(H):
        lim = L0.get(y)
        for x in range(W):
            p = px[x, y]
            if p[3] == 0:
                continue
            if lim is None:
                bad = red(p) and y < 105
            elif x < lim - 2:
                bad = y <= 104 or red(p)
            elif x < lim + 1 and red(p) and bp[x, y][3] == 0:
                bad = True
            else:
                bad = False
            if bad:
                px[x, y] = (0, 0, 0, 0)
                n += 1
    im.save(dst)
    return n


for nm, k in [("cBidle3", 5), ("cBwalk3", 9)]:
    print(nm, [clean(os.path.join(D, "%s_%d.png" % (nm, i)), os.path.join(D, "%sc_%d.png" % (nm, i))) for i in range(k)])
