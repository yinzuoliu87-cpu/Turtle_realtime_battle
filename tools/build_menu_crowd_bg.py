# -*- coding: utf-8 -*-
"""build_menu_crowd_bg.py — 用 28 只龟的第 0 帧合成主菜单背景 menu-bg-crowd.png。

由来(2026-09-17): 主菜单背景原来是 menu-bg-tile.png 平铺装备暗纹 —— 一张淡到几乎看不见的
纹理, 等于把屏幕上最大的一块画布浪费掉了。对标 151 款商业游戏主菜单后确认: 画面主体应该是
【游戏世界本身】(Fuga / Zombie Rollerz / River City Saga 都是让角色铺满整屏当背景)。
这个游戏正好有 28 只龟。

★为什么要有这个脚本, 而不是手工拼一张图:
  加龟 / 换立绘 / 调纵深参数时重跑一次就同步。手工拼的图在下一只龟进来时就烂了。

★切帧口径来自 data/pets.json 的 sprite={frames,frameW,frameH} —— 事实源, 不是我数出来的。
  sprite 为 null 的是单张图, 整张用。第 0 帧无论图集几行都在左上角 (0,0)。

跑法:
    python tools/build_menu_crowd_bg.py                 # 直接覆盖 assets/sprites/menu/menu-bg-crowd.png
    python tools/build_menu_crowd_bg.py --variants      # 额外吐 A/B/C 三档亮度供挑选
  跑完必须 `<godot> --headless --path . --import`, 否则游戏读到的还是旧图
  (memory fb-replaced-asset-needs-reimport)。

依赖: Pillow。
"""
import argparse
import io
import json
import os
import random
import sys

try:
    from PIL import Image, ImageEnhance, ImageFilter
except ImportError:  # pragma: no cover
    print("需要 Pillow: pip install pillow")
    sys.exit(2)

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PETS_JSON = os.path.join(ROOT, "data", "pets.json")
SPRITES = os.path.join(ROOT, "assets", "sprites")
OUT_PNG = os.path.join(SPRITES, "menu", "menu-bg-crowd.png")

W, H = 1280, 720
BASE_RGB = (26, 58, 42)     # = 菜单底色 #1a3a2a; 换背景不换色调
SEED = 20260917             # 固定 seed: 同一份代码永远出同一张图, 不然每次跑都换一张没法比较

# 后排→前排: (脚底线 y, 目标高度, 这一层几只, 明度, y 抖动幅度)
LAYERS = [
    (118, 92, 6, 0.40, 26),
    (258, 118, 6, 0.52, 30),
    (410, 152, 6, 0.66, 32),
    (562, 196, 5, 0.80, 30),
    (742, 248, 5, 0.96, 26),
]

# ★这三个数是【实拍叠上 UI 之后】定的, 不是拍脑袋(详见 docs/plans/20260917-主菜单版式重做.md R8):
#   像素龟饱和度极高(彩虹/糖果/凤凰), 满色时跟前景的金色木框正面打架;
#   而左栏的无框文字压在龟身上会读不出, 所以【左侧】要单独压到 0.24。
DIM_OVERALL, LEFT_DIM, VIGNETTE, DESAT = 0.54, 0.24, 0.62, 0.50


def load_pets():
    d = json.load(io.open(PETS_JSON, encoding="utf-8"))
    return d if isinstance(d, list) else d.get("pets", list(d.values()))


