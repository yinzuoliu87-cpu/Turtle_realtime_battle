# -*- coding: utf-8 -*-
"""build_menu_arena_bg.py — 主菜单「擂台 + 看台」背景的分层烘焙器 (2026-10-05)。

由来: 方案书 docs/plans/20260917-主菜单版式重做.md R1 —— 场景 = 擂台 + 看台。
  R1-a「尽量不要复用好吗」⇒ 擂台/看台/前景装饰一律新生成, 不拿 assets/sprites/map/ 的件拼;
  R1-b (2026-10-05)「不能用现有的龟立绘」⇒ 看台观众也全部新画, 不用 28 只龟的立绘。
  ⇒ 本脚本只读 assets/sprites/menu/arena/src/ (PixelLab 新生成的原件, 带 .gdignore 不进包),
    一张旧图都不碰。草图 2026-10-05 用户回「还可以」后精修成这一版。

产物 = assets/sprites/menu/arena/baked/ 下一组【分层】小图 + scripts/gamedata/menu_arena_layout.gd(排布常量),
  由 scripts/scenes/menu_arena_backdrop.gd 在游戏里拼起来并让它们动:
    base        场馆 + 静物(火盆架子、阴影), 去掉了会动的东西
    lights_k    顶沿的灯, 分 3 组各自明暗(原图一圈灯等距等亮 = 一眼 AI, 这里删掉一部分、各灯亮度不同)
    crowd_r_k   看台观众, 每一排拆成 2 组交错, 各自按自己的节拍蹦 1 像素(整排一起动会像一块板在晃)
    front_k     前景背影一排(带长凳)
    flame_s_f   两个火盆的火苗, 每边 4 帧
    banner      一面小旗(游戏里用着色器飘)
    fighter_*   两只角斗龟的 5 个姿势(进攻方: 架势/蓄力/突刺; 防守方: 架盾/顶盾)
  每一层都已按同一套调色(去饱和/左侧压暗/暗角)烘好 —— 调色是逐像素乘法, 分层烘与合起来烘结果一样。
  每层都裁到自己的包围盒并记下偏移: 全画布透明层叠二十几张, 手机上是白烧填充率。

像素口径: 原生 390×180, 游戏里整体放大(1280×720 / 1560×720 下都是 ×4)。所有件同一像素密度。

★R8 已定取舍(别反复): desat 0.50 / 左侧压暗 0.24。
  2026-10-05 精修只改了【左侧从 0.24 回到 1.0 的那段坡】: 原来 0~60 列整段钉在 0.24 再慢慢收,
  左栏文字背后是一片死黑; 现在是 0 列 0.24 线性收到 250 列, 文字背后 0.38~0.67, 有层次但仍压得住。

跑法:
    python tools/build_menu_arena_bg.py              # 重烘 baked/ + 写 menu_arena_layout.gd
    python tools/build_menu_arena_bg.py --preview P  # 另存一张静帧合成预览(看效果用, 不进游戏)
  跑完必须 `<godot> --headless --path . --import`(换了 png 不导入, 游戏读到的还是旧图)。
依赖: Pillow。
"""
import argparse
import json
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
SRC = os.path.join(ROOT, "assets", "sprites", "menu", "arena", "src")
OUT = os.path.join(ROOT, "assets", "sprites", "menu", "arena", "baked")
RES_OUT = "res://assets/sprites/menu/arena/baked/"
LAYOUT_GD = os.path.join(ROOT, "scripts", "gamedata", "menu_arena_layout.gd")

NW, NH = 390, 180          # 原生画布
SEED = 20261005

# ── 调色(R8 钉死两个, 其余是 2026-10-05 精修实拍定的) ──
DESAT, LEFT_DIM = 0.50, 0.24
LEFT_RAMP = 250.0          # 左侧压暗从第 0 列的 0.24 线性收回 1.0 用多少列
DIM_OVERALL = 1.0
VIGNETTE = 0.35
FIGHTER_DIM, FIGHTER_DESAT = 0.95, 0.80   # 主角不吃背景那一档去饱和/压暗 —— 它们是视觉焦点

