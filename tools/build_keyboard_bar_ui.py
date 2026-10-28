# -*- coding: utf-8 -*-
"""手机打字输入条(键盘弹起时贴在键盘正上方的整宽输入条)的专用像素素材(2026-10-28)。确定性生成, 重跑逐字节相同。

★由来: 10-27 用户「手机打字很难受」; 10-28 用户认可方向稿(键盘正上方整宽输入条、条里字放大约 2 倍、
  右边清空 / 完成、原界面不挪, 四处输入统一换成这一种; 条上按钮新画)。方向稿里底板 / 输入槽 / 清空 × / 类型小签
  都是纯色块占位, 条里两颗键借的是 card_button 配色 —— 这份脚本把它们全部换成新画的。
  风格与回放条 / 排队屏同一家族(tools/build_replay_queue_ui.py, 10-27 用户「行吧」): 实心色 + 粗深色描边 +
  顶部高光 + 底部暗边, 硬边; INK / CREAM / GOLD 与它同值; 键底座的画法照搬它的 key_base(几何必须一致, 见下)。
  全部逐像素写在这份脚本里, 0 次 PixelLab。

  输出(全是 1 倍源图; 游戏里一律 ×3 最近邻, 见 scripts/util/pixel_key.gd)→ assets/sprites/ui/keyboard_bar/:
    bar.png               输入条底板   九宫格源 16×16, 边距 左4 上4 右4 下2: 顶沿深描边 + 亮线 + 斜面, 主体深海军蓝,
                                       下沿两行压暗贴键盘(无描边)。整宽铺, 显示高 96~168
    slot.png              输入槽(凹)   九宫格源 16×16, 边距四边各 4: 描边 → 上左深影 / 下右亮缘 → 槽底(很深)
    slot-focus.png        输入槽·聚焦  同上, 内圈换成金边(与底板的蓝亮线、与青绿小签都分得开)
    icon-clear.png        清空 ×       11×11(奇数: ×3 后 33px 在槽里居中落整像素), 圆形石板深底 + 奶油色 ×
    key-gold(-down).png   主键底座     20×20 暖金(完成 / 提交 / 查找)
    key-steel(-down).png  副键底座     20×20 石板灰蓝(换一个 / 收起 / 粘贴)
                                       ★两套键的几何 = replay_bar/key-neutral(-down).png 同一套(同尺寸、同九宫格边距:
                                         常态 左4 上4 右3 下4; 按下 左2 上4 右2 下2, 面下沉 2 源像素), 因为代码直接
                                         PixelKey.skin(b, up, down, content_lr, bottom) 套皮; 本脚本出图后逐像素对账。
    tag.png               反馈类型小签 九宫格源 12×12, 边距四边各 3, 青绿(闪退 / 卡顿 …)
  ★键与小签上的字由代码用游戏字体渲染, 素材里不带字。
  ★九宫格会被拉伸的部分(中间一块 + 四条边带)一律沿拉伸方向逐行 / 逐列同色, 拉多宽多高都不出非整数倍花纹;
    本脚本出图后逐张核对。

  建议文字色(给代码用): 槽内字 #e8f0ff / 槽内提示字 #6c80a6 / 条上说明字 #a8c0e4 /
    主键字 #2e1a06(深棕, 不描边) / 副键字 #f6eed6(奶油) / 小签字 #effffa。

  硬边、零半透明(alpha 只有 0 / 255)、每张 ≤ 64 色(tools/pixel_art_audit.py 的判据; 本脚本出图后自查)。

  python tools/build_keyboard_bar_ui.py            生成全部
  python tools/build_keyboard_bar_ui.py --preview  另存一张 ×4 示意板到 C:/tmp/keyboard_bar_preview.png(不进仓库)
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR_KB = os.path.join(ROOT, "assets", "sprites", "ui", "keyboard_bar")
DIR_RB = os.path.join(ROOT, "assets", "sprites", "ui", "replay_bar")   # 只读: 键几何对账用
F_SC = os.path.join(ROOT, "assets", "fonts", "NotoSansSC-Regular.otf")  # 只给预览板摆示意文字

T = (0, 0, 0, 0)


def rgba(c):
    return tuple(c) + (255,) if len(c) == 3 else tuple(c)


# ═════════════════════════════════ 调色板 ═════════════════════════════════
INK = (7, 11, 22)                 # 最深描边(与回放条同值)
CREAM = (246, 238, 214)
GOLD = {"hi": (255, 238, 146), "mid": (255, 202, 58), "sh": (220, 148, 30)}   # 与回放条 GOLD 同值
## 输入条底板: 深海军蓝, 与战斗 HUD 深蓝 #172142 / #233967 同族、略提亮一档, 压暗的界面在它上方分得开
BAR = {"hi": (122, 170, 222), "bevel": (62, 92, 142), "body": (36, 56, 98), "sh": (26, 41, 74), "base": (16, 26, 48)}
## 输入槽: 凹进去 —— 上左墙背光(深), 下右墙迎光(亮缘); 槽底很深, 让 #e8f0ff 的字最清楚
SLOT = {"tl": (3, 6, 14), "br": (54, 80, 122), "tl2": (8, 13, 27), "in": (12, 19, 37)}
SLOT_FOCUS = dict(SLOT, tl=GOLD["mid"], br=GOLD["hi"])   # 聚焦: 只换贴着描边那一圈, 槽底不变(字不受影响)
CLEAR = {"hi": (98, 122, 160), "face": (56, 74, 108), "sh": (36, 50, 78), "x_sh": (20, 28, 46)}
## 主键: 暖金(字用深棕); 副键: 石板灰蓝(比回放条 NEUTRAL 的海水钢蓝灰、比底板亮, 两边都分得开)
KEY_GOLD = {
    "hi2": (255, 248, 206), "hi": (255, 226, 122), "face": (240, 180, 48),
    "sh": (200, 130, 28), "lip": (126, 70, 14), "face_dn": (222, 162, 40), "sh_dn": (170, 106, 22),
}
KEY_STEEL = {
    "hi2": (214, 222, 234), "hi": (150, 164, 188), "face": (92, 106, 132),
    "sh": (70, 82, 104), "lip": (40, 48, 66), "face_dn": (84, 97, 121), "sh_dn": (60, 71, 92),
}
TAG = {"hi": (92, 200, 184), "face": (28, 118, 114), "sh": (18, 84, 88)}

## 建议文字色(预览板按这组摆字; 回报给代码那边)
TXT = {"slot": (232, 240, 255), "hint": (108, 128, 166), "bar": (168, 192, 228),
       "key_gold": (46, 26, 6), "key_steel": CREAM, "tag": (239, 255, 250)}


# ═════════════════════════════════ 画法 ═════════════════════════════════
def bar_src():
    """输入条底板 16×16: 只有竖向的剖面(每一行整行同色), 横向怎么拉都一样 —— 整宽铺在键盘上方, 左右两端就是屏幕边。
    第 0 行深描边 → 第 1 行亮线 → 第 2 行斜面 → 主体 → 最后两行压暗贴键盘(不描边)。九宫格边距 左4 上4 右4 下2。"""
    rows = [INK, BAR["hi"], BAR["bevel"]] + [BAR["body"]] * 11 + [BAR["sh"], BAR["base"]]
    im = Image.new("RGBA", (16, len(rows)), T)
    px = im.load()
    for y, c in enumerate(rows):
        for x in range(16):
            px[x, y] = rgba(c)
    return im


def rounded_box(w, h, ring):
    """圆角盒(与键底座同一种圆角: 四角各切 1 格 + 内角补 1 格描边)。ring(d, x, y) → 颜色, d = 离最近一条边的格数。"""
    im = Image.new("RGBA", (w, h), T)
    px = im.load()
    for y in range(h):
        for x in range(w):
            if x in (0, w - 1) and y in (0, h - 1):
                continue
            d = min(x, y, w - 1 - x, h - 1 - y)
            if d == 0 or (x in (1, w - 2) and y in (1, h - 2)):
                px[x, y] = rgba(INK)
                continue
            px[x, y] = rgba(ring(d, x, y))
    return im


def slot_src(pal):
    """输入槽 16×16(九宫格边距四边各 4): 描边 → 贴边一圈(上 / 左 = tl, 下 / 右 = br)→ 第二圈上左再压一道暗 → 槽底。"""
    n = 16

    def ring(d, x, y):
        if d == 1:
            return pal["tl"] if (x == 1 or y == 1) else pal["br"]
        if d == 2:
            return pal["tl2"] if (x == 2 or y == 2) else pal["in"]
        return pal["in"]
    return rounded_box(n, n, ring)


def tag_src():
    """类型小签 12×12(九宫格边距四边各 3): 描边 → 上 / 左高光、下 / 右暗边 → 面。"""
    n = 12

    def ring(d, x, y):
        if d == 1:
            return TAG["hi"] if (x == 1 or y == 1) else TAG["sh"]
        return TAG["face"]
    return rounded_box(n, n, ring)


KEY = 20


def key_base(pal, pressed=False):
    """(照搬 tools/build_replay_queue_ui.key_base, 一个判断都没改 —— 几何必须与 key-neutral 同一套。)
    实心色键 20×20: 1 像素深描边(四角各切 1 格 + 内角补 1 格 = 圆角), 顶高光行 + 左高光列 + 左上 3 颗亮点,
    右暗列, 底部 2 行厚唇(键的厚度)。按下: 整个面下沉 2 行、唇没了、高光换成上 / 左内阴影。
    九宫格边距: 常态 左 4 上 4 右 3 下 4; 按下 左 2 上 4 右 2 下 2(pixel_key.gd 里同一组数)。"""
    w = h = KEY
    im = Image.new("RGBA", (w, h), T)
    px = im.load()
    top = 2 if pressed else 0
    bot = h - 1
    for y in range(top, bot + 1):
        for x in range(w):
            if x in (0, w - 1) and y in (top, bot):
                continue
            if x in (0, w - 1) or y in (top, bot) or (x in (1, w - 2) and y in (top + 1, bot - 1)):
                px[x, y] = rgba(INK)
                continue
            if not pressed:
                if y >= bot - 2:
                    c = pal["lip"]
                elif y == bot - 3:
                    c = pal["sh"]
                elif y == top + 1 or x == 1:
                    c = pal["hi"]
                elif x == w - 2:
                    c = pal["sh"]
                else:
                    c = pal["face"]
            else:
                c = pal["sh_dn"] if (y == top + 1 or x == 1) else pal["face_dn"]
            px[x, y] = rgba(c)
    if not pressed:
        for (x, y) in ((2, 2), (3, 2), (2, 3)):
            px[x, y] = rgba(pal["hi2"])
    return im


CIRCLE11 = [
    "...#####...",
    ".##ooooo##.",
    ".#ooooooo#.",
    "#ooooooooo#",
    "#ooooooooo#",
    "#ooooooooo#",
    "#ooooooooo#",
    "#ooooooooo#",
    ".#ooooooo#.",
    ".##ooooo##.",
    "...#####...",
]
X5 = [
    "#...#",
    ".#.#.",
    "..#..",
    ".#.#.",
    "#...#",
]


def icon_clear():
    """清空 × 11×11: 圆形深描边 → 贴边一圈左上亮 / 右下暗 → 石板深面; 中间奶油色 ×(5×5, 正下方 1 像素落影)。"""
    n = len(CIRCLE11)
    c = (n - 1) / 2.0
    im = Image.new("RGBA", (n, n), T)
    px = im.load()
    inside = {(x, y) for y in range(n) for x in range(n) if CIRCLE11[y][x] == "o"}
    for y in range(n):
        for x in range(n):
            ch = CIRCLE11[y][x]
            if ch == "#":
                px[x, y] = rgba(INK)
            elif ch == "o":
                edge = any(p not in inside for p in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
                lit = (c - x) + (c - y)
                col = CLEAR["face"]
                if edge and lit > 0.5:
                    col = CLEAR["hi"]
                elif edge and lit < -0.5:
                    col = CLEAR["sh"]
                px[x, y] = rgba(col)
    o = (n - len(X5)) // 2
    for y, r in enumerate(X5):
        for x, ch in enumerate(r):
            if ch == "#":
                px[o + x, o + y + 1] = rgba(CLEAR["x_sh"])
    for y, r in enumerate(X5):
        for x, ch in enumerate(r):
            if ch == "#":
                px[o + x, o + y] = rgba(CREAM)
    return im


# ═════════════════════════════════ 出图表 ═════════════════════════════════
## (文件名, 图, 九宫格边距 左 上 右 下 或 None)。文件名只用 ASCII。
M_UP = (4, 4, 3, 4)
M_DN = (2, 4, 2, 2)


def outputs():
    return [
        ("bar.png", bar_src(), (4, 4, 4, 2)),
        ("slot.png", slot_src(SLOT), (4, 4, 4, 4)),
        ("slot-focus.png", slot_src(SLOT_FOCUS), (4, 4, 4, 4)),
        ("icon-clear.png", icon_clear(), None),
        ("key-gold.png", key_base(KEY_GOLD), M_UP),
        ("key-gold-down.png", key_base(KEY_GOLD, True), M_DN),
        ("key-steel.png", key_base(KEY_STEEL), M_UP),
        ("key-steel-down.png", key_base(KEY_STEEL, True), M_DN),
        ("tag.png", tag_src(), (3, 3, 3, 3)),
    ]


# ═════════════════════════════════ 自查 ═════════════════════════════════
def check(outs):
    """出图后自查, 任何一条不过就不写盘: ①alpha 只有 0 / 255 ②≤ 64 色 ③九宫格拉伸区逐行 / 逐列同色
    ④四张键与 replay_bar/key-neutral(-down) 透明遮罩相同、颜色角色一一对应(只换配色、不换几何)。"""
    errs = []
    for name, im, m in outs:
        px = im.load()
        al = {px[x, y][3] for y in range(im.height) for x in range(im.width)}
        if not al <= {0, 255}:
            errs.append("%s 有半透明 alpha %s" % (name, sorted(al - {0, 255})))
        cols = {px[x, y][:3] for y in range(im.height) for x in range(im.width) if px[x, y][3]}
        if len(cols) > 64:
            errs.append("%s %d 色 > 64" % (name, len(cols)))
        if m:
            l, t, r, b = m
            xs, ys = range(l, im.width - r), range(t, im.height - b)
            for y in range(im.height):            # 横向拉伸的列段(上下边带 + 中间): 每行在 xs 里同色
                if len({px[x, y] for x in xs}) > 1:
                    errs.append("%s 第 %d 行在横向拉伸区里不同色" % (name, y))
            for x in range(im.width):             # 竖向拉伸的行段(左右边带 + 中间): 每列在 ys 里同色
                if len({px[x, y] for y in ys}) > 1:
                    errs.append("%s 第 %d 列在竖向拉伸区里不同色" % (name, x))
    by = {n: im for n, im, _ in outs}
    pairs = [("key-gold.png", "key-neutral.png"), ("key-steel.png", "key-neutral.png"),
             ("key-gold-down.png", "key-neutral-down.png"), ("key-steel-down.png", "key-neutral-down.png")]
    n_ref = 0
    for mine, ref in pairs:
        rp = os.path.join(DIR_RB, ref)
        if not os.path.exists(rp):
            errs.append("对账用的 %s 不在" % rp)
            continue
        a, b = by[mine].load(), Image.open(rp).convert("RGBA")
        if b.size != by[mine].size:
            errs.append("%s 尺寸 %s ≠ %s %s" % (mine, by[mine].size, ref, b.size))
            continue
        bp = b.load()
        fwd, back = {}, {}
        for y in range(b.height):
            for x in range(b.width):
                p, q = a[x, y], bp[x, y]
                if (p[3] == 0) != (q[3] == 0):
                    errs.append("%s (%d,%d) 透明与 %s 不一致" % (mine, x, y, ref))
                    continue
                if q[3] == 0:
                    continue
                if fwd.setdefault(q[:3], p[:3]) != p[:3] or back.setdefault(p[:3], q[:3]) != q[:3]:
                    errs.append("%s (%d,%d) 颜色角色与 %s 不是一一对应" % (mine, x, y, ref))
        n_ref += 1
    if n_ref != len(pairs):
        errs.append("键几何只对上了 %d / %d 张" % (n_ref, len(pairs)))
    return errs


# ═════════════════════════════════ 预览板(不进仓库) ═════════════════════════════════
def nine(src, w, h, m):
    """1 倍源图按九宫格拉成 w×h(源像素单位, 最近邻) —— 与 StyleBoxTexture 的拉伸同一种切法。"""
    l, t, r, b = m
    sw, sh = src.size
    out = Image.new("RGBA", (w, h), T)
    xs = [(0, l, 0, l), (l, sw - r, l, w - r), (sw - r, sw, w - r, w)]
    ys = [(0, t, 0, t), (t, sh - b, t, h - b), (sh - b, sh, h - b, h)]
    for sx0, sx1, dx0, dx1 in xs:
        for sy0, sy1, dy0, dy1 in ys:
            if sx1 <= sx0 or sy1 <= sy0 or dx1 <= dx0 or dy1 <= dy0:
                continue
            out.alpha_composite(src.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.NEAREST), (dx0, dy0))
    return out


def preview(outs, path):
    K = 4
    by = {n: (im, m) for n, im, m in outs}
    f43 = ImageFont.truetype(F_SC, 43)      # 32 号字(条里正文)在 ×4 预览上 = 32 × 4/3
    f40 = ImageFont.truetype(F_SC, 40)      # 键字 30 号
    f29 = ImageFont.truetype(F_SC, 29)      # 22 号(说明字 / 小签)
    f22 = ImageFont.truetype(F_SC, 22)
    W = 520                                 # 1560 设计宽 ÷ 3

    def put(canvas, name, x, y, w=None, h=None):
        im, m = by[name]
        canvas.alpha_composite(nine(im, w, h, m) if w else im, (x, y))

    def scene(bar_h, kb_col, keys_down, multiline):
        top = 10
        cv = Image.new("RGBA", (W, top + bar_h + 16), rgba(kb_col))
        d = ImageDraw.Draw(cv)
        d.rectangle((0, 0, W - 1, top - 1), fill=rgba((13, 17, 29)))          # 上方被压暗的原界面
        d.rectangle((150, 0, 370, top - 1), fill=rgba((24, 30, 52)))
        put(cv, "bar.png", 0, top, W, bar_h)
        kh = 27                                                               # 键 / 单行槽 81 高 = 27 源像素
        ky = top + bar_h - 1 - kh
        suf = "-down.png" if keys_down else ".png"
        put(cv, "key-steel" + suf, 389, ky, 47, kh)
        put(cv, "key-gold" + suf, 441, ky, 47, kh)
        if multiline:
            put(cv, "tag.png", 33, top + 3, 50, 10)
            sy = top + 14
            sh = bar_h - 14 - 1
            put(cv, "slot.png", 33, sy, 350, sh)
        else:
            sy, sh = ky, kh
            put(cv, "slot-focus.png", 33, sy, 350, sh)
            cv.alpha_composite(by["icon-clear.png"][0], (383 - 4 - 11 - 2, sy + (sh - 11) // 2))
        big = cv.resize((cv.width * K, cv.height * K), Image.NEAREST)
        dd = ImageDraw.Draw(big)
        X = lambda v: int(v * K)
        if multiline:
            dd.text((X(33 + 25), X(top + 3 + 5)), "闪退 / 卡顿", font=f29, fill=rgba(TXT["tag"]), anchor="mm",
                    stroke_width=2, stroke_fill=rgba(TAG["sh"]))
            dd.text((X(90), X(top + 8)), "问题描述", font=f29, fill=rgba(TXT["bar"]), anchor="lm")
            dd.text((X(380), X(top + 8)), "41 / 500", font=f29, fill=rgba(TXT["bar"]), anchor="rm")
            f37 = ImageFont.truetype(F_SC, 37)                                # 多行 28 号(方向稿 B)
            for i, s in enumerate(["第三局打到一半闪退了，回到游戏后", "这一局的记录没有了。", "机型 iPhone 13，系统 iOS 18"]):
                dd.text((X(40), X(sy) + 18 + i * 46), s, font=f37, fill=rgba(TXT["slot"]))
        else:
            dd.text((X(40), X(sy + sh / 2)), "芝士奶盖", font=f43, fill=rgba(TXT["slot"]), anchor="lm")
            dd.text((X(150), X(sy + sh / 2)), "（未输入时的提示字）", font=f29, fill=rgba(TXT["hint"]), anchor="lm")
            dd.text((X(362), X(sy + sh / 2)), "4 / 8", font=f29, fill=rgba(TXT["hint"]), anchor="rm")
        cy = (ky + 4 + (kh - 4 - 3) / 2) if keys_down else (ky + (kh - 3) / 2)
        lab = ("收起", "提交") if multiline else ("换一个", "完成")
        dd.text((X(389 + 23.5), X(cy)), lab[0], font=f40, fill=rgba(TXT["key_steel"]), anchor="mm",
                stroke_width=2, stroke_fill=rgba(KEY_STEEL["lip"]))
        dd.text((X(441 + 23.5), X(cy)), lab[1], font=f40, fill=rgba(TXT["key_gold"]), anchor="mm")
        return big

    shots = [
        ("单行 · 起名(槽聚焦; 键常态) —— 条 96 高, 浅色系统键盘", scene(32, (206, 210, 218), False, False)),
        ("多行 · 反馈(槽未聚焦; 键按下) —— 条 168 高, 深色系统键盘", scene(56, (44, 44, 48), True, True)),
    ]
    S = 6                                   # 原图条: 每张 ×6 便于看像素
    raw = [(n, im) for n, im, _ in outs]
    raw_w = sum(im.width * S + 24 for _, im in raw) + 24
    raw_h = max(im.height for _, im in raw) * S + 40
    PW = max(raw_w, W * K) + 40
    PH = 20 + sum(b.height + 44 for _, b in shots) + raw_h + 60
    pv = Image.new("RGBA", (PW, PH), (92, 98, 112, 255))
    d = ImageDraw.Draw(pv)
    y = 20
    for cap, b in shots:
        d.text((20, y), cap, font=f22, fill=(240, 240, 240, 255))
        pv.alpha_composite(b, (20, y + 30))
        y += b.height + 44
    d.text((20, y), "1 倍源图 ×%d(依次: %s)" % (S, " / ".join(n for n, _ in raw)), font=f22, fill=(240, 240, 240, 255))
    x = 20
    for n, im in raw:
        pv.alpha_composite(im.resize((im.width * S, im.height * S), Image.NEAREST), (x, y + 34))
        x += im.width * S + 24
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pv.save(path)
    print("  预览 %s (%dx%d)" % (path, pv.width, pv.height))


def main():
    outs = outputs()
    errs = check(outs)
    if errs:
        for e in errs:
            print("[FAIL] " + e)
        return 1
    os.makedirs(DIR_KB, exist_ok=True)
    for name, im, m in outs:
        im.save(os.path.join(DIR_KB, name), optimize=False)
        print("  %-20s %dx%d  九宫格 %s" % (name, im.width, im.height, "左%d 上%d 右%d 下%d" % m if m else "-"))
    if "--preview" in sys.argv:
        preview(outs, "C:/tmp/keyboard_bar_preview.png")
    print("ALL OK  %d 张(自查: 零半透 / ≤64 色 / 拉伸区同色 / 键几何 = key-neutral)" % len(outs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
