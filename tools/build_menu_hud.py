# -*- coding: utf-8 -*-
"""build_menu_hud.py — 主菜单 UI 件(木板 / 货币牌 / 铜牌 / 绶带 / 左栏挂旗)的烘焙器 (2026-10-05 草稿)。

由来: 主菜单背景换成擂台 + 看台(v0.19.546)后, 用户:「主菜单背景没问题。但UI呢」。
  原 UI 三套语言混着: 右上 ?/⚙ 是厚像素木框, 货币是裸图标+数字, 底部赛程条是冷色藏青块(像网页控件)。
  ⇒ 统一成一套「像素木头 + 金属包边」。所有件都是 PixelLab 本次新生成的(R1-a 不复用铁律),
    原件在 assets/sprites/menu/hud/src/(.gdignore 不进包), 本脚本只做裁边/抠底/压平, 不画新内容。

  src/plank.png   320×80  三块横木 + 两端铁箍铆钉   → strip-plank.png(去掉两端伸出的木头, 赛程条九宫格)
                                                     btn-plank.png  (整块, 训龟大师次级键九宫格)
  src/chip.png    128×40  暗木 + 黄铜包边 + 左端币槽 → chip.png ×2(货币底座九宫格)
  src/brass.png    64×64  黄铜铆钉牌                  → brass.png(赛程条「今天」那一格)
  src/ribbon.png  192×40  绯红绶带 + 金边 + 燕尾     → ribbon.png(状态区标题条; 中段改成只有竖向明暗,
                                                     去掉 PixelLab 画的径向高光 = 「渐变胶囊」那种 AI 味)
  src/banner.png  192×384 酒红挂旗 + 金线 + 燕尾     → banner.png ×2(左栏底板; 抠掉灰底、裁掉挂杆与燕尾 —— 上沿由绶带压住, 下沿藏在赛程条后)

跑法: python tools/build_menu_hud.py
"""
import os
from collections import deque
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sprites", "menu", "hud")
SRC = os.path.join(ROOT, "src")


def up(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def key_out_grey(im):
    """PixelLab 有时 no_background 失手留一层灰底: 从四边泛洪抠掉与角色差 <24 的像素。"""
    im = im.copy()
    W, H = im.size
    p = im.load()
    bg = p[2, H // 2]
    if bg[3] == 0:
        return im

    def near(c):
        return abs(c[0] - bg[0]) + abs(c[1] - bg[1]) + abs(c[2] - bg[2]) < 24

    seen = set()
    q = deque([(x, 0) for x in range(W)] + [(x, H - 1) for x in range(W)]
              + [(0, y) for y in range(H)] + [(W - 1, y) for y in range(H)])
    while q:
        x, y = q.popleft()
        if (x, y) in seen or not (0 <= x < W and 0 <= y < H):
            continue
        seen.add((x, y))
        if p[x, y][3] == 0 or not near(p[x, y]):
            continue
        p[x, y] = (0, 0, 0, 0)
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return im


def main():
    out = {}
    plank = Image.open(os.path.join(SRC, "plank.png")).convert("RGBA")
    out["btn-plank.png"] = plank.crop((9, 5, 311, 75))                  # 302×70
    out["strip-plank.png"] = plank.crop((26, 5, 294, 75))               # 268×70, 两端只剩铁箍

    chip = Image.open(os.path.join(SRC, "chip.png")).convert("RGBA")
    out["chip.png"] = up(chip.crop((8, 6, 120, 34)), 2)                 # 224×56

    brass = Image.open(os.path.join(SRC, "brass.png")).convert("RGBA")
    out["brass.png"] = brass.crop((5, 5, 59, 59))                       # 54×54

    rib = Image.open(os.path.join(SRC, "ribbon.png")).convert("RGBA")
    p = rib.load()
    col = [p[96, y] for y in range(rib.height)]
    for x in range(30, 162):                                            # 中段只留竖向明暗
        for y in range(rib.height):
            if p[x, y][3] > 0 and col[y][3] > 0:
                p[x, y] = col[y]
    out["ribbon.png"] = rib.crop((0, 2, 192, 38))                       # 192×36

    ban = key_out_grey(Image.open(os.path.join(SRC, "banner.png")).convert("RGBA"))
    out["banner.png"] = up(ban.crop((32, 40, 160, 318)), 2)             # 256×556, 挂杆与燕尾都裁掉(上沿由绶带压住, 下沿藏在赛程条后)

    for name, im in out.items():
        im.save(os.path.join(ROOT, name))
        print("%-16s %dx%d" % (name, im.width, im.height))


if __name__ == "__main__":
    main()
