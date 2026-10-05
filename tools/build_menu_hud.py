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
  src/plaque.png  192×48  单块窄木牌 + 四角铜钉     → (第三轮已下线; 原来烘 plaque.png 给左栏每行一块短牌)

2026-10-05 第三轮「大厅骨架」(对标 6 张手游主大厅, 方案书 20260917 第三轮)新增, 同样是 PixelLab 本次新生成:
  src/card.png     192×64  铭牌木板 + 左端黄铜圆环    → card.png(左上玩家信息卡, ×2 像素, 圆环里放头像)
  src/avatar.png    48×48  龟壳纹章铜徽章             → avatar.png(玩家卡头像槽, 原样)
  src/sqbtn.png     64×64  方木块 + 四角铜包角        → sqbtn.png(左列方形图标键, ×2 像素九宫格)
  src/modecard.png 160×96  木告示牌 + 铜包角 + 顶铜条 → modecard.png(「今天」模式卡; 中段那团径向亮斑压平 = AI 味)
  (无原件)                                           → cta-face.png(主 CTA 的亮黄面, 本脚本按像素直接画:
                                                     木框保留(R2), 只把框里那块面换成全屏唯一的饱和亮黄)

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


def widen(im, left, right, W):
    """横向接长到 W: 左 left / 右 right 像素原样, 中段用原中段正反交替拼(接缝处纹理连续, 不缩放一个像素)。"""
    mid = im.crop((left, 0, im.width - right, im.height))
    out = Image.new("RGBA", (W, im.height))
    out.paste(im.crop((0, 0, left, im.height)), (0, 0))
    x, k = left, 0
    while x < W - right:
        seg = mid if k % 2 == 0 else mid.transpose(Image.FLIP_LEFT_RIGHT)
        out.paste(seg.crop((0, 0, min(seg.width, W - right - x), seg.height)), (x, 0))
        x += seg.width
        k += 1
    out.paste(im.crop((im.width - right, 0, im.width, im.height)), (W - right, 0))
    return out


def cta_face():
    """主 CTA 的亮黄面(64×32 画布 ×2)。一圈深棕描边 + 顶 2 行高光 + 底 3 行压暗 + 斜向两道细亮痕(像素笔触, 不是渐变)。"""
    W, H = 64, 32
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    p = im.load()
    OUT, HI, BODY, MID, LO = (74, 36, 6, 255), (255, 246, 168, 255), (255, 206, 38, 255), (247, 182, 22, 255), (214, 136, 14, 255)
    for y in range(H):
        for x in range(W):
            if (x in (0, W - 1) and y in (0, H - 1)):
                continue                                                # 四角缺一格 = 像素圆角
            if x == 0 or y == 0 or x == W - 1 or y == H - 1:
                p[x, y] = OUT
            elif y <= 2:
                p[x, y] = HI
            elif y >= H - 4:
                p[x, y] = LO
            elif y >= H - 9:
                p[x, y] = MID
            else:
                p[x, y] = BODY
    for x0 in (8, 13):                                                  # 左上两道斜亮痕
        for k in range(6):
            if 0 < x0 + k < W - 1 and 3 + k < H - 4:
                p[x0 + k, 3 + k] = HI
    return up(im, 2)                                                   # 128×64


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

    ## (plaque.png 左栏短木牌 2026-10-05 第三轮下线: 左栏换成方形图标键 sqbtn.png, 原件 src/plaque.png 留作历史)

    card = Image.open(os.path.join(SRC, "card.png")).convert("RGBA")
    ## 卡宽 462 = 主菜单 CARD_SIZE.x: 直接烘成成品宽, 游戏里 1:1 贴, 中段不 TILE 不拉伸(TILE 实拍有一道竖接缝)
    ## 第三轮返工: 卡宽跟着内容收(游戏里九宫格只横向压中段木纹), 这里烘最宽那一档 456;
    ##   竖向在**圆环下面的木面**(第 90 行)插 18 行 ⇒ 130 高, 木面 16..111 装得下昵称 22 号 + 三行 17 号,
    ##   战绩那行不再压到底边的铜线上(上一版实拍「战绩-还没上过场」那道横线就是底边铜线从字缝里露出来)。
    cw = widen(up(card.crop(card.getbbox()), 2), 112, 40, 456)
    rows = list(range(0, 90)) + [90] * 18 + list(range(90, cw.height))
    ct = Image.new("RGBA", (cw.width, len(rows)))
    for i, r in enumerate(rows):
        ct.paste(cw.crop((0, r, cw.width, r + 1)), (0, i))
    out["card.png"] = ct                                               # 456×130
    av = Image.open(os.path.join(SRC, "avatar.png")).convert("RGBA")
    out["avatar.png"] = av.crop(av.getbbox())                          # 40×40
    sq = Image.open(os.path.join(SRC, "sqbtn.png")).convert("RGBA")
    out["sqbtn.png"] = up(sq.crop(sq.getbbox()), 2)                    # 112×114

    mc = Image.open(os.path.join(SRC, "modecard.png")).convert("RGBA")
    mc = mc.crop(mc.getbbox())                                          # 148×84
    mp = mc.load()
    ref = mc.copy().load()
    from collections import Counter
    ## 面板中段压成**一块平的暗木面**: 原件中间那团径向亮斑是 AI 味; 板缝横线也去掉 ——
    ##   上面要压三行字, 板缝会从字中间穿过去(也让 verify_ui_consistency 量到的边带从 28 缩回到真实的木框宽 ~11)。
    face = Counter(ref[x, y] for y in range(40, 60) for x in range(110, 134)).most_common(1)[0][0]
    for y in range(14, 70):
        for x in range(12, 136):
            if mp[x, y][3] > 0:
                mp[x, y] = face
    rows = list(range(0, 42)) + [42] * 24 + list(range(42, mc.height))   # 竖向插 24 行平木面 ⇒ 108 高(与开始战斗同一档高度)
    tall = Image.new("RGBA", (mc.width, len(rows)))
    for i, r in enumerate(rows):
        tall.paste(mc.crop((0, r, mc.width, r + 1)), (0, i))
    ## 横向接长到 300(= 主菜单 MODE_SIZE, 1:1): 顶铜条只能有一块且居中 ⇒ 左角 | 填充 | 铜条 | 填充 | 右角,
    ##   填充取铜条左边那段素木(28..42), 正反交替拼。
    W = 320
    left, head, right = tall.crop((0, 0, 28, tall.height)), tall.crop((42, 0, 106, tall.height)), tall.crop((tall.width - 28, 0, tall.width, tall.height))
    fill = tall.crop((28, 0, 42, tall.height))
    room = W - left.width - head.width - right.width
    def band(n):
        b = Image.new("RGBA", (n, tall.height)); x, k = 0, 0
        while x < n:
            seg = fill if k % 2 == 0 else fill.transpose(Image.FLIP_LEFT_RIGHT)
            b.paste(seg.crop((0, 0, min(seg.width, n - x), seg.height)), (x, 0)); x += seg.width; k += 1
        return b
    mcw = Image.new("RGBA", (W, tall.height)); x = 0
    for part in (left, band(room // 2), head, band(room - room // 2), right):
        mcw.paste(part, (x, 0)); x += part.width
    out["modecard.png"] = mcw                                          # 320×108

    out["cta-face.png"] = cta_face()

    for name, im in out.items():
        im.save(os.path.join(ROOT, name))
        print("%-16s %dx%d" % (name, im.width, im.height))


if __name__ == "__main__":
    main()
