# -*- coding: utf-8 -*-
"""结算屏大字美术字(2026-10-27 用户选「方案 A」)。确定性生成, 重跑逐字节相同。

★由来: 标题统一换成 12px 像素标题字(当时是方舟像素, 同日换成缝合像素, 字形相同)之后, 结算屏「胜利」是 12 格的字放大 7 倍 ——「利」的禾散成几颗方块,
  各路「负」的贝被省成一个框加一竖。查了 9 款有中文结算大字的商业游戏(玩家实截, 逐张数像素格):
  只有哥布林弹球一款是小格字直接放大; 想保留像素感的(战律 / 星之海)都是【大格子的字 + 描边 + 渐变 + 落影】,
  正文另用 11~12 格的小字。⇒ 结算屏这几个固定词单独出图, 中号标题仍是像素标题字体。

  做法: Noto Sans SC Black 单色栅格化到「一个汉字约 N 格高」的源像素格(大字 26 格 / 小字 15 格),
  再在源像素格上加 1 格深色描边、2 格落影、竖向三段渐变。存 1 倍源图, 游戏里按整数倍(BigTitle.SCALE)最近邻放大。
  硬边、零半透明。

  输出: assets/sprites/ui/bigtitle/<名>.png  (文字 → 文件名的表 = WORDS, scripts/util/big_title.gd 的 FILES 是同一张表,
        门禁 verify_big_title 对账)

  python tools/build_big_titles.py            生成全部
  python tools/build_big_titles.py --preview  另存一张 ×3 放大对照图到 C:/tmp(不进仓库)

★字体: 本机 C:/Windows/Fonts/NotoSansSC-VF.ttf(Noto Sans SC 可变字体, OFL 1.1; 用的是 Black 字重)。
  只有生成时要, 游戏里不加载它(产物是图)。sha256 前 16 位 FONT_SHA 对不上时照样生成, 但会提示字形可能变了。
"""
import hashlib
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "ui", "bigtitle")
FONT = r"C:\Windows\Fonts\NotoSansSC-VF.ttf"
FONT_SHA = "763146584cf07102"
WEIGHT = b"Black"

## 源像素格高: 大字(结算屏中央) / 小字(左栏、各路)
BIG = 26
SMALL = 15

## 三段竖向渐变: 顶 / 中 / 底
GOLD = ((255, 250, 205), (255, 217, 61), (240, 138, 36))
RED = ((255, 190, 190), (255, 107, 107), (196, 52, 52))
GREY = ((228, 236, 245), (159, 179, 200), (92, 108, 130))
OUTLINE = (58, 26, 18)
SHADOW = (14, 10, 20)

## (文件名, 文字, 格高, 渐变)。★文件名只用 ASCII(导出到 iOS / Android 时中文文件名不稳)
WORDS = [
    ("big_win", "胜利", BIG, GOLD),
    ("big_lose", "失败", BIG, RED),
    ("big_promoted", "已晋级！", BIG, GOLD),
    ("big_sealed", "结果已封存", BIG, GREY),
    ("rail_win", "胜利", SMALL, GOLD),
    ("rail_lose", "失败", SMALL, RED),
    ("rail_sealed", "已封存", SMALL, GREY),
    ("lane_win", "胜", SMALL, GOLD),
    ("lane_lose", "负", SMALL, RED),
    ("lane_draw", "平", SMALL, GREY),
]


def _font(px):
    f = ImageFont.truetype(FONT, px)
    f.set_variation_by_name(WEIGHT)
    return f


def _mask(text, grid):
    """单色栅格化 → 0/255 蒙版, 裁到墨迹。字号 = 格高 × 1.12(汉字墨迹约占 em 的 0.9)。"""
    f = _font(int(grid * 1.12))
    im = Image.new("L", (grid * 2 * len(text) + 8, grid * 2), 0)
    d = ImageDraw.Draw(im)
    d.fontmode = "1"
    d.text((4, 2), text, font=f, fill=255)
    return im.crop(im.getbbox())


def _ramp(h, top, mid, bot):
    out = []
    for y in range(h):
        t = y / max(1, h - 1)
        a, b, u = (top, mid, t / 0.5) if t < 0.5 else (mid, bot, (t - 0.5) / 0.5)
        out.append(tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)))
    return out


def build(text, grid, ramp):
    m = _mask(text, grid)
    ## 四周留 2 格(描边 1 + 余量), 底下再多 3 格给落影
    w, h = m.size[0] + 4, m.size[1] + 5
    fill_m = Image.new("L", (w, h), 0)
    fill_m.paste(m, (2, 2))
    ol = fill_m.filter(ImageFilter.MaxFilter(3))
    sh = Image.new("L", (w, h), 0)
    sh.paste(ol, (0, 2))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (w, h), SHADOW + (255,)), (0, 0), sh)
    out.paste(Image.new("RGBA", (w, h), OUTLINE + (255,)), (0, 0), ol)
    g = _ramp(h, *ramp)
    grad = Image.new("RGBA", (w, h))
    gp = grad.load()
    for y in range(h):
        for x in range(w):
            gp[x, y] = g[y] + (255,)
    out.paste(grad, (0, 0), fill_m)
    return out


def main():
    sha = hashlib.sha256(open(FONT, "rb").read()).hexdigest()[:16]
    if sha != FONT_SHA:
        print("[WARN] 字体 sha256 前 16 位 %s ≠ %s: 字形可能与仓库里的图不同" % (sha, FONT_SHA))
    os.makedirs(OUT_DIR, exist_ok=True)
    ims = []
    for name, text, grid, ramp in WORDS:
        im = build(text, grid, ramp)
        im.save(os.path.join(OUT_DIR, name + ".png"), optimize=False)
        ims.append(im)
        print("  %-14s %-6s %dx%d" % (name, text, im.width, im.height))
    if "--preview" in sys.argv:
        W = max(i.width for i in ims) * 3 + 20
        H = sum(i.height * 3 + 10 for i in ims) + 10
        pv = Image.new("RGB", (W, H), (40, 42, 69))
        y = 10
        for i in ims:
            s = i.resize((i.width * 3, i.height * 3), Image.NEAREST)
            pv.paste(s, (10, y), s)
            y += s.height + 10
        pv.save("C:/tmp/bigtitle_preview.png")
        print("  预览 C:/tmp/bigtitle_preview.png")
    print("ALL OK  %d 张" % len(ims))
    return 0


if __name__ == "__main__":
    sys.exit(main())