# ── 看台几何(在 arena_bowl.png 原生 400 宽坐标上量的: 加网格逐格看) ──
#   一排观众是一条抛物线: 中间 y = yc, 两端偏移 e(yc)。远排(上)两端往上翘, 近排(下)往下弯。
ARENA_ELLIPSE = (200, 141, 120, 36)   # 擂台沙地 + 围栏, 观众不许坐进去
GATE_BOX = (185, 98, 216, 124)        # 正中入场门洞
# ★观众只坐在看台的座区里, 层与层之间的走道/栏杆留空 —— 草图第一版每 6px 一排铺满,
#   整片看台成了彩色噪点毯, 场馆结构全被盖掉。
FAR_ROWS = [58, 67, 76, 85, 102, 111, 120]
NEAR_ROWS = [156, 168]
FILL = 0.74

# ── 主角站位(原生坐标, 400 宽底图口径) ──
#   ★叠真 UI 实拍后定的: 1280 与 1560 两个比例下, UI 落在原生坐标上是同一个位置
#   (背景按高度 ×4 铺满, 内容框 1280 居中 ⇒ 内容 x = (原生x − 35 − 裁边)×4)。
#   左栏文字右沿 ≈ 原生 142, 主 CTA 左沿 = 原生 218(+5 裁边) ⇒ 两只挤在 145~220 之间。
ATK_X, DEF_X, FOOT_Y = 170, 204, 151
BANNER_X, BANNER_TOP = 206, 57        # 一面小旗挂在入场门正上方的看台沿下(离 LOGO 远, 也不压按钮)

# 火盆: (左上角 x, 左上角 y, 是否镜像)
BRAZIERS = [(-14 + 5, NH - 70, False), (NW - 50 + 5, NH - 70, True)]
FLAME_ROWS = 28            # 火盆图里 y < 28 的橙黄像素是火苗(逐行打印过 F/# 图确认)


def _edge(yc):
    return -30.0 + (yc - 45.0) * 55.0 / 85.0


def _row_y(x, yc):
    t = (x - 200.0) / 200.0
    return yc + _edge(yc) * t * t


def _in_arena(x, y):
    cx, cy, rx, ry = ARENA_ELLIPSE
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 1.0


def _largest_blob(im):
    """PixelLab 的多候选会互相渗边: 只留最大的不透明连通块。"""
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


