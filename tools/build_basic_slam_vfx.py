# -*- coding: utf-8 -*-
"""build_basic_slam_vfx.py — 小龟·过肩摔【落地】专用逐帧像素素材(2026-10-24 重做)。

由来: 用户 10-24 看完第一版落地追问「为什么搞公用？」「全部是不是动画？」「你整个敷衍我有意思吗」——
  第一版落地只有一张新画的静态裂纹, 伤害圈 / 尘环用公用 skill-ring, 尘爆是共用静图, 碎屑是程序金色方片。
  ⇒ 这里画过肩摔专用的 5 套逐帧素材(地面裂纹那张是 PixelLab 出的 basic-slam-crack.png, 本脚本把它做成裂开 / 碎散的逐帧)。
参考: LoL 瑟提 R 落地(YouTube Jc8njGBO71U 慢放, 逐帧研究见 docs/studies/20261024b-过肩摔落地逐帧.md):
  砸中帧 = 陷坑 + 中心光柱 → 坑沿往上溅一圈尖刺爆冠 → 贴地细环外扩 + 石块抛出 + 低尘沿地面外卷 → 龟裂地面久留。

画风与项目其它砸地素材同一路(twohead-quake-* / bear-quake-erupt): 硬边像素 + 深色描边 + 锁定调色板, 逐帧(不靠缩放)。
★全部确定性(没有随机数): 噪声用整数哈希, 重跑逐字节相同。

跑法:  python tools/build_basic_slam_vfx.py            # 写进 assets/sprites/vfx/
       python tools/build_basic_slam_vfx.py --preview C:/tmp/x.png   # 另出一张放大预览
"""
import argparse
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx")

# ── 锁定调色板(沙土地面: 与竞技场地砖同一族暖棕) ──
OUTL = (42, 29, 18, 255)       # 描边
DARK = (91, 61, 34, 255)       # 暗土
MID = (138, 98, 54, 255)       # 中土
LITE = (196, 154, 92, 255)     # 亮土
HIL = (232, 207, 154, 255)     # 高光
DUST_O = (90, 74, 56, 255)     # 尘团描边
DUST_D = (166, 140, 104, 255)  # 尘暗面(偏土色: 第一版太白, 实拍像天上的云)
DUST_M = (196, 172, 132, 255)  # 尘
DUST_L = (222, 204, 166, 255)  # 尘亮面
FLASH_W = (255, 250, 232, 255)
FLASH_Y = (255, 222, 120, 255)
FLASH_O = (240, 160, 60, 255)
CLEAR = (0, 0, 0, 0)


def h2(x, y, s=0):
    """整数哈希 → [0,1)。确定性噪声。"""
    n = (x * 374761393 + y * 668265263 + s * 2147483647) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return (n & 0xFFFF) / 65536.0


def outline(img, col=OUTL):
    """给不透明区域外沿描 1 像素边(4 邻接)。"""
    w, h = img.size
    px = img.load()
    add = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] != 0 and px[nx, ny] != col:
                    add.append((x, y))
                    break
    for x, y in add:
        px[x, y] = col
    return img


def sheet(frames):
    w, h = frames[0].size
    s = Image.new("RGBA", (w * len(frames), h), CLEAR)
    for i, f in enumerate(frames):
        s.paste(f, (i * w, 0))
    return s


# ═══════════════════════ ① 贴地冲击环(俯视, 躺平贴地) ═══════════════════════
# 128×128 一格 × 8 帧。末帧外沿半径 = RING_LAST_R 像素 —— 代码按它换算 pixel_size, 外沿 = 伤害半径(350 码)。
RING_CELL = 128
RING_LAST_R = 62.0
RING_FRAMES = 8


