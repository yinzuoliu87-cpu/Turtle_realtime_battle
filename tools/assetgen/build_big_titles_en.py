# -*- coding: utf-8 -*-
"""结算屏 / 决赛日大字美术字的英文版(2026-11-23 · 语言选项)。确定性生成, 重跑逐字节相同。

★由来: 大字是中文美术图贴在标签上(BigTitle.apply / FinalsCtx.dress_art), 英文界面下标签的字已经翻成英文、
  但贴上去的图还是「胜利」「上路战场」—— 英文玩家看到的是中文。
  ⇒ 每张中文图配一张 <名>_en.png; 游戏在英文下只找 _en 图, 找不到就不贴图(标签显示自己的英文字)。

  做法与 build_big_titles.py 同一套(Noto Sans SC Black 单色栅格化 + 1 格描边 + 2 格落影 + 竖向渐变), 但三样直接从对应的中文图量:
    · 墨迹高 = 中文图高 - 5(build() 四周 2 格 + 底下 3 格落影), 英文大写字按这个高度反推字号;
    · 描边色 = 中文图出现最多的颜色(金字是深褐, 冷色「惜败」是深蓝);
    · 渐变 = 中文图每一行最多的填充色(去掉描边 / 落影), 英文图同高, 逐行照抄 —— 不另调一套颜色。
  图上的字比标签里的完整译文短(「Advanced to the Semifinals」⇒ SEMIFINALS): 大字是一眼读的, 完整句子留给标签(读屏 / 测试)。

  python tools/assetgen/build_big_titles_en.py            生成全部
  python tools/assetgen/build_big_titles_en.py --preview  另存一张 ×3 放大对照图到 .out/
"""
import os
import sys
from collections import Counter

from PIL import Image, ImageDraw, ImageFilter, ImageFont

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT = r"C:\Windows\Fonts\NotoSansSC-VF.ttf"
WEIGHT = b"Black"
SHADOW = (14, 10, 20)
BT = "assets/sprites/ui/bigtitle/"
FN = "assets/sprites/finals/"

## (中文图, 英文字)。英文图 = 中文图同目录 <名>_en.png
WORDS = [
    (BT + "big_win.png", "VICTORY"),
    (BT + "big_lose.png", "DEFEAT"),
    (BT + "big_promoted.png", "QUALIFIED!"),
    (BT + "big_sealed.png", "RESULT SEALED"),
    (BT + "rail_win.png", "VICTORY"),
    (BT + "rail_lose.png", "DEFEAT"),
    (BT + "rail_sealed.png", "SEALED"),
    (BT + "lane_win.png", "W"),
    (BT + "lane_lose.png", "L"),
    (BT + "lane_draw.png", "D"),
    (FN + "bt-kaizhan.png", "FIGHT!"),
    (FN + "bt-xibai.png", "SO CLOSE"),
    (FN + "bt-huosheng.png", "WINS"),
    (FN + "bt-adv-final.png", "TO THE FINAL"),
    (FN + "bt-adv-semi.png", "SEMIFINALS"),
    (FN + "bt-adv-8.png", "TOP 8"),
    (FN + "bt-adv-16.png", "TOP 16"),
    (FN + "bt-adv-cup.png", "TO THE CUP"),
    (FN + "bt-cup-champ.png", "CUP CHAMPION"),
    (FN + "bt-lane-top.png", "TOP LANE"),
    (FN + "bt-lane-bottom.png", "BOTTOM LANE"),
    (FN + "bt-lane-final.png", "FINAL BATTLE"),
]


def _mask(text, px):
    f = ImageFont.truetype(FONT, px)
    f.set_variation_by_name(WEIGHT)
    im = Image.new("L", (px * len(text) + 16, px * 2), 0)
    d = ImageDraw.Draw(im)
    d.fontmode = "1"
    d.text((4, 2), text, font=f, fill=255)
    return im.crop(im.getbbox())


def _mask_h(text, ink_h):
    """字号从小往大试, 取墨迹高 ≤ ink_h 的最大一档(大写字没有下伸, 墨迹高 ≈ 大写高)。"""
    best = None
    for px in range(6, 200):
        m = _mask(text, px)
        if m.size[1] > ink_h:
            break
        best = m
    return best


def _style(zh):
    """从中文图量出描边色 + 逐行填充色。"""
    im = zh.convert("RGBA")
    px = im.load()
    allc = Counter(px[x, y][:3] for y in range(im.height) for x in range(im.width) if px[x, y][3])
    outline = allc.most_common(1)[0][0]
    rows = []
    for y in range(im.height):
        c = Counter(px[x, y][:3] for x in range(im.width)
                    if px[x, y][3] and px[x, y][:3] not in (outline, SHADOW))
        rows.append(c.most_common(1)[0][0] if c else None)
    ## 没有填充的行(顶上描边行 / 底下落影行)补最近一行的颜色
    known = [i for i, c in enumerate(rows) if c is not None]
    for i in range(len(rows)):
        if rows[i] is None:
            rows[i] = rows[min(known, key=lambda k: abs(k - i))]
    return outline, rows


def build(zh_path, text):
    zh = Image.open(os.path.join(ROOT, zh_path))
    outline, rows = _style(zh)
    m = _mask_h(text, zh.height - 5)
    w, h = m.size[0] + 4, zh.height
    fill_m = Image.new("L", (w, h), 0)
    fill_m.paste(m, (2, 2 + (h - 5 - m.size[1])))
    ol = fill_m.filter(ImageFilter.MaxFilter(3))
    sh = Image.new("L", (w, h), 0)
    sh.paste(ol, (0, 2))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (w, h), SHADOW + (255,)), (0, 0), sh)
    out.paste(Image.new("RGBA", (w, h), outline + (255,)), (0, 0), ol)
    grad = Image.new("RGBA", (w, h))
    gp = grad.load()
    for y in range(h):
        for x in range(w):
            gp[x, y] = rows[y] + (255,)
    out.paste(grad, (0, 0), fill_m)
    return zh, out


def main():
    pairs = []
    for zh_path, text in WORDS:
        zh, im = build(zh_path, text)
        dst = os.path.join(ROOT, zh_path[:-4] + "_en.png")
        im.save(dst, optimize=False)
        pairs.append((zh, im))
        print("  %-34s %-14s %3dx%-3d (中文 %dx%d)" % (os.path.basename(dst), text, im.width, im.height, zh.width, zh.height))
    if "--preview" in sys.argv:
        W = max(a.width + b.width for a, b in pairs) * 3 + 40
        H = sum(max(a.height, b.height) * 3 + 10 for a, b in pairs) + 10
        pv = Image.new("RGB", (W, H), (40, 42, 69))
        y = 10
        for a, b in pairs:
            sa = a.convert("RGBA").resize((a.width * 3, a.height * 3), Image.NEAREST)
            sb = b.resize((b.width * 3, b.height * 3), Image.NEAREST)
            pv.paste(sa, (10, y), sa)
            pv.paste(sb, (30 + sa.width, y), sb)
            y += max(sa.height, sb.height) + 10
        p = os.path.join(ROOT, ".out", "bigtitle_en_preview.png")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        pv.save(p)
        print("  预览 " + p)
    print("ALL OK  %d 张" % len(pairs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