def _cells(name, cell, min_px=60):
    sheet = Image.open(os.path.join(SRC, name)).convert("RGBA")
    out = []
    for r in range(sheet.height // cell):
        for c in range(sheet.width // cell):
            im = _largest_blob(sheet.crop((c * cell, r * cell, (c + 1) * cell, (r + 1) * cell)))
            n = sum(1 for p in im.getdata() if p[3])
            if n >= min_px:
                out.append(im)
    return out


def _lum(im):
    tot = n = 0
    for r, g, b, a in im.getdata():
        if a:
            tot += 0.299 * r + 0.587 * g + 0.114 * b
            n += 1
    return tot / n if n else 0.0


def _tint(im, f, tint=(1.0, 0.86, 0.68)):
    """按纵深压暗 + 往场馆暖光里染 —— 不染的话 PixelLab 的高饱和绿/紫会浮在褐色看台上。"""
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (int(r * f * tint[0]), int(g * f * tint[1]), int(b * f * tint[2]), a)
    return im


def _grade_factor(x, y):
    """画布坐标 (原生 390 宽) 上的明度系数: 整体压暗 × 左侧压暗 × 暗角。"""
    t = max(0.0, 1.0 - x / LEFT_RAMP)
    fx = 1.0 - (1.0 - LEFT_DIM) * t
    cx, cy = NW / 2.0, NH / 2.0
    maxd = (cx * cx + cy * cy) ** 0.5
    d = (((x - cx) ** 2 + (y - cy) ** 2) ** 0.5) / maxd
    return DIM_OVERALL * fx * (1.0 - VIGNETTE * max(0.0, (d - 0.60) / 0.40) ** 1.6)


def grade(layer, ox=0, oy=0, dim=None, desat=DESAT):
    """给一层(左上角在画布 (ox,oy))逐像素调色。dim=None ⇒ 走背景那套位置相关的系数。"""
    rgb = layer.convert("RGB")
    a = layer.split()[3]
    rgb = ImageEnhance.Color(rgb).enhance(desat)
    px = rgb.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            f = _grade_factor(ox + x, oy + y) if dim is None else dim * (0.55 + 0.45 * _grade_factor(ox + x, oy + y) / DIM_OVERALL)
            r, g, b = px[x, y]
            px[x, y] = (min(255, int(r * f)), min(255, int(g * f)), min(255, int(b * f)))
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def _bbox_save(layer, name, entries, **extra):
    """裁到包围盒存盘 + 记下偏移。空层不存(返回 None) —— 让调用方的分母断言能看见。"""
    bb = layer.getbbox()
    if not bb:
        return None
    layer.crop(bb).save(os.path.join(OUT, name + ".png"))
    e = {"tex": RES_OUT + name + ".png", "x": bb[0], "y": bb[1], "w": bb[2] - bb[0], "h": bb[3] - bb[1]}
    e.update(extra)
    entries.append(e)
    return e


# ─────────────────────────── 底图: 灯打散 ───────────────────────────
def split_lights(bowl, rnd):
    """把顶沿那一圈【等距等亮】的灯拆出来: 删掉约三成, 余下每盏各给一个亮度, 分进 3 组(游戏里各自明暗)。
    返回 (去灯底图, [3 个灯层])。灯 = 顶沿 50 行内 lum>200 的连通块(实测核心色 251,224,129), 外扩 2px 带上光晕。"""
    W, H = bowl.size
    px = bowl.load()
    lum = lambda p: 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]
    mask = set((x, y) for y in range(0, 50) for x in range(W) if lum(px[x, y]) > 200)
    seen, blobs = set(), []
    for p in sorted(mask):
        if p in seen:
            continue
        st, comp = [p], []
        seen.add(p)
        while st:
            a = st.pop()
            comp.append(a)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q = (a[0] + dx, a[1] + dy)
                    if q in mask and q not in seen:
                        seen.add(q)
                        st.append(q)
        if len(comp) >= 4:
            blobs.append(comp)
    clean = bowl.copy()
    cpx = clean.load()
    layers = [Image.new("RGBA", (W, H)) for _ in range(3)]
    kept = 0
    for comp in blobs:
        xs = [p[0] for p in comp]
        ys = [p[1] for p in comp]
        x0, x1, y0, y1 = min(xs) - 2, max(xs) + 2, min(ys) - 2, max(ys) + 2
        bw = x1 - x0 + 1
        # 背景 = 同一行往左或往右挪开一个灯宽+2 取样(那边没灯就用那边)
        side = bw + 2 if all((x + bw + 2, y) not in mask for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)) else -(bw + 2)
        region = [(x, y) for y in range(max(0, y0), min(H, y1 + 1)) for x in range(max(0, x0), min(W, x1 + 1))]
        orig = {p: px[p] for p in region}
        for (x, y) in region:
            sx = min(W - 1, max(0, x + side))
            cpx[x, y] = px[sx, y]
        r = rnd.random()
        if r < 0.32:
            continue                       # 这盏删掉
        kept += 1
        f = rnd.choice([1.0, 1.0, 0.85, 0.7, 0.55])
        g = rnd.randrange(3)
        lp = layers[g].load()
        for (x, y) in region:
            o = orig[(x, y)]
            b = cpx[x, y]
            if o != b:
                lp[x, y] = (o[0], o[1], o[2], int(255 * f))
    return clean, layers, len(blobs), kept


# ─────────────────────────── 火苗帧 ───────────────────────────
def _is_flame(p, y):
    r, g, b, a = p
    return a > 0 and y < FLAME_ROWS and r > 170 and g > 60 and b < 120 and r - b > 90


def flame_frames(brazier):
    """火盆 → (去掉火苗的架子, [4 帧火苗])。帧是程序造的: 原样 / 尖端右摆 / 尖端左摆 / 矮一截。"""
    W, H = brazier.size
    px = brazier.load()
    stand = brazier.copy()
    spx = stand.load()
    flame = Image.new("RGBA", (W, H))
    fpx = flame.load()
    for y in range(H):
        for x in range(W):
            if _is_flame(px[x, y], y):
                fpx[x, y] = px[x, y]
                spx[x, y] = (0, 0, 0, 0)

    def sway(shifts):
        o = Image.new("RGBA", (W, H))
        op = o.load()
        for y in range(H):
            s = shifts(y)
            for x in range(W):
                p = fpx[x, y]
                if p[3] and 0 <= x + s < W:
                    op[x + s, y] = p
        return o

    f0 = flame
    f1 = sway(lambda y: 2 if y < 8 else (1 if y < 15 else 0))
    f2 = sway(lambda y: -2 if y < 8 else (-1 if y < 15 else 0))
    f3 = Image.new("RGBA", (W, H))            # 矮一截: 顶上 4 行往下压, 整体亮一点
    f3p = f3.load()
    for y in range(H):
        for x in range(W):
            p = fpx[x, y]
            if p[3] and y >= 7:
                f3p[x, y] = (min(255, p[0] + 12), min(255, p[1] + 18), p[2], p[3])
    return stand, [f0, f1, f2, f3]


