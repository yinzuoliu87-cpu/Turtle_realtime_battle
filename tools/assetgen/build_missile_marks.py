# -*- coding: utf-8 -*-
"""build_missile_marks.py —— 炸弹羁绊导弹的【天降瞄准激光】与【地面靶心】贴图(2026-11-25)。

由来: 用户 11-25「卫星定位器是这么指的吗？…它不是指向天空，然后天空落下一道这个红线吗？」——
  原来定位器是从我方阵地沿地面横拉到场地中心的一条红线; 改成从天上竖直打下来的一道红色瞄准激光, 落在中心的靶心上。
做法(如实): 脚本按几何画(PIL), 不是手画: 激光 = 竖条, 白芯 → 红 → 暗红外晕, 三档硬边 + 外晕一档半透明;
  4 帧之间只让芯的亮度和外晕宽度抖一下(闪烁感), 从上到下每隔一段有一节更亮的「能量脉冲」, 4 帧往下挪(看起来在往下灌)。
  靶心 = 俯视图(游戏里平铺在地上): 两圈红环 + 四个刻度 + 中心十字, 像素硬边。
确定性: 纯几何, 重跑逐字节相同。
  python tools/assetgen/build_missile_marks.py
产出: assets/sprites/vfx/missile-laser.png (4 帧 × 24×256 横排) · assets/sprites/vfx/missile-reticle.png (128×128)
  · assets/sprites/vfx/missile-drop.png: 竖直下落的导弹 4 帧循环 —— 取 bomb-missile-strike.png(原来斜着飞进来的那张, 特效工作台出的)
    第 3~6 帧的弹体, 按弹体主轴(实测 -60°, 即往右上斜)逆时针转 30° 摆成竖直、弹头朝下, 最近邻采样(不糊);
    用户 11-25「它不是指向天空，然后天空落下一道这个红线吗？」⇒ 导弹顺着竖直的激光落下, 不再从右上斜着飞进来。
    依赖 pack_bomb_vfx.py 先产出 bomb-missile-strike.png。
  · assets/sprites/vfx/missile-zone.png: 打击范围 = 整个棋盘(用户 11-25「范围是整个棋盘，我再跟你说一遍」): 俯视的整圆, 里面铺满红色斜纹警示条
    (两档半透明硬边) + 外沿一圈实心红边; 游戏里按岛的两条半轴拉成椭圆、平铺盖住整座岛。
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx")

W, H, NF = 24, 256, 4
C_CORE = (255, 240, 240, 255)
C_RED = (255, 60, 50, 255)
C_DARK = (190, 20, 25, 255)
C_GLOW = (255, 40, 30, 90)


def laser():
    sheet = Image.new("RGBA", (W * NF, H), (0, 0, 0, 0))
    cx = W // 2
    for f in range(NF):
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        px = im.load()
        glow = 9 if f % 2 == 0 else 8
        for y in range(H):
            pulse = ((y + f * 16) // 8) % 8 == 0          # 每 64 行一节亮脉冲, 每帧往下挪 16 行
            for x in range(W):
                d = abs(x - cx + 0.5)
                if d < (1.5 if not pulse else 2.5):
                    px[x, y] = C_CORE
                elif d < 3.5:
                    px[x, y] = C_RED
                elif d < 5.0:
                    px[x, y] = C_DARK
                elif d < glow:
                    px[x, y] = C_GLOW
        sheet.paste(im, (f * W, 0))
    sheet.save(os.path.join(OUT, "missile-laser.png"), optimize=False)


def reticle():
    S = 128
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = S // 2
    for r, w in ((60, 3), (40, 2)):
        d.ellipse([c - r, c - r, c + r, c + r], outline=C_RED, width=w)
    for ang in range(4):
        if ang == 0:
            d.rectangle([c - 2, c - 62, c + 1, c - 48], fill=C_RED)
        elif ang == 1:
            d.rectangle([c - 2, c + 48, c + 1, c + 62], fill=C_RED)
        elif ang == 2:
            d.rectangle([c - 62, c - 2, c - 48, c + 1], fill=C_RED)
        else:
            d.rectangle([c + 48, c - 2, c + 62, c + 1], fill=C_RED)
    d.rectangle([c - 10, c - 1, c + 9, c], fill=C_CORE)
    d.rectangle([c - 1, c - 10, c, c + 9], fill=C_CORE)
    im.save(os.path.join(OUT, "missile-reticle.png"), optimize=False)


def drop():
    src = Image.open(os.path.join(OUT, "bomb-missile-strike.png")).convert("RGBA")
    FW, FH, S = 132, 151, 72
    out = Image.new("RGBA", (S * 4, S), (0, 0, 0, 0))
    for i, k in enumerate((3, 4, 5, 6)):
        f = src.crop((k * FW, 0, k * FW + FW, FH))
        px = f.load()
        pts = [(x, y) for y in range(FH) for x in range(FW) if px[x, y][3] > 128]
        cx = sum(p[0] for p in pts) // len(pts)
        cy = sum(p[1] for p in pts) // len(pts)
        big = Image.new("RGBA", (S * 2, S * 2), (0, 0, 0, 0))
        big.paste(f, (S - cx, S - cy))
        rot = big.rotate(30, resample=Image.NEAREST)
        out.paste(rot.crop((S // 2, S // 2, S // 2 + S, S // 2 + S)), (i * S, 0))
    out.save(os.path.join(OUT, "missile-drop.png"), optimize=False)


def zone():
    S = 256
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = im.load()
    c = (S - 1) / 2.0
    for y in range(S):
        for x in range(S):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
            if d > S / 2.0 - 0.5:
                continue
            if d > S / 2.0 - 6:
                px[x, y] = (255, 50, 40, 230)          # 外沿实心红边
            elif ((x + y) // 12) % 2 == 0:
                px[x, y] = (255, 40, 30, 110)          # 斜纹亮条
            else:
                px[x, y] = (200, 20, 20, 55)           # 斜纹暗条
    im.save(os.path.join(OUT, "missile-zone.png"), optimize=False)


if __name__ == "__main__":
    zone()
    laser()
    reticle()
    drop()
    print("ok")
