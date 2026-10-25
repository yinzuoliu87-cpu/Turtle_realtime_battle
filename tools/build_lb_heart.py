# -*- coding: utf-8 -*-
"""排行榜「剩余生命」的心形(2026-10-24 用户「画吧」)。确定性生成, 重跑逐字节相同。

  assets/sprites/leaderboard/lb-heart.png        还在的命(红心)
  assets/sprites/leaderboard/lb-heart-empty.png  丢掉的命(暗色空槽)

9×8 美术像素, 1 美术像素 = 2 屏幕像素(与 lb-row / lb-medal 同一个口径) ⇒ 存成 18×16。
硬边、零半透明(tools/pixel_art_audit.py 的三条)。

  python tools/build_lb_heart.py            生成两张
  python tools/build_lb_heart.py --preview  另存一张 ×8 放大对照图到 scratch(不进仓库)
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "leaderboard")
SCALE = 2

# O 描边 / r 心身 / H 高光 / D 右下暗面 / . 透明
SHAPE = [
    ".OO...OO.",
    "OHrO.OrrO",
    "OHrrOrrrO",
    "OrrrrrrDO",
    ".OrrrrDO.",
    "..OrrDO..",
    "...ODO...",
    "....O....",
]

FULL = {
    "O": (40, 14, 22, 255),
    "r": (222, 52, 66, 255),
    "H": (255, 170, 176, 255),
    "D": (150, 26, 44, 255),
}
# 丢掉的命: 同一个轮廓, 里面是压暗的空槽(不画高光), 在金 / 银 / 铜 / 自己各种行卡上都读得出「这一格空了」
EMPTY = {
    "O": (40, 14, 22, 255),
    "r": (78, 58, 68, 255),
    "H": (78, 58, 68, 255),
    "D": (58, 42, 52, 255),
}


def render(pal):
    w, h = len(SHAPE[0]), len(SHAPE)
    im = Image.new("RGBA", (w * SCALE, h * SCALE), (0, 0, 0, 0))
    px = im.load()
    for y, row in enumerate(SHAPE):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            for dy in range(SCALE):
                for dx in range(SCALE):
                    px[x * SCALE + dx, y * SCALE + dy] = pal[ch]
    return im


def main():
    full = render(FULL)
    empty = render(EMPTY)
    full.save(os.path.join(OUT_DIR, "lb-heart.png"))
    empty.save(os.path.join(OUT_DIR, "lb-heart-empty.png"))
    print("lb-heart.png / lb-heart-empty.png", full.size)
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1] if len(sys.argv) > sys.argv.index("--preview") + 1 else "lb-heart-preview.png"
        bg = Image.new("RGBA", (full.width * 2 + 6, full.height + 4), (118, 122, 134, 255))
        bg.alpha_composite(full, (2, 2))
        bg.alpha_composite(empty, (full.width + 4, 2))
        bg.resize((bg.width * 8, bg.height * 8), Image.NEAREST).save(out)
        print("preview", out)


if __name__ == "__main__":
    main()