def _glow_tex(r, col=(255, 150, 60)):
    """火光: 离散 4 档的圆形光晕(像素风不用平滑渐变 —— 平滑径向渐变正是用户点名的 AI 味)。"""
    d = r * 2
    im = Image.new("RGBA", (d, d))
    px = im.load()
    for y in range(d):
        for x in range(d):
            t = (((x - r + 0.5) ** 2 + (y - r + 0.5) ** 2) ** 0.5) / r
            if t < 1.0:
                level = 3 - int(t * 4)             # 3,2,1,0
                a = [10, 22, 38, 56][level]
                px[x, y] = (col[0], col[1], col[2], a)
    return im


def _recolor_plume(im):
    """防守方的红缨换成青色 —— 两只同一套设计, 不换颜色分不出是两边。"""
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a and r > 120 and g < 70 and b < 70:
                px[x, y] = (int(g * 0.6), int(r * 0.62), int(r * 0.66), a)
    return im


def build():
    rnd = random.Random(SEED)
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".png") or f.endswith(".png.import"):
            os.remove(os.path.join(OUT, f))
    bowl = Image.open(os.path.join(SRC, "arena_bowl.png")).convert("RGBA")
    ox = (bowl.width - NW) // 2                         # 400 → 390 居中裁; 下面所有 400 口径坐标都要 −ox
    bowl, light_layers, n_lamps, n_kept = split_lights(bowl, rnd)
    canvas = bowl.crop((ox, 0, ox + NW, NH))
    lay = {"native": [NW, NH], "base": None, "lights": [], "crowd": [], "front": [],
           "flames": [], "glows": [], "banner": None, "fighters": {}}

    # ── 火盆: 架子进底图, 火苗与火光单独出 ──
    braz = Image.open(os.path.join(SRC, "prop_brazier.png")).convert("RGBA")
    stand, frames = flame_frames(braz)
    for side, (bx, by, mirror) in enumerate(BRAZIERS):
        st = stand.transpose(Image.FLIP_LEFT_RIGHT) if mirror else stand
        canvas.alpha_composite(st, (bx - ox, by))
        fr_entries = []
        for k, fr in enumerate(frames):
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT) if mirror else fr
            layer = Image.new("RGBA", (NW, NH))
            layer.alpha_composite(fr, (bx - ox, by))
            layer = grade(layer, dim=1.0, desat=0.85)   # 火是光源: 不吃背景的压暗, 只轻微去饱和
            _bbox_save(layer, "flame_%d_%d" % (side, k), fr_entries)
        lay["flames"].append(fr_entries)
        bb = frames[0].getbbox()
        gx = bx - ox + ((braz.width - bb[2]) if mirror else bb[0]) + (bb[2] - bb[0]) // 2
        lay["glows"].append({"cx": gx, "cy": by + 18, "r": 30})
    _glow_tex(30).save(os.path.join(OUT, "glow.png"))

    # ── 主角脚下阴影进底图 ──
    for cx in (ATK_X, DEF_X):
        sh = Image.new("RGBA", (NW, NH))
        spx = sh.load()
        for y in range(FOOT_Y - 4, FOOT_Y + 3):
            for x in range(cx - ox - 14, cx - ox + 15):
                if ((x - (cx - ox)) / 14.0) ** 2 + ((y - (FOOT_Y - 1)) / 3.0) ** 2 <= 1.0:
                    spx[x, y] = (20, 10, 4, 110)
        canvas.alpha_composite(sh)

    _bbox_save(grade(canvas), "base", tmp := [])
    lay["base"] = tmp[0]
    for g, L in enumerate(light_layers):
        L = L.crop((ox, 0, ox + NW, NH))
        e = _bbox_save(grade(L, dim=1.0, desat=0.75), "lights_%d" % g, lay["lights"],
                       base=round(0.82 + 0.06 * g, 2), amp=0.16, period=round(2.3 + 0.9 * g, 2), phase=round(rnd.random() * 6.28, 2))

    # ── 看台观众: 每排拆两组交错, 各自蹦 ──
    far = _cells("crowd_far_24.png", 24)
    near = _cells("crowd_near_32.png", 32, min_px=120)
    n_far = n_near = 0
    for row_i, yc in enumerate(FAR_ROWS + NEAR_ROWS):
        is_near = yc in NEAR_ROWS
        sprites = near if is_near else far
        step = 15 if is_near else 12
        depth = min(1.0, (yc - 57) / 80.0)
        f = 0.55 + 0.35 * depth
        subs = [Image.new("RGBA", (NW, NH)), Image.new("RGBA", (NW, NH))]
        x = rnd.uniform(-6, step)
        k = 0
        while x < 400 + 8:
            y = _row_y(x, yc)
            skip = (y > NH + 10 or y < 44 or _in_arena(x, y) or
                    (GATE_BOX[0] - 6 < x < GATE_BOX[2] + 6 and GATE_BOX[1] - 4 < y < GATE_BOX[3] + 6) or
                    (is_near and 128 < x < 272))          # 近排别挡擂台正前方
            if not skip and rnd.random() < FILL:
                sp = rnd.choice(sprites)
                if rnd.random() < 0.5:
                    sp = sp.transpose(Image.FLIP_LEFT_RIGHT)
                # 亮度拉齐: 黄壳那几只比别的亮一截, 在暗看台上会跳成一个个亮点
                sp = _tint(sp, f * rnd.uniform(0.85, 1.05) * min(1.0, 105.0 / max(1.0, _lum(sp))))
                bb = sp.getbbox()
                subs[k % 2].alpha_composite(sp, (int(x - ox - sp.width / 2), int(y - bb[3] + rnd.randint(-1, 1))))
                k += 1
                if is_near:
                    n_near += 1
                else:
                    n_far += 1
            x += step * rnd.uniform(0.85, 1.15)
        for s, sub in enumerate(subs):
            _bbox_save(grade(sub), "crowd_%02d_%d" % (row_i, s), lay["crowd"],
                       period=round(rnd.uniform(0.9, 1.9), 2), duty=round(rnd.uniform(0.25, 0.45), 2),
                       phase=round(rnd.random(), 3))

    # ── 前景: 背对镜头一排(带长凳), 压左下/右下两角出画 ──
    back = _cells("crowd_back_32.png", 32, min_px=120)
    fronts = [Image.new("RGBA", (NW, NH)), Image.new("RGBA", (NW, NH))]
    n_back = 0
    for x0, x1 in ((-10, 120), (285, 405)):
        x = x0
        while x < x1:
            sp = rnd.choice(back)
            if rnd.random() < 0.5:
                sp = sp.transpose(Image.FLIP_LEFT_RIGHT)
            sp = _tint(sp, 0.6, (1.0, 0.82, 0.62))
            fronts[n_back % 2].alpha_composite(sp, (int(x - ox), NH - 26 + rnd.randint(-1, 2)))
            n_back += 1
            x += rnd.randint(22, 28)
    for s, fl in enumerate(fronts):
        _bbox_save(grade(fl), "front_%d" % s, lay["front"],
                   period=round(rnd.uniform(1.6, 2.4), 2), duty=0.3, phase=round(rnd.random(), 3))

    # ── 小旗 ──
    bn = Image.open(os.path.join(SRC, "banner_small.png")).convert("RGBA")
    bb = bn.getbbox()
    bx, by = BANNER_X - ox - (bb[0] + bb[2]) // 2, BANNER_TOP - bb[1]
    layer = Image.new("RGBA", (NW, NH))
    layer.alpha_composite(bn, (bx, by))
    tmp = []
    _bbox_save(grade(layer), "banner", tmp)
    lay["banner"] = tmp[0]

    # ── 两只角斗龟: 每个姿势按同一脚底线、同一中心对齐 ──
    poses = {"atk": [("stance", "fighter_atk_stance.png"), ("windup", "fighter_atk_windup.png"), ("thrust", "fighter_atk_thrust.png")],
             "def": [("guard", "fighter_def_guard.png"), ("brace", "fighter_def_brace.png")]}
    for side, lst in poses.items():
        cx = (ATK_X if side == "atk" else DEF_X) - ox
        lay["fighters"][side] = {}
        for pose, fn in lst:
            sp = _largest_blob(Image.open(os.path.join(SRC, fn)).convert("RGBA"))
            if side == "def":
                sp = _recolor_plume(sp).transpose(Image.FLIP_LEFT_RIGHT)   # 原图朝右 ⇒ 镜像成朝左对峙
            sb = sp.getbbox()
            px_ = int(cx - (sb[0] + sb[2]) / 2)
            py_ = FOOT_Y - sb[3]
            layer = Image.new("RGBA", (NW, NH))
            layer.alpha_composite(sp, (px_, py_))
            tmp = []
            _bbox_save(grade(layer, dim=FIGHTER_DIM, desat=FIGHTER_DESAT), "fighter_%s_%s" % (side, pose), tmp)
            lay["fighters"][side][pose] = tmp[0]

    # ★排布表写成 GDScript 常量, 不写 json: 导出包只带资源, res:// 下的散 json 要另配 include_filter,
    #   漏配就是"编辑器里好好的、真机上背景一片空"。常量表跟着脚本走, 不会丢。
    write_layout_gd(lay)
    counts = {"灯": "%d 盏留 %d" % (n_lamps, n_kept), "远看台": n_far, "近看台": n_near, "前景背影": n_back,
              "看台层": len(lay["crowd"]), "火苗帧": sum(len(f) for f in lay["flames"])}
    return lay, counts


