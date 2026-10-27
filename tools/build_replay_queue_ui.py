# -*- coding: utf-8 -*-
"""回放操作条 + 闯关排队等待屏的专用像素素材(2026-10-27, 用户看完风格稿回「行吧」)。确定性生成, 重跑逐字节相同。

★由来: 方向稿的布局用户认了, 但样式套的是旧素材(商店卡片按钮的棕底铜边、匹配成功那一屏的卡框、程序画的纯色块),
  用户问「这个样式，你又用旧素材是吧？」。UI 美术规矩(docs/plans/20261027-UI美术规矩.md)§4.6-6:
  叠在战斗画面上的控制键照同类商业游戏做小方形图标键, 素材为这几屏专门新做。
  参考(像素游戏的回放 / 排队: Wargroove / Duelyst / TeamfightManager / Super Auto Pets / 斯普拉遁战绩卡):
  实心色键 + 粗深色描边 + 顶部高光 + 底部暗边; 退出 / 取消是红色; 进度条是深色槽 + 亮色填充; 战绩胜负格形状不同。
  全部逐像素写在这份脚本里, 0 次 PixelLab。

  输出(全是 1 倍源图; 游戏里一律 ×3 最近邻, 见 scripts/util/pixel_key.gd):
    assets/sprites/ui/replay_bar/   键底座(中性 / 红 × 常态 / 按下)、暂停 / 播放 / 退出 / x1 x2 x4 图标、
                                    进度槽(九宫格源)、已播填充、路分界菱形(已到 / 未到)、播放头
    assets/sprites/ui/queue_wait/   战绩格(胜 / 负 × 空 / 满)、阵容卡框(我 / 对手, 九宫格源)、单位槽(稀有度 7 种)、
                                    已锁定锁徽记、问号、对手剪影图集、扫描亮带、取消键里的小 X、背景
  ★取消键用的是回放条那一张红键底座(同一套键), 不另画: tools/asset_borrow_audit.py CROSS_OK 里写了理由。
  ★对手剪影 = 龟头像(assets/sprites/avatars/*.png, 游戏真内容)的轮廓阈值化成单色, 由本脚本从头像现算。

  硬边、零半透明、每张 ≤ 64 色(tools/pixel_art_audit.py 的判据; 门禁 verify_replay_queue_art 逐张量)。

  python tools/build_replay_queue_ui.py            生成全部
  python tools/build_replay_queue_ui.py --preview  另存一张 ×4 素材板到 C:/tmp(不进仓库)
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR_RB = os.path.join(ROOT, "assets", "sprites", "ui", "replay_bar")
DIR_QW = os.path.join(ROOT, "assets", "sprites", "ui", "queue_wait")
AVATAR = os.path.join(ROOT, "assets", "sprites", "avatars")
F_M6 = os.path.join(ROOT, "assets", "fonts", "m6x11.ttf")   # x1 / x2 / x4 用 m6x11 原生 16 号(1 字体像素 = 1 源像素)单色渲染

T = (0, 0, 0, 0)


def rgba(c):
    return tuple(c) + (255,) if len(c) == 3 else tuple(c)


# ═════════════════════════════════ 调色板(两屏一套) ═════════════════════════════════
INK = (7, 11, 22)                 # 最深描边
CREAM = (246, 238, 214)
CREAM_SH = (188, 168, 136)
CREAM_HI = (255, 252, 240)
NEUTRAL = {   # 中性键: 海水钢蓝(配水下战场 + 深蓝 HUD #172142 / #233967 / #2e9deb)
    "hi2": (186, 224, 248), "hi": (112, 164, 214), "face": (58, 106, 160),
    "sh": (40, 78, 124), "lip": (22, 42, 74), "face_dn": (50, 94, 144), "sh_dn": (30, 60, 100),
}
RED = {       # 红键: 退出 / 取消
    "hi2": (255, 200, 176), "hi": (250, 122, 94), "face": (204, 58, 46),
    "sh": (160, 38, 36), "lip": (98, 18, 26), "face_dn": (184, 50, 42), "sh_dn": (128, 28, 30),
}
GOLD = {"hi": (255, 238, 146), "mid": (255, 202, 58), "sh": (220, 148, 30), "dk": (96, 54, 10)}
STEEL_MARK = {"hi": (206, 222, 240), "mid": (150, 176, 206), "sh": (100, 124, 158)}
CREAM_MARK = {"hi": CREAM_HI, "mid": CREAM, "sh": CREAM_SH}   # 已到那一路: 压在金色已播段上要跳出来, 不能再用金
FRAME_ME = {   # 我方卡框: 蓝(与战斗 HUD 左侧单位卡同一色系)
    "bhi": (112, 172, 232), "bd": (48, 100, 162), "bsh": (28, 58, 104), "line": (6, 10, 20),
    "head": (24, 44, 76), "sep": (60, 106, 164), "panel": (14, 24, 42), "panel_sh": (9, 16, 30),
}
FRAME_FOE = {  # 对手空位: 紫(与战斗 HUD 右侧 / 顶栏紫血条同一色系)
    "bhi": (178, 132, 222), "bd": (104, 68, 150), "bsh": (62, 38, 96), "line": (8, 6, 16),
    "head": (40, 28, 62), "sep": (112, 78, 158), "panel": (22, 16, 34), "panel_sh": (15, 10, 24),
}
## 槽的环色 = 游戏稀有度色(RealtimeBattle3DScene._pet_rarity_color), 小将灰(dual_lane_flow 小将头像框 #8b949e)
RARITY = [("c", (154, 166, 179)), ("b", (74, 222, 128)), ("a", (96, 165, 250)), ("s", (192, 132, 252)),
          ("ss", (251, 191, 36)), ("minion", (139, 148, 158))]
SOCKET_COL = {"top": (5, 9, 18), "bot": (44, 68, 102), "in": (13, 22, 38)}
SOCKET_FOE = {"top": (8, 5, 14), "bot": (52, 38, 80), "in": (20, 14, 32)}
SIL_COL = (58, 44, 88)
## 对手剪影轮换用的龟(顺序 = 图集里的格序; scripts/scenes/queue_wait_view.gd 的 SIL_IDS 是同一张表, 门禁对账)
SIL_IDS = ["candy", "hunter", "space", "stone", "ghost", "rainbow", "hiding", "angel",
           "lightning", "ice", "crystal", "gambler", "fortune", "bamboo", "basic", "diamond"]
SIL = 18                           # 剪影格 = 单位槽内框(24 - 2×3)


# ═════════════════════════════════ 小工具 ═════════════════════════════════
def art(rows, cmap):
    h, w = len(rows), len(rows[0])
    im = Image.new("RGBA", (w, h), T)
    px = im.load()
    for y, r in enumerate(rows):
        assert len(r) == w, (rows, y)
        for x, ch in enumerate(r):
            if ch != ".":
                px[x, y] = rgba(cmap[ch])
    return im


def with_shadow(rows, ink, shadow):
    """图标 = 墨 + 正下方 1 像素落影(落影色 = 键的唇色, 白图标在亮面上立得起来)。"""
    h, w = len(rows), len(rows[0])
    im = Image.new("RGBA", (w, h + 1), T)
    px = im.load()
    for y in range(h):
        for x in range(w):
            if rows[y][x] == "#":
                px[x, y + 1] = rgba(shadow)
    for y in range(h):
        for x in range(w):
            if rows[y][x] == "#":
                px[x, y] = rgba(ink)
    return im


def pad(im, left=0, top=0, right=0, bottom=0):
    out = Image.new("RGBA", (im.width + left + right, im.height + top + bottom), T)
    out.paste(im, (left, top))
    return out


def centered_in_key(im):
    """键里的图标: 宽补成偶数、高补成奇数 —— ×3 后在 60 像素的键里居中正好落在整像素上
    (键面中心 x = 30、y = 25.5: 偶数宽 ⇒ 左缘 30 - 1.5w 是整数; 奇数高 ⇒ 上缘 25.5 - 1.5h 是整数)。
    奇数宽补在左边(播放三角往右挪 1 格, 视觉居中), 偶数高补在上边。"""
    if im.width % 2:
        im = pad(im, left=1)
    if im.height % 2 == 0:
        im = pad(im, top=1)
    return im


def m6_rows(text):
    f = ImageFont.truetype(F_M6, 16)
    m = Image.new("L", (64, 24), 0)
    d = ImageDraw.Draw(m)
    d.fontmode = "1"
    d.text((2, 2), text, font=f, fill=255)
    m = m.crop(m.getbbox())
    px = m.load()
    return ["".join("#" if px[x, y] > 127 else "." for x in range(m.width)) for y in range(m.height)]


# ═════════════════════════════════ 一、回放条 ═════════════════════════════════
KEY = 20


def key_base(pal, pressed=False):
    """实心色键 20×20: 1 像素深描边(四角各切 1 格 + 内角补 1 格 = 圆角), 顶高光行 + 左高光列 + 左上 3 颗亮点,
    右暗列, 底部 2 行厚唇(键的厚度)。按下: 整个面下沉 2 行、唇没了、高光换成上 / 左内阴影。
    九宫格边距(游戏里拉宽当取消键): 常态 左 4 上 4 右 3 下 4; 按下 左 2 上 4 右 2 下 2(pixel_key.gd 里同一组数)。"""
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


ICON_PAUSE = ["###..###"] * 10
ICON_PLAY = ["#" * n + "." * (6 - n) for n in (1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1)]
ICON_EXIT = [
    "##......##",
    "###....###",
    ".###..###.",
    "..######..",
    "...####...",
    "...####...",
    "..######..",
    ".###..###.",
    "###....###",
    "##......##",
]
ICON_EXIT_SMALL = [
    "##...##",
    "###.###",
    ".#####.",
    "..###..",
    ".#####.",
    "###.###",
    "##...##",
]

GROOVE = art([
    ".####.",
    "#dddd#",
    "#mmmm#",
    "#mmmm#",
    ".rrrr.",
], {"#": INK, "d": (12, 20, 36), "m": (30, 46, 72), "r": (78, 112, 156)})   # 九宫格: 左右各 1 列不拉伸; 底边亮缘 = 凹槽
FILL = art(["h", "m", "s"], {"h": GOLD["hi"], "m": GOLD["mid"], "s": GOLD["sh"]})   # 已播: 横向拉伸, 叠在槽的 1~3 行
DIAMOND = [
    "...#...",
    "..#H#..",
    ".#HFF#.",
    "#HFFFS#",
    ".#FFS#.",
    "..#S#..",
    "...#...",
]
PLAYHEAD = art([
    ".###.",
    "#WCC#",
    "#WCC#",
    "#WCC#",
    "#ggg#",
    "#WCS#",
    "#ggg#",
    "#WCS#",
    "#CCS#",
    "#CSS#",
    ".###.",
], {"#": INK, "W": CREAM_HI, "C": CREAM, "S": CREAM_SH, "g": CREAM_SH})


def diamond(pal):
    return art(DIAMOND, {"#": INK, "H": pal["hi"], "F": pal["mid"], "S": pal["sh"]})


# ═════════════════════════════════ 二、排队等待屏 ═════════════════════════════════
def disc_depth(n, kind):
    """n×n 圆 / 菱形: {(x,y): 深度}; 0 = 描边, 1 = 贴着描边那一圈, 2 = 里面。"""
    c = (n - 1) / 2.0
    inside = set()
    for y in range(n):
        for x in range(n):
            if kind == "circle":
                ok = (x - c) ** 2 + (y - c) ** 2 <= (c + 0.35) ** 2
            else:
                ok = abs(x - c) + abs(y - c) <= c + 0.01
            if ok:
                inside.add((x, y))
    dep = {}
    for (x, y) in sorted(inside):
        nb = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        dep[(x, y)] = 0 if any(p not in inside for p in nb) else 2
    for (x, y) in sorted(dep):
        if dep[(x, y)] == 2:
            nb = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
            if any(dep.get(p, -1) == 0 for p in nb):
                dep[(x, y)] = 1
    return dep


def record_cell(kind, filled):
    """战绩格 13×13。胜 = 圆, 负 = 菱形(形状不同, 不只靠颜色); 空 = 凹进去的暗槽, 满 = 亮面 + 记号(勾 / 叉)。"""
    n = 13
    dm = disc_depth(n, "circle" if kind == "win" else "diamond")
    im = Image.new("RGBA", (n, n), T)
    px = im.load()
    c = (n - 1) / 2.0
    pal = ({"hi": GOLD["hi"], "mid": GOLD["mid"], "sh": GOLD["sh"]} if kind == "win" else
           {"hi": RED["hi"], "mid": RED["face"], "sh": RED["sh"]})
    for (x, y), dep in sorted(dm.items()):
        if dep == 0:
            px[x, y] = rgba(INK)
            continue
        lit = (c - x) + (c - y)                     # > 0 = 左上(迎光)
        if not filled:
            col = SOCKET_COL["top"] if (dep == 1 and lit > 0.5) else (SOCKET_COL["bot"] if (dep == 1 and lit < -0.5) else SOCKET_COL["in"])
        else:
            col = pal["hi"] if (dep == 1 and lit > 0.5) else (pal["sh"] if (dep == 1 and lit < -0.5) else pal["mid"])
        px[x, y] = rgba(col)
    if filled and kind == "win":
        im.alpha_composite(art([
            "......#",
            ".....##",
            "#...##.",
            "##.##..",
            ".###...",
            "..#....",
        ], {"#": GOLD["dk"]}), (3, 4))
        px[4, 3] = rgba(CREAM_HI)
    if filled and kind == "loss":
        im.alpha_composite(art([
            "##...##",
            ".##.##.",
            "..###..",
            ".##.##.",
            "##...##",
        ], {"#": CREAM}), (3, 4))
    return im


FRAME_W, FRAME_H = 16, 30
FRAME_MARGIN = (4, 19, 4, 4)   # 左 上 右 下(queue_wait_view.gd 同一组)


def frame_src(pal):
    """卡框九宫格源 16×30: 切角 2 格; 外描边 → 2 圈边框(上左亮 / 下右暗)→ 1 圈内线 → 名牌带(13 行)→ 分隔线 → 面板。"""
    C = 2
    W, H = FRAME_W, FRAME_H
    im = Image.new("RGBA", (W, H), T)
    px = im.load()
    for y in range(H):
        for x in range(W):
            terms = [(x, "L"), (y, "T"), (W - 1 - x, "R"), (H - 1 - y, "B"),
                     (x + y - C, "T"), ((W - 1 - x) + y - C, "T"), (x + (H - 1 - y) - C, "B"),
                     ((W - 1 - x) + (H - 1 - y) - C, "B")]
            d, side = min(terms, key=lambda t: t[0])
            if d < 0:
                continue
            if d == 0:
                col = INK
            elif d == 1:
                col = pal["bhi"] if side in ("L", "T") else pal["bsh"]
            elif d == 2:
                col = pal["bd"]
            elif d == 3:
                col = pal["line"]
            elif y <= 16:
                col = pal["head"]
            elif y == 17:
                col = pal["sep"]
            elif y == 18:
                col = pal["panel_sh"]
            else:
                col = pal["panel"]
            px[x, y] = rgba(col)
    return im


def socket(ring, sc):
    """单位槽 24×24: 描边(切 1 角)→ 1 圈环色 → 凹槽(上左暗 / 下右亮)→ 槽底。"""
    n = 24
    im = Image.new("RGBA", (n, n), T)
    px = im.load()
    for y in range(n):
        for x in range(n):
            d = min(x, y, n - 1 - x, n - 1 - y, x + y - 1, (n - 1 - x) + y - 1, x + (n - 1 - y) - 1,
                    (n - 1 - x) + (n - 1 - y) - 1)
            if d < 0:
                continue
            if d == 0:
                col = INK
            elif d == 1:
                col = ring
            elif d == 2:
                col = sc["top"] if (x <= 2 or y <= 2) else sc["bot"]
            else:
                col = sc["in"]
            px[x, y] = rgba(col)
    return im


LOCK = art([
    "...#####...",
    "..#mmmmm#..",
    ".#m#####m#.",
    ".#m#...#m#.",
    ".#m#...#m#.",
    "###########",
    "#hhhhhhhhs#",
    "#hggkkkggs#",
    "#hggkkkggs#",
    "#hgggkgggs#",
    "#hgggkgggs#",
    "#sssssssss#",
    "###########",
], {"#": INK, "m": (198, 210, 224), "h": GOLD["hi"], "g": GOLD["mid"], "s": GOLD["sh"], "k": (60, 34, 8)})

QMARK = [
    ".#####.",
    "##...##",
    "##...##",
    "....##.",
    "...##..",
    "...##..",
    ".......",
    "...##..",
    "...##..",
]


def outlined(rows, col):
    """字符画 + 1 像素外描边(8 邻域)。"""
    h, w = len(rows), len(rows[0])
    im = Image.new("RGBA", (w + 2, h + 2), T)
    px = im.load()
    on = {(x + 1, y + 1) for y in range(h) for x in range(w) if rows[y][x] == "#"}
    for (x, y) in sorted(on):
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if (x + dx, y + dy) not in on:
                    px[x + dx, y + dy] = rgba(INK)
    for (x, y) in sorted(on):
        px[x, y] = rgba(col)
    return im


def silhouette(pid):
    """龟头像轮廓的单色剪影 SIL×SIL: alpha 等比缩进格子 → 阈值 50% → 一种颜色。"""
    a = Image.open(os.path.join(AVATAR, pid + ".png")).convert("RGBA")
    a = a.crop(a.getbbox())
    s = min(SIL / a.width, SIL / a.height)
    w, h = max(1, int(round(a.width * s))), max(1, int(round(a.height * s)))
    al = a.getchannel("A").resize((w, h), Image.LANCZOS).point(lambda v: 255 if v >= 128 else 0)
    out = Image.new("RGBA", (SIL, SIL), T)
    out.paste(Image.new("RGBA", (w, h), rgba(SIL_COL)), ((SIL - w) // 2, (SIL - h) // 2), al)
    return out


SCAN = art(["a", "b"], {"a": (22, 16, 34), "b": (12, 9, 18)})   # 扫描亮带: 叠加(BLEND_ADD)的两行, 光不描边(§4.3)

# ───────────── 背景: 水下氛围底纹(规则手画, 无随机数) ─────────────
## 576×324 源像素 ×3 = 1728×972: 盖得住最宽的 21:9(设计框宽约 1707)与 4:3(高 960)。游戏里底边对齐、水平居中。
BG_W, BG_H = 576, 324
BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
BANDS = [(17, 40, 60), (14, 33, 51), (11, 27, 43), (9, 21, 35), (7, 16, 28), (5, 12, 21), (3, 8, 15)]
SHAFT_ADD = (7, 15, 17)
SEABED = (2, 6, 11)
SEABED_RIM = (12, 28, 38)
WEED = (5, 22, 27)
WEED_HI = (11, 42, 45)
BUBBLE = (54, 104, 132)
BUBBLE_HI = (128, 178, 204)
SNOW = (34, 64, 84)


def hsh(*v):
    """整数散列(确定性, 不依赖 PYTHONHASHSEED)。"""
    h = 2166136261
    for x in v:
        h ^= (x & 0xFFFFFFFF)
        h = (h * 16777619) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0x5bd1e995) & 0xFFFFFFFF
    h ^= h >> 15
    return h


def background(w, h):
    im = Image.new("RGBA", (w, h), T)
    px = im.load()
    nb = len(BANDS)
    for y in range(h):                                             # ① 色带 + 交界处有序抖动
        f = y / (h - 1) * (nb - 1)
        i = int(f)
        frac = f - i
        for x in range(w):
            j = i + 1 if (i + 1 < nb and frac * 16 > BAYER4[y % 4][x % 4] + 0.5 and frac > 0.62) else i
            px[x, y] = rgba(BANDS[min(j, nb - 1)])
    for sx, sw in [(0.16, 13), (0.44, 21), (0.71, 9), (0.86, 15)]:   # ② 光柱: 从水面斜下, 越深越淡(加亮, 不描边)
        for y in range(int(h * 0.72)):
            inten = 1.0 - y / (h * 0.72)
            cx = sx * w + y * 0.38
            for x in range(int(cx - sw / 2) - 2, int(cx + sw / 2) + 3):
                if x < 0 or x >= w:
                    continue
                edge = 1.0 - min(1.0, abs(x - cx) / (sw / 2 + 1.5))
                v = inten * (0.35 + 0.65 * edge) * 0.85
                if v * 16 > BAYER4[y % 4][x % 4] + 0.5:
                    r, g, b, _ = px[x, y]
                    px[x, y] = rgba((min(255, r + SHAFT_ADD[0]), min(255, g + SHAFT_ADD[1]), min(255, b + SHAFT_ADD[2])))
    floor = []                                                     # ③ 海底礁石剪影 + 一道浅色顶缘
    for x in range(w):
        y0 = h - 10 - 4 * math.sin(x / 23.0) - 3 * math.sin(x / 9.0 + 1.3) - 5 * max(0.0, math.sin(x / 61.0 + 0.6))
        floor.append(int(round(y0)))
    for x in range(w):
        for y in range(max(0, floor[x]), h):
            px[x, y] = rgba(SEABED_RIM if y == floor[x] else SEABED)
    for i in range(14):                                            # ④ 两侧海草(左右各 16%, 不进中间内容区)
        side = i % 2
        xr = (hsh(i, 7) % 1000) / 1000.0
        x0 = int((0.01 + 0.15 * xr) * w) if side == 0 else int((0.84 + 0.15 * xr) * w)
        hh = 22 + hsh(i, 11) % 34
        ph = (hsh(i, 13) % 628) / 100.0
        base = floor[min(w - 1, max(0, x0))] + 1
        for k in range(hh):
            y = base - k
            if y < 0:
                break
            sway = int(round(2.2 * math.sin(k / 6.0 + ph) * (k / hh)))
            bw = 3 if k < hh * 0.45 else (2 if k < hh * 0.8 else 1)   # 草叶由根到梢 3 → 2 → 1 像素
            for dx in range(bw):
                x = x0 + sway + dx
                if 0 <= x < w:
                    px[x, y] = rgba(WEED_HI if (dx == 0 and bw > 1) else WEED)
    for gy in range(0, h, 9):                                      # ⑤ 气泡与悬浮颗粒: 规则网格上散列取位
        for gx in range(0, w, 9):
            hv = hsh(gx, gy, 3)
            if hv % 23 == 0:
                x, y = gx + hv % 7, gy + (hv >> 4) % 7
                if 0 <= x < w and 0 <= y < h - 16:
                    px[x, y] = rgba(SNOW)
            if hv % 61 == 1:
                x, y = gx + (hv >> 8) % 6, gy + (hv >> 12) % 6
                kind = (hv >> 16) % 3
                if y < h - 20:
                    if kind == 0:
                        for (dx, dy) in ((0, 0), (1, 0), (0, 1), (1, 1)):
                            if 0 <= x + dx < w and 0 <= y + dy < h:
                                px[x + dx, y + dy] = rgba(BUBBLE)
                        if 0 <= x < w:
                            px[x, y] = rgba(BUBBLE_HI)
                    else:
                        n = 3 if kind == 1 else 5
                        for dy in range(n):
                            for dx in range(n):
                                edge = dx in (0, n - 1) or dy in (0, n - 1)
                                corner = dx in (0, n - 1) and dy in (0, n - 1)
                                if edge and not corner and 0 <= x + dx < w and 0 <= y + dy < h:
                                    px[x + dx, y + dy] = rgba(BUBBLE)
                        if 0 <= x + 1 < w and 0 <= y + 1 < h:
                            px[x + 1, y + 1] = rgba(BUBBLE_HI)
    return im


# ═════════════════════════════════ 出图表 ═════════════════════════════════
def sil_atlas():
    out = Image.new("RGBA", (SIL * len(SIL_IDS), SIL), T)
    for i, pid in enumerate(SIL_IDS):
        out.alpha_composite(silhouette(pid), (i * SIL, 0))
    return out


def outputs():
    """(目录, 文件名, 图)。文件名只用 ASCII。"""
    o = [
        (DIR_RB, "key-neutral.png", key_base(NEUTRAL)),
        (DIR_RB, "key-neutral-down.png", key_base(NEUTRAL, True)),
        (DIR_RB, "key-red.png", key_base(RED)),
        (DIR_RB, "key-red-down.png", key_base(RED, True)),
        (DIR_RB, "icon-pause.png", centered_in_key(with_shadow(ICON_PAUSE, CREAM, NEUTRAL["lip"]))),
        (DIR_RB, "icon-play.png", centered_in_key(pad(with_shadow(ICON_PLAY, CREAM, NEUTRAL["lip"]), left=1))),
        (DIR_RB, "icon-exit.png", centered_in_key(with_shadow(ICON_EXIT, CREAM, RED["lip"]))),
    ]
    for s in ("x1", "x2", "x4"):
        o.append((DIR_RB, "icon-%s.png" % s, centered_in_key(with_shadow(m6_rows(s), CREAM, NEUTRAL["lip"]))))
    o += [
        (DIR_RB, "groove.png", GROOVE),
        (DIR_RB, "fill.png", FILL),
        (DIR_RB, "mark-reached.png", diamond(CREAM_MARK)),
        (DIR_RB, "mark-next.png", diamond(STEEL_MARK)),
        (DIR_RB, "playhead.png", PLAYHEAD),
        (DIR_QW, "cell-win.png", record_cell("win", False)),
        (DIR_QW, "cell-win-on.png", record_cell("win", True)),
        (DIR_QW, "cell-loss.png", record_cell("loss", False)),
        (DIR_QW, "cell-loss-on.png", record_cell("loss", True)),
        (DIR_QW, "frame-me.png", frame_src(FRAME_ME)),
        (DIR_QW, "frame-foe.png", frame_src(FRAME_FOE)),
    ]
    for r, col in RARITY:
        o.append((DIR_QW, "socket-%s.png" % r, socket(col, SOCKET_COL)))
    o += [
        (DIR_QW, "socket-foe.png", socket((84, 62, 120), SOCKET_FOE)),
        (DIR_QW, "lock.png", LOCK),
        (DIR_QW, "qmark.png", outlined(QMARK, (190, 172, 230))),
        (DIR_QW, "sil-atlas.png", sil_atlas()),
        (DIR_QW, "scan.png", SCAN),
        (DIR_QW, "icon-cancel-x.png", with_shadow(ICON_EXIT_SMALL, CREAM, RED["lip"])),
        (DIR_QW, "bg.png", background(BG_W, BG_H)),
    ]
    return o


def main():
    os.makedirs(DIR_RB, exist_ok=True)
    os.makedirs(DIR_QW, exist_ok=True)
    outs = outputs()
    for d, name, im in outs:
        im.save(os.path.join(d, name), optimize=False)
        print("  %-12s %-22s %dx%d" % (os.path.basename(d), name, im.width, im.height))
    if "--preview" in sys.argv:
        K = 4
        W = 2200
        x, y, rowh = 10, 10, 0
        pos = []
        for d, name, im in outs:
            w, h = im.width * K, im.height * K
            if x + w > W - 10:
                x, y, rowh = 10, y + rowh + 10, 0
            pos.append((im, x, y))
            x += w + 10
            rowh = max(rowh, h)
        pv = Image.new("RGBA", (W, y + rowh + 10), (92, 98, 112, 255))
        for im, x, y in pos:
            pv.alpha_composite(im.resize((im.width * K, im.height * K), Image.NEAREST), (x, y))
        pv.save("C:/tmp/replay_queue_ui_preview.png")
        print("  预览 C:/tmp/replay_queue_ui_preview.png")
    print("ALL OK  %d 张" % len(outs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
