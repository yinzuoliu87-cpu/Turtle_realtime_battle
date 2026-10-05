# -*- coding: utf-8 -*-
"""build_menu_arena_bg.py — 主菜单「擂台 + 看台」背景【草图】合成器 (2026-10-05)。

由来: 方案书 docs/plans/20260917-主菜单版式重做.md R1 —— 场景 = 擂台 + 看台。
  R1-a「尽量不要复用好吗」⇒ 擂台/看台/前景装饰一律新生成, 不拿 assets/sprites/map/ 的件拼;
  R1-b (2026-10-05)「不能用现有的龟立绘」⇒ 看台观众也全部新画, 不用 28 只龟的立绘。
  ⇒ 本脚本只读 assets/sprites/menu/arena/ 里 PixelLab 新生成的素材, 一张旧图都不碰。

★这是【草图】阶段: 产物写到 docs/plans/img-20261005-主菜单擂台/, 不覆盖游戏正在用的
  menu-bg-crowd.png (那张由 build_menu_crowd_bg.py 生成、menu_crowd_sync_audit 守着)。
  用户点头后才会接进 MainMenuScene。

像素口径: 整张图在【原生 390×180】上合成, 最后 ×4 最近邻放大到 1560×720。
  ⇒ 所有件同一像素密度(一格 = 4 屏幕像素), 不出现大小像素混排。
  游戏里背景是 STRETCH_KEEP_ASPECT_COVERED: 1280×720 视口看到的是中间 320 列。

R8 已定取舍(别反复): desat 0.50 / 左侧压暗 0.24 —— 左栏是无框文字, 背后必须暗。

跑法: python tools/build_menu_arena_bg.py [--out <png>]
依赖: Pillow。
"""
import argparse
import os
import random
import sys

try:
    from PIL import Image, ImageEnhance
except ImportError:  # pragma: no cover
    print("需要 Pillow: pip install pillow")
    sys.exit(2)

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "sprites", "menu", "arena")
OUT_DIR = os.path.join(ROOT, "docs", "plans", "img-20261005-主菜单擂台")
OUT_PNG = os.path.join(OUT_DIR, "draft-bg-1560.png")

NW, NH = 390, 180          # 原生画布; ×4 = 1560×720
SCALE = 4
SEED = 20261005

# R8 取舍(钉死): 去饱和 0.50 / 左侧压到 0.24
DESAT, LEFT_DIM = 0.50, 0.24
DIM_OVERALL = 0.80         # 这张底图本身比群像暗, 0.54 会糊成一团 —— 草图阶段的值, 待实拍定
VIGNETTE = 0.45

# 看台几何(在 arena_bowl.png 原生 400 宽坐标上量的, 量法: 加网格逐格看)
#   一排观众是一条抛物线: 中间 y = yc, 两端偏移 e(yc)。远排(上)两端往上翘, 近排(下)往下弯。
ARENA_ELLIPSE = (200, 141, 120, 36)
# ★观众只坐在看台的三层座区里, 层与层之间的走道/栏杆留空 —— 第一版每 6px 一排铺满,
#   结果整片看台成了一张彩色噪点毯, 场馆的结构(层次/栏杆)全被盖掉, 读不出"看台"。
ROWS = [50, 55, 66, 72, 78, 84, 98, 104, 110, 116, 156, 168]
FILL = 0.80
FIGHTER_X = (160, 203)
FIGHTER_DIM, FIGHTER_DESAT = 0.88, 0.80   # 擂台沙地 + 围栏, 观众不许坐进去
GATE_BOX = (185, 98, 216, 124)        # 正中入场门洞


def _edge(yc):
    return -30.0 + (yc - 45.0) * 55.0 / 85.0


def _row_y(x, yc):
    t = (x - 200.0) / 200.0
    return yc + _edge(yc) * t * t


def _in_arena(x, y):
    cx, cy, rx, ry = ARENA_ELLIPSE
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 1.0