def ring_frames():
    out = []
    for k in range(RING_FRAMES):
        t = k / (RING_FRAMES - 1)
        r_out = 10.0 + (RING_LAST_R - 10.0) * (1.0 - (1.0 - t) ** 2.2)   # 先快后慢: 冲击波
        band = 5.0 - 2.5 * t                                              # 细环(第一版 12→5 太粗, 实拍像一整块米白甜甜圈盖住人)
        fade = 0.0 if k < 6 else (k - 5) / 2.6                            # 末两帧碎散
        img = Image.new("RGBA", (RING_CELL, RING_CELL), CLEAR)
        px = img.load()
        c = RING_CELL / 2.0 - 0.5
        for y in range(RING_CELL):
            for x in range(RING_CELL):
                dx, dy = x - c, y - c
                d = math.hypot(dx, dy)
                ang = math.atan2(dy, dx)
                jag = (h2(int((ang + math.pi) * 24), k, 3) - 0.5) * 2.4           # 外沿锯齿(沿角度分段)
                ro = r_out + jag
                ri = r_out - band + (h2(int((ang + math.pi) * 18), k, 5) - 0.5) * 2.0
                if ri <= d <= ro:
                    if fade > 0.0 and h2(x // 2, y // 2, 11 + k) < fade:
                        continue
                    f = (d - ri) / max(0.5, ro - ri)     # 0 内沿 → 1 外沿
                    col = HIL if f > 0.62 else (LITE if f > 0.3 else MID)
                    if h2(x, y, 17) < 0.12:
                        col = DUST_L
                    px[x, y] = col
        outline(img, DUST_O)
        out.append(img)
    return out


# ═══════════════════════ ② 陷坑裂纹: 逐帧裂开 → 停 → 碎散(俯视, 躺平贴地) ═══════════════════════
# 底图 = basic-slam-crack.png(PixelLab 出的那张, 64×64)。帧: 0..3 由心往外露出(裂开), 4 完整, 5..7 逐块碎掉。
CRACK_FRAMES = 8


def crater_frames():
    base = Image.open(os.path.join(OUT, "basic-slam-crack.png")).convert("RGBA")
    w, h = base.size
    c = (w / 2.0 - 0.5, h / 2.0 - 0.5)
    rmax = max(math.hypot(x - c[0], y - c[1]) for y in range(h) for x in range(w) if base.getpixel((x, y))[3] > 0)
    reveal = [0.28, 0.5, 0.74, 0.92, 1.01, 1.01, 1.01, 1.01]
    crumble = [0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.6, 0.86]
    out = []
    for k in range(CRACK_FRAMES):
        img = Image.new("RGBA", (w, h), CLEAR)
        src = base.load()
        px = img.load()
        for y in range(h):
            for x in range(w):
                p = src[x, y]
                if p[3] == 0:
                    continue
                d = math.hypot(x - c[0], y - c[1]) / rmax
                ang = math.atan2(y - c[1], x - c[0])
                # 裂纹尖比坑先到: 露出半径沿角度有起伏(裂开不是一个整圆往外推)
                lim = reveal[k] + (h2(int((ang + math.pi) * 6), 0, 7) - 0.5) * 0.16
                if d > lim:
                    continue
                if crumble[k] > 0.0 and h2(x // 3, y // 3, 23) < crumble[k] * (0.55 + 0.6 * d):
                    continue   # 碎散从外圈先掉(外圈系数大)
                px[x, y] = p
        out.append(img)
    return out


# ═══════════════════════ ③ 土刺爆冠(正对镜头, 立着) ═══════════════════════
# 160×72 一格 × 7 帧。两侧高、中间低(瑟提 R 的爆冠是一圈往外张的尖刺; 我们是立牌, 正中留低 ⇒ 不挡住摔在中间的目标)。
ERUPT_W, ERUPT_H, ERUPT_FRAMES = 160, 72, 7


def erupt_frames():
    out = []
    # 尖刺: (中心 x 偏移比例 -1..1, 最大高, 宽)
    spikes = []
    ## 9 根, 位置带抖动; 两侧高、中间低; 越靠外越往外倒(爆冠往外张)。第一版 13 根等距等高的直刺 = 一排栅栏。
    for i in range(9):
        s = -1.0 + 2.0 * i / 8.0 + (h2(i, 9, 29) - 0.5) * 0.12
        side = abs(s)
        hmax = 14 + 50 * (side ** 0.9) * (0.6 + 0.8 * h2(i, 1, 31))
        if side < 0.22:
            hmax = 9 + 6 * h2(i, 4, 33)
        wdt = 11 + 8 * h2(i, 2, 37)
        lean = s * (14 + 12 * h2(i, 3, 41))
        spikes.append((s, hmax, wdt, lean))
    grow = [0.35, 0.8, 1.0, 0.92, 0.6, 0.3, 0.1]
    for k in range(ERUPT_FRAMES):
        img = Image.new("RGBA", (ERUPT_W, ERUPT_H), CLEAR)
        px = img.load()
        base_y = ERUPT_H - 3
        for (s, hmax, wdt, lean) in spikes:
            cx = ERUPT_W / 2.0 + s * (ERUPT_W / 2.0 - 12)
            hh = hmax * grow[k]
            if hh < 3:
                continue
            breakup = 0.0 if k < 4 else (k - 3) / 3.0                   # 后几帧碎成块往下掉
            for yy in range(int(hh)):
                t = yy / max(1.0, hh)
                half = (wdt / 2.0) * (1.0 - t) + 0.6
                xc = cx + lean * t
                y = int(base_y - yy - (k >= 4) * int(8 * breakup * t))
                for x in range(int(xc - half), int(xc + half) + 1):
                    if 0 <= x < ERUPT_W and 0 <= y < ERUPT_H:
                        if breakup > 0.0 and h2(x // 3, y // 3, 50 + k) < breakup * 0.8:
                            continue
                        f = (x - (xc - half)) / max(1.0, 2 * half)
                        col = LITE if f < 0.35 else (MID if f < 0.75 else DARK)
                        if t > 0.8:
                            col = HIL
                        px[x, y] = col
        # 飞起的土块(第 1~4 帧): 从刺尖往外上方抛
        if 1 <= k <= 4:
            for j in range(10):
                sj = -1.0 + 2.0 * h2(j, 5, 43)
                if abs(sj) < 0.25:
                    continue
                cxj = ERUPT_W / 2.0 + sj * (ERUPT_W / 2.0 - 14) + sj * 10 * k
                cyj = base_y - (30 + 30 * h2(j, 6, 47)) * (1.0 - ((k - 2.2) / 2.6) ** 2)
                rr = 1.5 + 2.0 * h2(j, 7, 53)
                for y in range(int(cyj - rr), int(cyj + rr) + 1):
                    for x in range(int(cxj - rr), int(cxj + rr) + 1):
                        if 0 <= x < ERUPT_W and 0 <= y < ERUPT_H and math.hypot(x - cxj, y - cyj) <= rr:
                            px[x, y] = LITE if y < cyj else MID
        # 地面一道土线(爆冠的根)
        if k <= 4:
            for x in range(8, ERUPT_W - 8):
                for y in range(base_y - 1, base_y + 2):
                    if h2(x, y, 60) > 0.2 * k:
                        px[x, y] = MID if y == base_y else DARK
        outline(img)
        out.append(img)
    return out


# ═══════════════════════ ④ 扬尘团(正对镜头, 立着, 沿地面往外卷) ═══════════════════════
# 56×40 一格 × 7 帧: 冒起 → 鼓大 → 散成几团 → 残点。
DUST_W, DUST_H, DUST_FRAMES = 56, 40, 7


def dust_frames():
    out = []
    blobs = [(-0.5, 0.0, 0.55), (0.0, -0.25, 0.75), (0.5, 0.05, 0.6), (-0.15, 0.2, 0.5), (0.3, 0.3, 0.45)]
    size = [0.25, 0.55, 0.8, 0.95, 1.0, 0.85, 0.6]
    split = [0.0, 0.0, 0.0, 0.0, 0.35, 0.7, 1.0]
    for k in range(DUST_FRAMES):
        img = Image.new("RGBA", (DUST_W, DUST_H), CLEAR)
        px = img.load()
        for bi, (bx, by, br) in enumerate(blobs):
            r = br * size[k] * 15.0
            if r < 1.5:
                continue
            sx = bx * (1.0 + split[k] * 0.9)
            cx = DUST_W / 2.0 + sx * 22.0
            cy = DUST_H - 8 - r * 0.7 + by * 10.0 - k * 1.2
            for y in range(DUST_H):
                for x in range(DUST_W):
                    d = math.hypot((x - cx), (y - cy) * 1.15)
                    lim = r * (1.0 - split[k] * 0.35) + (h2(x, y, 70 + bi) - 0.5) * 1.6
                    if d <= lim:
                        if split[k] > 0.6 and h2(x // 2, y // 2, 80 + k) < (split[k] - 0.5):
                            continue
                        ly = (y - (cy - r)) / max(1.0, 2 * r)
                        col = DUST_L if ly < 0.35 else (DUST_M if ly < 0.7 else DUST_D)
                        px[x, y] = col
        outline(img, DUST_O)
        out.append(img)
    return out


# ═══════════════════════ ⑤ 石块碎屑(4 种, 各 12×12) ═══════════════════════
def rock_frames():
    out = []
    shapes = [
        ["....xxxx....", "..xxxxxxx...", ".xxxxxxxxx..", ".xxxxxxxxxx.", "xxxxxxxxxxx.", "xxxxxxxxxxx.",
         ".xxxxxxxxxx.", ".xxxxxxxxx..", "..xxxxxxx...", "...xxxxx....", "............", "............"],
        ["............", "...xxxxx....", "..xxxxxxxx..", ".xxxxxxxxxx.", ".xxxxxxxxxx.", "..xxxxxxxxx.",
         "..xxxxxxxx..", "...xxxxxx...", "....xxx.....", "............", "............", "............"],
        ["............", "............", "..xxxx......", ".xxxxxxx....", ".xxxxxxxxx..", "xxxxxxxxxxx.",
         ".xxxxxxxxxx.", "..xxxxxxxx..", "....xxxx....", "............", "............", "............"],
        ["............", "............", "............", "....xxx.....", "...xxxxxx...", "..xxxxxxxx..",
         "..xxxxxxxx..", "...xxxxxx...", "....xxx.....", "............", "............", "............"],
    ]
    for s in shapes:
        img = Image.new("RGBA", (12, 12), CLEAR)
        px = img.load()
        ys = [y for y in range(12) if "x" in s[y]]
        y0, y1 = min(ys), max(ys)
        for y in range(12):
            for x in range(12):
                if s[y][x] == "x":
                    ly = (y - y0) / max(1, y1 - y0)
                    xs = [i for i in range(12) if s[y][i] == "x"]
                    lx = (x - min(xs)) / max(1, max(xs) - min(xs))
                    v = 0.55 * ly + 0.45 * lx
                    px[x, y] = HIL if v < 0.18 else (LITE if v < 0.45 else (MID if v < 0.75 else DARK))
        # 描边画在形状内沿(石块小, 外扩会让它更大一圈)
        src = img.copy().load()
        for y in range(12):
            for x in range(12):
                if src[x, y][3] == 0:
                    continue
                edge = any(not (0 <= x + dx < 12 and 0 <= y + dy < 12) or src[x + dx, y + dy][3] == 0
                           for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                if edge:
                    px[x, y] = OUTL
        out.append(img)
    return out


# ═══════════════════════ ⑥ 砸中闪光(正对镜头, 4 帧) ═══════════════════════
FLASH_CELL, FLASH_FRAMES = 56, 4


def flash_frames():
    out = []
    for k in range(FLASH_FRAMES):
        img = Image.new("RGBA", (FLASH_CELL, FLASH_CELL), CLEAR)
        px = img.load()
        c = FLASH_CELL / 2.0 - 0.5
        core = [8.0, 11.0, 7.0, 3.0][k]
        ray = [20.0, 27.0, 24.0, 14.0][k]
        nray = 8
        for y in range(FLASH_CELL):
            for x in range(FLASH_CELL):
                dx, dy = x - c, (y - c) * 1.25
                d = math.hypot(dx, dy)
                ang = math.atan2(dy, dx)
                a8 = (ang + math.pi) / (2 * math.pi) * nray
                frac = abs(a8 - round(a8))
                long_ray = int(round(a8)) % 2 == 0
                rlen = ray * (1.0 if long_ray else 0.6)
                width = (0.16 if long_ray else 0.11) * (1.0 - d / max(1.0, rlen))
                if d <= core:
                    px[x, y] = FLASH_W if d < core * 0.6 else FLASH_Y
                elif d <= rlen and frac < width and k < 3:
                    px[x, y] = FLASH_W if d < rlen * 0.5 else FLASH_Y
        outline(img, FLASH_O)
        out.append(img)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    sets = {
        "basic-slam-shock.png": ring_frames(),
        "basic-slam-crater.png": crater_frames(),
        "basic-slam-erupt.png": erupt_frames(),
        "basic-slam-dust.png": dust_frames(),
        "basic-slam-rocks.png": rock_frames(),
        "basic-slam-flash.png": flash_frames(),
    }
    for name, fr in sets.items():
        sheet(fr).save(os.path.join(OUT, name))
        print("%-26s %d 帧 × %dx%d" % (name, len(fr), fr[0].size[0], fr[0].size[1]))
    if a.preview:
        rows = []
        for name, fr in sets.items():
            s = sheet(fr)
            sc = max(1, int(160 / s.size[1]))
            bg = Image.new("RGBA", (s.size[0] * sc, s.size[1] * sc), (88, 96, 72, 255))
            big = s.resize((s.size[0] * sc, s.size[1] * sc), Image.NEAREST)
            bg.alpha_composite(big)
            rows.append(bg)
        W = max(r.size[0] for r in rows)
        H = sum(r.size[1] + 8 for r in rows)
        pv = Image.new("RGBA", (W, H), (30, 30, 30, 255))
        y = 0
        for r in rows:
            pv.paste(r, (0, y))
            y += r.size[1] + 8
        pv.convert("RGB").save(a.preview)
        print("preview", a.preview, pv.size)


if __name__ == "__main__":
    main()
