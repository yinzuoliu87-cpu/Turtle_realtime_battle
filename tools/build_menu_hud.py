# -*- coding: utf-8 -*-
"""build_menu_hud.py — 主菜单 UI 件(木板 / 货币牌 / 铜牌 / 绶带 / 左栏挂旗)的烘焙器 (2026-10-05 草稿)。

由来: 主菜单背景换成擂台 + 看台(v0.19.546)后, 用户:「主菜单背景没问题。但UI呢」。
  原 UI 三套语言混着: 右上 ?/⚙ 是厚像素木框, 货币是裸图标+数字, 底部赛程条是冷色藏青块(像网页控件)。
  ⇒ 统一成一套「像素木头 + 金属包边」。所有件都是 PixelLab 本次新生成的(R1-a 不复用铁律),
    原件在 assets/sprites/menu/hud/src/(.gdignore 不进包), 本脚本只做裁边/接长/挖空/压平, 不画新内容。

  src/plank.png   320×80  三块横木 + 两端铁箍铆钉   → strip-plank.png(赛程条九宫格, 两端只剩铁箍)。
                                                     ★中段不拉伸: 按像素拼成 1400×95 的长板(镜像接长, 竖向插一道板缝),
                                                       Godot 里九宫格中段走 TILE —— 条子多宽都是原像素裁出来的, 木纹不被拉糊
                                                       (高 95 = 赛程格 81 + 上下内边距 7, 竖向恰好 1:1)
                                                     btn-plank.png  (整块, 训龟大师次级键九宫格)
  src/chip.png    128×40  暗木 + 黄铜包边 + 左端币槽 → chip.png ×2(货币底座九宫格)
  src/brass.png    64×64  黄铜铆钉牌                  → brass.png(周末的门) / brass-frame.png(中间挖空 = 「今天」那一格的铜边框)
  src/ribbon.png  192×40  绯红绶带 + 金边 + 燕尾     → ribbon.png(状态区标题条, 抽掉中段 8 行 ⇒ 28 高; 中段改成只有竖向明暗,
                                                     去掉 PixelLab 画的径向高光 = 「渐变胶囊」那种 AI 味)
  src/plaque.png  192×48  单块窄木牌 + 四角铜钉     → plaque.png(左栏每行一块短牌, 高 44: 竖向插 4 行木面, 不拉伸)

跑法: python tools/build_menu_hud.py
"""
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sprites", "menu", "hud")
SRC = os.path.join(ROOT, "src")


def up(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def long_plank(plank):
    """赛程条木板: 两端铁箍原样, 中段按像素接长(镜像拼接, 接缝处纹理连续), 竖向插一道板缝到 95 高。"""
    src = plank.crop((26, 5, 294, 75))                                  # 268×70: 铁箍 0..22 / 面 22..246 / 铁箍 246..268
    W, H = 1400, 95
    rows = list(range(0, 11)) + list(range(11, 58)) + [10] + list(range(11, 35)) + list(range(58, 70))
    assert len(rows) == H, len(rows)
    face = src.crop((22, 0, 246, 70))
    strip = Image.new("RGBA", (W - 44, 70))
    x, k = 0, 0
    while x < strip.width:
        seg = face if k % 2 == 0 else face.transpose(Image.FLIP_LEFT_RIGHT)
        strip.paste(seg, (x, 0))
        x += seg.width
        k += 1
    full = Image.new("RGBA", (W, 70))
    full.paste(src.crop((0, 0, 22, 70)), (0, 0))
    full.paste(strip, (22, 0))
    full.paste(src.crop((246, 0, 268, 70)), (W - 22, 0))
    out = Image.new("RGBA", (W, H))
    for i, r in enumerate(rows):
        out.paste(full.crop((0, r, W, r + 1)), (0, i))
    return out


def main():
    out = {}
    plank = Image.open(os.path.join(SRC, "plank.png")).convert("RGBA")
    out["btn-plank.png"] = plank.crop((9, 5, 311, 75))                  # 302×70
    out["strip-plank.png"] = long_plank(plank)                          # 1400×95

    chip = Image.open(os.path.join(SRC, "chip.png")).convert("RGBA")
    out["chip.png"] = up(chip.crop((8, 6, 120, 34)), 2)                 # 224×56

    brass = Image.open(os.path.join(SRC, "brass.png")).convert("RGBA")
    out["brass.png"] = brass.crop((5, 5, 59, 59))                       # 54×54
    fr = out["brass.png"].copy()
    fp = fr.load()
    for y in range(10, 44):                                             # 挖空 ⇒ 只剩一圈铜边 + 四角铆钉
        for x in range(10, 44):
            fp[x, y] = (0, 0, 0, 0)
    out["brass-frame.png"] = fr

    rib = Image.open(os.path.join(SRC, "ribbon.png")).convert("RGBA")
    p = rib.load()
    col = [p[96, y] for y in range(rib.height)]
    for x in range(30, 162):                                            # 中段只留竖向明暗
        for y in range(rib.height):
            if p[x, y][3] > 0 and col[y][3] > 0:
                p[x, y] = col[y]
    rib = rib.crop((0, 2, 192, 38))                                     # 192×36
    rows = [r for r in range(rib.height) if not (12 <= r < 20)]         # 抽掉中段 8 行 ⇒ 28 高(更细更轻)
    small = Image.new("RGBA", (rib.width, len(rows)))
    for i, r in enumerate(rows):
        small.paste(rib.crop((0, r, rib.width, r + 1)), (0, i))
    out["ribbon.png"] = small

    pq = Image.open(os.path.join(SRC, "plaque.png")).convert("RGBA").crop((6, 4, 184, 44))   # 178×40
    rows = list(range(0, 22)) + list(range(18, 22)) + list(range(22, 40))                 # 插 4 行木面 ⇒ 44 高
    tall = Image.new("RGBA", (pq.width, len(rows)))
    for i, r in enumerate(rows):
        tall.paste(pq.crop((0, r, pq.width, r + 1)), (0, i))
    out["plaque.png"] = tall

    for name, im in out.items():
        im.save(os.path.join(ROOT, name))
        print("%-16s %dx%d" % (name, im.width, im.height))


if __name__ == "__main__":
    main()