def _cells(path, cell):
    """把 16 列的候选图集切回一格一格, 每格只留最大的不透明连通块
    (PixelLab 的多候选会互相渗边, 不清会在观众头顶多出别人的旗子尖)。"""
    sheet = Image.open(path).convert("RGBA")
    out = []
    for r in range(sheet.height // cell):
        for c in range(sheet.width // cell):
            im = sheet.crop((c * cell, r * cell, (c + 1) * cell, (r + 1) * cell))
            im = _largest_blob(im)
            if im.getbbox():
                out.append(im)
    return out


def _largest_blob(im):
    w, h = im.size
    px = im.load()
    seen, best = set(), []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 0 and (x, y) not in seen:
                comp, st = [], [(x, y)]
                seen.add((x, y))
                while st:
                    a, b = st.pop()
                    comp.append((a, b))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            c, d = a + dx, b + dy
                            if 0 <= c < w and 0 <= d < h and (c, d) not in seen and px[c, d][3] > 0:
                                seen.add((c, d))
                                st.append((c, d))
                if len(comp) > len(best):
                    best = comp
    o = Image.new("RGBA", (w, h))
    op = o.load()
    for (x, y) in best:
        op[x, y] = px[x, y]
    return o


def _shade(im, f, tint=(1.0, 0.86, 0.68)):
    """按纵深压暗 + 往场馆暖光里染 —— 不染的话 PixelLab 的高饱和绿/紫会浮在褐色看台上。"""
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (int(r * f * tint[0]), int(g * f * tint[1]), int(b * f * tint[2]), a)
    return im


def _lum(im):
    tot = n = 0
    for r, g, b, a in im.getdata():
        if a:
            tot += 0.299 * r + 0.587 * g + 0.114 * b
            n += 1
    return tot / n if n else 0.0


def _shadow(canvas, cx, cy, rx, ry, alpha=110):
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    px = sh.load()
    for y in range(int(cy - ry), int(cy + ry) + 1):
        for x in range(int(cx - rx), int(cx + rx) + 1):
            if 0 <= x < canvas.width and 0 <= y < canvas.height:
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    px[x, y] = (20, 10, 4, alpha)
    canvas.alpha_composite(sh)


def compose():
    rnd = random.Random(SEED)
    bowl = Image.open(os.path.join(ART, "arena_bowl.png")).convert("RGBA")
    ox = (bowl.width - NW) // 2                         # 400→390 居中裁
    canvas = bowl.crop((ox, 0, ox + NW, NH))
    far = _cells(os.path.join(ART, "crowd_far_16.png"), 16)
    near = _cells(os.path.join(ART, "crowd_near_32.png"), 32)
    back = _cells(os.path.join(ART, "crowd_back_32.png"), 32)
    n_far = n_near = n_back = 0

    # ① 远看台: 16px 小龟, 一排一排沿弧线坐, 后排先画、前排压在上面(只露头 = 人群感)
    for yc in ROWS:
        depth = min(1.0, (yc - 52) / 90.0)
        f = 0.50 + 0.38 * depth
        sprites = near if yc >= 150 else far
        step = 15 if yc >= 150 else 8
        x = rnd.uniform(-6, step)
        while x < 400 + 8:
            y = _row_y(x, yc)
            gx, gy = x, y
            skip = (y > NH + 10 or y < 44 or _in_arena(gx, gy) or
                    (GATE_BOX[0] - 6 < gx < GATE_BOX[2] + 6 and GATE_BOX[1] - 4 < gy < GATE_BOX[3] + 6))
            if sprites is near and 128 < gx < 272:
                skip = True                         # 近排别挡擂台正前方(两只对峙的脚在这里)
            if not skip and rnd.random() < FILL:
                sp = rnd.choice(sprites)
                if rnd.random() < 0.5:
                    sp = sp.transpose(Image.FLIP_LEFT_RIGHT)
                # 亮度拉齐: 黄壳那几只比别的亮一截, 在暗看台上会跳成一个个亮点
                sp = _shade(sp, f * rnd.uniform(0.85, 1.05) * min(1.0, 110.0 / max(1.0, _lum(sp))))
                bb = sp.getbbox()
                foot = bb[3] if bb else sp.height
                canvas.alpha_composite(sp, (int(gx - ox - sp.width / 2), int(gy - foot + rnd.randint(-1, 1))))
                if sprites is near:
                    n_near += 1
                else:
                    n_far += 1
            x += step * rnd.uniform(0.8, 1.2)

    # ② 擂台上两只对峙 —— 新画的角斗龟, 一只镜像成朝左
    #    ★位置是叠真 UI 实拍后挪的: 第一版放在擂台正中(176/222), 右边那只整个被「开始战斗」盖住。
    #    1560 宽下主 CTA 左缘 = 屏幕 880 = 原生 225, 左栏文字右缘 ≈ 原生 135 ⇒ 两只挤在 140~215 之间。
    #    ⚠ 只记位置, 不在这里贴 —— 主角在 finish() 之后再贴, 不吃背景的去饱和/压暗(它们是视觉焦点)。
    fighters = []
    fa = Image.open(os.path.join(ART, "fighter_a.png")).convert("RGBA")
    fb = Image.open(os.path.join(ART, "fighter_b.png")).convert("RGBA").transpose(Image.FLIP_LEFT_RIGHT)
    for sp, cx, foot in ((fa, FIGHTER_X[0], 150), (fb, FIGHTER_X[1], 151)):
        _shadow(canvas, cx - ox, foot - 1, 13, 3)
        bb = sp.getbbox()
        fighters.append((sp, (int(cx - ox - (bb[0] + bb[2]) / 2), foot - bb[3])))

    # ③ 前景: 背对镜头的一排看客(带长凳), 只压左下 / 右下两角, 出画
    for x0, x1 in ((-10, 120), (285, 405)):
        x = x0
        while x < x1:
            sp = rnd.choice(back)
            if rnd.random() < 0.5:
                sp = sp.transpose(Image.FLIP_LEFT_RIGHT)
            sp = _shade(sp, 0.55, (1.0, 0.82, 0.62))
            canvas.alpha_composite(sp, (int(x - ox), NH - 26 + rnd.randint(-1, 2)))
            n_back += 1
            x += rnd.randint(22, 28)

    # ④ 道具: 火盆压两角, 旗子从顶沿垂下
    brazier = Image.open(os.path.join(ART, "prop_brazier.png")).convert("RGBA")
    canvas.alpha_composite(brazier, (-14, NH - 70))
    canvas.alpha_composite(brazier.transpose(Image.FLIP_LEFT_RIGHT), (NW - 50, NH - 70))
    for name, x in (("prop_banner_red.png", 168),):
        bn = Image.open(os.path.join(ART, name)).convert("RGBA")
        bb = bn.getbbox()
        canvas.alpha_composite(bn, (x - ox, -bb[1] - 8))

    return canvas, fighters, (n_far, n_near, n_back)


def finish(canvas):
    flat = Image.new("RGB", canvas.size, (0, 0, 0))
    flat.paste(canvas, (0, 0), canvas)
    flat = ImageEnhance.Brightness(flat).enhance(DIM_OVERALL)
    flat = ImageEnhance.Color(flat).enhance(DESAT)
    px = flat.load()
    w, h = flat.size
    cx, cy = w / 2.0, h / 2.0
    maxd = (cx * cx + cy * cy) ** 0.5
    for x in range(w):
        # 左侧压暗: 1560 宽下左栏文字在 x<560(原生 140); 1280 视口左缘在原生 35 ⇒ 平台拉到 60 再缓收到 230
        t = 1.0 if x < 60 else max(0.0, 1.0 - (x - 60) / 170.0) ** 1.25
        fx = 1.0 - (1.0 - LEFT_DIM) * t
        for y in range(h):
            d = (((x - cx) ** 2 + (y - cy) ** 2) ** 0.5) / maxd
            f = fx * (1.0 - VIGNETTE * max(0.0, (d - 0.60) / 0.40) ** 1.6)
            r, g, b = px[x, y]
            px[x, y] = (int(r * f), int(g * f), int(b * f))
    return flat


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=OUT_PNG)
    ap.add_argument("--raw", default="", help="另存一张不压暗的原色版, 看素材本身用")
    args = ap.parse_args()
    canvas, fighters, counts = compose()
    print("远看台 %d 只 / 近看台 %d 只 / 前景背影 %d 只" % counts)
    if min(counts) == 0:
        print("★有一层观众是 0 只 —— 几何参数把它们全跳过了")
        return 1
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    bg = finish(canvas).convert("RGBA")
    for sp, pos in fighters:
        sp = ImageEnhance.Color(ImageEnhance.Brightness(sp).enhance(FIGHTER_DIM)).enhance(FIGHTER_DESAT)
        bg.alpha_composite(sp, pos)
    bg.convert("RGB").resize((NW * SCALE, NH * SCALE), Image.NEAREST).save(args.out)
    print("写出 %s" % args.out)
    if args.raw:
        for sp, pos in fighters:
            canvas.alpha_composite(sp, pos)
        canvas.convert("RGB").resize((NW * SCALE, NH * SCALE), Image.NEAREST).save(args.raw)
        print("原色版 %s" % args.raw)
    return 0


if __name__ == "__main__":
    sys.exit(main())