def layout_gd_text(lay):
    """排布常量的 GDScript 源码。menu_arena_sync_audit 也调它来比对 —— 判据只有这一处。"""
    body = json.dumps(lay, ensure_ascii=False, indent="\t")   # 本仓缩进一律 tab
    return ("extends RefCounted\n"
            "## menu_arena_layout.gd —— 【生成文件, 别手改】由 tools/build_menu_arena_bg.py 写出。\n"
            "## 主菜单擂台背景的分层排布(原生 390x180 坐标), 读它的是 scripts/scenes/menu_arena_backdrop.gd。\n"
            "## 改排布/换素材: 改生成器重跑, 再 --import。tools/menu_arena_sync_audit.py 守着两边一致。\n\n"
            "const LAYOUT := " + body + "\n")


def write_layout_gd(lay):
    data = layout_gd_text(lay).encode("utf-8")     # 先 encode 再开文件(open(w) 先清空, encode 炸了会留 0 字节)
    with open(LAYOUT_GD, "wb") as fh:
        fh.write(data)


def preview(lay, path, scale=4, pick=None):
    """按排布表拼一张静帧(看效果用)。pick: {"atk": pose, "def": pose, "flame": k}。"""
    pick = pick or {"atk": "stance", "def": "guard", "flame": 0}
    cv = Image.new("RGBA", (NW, NH), (0, 0, 0, 255))

    def put(e):
        cv.alpha_composite(Image.open(os.path.join(OUT, os.path.basename(e["tex"]))).convert("RGBA"), (e["x"], e["y"]))

    put(lay["base"])
    for e in lay["lights"]:
        put(e)
    for e in lay["crowd"]:
        put(e)
    put(lay["banner"])
    put(lay["fighters"]["atk"][pick["atk"]])
    put(lay["fighters"]["def"][pick["def"]])
    for fl in lay["flames"]:
        put(fl[pick["flame"]])
    for e in lay["front"]:
        put(e)
    cv.convert("RGB").resize((NW * scale, NH * scale), Image.NEAREST).save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="")
    args = ap.parse_args()
    lay, counts = build()
    print("  ".join("%s %s" % kv for kv in counts.items()))
    if counts["远看台"] == 0 or counts["近看台"] == 0 or counts["前景背影"] == 0 or counts["火苗帧"] != 8:
        print("★有一层是空的 —— 几何参数把它们全跳过了")
        return 1
    print("写出 %s (%d 张) + %s" % (OUT, len([f for f in os.listdir(OUT) if f.endswith('.png')]), LAYOUT_GD))
    if args.preview:
        preview(lay, args.preview)
        print("预览 %s" % args.preview)
    print("★别忘了 --import")
    return 0


if __name__ == "__main__":
    sys.exit(main())
