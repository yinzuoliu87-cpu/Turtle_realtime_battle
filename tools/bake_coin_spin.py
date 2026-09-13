# -*- coding: utf-8 -*-
"""035 黄铜齿轮【进账深海币】—— 头顶旋转的金币 (2026-09-13)。

用户 2026-09-13:「这最好做一个头顶获得金币旋转的特效吧, 我也说不清,
你搜搜网上 blender 有没有例子, 照着做一板板」。

★做法照 memory[[fb-match-reference-by-measured-curve]]: **把参考逐帧量成包络表**,
  不手调系数。参考取的是 OpenGameArt 的 CC0「Spinning Coin Sprites」(plain_coin_32,
  16 帧 × 32×32) —— **只量不用**(素材不复用铁律, 也不掺别人的图进包)。

量出来的每帧不透明宽度(高恒为 30)：
  30 30 30 28 24 20 16 10 **4** 10 16 20 24 28 30 30
归一 ⇒ 1.00 1.00 1.00 .93 .80 .67 .53 .33 **.13** .33 .53 .67 .80 .93 1.00 1.00

两条细节是**纯 cos 给不出**的, 也正是"照着做"的价值:
  ① 正面要**多停 2 帧**(cos 在那一段已经开始收了) —— 不停的话看着像在抖不像在转;
  ② 侧面最窄**不为 0**(0.13) —— 那是币的厚度, 归零就成了"消失一帧"。
重采样到 12 帧后即下面的 ENV。

★配色跟游戏里既有的金币同族(storm-coin 的取色): 亮 #fdf333 / 中 #d79a08 / 暗 #85 49 00 /
  描边 #4c0601 / 高光 #fdfaf5。同色系不等于复用素材 —— 形状与帧序都是新画的。
"""
import os
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

D = (76, 6, 1, 255)        # 描边
DK = (133, 73, 0, 255)     # 暗金(背光面/滚边阴影)
M = (215, 154, 8, 255)     # 中金(币面)
L = (253, 243, 51, 255)    # 亮金
W = (253, 250, 245, 255)   # 高光
CLR = (0, 0, 0, 0)

CW = CH = 18
CN = 12
R = 8.0                    # 币的半径(texel)
# 从参考 16 帧线性重采样到 12 帧的宽度比例
ENV = [1.00, 1.00, 0.95, 0.80, 0.62, 0.40, 0.13, 0.40, 0.62, 0.80, 0.95, 1.00]
# 正面朝向: 前半圈看正面(有纹样), 后半圈看背面(纹样换成素面)
FACE = [True, True, True, True, True, True, True, False, False, False, False, False]


def _px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c)


def bake():
    im = Image.new("RGBA", (CW * CN, CH), CLR)
    cx = cy = CW // 2
    for f in range(CN):
        ox = f * CW
        rx = max(1.0, R * ENV[f])
        face = FACE[f]
        for y in range(CH):
            dy = (y - cy) / R
            if abs(dy) > 1.0:
                continue
            for x in range(CW):
                dx = (x - cx) / rx
                d2 = dx * dx + dy * dy
                if d2 > 1.0:
                    continue
                edge = d2 > 0.62                     # 靠近轮廓 = 滚边
                ## 受光在左上: 用 (dx+dy) 定明暗, 转到背面时整体压暗一档
                lit = (-dx - dy) * 0.5 if face else (dx - dy) * 0.5   # 背面把受光翻到另一侧
                if edge:
                    c = L if lit > 0.25 else (M if lit > -0.2 else DK)
                else:
                    c = L if lit > 0.42 else (M if lit > -0.3 else DK)

                _px(im, ox + x, y, c)
        ## 纹样: 币面中间一圈内环 + 中心一点 —— 一眼就是"币"。
        ## ★第一版画的是两道横「浪」, 并排渲出来像**一张脸**(两只眼睛 + 一张嘴), 换掉。
        if ENV[f] >= 0.55:
            for y in range(CH):
                dy = (y - cy) / (R * 0.58)
                if abs(dy) > 1.0:
                    continue
                for x in range(CW):
                    dx = (x - cx) / (rx * 0.58)
                    d2 = dx * dx + dy * dy
                    if 0.66 <= d2 <= 1.0:
                        _px(im, ox + x, y, DK)
            _px(im, ox + cx, cy, DK)
        ## 高光: 一小段随帧扫过的亮点(参考图里那一下"闪")
        if ENV[f] >= 0.62:
            hx = cx + int(round((-0.40 + f * 0.10) * rx))
            _px(im, ox + hx, cy - int(R * 0.55), W)
            _px(im, ox + hx + 1, cy - int(R * 0.55), W)
            _px(im, ox + hx, cy - int(R * 0.55) + 1, L)

    ## ★描边统一在最后做, 用**膨胀**(有色像素的四邻里凡是空的就填暗边) ——
    ##   第一版用 `1.0 < d2 <= 1.45` 的椭圆带, 窄帧时那条带子横向摊得极宽,
    ##   并排渲出来像给每枚币套了个暗红色的框。
    src = im.copy()
    for f in range(CN):
        ox = f * CW
        for y in range(CH):
            for x in range(CW):
                if src.getpixel((ox + x, y))[3] != 0:
                    continue
                near = False
                for dx2, dy2 in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = x + dx2, y + dy2
                    if 0 <= xx < CW and 0 <= yy < CH and src.getpixel((ox + xx, yy))[3] != 0:
                        near = True
                        break
                if near:
                    _px(im, ox + x, y, D)

    p = os.path.join(OUT, "deepsea-coin-spin.png")
    im.save(p)
    return p, im


if __name__ == "__main__":
    p, im = bake()
    print("  deepsea-coin-spin.png  %dx%d = %d 帧 × %dx%d" % (im.width, im.height, CN, CW, CH))
    print("  帧号  实测宽  目标宽  不透明  亮/不透明")
    for f in range(CN):
        cell = im.crop((f * CW, 0, (f + 1) * CW, CH))
        px = list(cell.getdata())
        op = [q for q in px if q[3] > 0]
        br = [q for q in op if (q[0] + q[1] + q[2]) / 3.0 >= 110]
        xs = [i % CW for i, q in enumerate(px) if q[3] > 0]
        wid = (max(xs) - min(xs) + 1) if xs else 0
        want = 2.0 * R * ENV[f] + 2.0
        print("   f%-2d   %2d      %4.1f    %3d     %.2f"
              % (f, wid, want, len(op), (len(br) / len(op)) if op else 0.0))
    print("→", p)