def first_frames():
    """每只龟的第 0 帧, autocrop 掉透明边。返回 [(id, Image)]。"""
    out, bad = [], []
    for p in load_pets():
        pid, img = p.get("id"), p.get("img", "")
        path = os.path.join(SPRITES, img)
        if not os.path.exists(path):
            bad.append((pid, "缺文件 " + img))
            continue
        im = Image.open(path).convert("RGBA")
        sp = p.get("sprite")
        if sp:
            fw, fh, n = int(sp["frameW"]), int(sp["frameH"]), int(sp["frames"])
            # 分母: 图集【总格数】要装得下 n 帧。★别写成 width < fw*n —— 那假设单行,
            #   而 11 只龟是多行图集(4000×1500 = 8帧/行 × 3 行 = 24 格装 17 帧), 会全部误报。
            cells = (im.width // fw) * (im.height // fh)
            if cells < n:
                bad.append((pid, "图集 %d 格 < 声明 %d 帧" % (cells, n)))
            frame = im.crop((0, 0, min(fw, im.width), min(fh, im.height)))
        else:
            frame = im
        box = frame.getbbox()
        out.append((pid, frame.crop(box) if box else frame))
    return out, bad


def mean_lum(im):
    """一只龟的平均亮度(只算不透明像素)。决定它站左边还是右边。"""
    px = im.convert("RGBA").resize((32, 32), Image.BILINEAR).load()
    tot = n = 0
    for x in range(32):
        for y in range(32):
            r, g, b, a = px[x, y]
            if a > 40:
                tot += 0.299 * r + 0.587 * g + 0.114 * b
                n += 1
    return tot / n if n else 0.0


def compose(pets):
    """五层纵深排布。四条规则(照 Fuga / Zombie Rollerz 的人群实拍来, 不是等距摆件):
       ① 不在同一基线 —— 层内再给 y 抖动, 高低交错
       ② 大量重叠 —— 相邻必然咬合
       ③ 铺满整个画面含四角, 边上的裁出画
       ④ 大小差异要大(90~250px), 纵深只有 scale 拉得开
    """
    rnd = random.Random(SEED)
    pets = sorted(pets, key=lambda kv: kv[1].height)     # 小的往后排
    canvas = Image.new("RGBA", (W, H), BASE_RGB + (255,))
    i, placed = 0, []
    for (base_y, tgt_h, n, bright, jit) in LAYERS:
        layer = pets[i:i + n]
        i += n
        if not layer:
            continue
        # 同层左右顺序按平均亮度升序: 暗的站左边。★不是为了好看 —— 主菜单文字全在左侧,
        #   而白骰子/线条龟是纯白高对比, 随机摆会正好落在按钮区上把文字盖掉。
        #   (只按亮度排会成渐变栅栏, 所以同档内再 shuffle 打散。)
        order = sorted(layer, key=lambda kv: mean_lum(kv[1]))
        half = len(order) // 2
        a, b = order[:half], order[half:]
        rnd.shuffle(a)
        rnd.shuffle(b)
        order = a + b
        span = W + 260                                    # ③两端出画
        step = span / float(n)
        for k, (pid, im) in enumerate(order):
            s = tgt_h / float(im.height)
            w2, h2 = max(1, int(im.width * s)), max(1, int(im.height * s))
            sp = im.resize((w2, h2), Image.LANCZOS)
            sp = ImageEnhance.Brightness(sp).enhance(bright)
            if bright < 0.45:
                sp = sp.filter(ImageFilter.GaussianBlur(0.7))   # 只糊最后一层 = 空气透视
            cx = -130 + step * (k + 0.5) + rnd.uniform(-0.42, 0.42) * step   # ②咬合
            y = int(base_y - h2 + rnd.randint(-jit, jit))                    # ①交错
            canvas.alpha_composite(sp, (int(cx - w2 / 2), y))
            placed.append((pid, int(cx), y, w2, h2))
    return canvas, placed


def finish(canvas, dim_overall, left_dim, vignette, desat):
    flat = Image.new("RGB", (W, H), BASE_RGB)
    flat.paste(canvas, (0, 0), canvas)
    flat = ImageEnhance.Brightness(flat).enhance(dim_overall)
    flat = ImageEnhance.Color(flat).enhance(desat)
    px = flat.load()
    cx, cy = W / 2.0, H / 2.0
    maxd = (cx * cx + cy * cy) ** 0.5
    for x in range(W):
        # 左侧压暗: 0 处最暗, 到 x=860 收回。★过渡要拉长 —— 第一版 320px 时画面上
        #   看得见一条竖色带(实拍抓到的, 不是猜的)。
        t = max(0.0, 1.0 - x / 860.0) ** 1.25
        fx = 1.0 - (1.0 - left_dim) * t
        for y in range(H):
            f = fx
            if vignette > 0:
                d = (((x - cx) ** 2 + (y - cy) ** 2) ** 0.5) / maxd
                f *= 1.0 - vignette * max(0.0, (d - 0.60) / 0.40) ** 1.6
            r, g, b = px[x, y]
            px[x, y] = (int(r * f), int(g * f), int(b * f))
    return flat


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variants", action="store_true", help="额外吐 A/B/C 三档亮度到 build/")
    ap.add_argument("--out", default=OUT_PNG)
    args = ap.parse_args()

    pets, bad = first_frames()
    print("切出 %d 只 / 异常 %d" % (len(pets), len(bad)))
    for pid, msg in bad:
        print("   ★ %-12s %s" % (pid, msg))
    if len(pets) < 20:
        print("★龟数 %d < 20, 不像话 —— 先查 data/pets.json 与 assets/sprites/pets/" % len(pets))
        return 1

    canvas, placed = compose(pets)
    print("排了 %d 只" % len(placed))
    if len(placed) != len(pets):
        print("★排布数 %d ≠ 切出数 %d: LAYERS 的名额总和与龟数对不上" % (len(placed), len(pets)))
        return 1
    # 覆盖率分母: 四象限各有几只龟的中心 ——「铺满」不能靠眼睛说
    q = [0, 0, 0, 0]
    for _pid, x, y, _w, h2 in placed:
        q[(0 if x < W / 2 else 1) + (0 if y + h2 / 2 < H / 2 else 2)] += 1
    print("四象限 左上%d 右上%d 左下%d 右下%d  (任一象限=0 说明没铺满)" % tuple(q))
    if min(q) == 0:
        print("★有象限为空, 背景会露出大片纯色")
        return 1

    finish(canvas, DIM_OVERALL, LEFT_DIM, VIGNETTE, DESAT).save(args.out)
    print("写出 %s" % args.out)

    if args.variants:
        bd = os.path.join(ROOT, "build")
        os.makedirs(bd, exist_ok=True)
        for name, dim, ld, vg in [("A", 0.72, 0.38, 0.46), ("B", 0.54, 0.24, 0.62), ("C", 0.44, 0.18, 0.68)]:
            p = os.path.join(bd, "menu-bg-crowd-%s.png" % name)
            finish(canvas, dim, ld, vg, DESAT).save(p)
            print("  变体 %s -> %s" % (name, p))
    print("★别忘了 --import, 否则游戏读到的还是旧图")
    return 0


if __name__ == "__main__":
    sys.exit(main())
