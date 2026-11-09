# -*- coding: utf-8 -*-
"""tools/assetgen/build_shell_vfx.py — 龟壳「复制」「暗影俯冲」两个技能的像素帧表(2026-11-08)。

用户 11-08:「龟壳的复制和暗影，这些需要优…需要设计。」复制对标塞拉斯 R(用户指定「谢老师 R 偷别人大招」), 暗影俯冲对标库奇 W。
参考逐帧: docs/studies/20261108-龟壳复制参考-塞拉斯R逐帧.md(78 帧)、docs/studies/20261108-龟壳暗影俯冲参考-库奇W逐帧.md(62 帧)。
方向: docs/plans/20261108-训龟大师羁绊与画面一批.md 第二批「龟壳复制 / 暗影」。
原来两个技能全是程序柔光团(VfxTex._make_fire_glow_tex), 这里换成硬边像素帧表(零半透明、3~4 级色阶)。
配色: 龟壳暗紫 + 白, 暗部近黑紫; 不用金黄(金是龟壳「觉醒」的颜色)。

出的图(都在 assets/sprites/vfx/, 横排帧, 帧宽 = 帧高的整数倍或写在下面):
  暗影俯冲
    shell-dive-launch.png   4 帧 64×64 公告板: 黑紫烟团 2 帧 → 紫芯白亮火球 2 帧(起飞喷焰, 库奇第 9~10 帧)
    shell-dive-patch.png   11 帧 64×64 贴地(俯视画, 躺平后镜头自然压扁):
                           0~2 生成(亮紫火圈 → 暗紫细边圈 + 芯 → 定型烟晕 + 网状裂纹芯) /
                           3~6 持续循环(裂纹亮块轮换 + 火星上飘) / 7~10 消散(前 2 帧烟散、后 2 帧芯缩没)
    shell-dive-hit.png      4 帧 64×64 公告板: 路径命中火球(1 帧最亮 + 3 帧收, 库奇第 14 帧)
  复制
    shell-copy-crescent.png 2 帧 64×64 公告板: 甩链月牙闪光(白芯 + 暗紫外缘, 朝右; 朝左时 flip_h)
    shell-copy-link.png    12 帧 10×6: 分节锁链的一节。帧 = 状态 × 4 + 色阶;
                           状态 0 粗 / 1 细 / 2 只剩一条暗紫细线; 色阶 0 龟壳端暗紫 → 3 原主端白
    shell-copy-head.png     2 帧 16×10: 锁链链头(尾环 + 白刃尖, 朝右; 0 飞行 / 1 扎中), 11-09 加
    shell-copy-vortex.png   2 帧 32×32 公告板: 原主身上的紫色小旋涡
    shell-copy-grab.png     3 帧 64×64 公告板: 抓住时原主身后的爆闪(白芯 + 放射尖刺 → 白环碎开 → 碎光), 11-09 由 2 帧圆闪改
    shell-copy-mark.png     4 帧 32×32 贴地: 原主脚下「已被偷」紫色细圈 + 尾巴小环(出现 / 挂着 / 淡 2 帧)
    shell-copy-drain.png    3 帧 16×12: 抽能量的紫流一段(沿线平铺): 粗流 2 帧(白芯, 纹路错开半段 = 在流) → 细锯齿闪电
    shell-copy-badge.png    6 帧 32×32 公告板: 头顶技能图标的边框(2 像素暗紫描边 + 1 像素白外发光, 中间空出来露图标)
                           0~3 弹出(小 → 大 → 过冲 → 定) / 4~5 淡(描边断成虚线 → 只剩四角)
    shell-copy-arc.png      4 帧 48×48 公告板: 持有态龟壳身上的紫色碎电弧(循环)
  潜影(被动; 用户 11-08 晚「隐形的话，透明的还是怎么样的？这都没设计啊」; 参考 Twitch Q / 伊芙琳被动官方演示, .out/ref_stealth)
    shell-shade-enter.png   6 帧 64×64 公告板: 进入 —— 黑紫烟球胀开、边缘窜出紫色弯火舌(最满那帧中间一点亮), 再散成三团往上飘
    shell-shade-break.png   5 帧 64×64 公告板: 破隐 —— 亮紫一闪 + 一圈暗烟往外散
    shell-shade-pool.png    4 帧 64×64 贴地: 脚下暗影池(俯视圆, 外沿棋盘虚边, 三条暗紫旋臂每帧转 30° ⇒ 4 帧无缝循环)
    shell-shade-wisp.png    6 帧 48×64 公告板: 身上往上窜的三缕暗火(错开相位, 6 帧循环)

★全部确定性(没有随机数): 形状噪声用整数哈希与固定相位的正弦, 重跑逐字节相同。
跑法:  python tools/assetgen/build_shell_vfx.py
       python tools/assetgen/build_shell_vfx.py --preview <png>   # 另出一张放大预览(不进仓库)
"""
import argparse
import math
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx")

# ── 锁定调色板(龟壳暗紫 + 白; 暗部近黑紫) ──
K0 = (12, 6, 22, 255)        # 近黑紫: 描边
K1 = (34, 16, 56, 255)       # 烟暗
K2 = (58, 28, 92, 255)       # 烟中 / 暗紫
P1 = (92, 40, 150, 255)      # 暗紫
P2 = (134, 64, 206, 255)     # 紫
P3 = (178, 104, 240, 255)    # 亮紫
M1 = (206, 82, 226, 255)     # 品红紫(火芯)
L1 = (226, 200, 255, 255)    # 淡紫白
W = (255, 255, 255, 255)     # 白
CLEAR = (0, 0, 0, 0)


def h2(x, y, s=0):
    """整数哈希 → [0,1)。确定性噪声。"""
    n = (x * 374761393 + y * 668265263 + s * 2147483647) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return (n & 0xFFFF) / 65536.0


def new(w, h):
    return Image.new("RGBA", (w, h), CLEAR)


def outline(img, col=K0, skip=()):
    """不透明区域外沿描 1 像素边(4 邻接)。skip: 这些颜色的像素不算「要描边的实体」。"""
    w, h = img.size
    px = img.load()
    add = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    q = px[nx, ny]
                    if q[3] != 0 and q != col and q not in skip:
                        add.append((x, y))
                        break
    for x, y in add:
        px[x, y] = col
    return img


def sheet(frames):
    w, h = frames[0].size
    s = new(w * len(frames), h)
    for i, f in enumerate(frames):
        s.paste(f, (i * w, 0))
    return s


def lumpy(theta, r, seed, amp):
    """不规则半径: 三组固定相位正弦叠加(相位由 seed 的哈希定)。"""
    p1 = h2(seed, 1, 7) * math.tau
    p2 = h2(seed, 2, 7) * math.tau
    p3 = h2(seed, 3, 7) * math.tau
    k = 0.5 * math.sin(3 * theta + p1) + 0.3 * math.sin(5 * theta + p2) + 0.2 * math.sin(7 * theta + p3)
    return r * (1.0 + amp * k)


def blob_f(x, y, cx, cy, r, seed, amp, sy=1.0):
    """像素 (x,y) 在不规则圆里的归一距离 f(0 圆心 → 1 边); 圆外返回 None。sy: 纵向压缩。"""
    dx = x + 0.5 - cx
    dy = (y + 0.5 - cy) / sy
    d = math.hypot(dx, dy)
    rr = lumpy(math.atan2(dy, dx), r, seed, amp)
    if d > rr:
        return None
    return d / max(0.5, rr)


def paint_blob(img, cx, cy, r, seed, amp, ramp, holes=0.0, hole_from=0.0, hseed=0, off=(0.0, 0.0), sy=1.0):
    """按归一距离分段上色。ramp = [(上限 f, 颜色), …] 由内到外; off: 内层色阶的光心偏移(体积感)。
    holes: f ≥ hole_from 的像素按哈希挖掉这个比例(碎散)。"""
    w, h = img.size
    px = img.load()
    for y in range(h):
        for x in range(w):
            f = blob_f(x, y, cx, cy, r, seed, amp, sy)
            if f is None:
                continue
            if holes > 0.0 and f >= hole_from and h2(x, y, hseed) < holes:
                continue
            g = blob_f(x, y, cx + off[0], cy + off[1], r, seed, amp, sy)
            fv = f if g is None else min(f, g)
            col = ramp[-1][1]
            for lim, c in ramp:
                if fv < lim:
                    col = c
                    break
            px[x, y] = col
    return img


def put(img, x, y, col):
    w, h = img.size
    if 0 <= x < w and 0 <= y < h:
        img.load()[x, y] = col


def line(img, x0, y0, x1, y1, col):
    """整数 Bresenham。"""
    x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        put(img, x0, y0, col)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


# ═══════════════════════ 暗影俯冲 ① 起飞喷焰(公告板 64×64 × 4) ═══════════════════════
def _sparks(img, cx, cy, r0, r1, n, seed, cols=(L1, P3)):
    for k in range(n):
        a = h2(k, seed, 11) * math.tau
        d = r0 + (r1 - r0) * h2(k, seed, 13)
        put(img, int(cx + math.cos(a) * d), int(cy + math.sin(a) * d * 0.85), cols[k % len(cols)])


def launch_frames():
    out = []
    smoke = [(0.55, K2), (1.01, K1)]
    # f0 黑紫烟团(小)
    im = new(64, 64)
    paint_blob(im, 32, 40, 13, 3, 0.16, smoke, off=(-3, -3))
    outline(im)
    _sparks(im, 32, 40, 16, 20, 4, 1)
    out.append(im)
    # f1 烟团胀大(三团叠)
    im = new(64, 64)
    for (cx, cy, r, sd) in ((27, 41, 14, 4), (39, 39, 12, 5), (33, 31, 10, 6)):
        paint_blob(im, cx, cy, r, sd, 0.14, smoke, off=(-3, -3))
    outline(im)
    _sparks(im, 32, 38, 22, 27, 5, 2)
    out.append(im)
    # f2 紫芯白亮火球(烟留在底下两侧)
    im = new(64, 64)
    paint_blob(im, 21, 47, 7, 8, 0.2, [(1.01, K1)])
    paint_blob(im, 43, 47, 6, 9, 0.2, [(1.01, K1)])
    paint_blob(im, 32, 35, 19, 10, 0.14, [(0.3, W), (0.5, L1), (0.68, M1), (0.85, P2), (1.01, P1)], off=(-2, -2))
    outline(im)
    _sparks(im, 32, 35, 22, 27, 6, 3)
    out.append(im)
    # f3 火球收小、外沿碎散
    im = new(64, 64)
    paint_blob(im, 22, 46, 6, 8, 0.25, [(1.01, K1)], holes=0.45, hseed=21)
    paint_blob(im, 42, 46, 5, 9, 0.25, [(1.01, K1)], holes=0.45, hseed=22)
    paint_blob(im, 32, 34, 15, 11, 0.18, [(0.35, P3), (0.55, M1), (0.75, P2), (1.01, P1)],
               holes=0.35, hole_from=0.7, hseed=23, off=(-2, -2))
    outline(im)
    _sparks(im, 32, 33, 18, 24, 4, 4, cols=(P3,))
    out.append(im)
    return out


# ═══════════════════════ 暗影俯冲 ⑤ 路径命中火球(公告板 64×64 × 4) ═══════════════════════
def hit_frames():
    out = []
    # f0 最亮: 大火球 + 六道尖刺
    im = new(64, 64)
    for k in range(6):
        a = math.radians(k * 60 + 15)
        line(im, 32 + math.cos(a) * 22, 32 + math.sin(a) * 22, 32 + math.cos(a) * 30, 32 + math.sin(a) * 30, L1)
    paint_blob(im, 32, 32, 26, 31, 0.18, [(0.5, W), (0.7, L1), (0.86, P3), (1.01, P2)], off=(-2, -2))
    outline(im, P1)
    out.append(im)
    # f1
    im = new(64, 64)
    paint_blob(im, 32, 32, 22, 32, 0.16, [(0.25, W), (0.45, L1), (0.65, P3), (0.82, M1), (1.01, P2)], off=(-2, -2))
    outline(im, P1)
    out.append(im)
    # f2 收、外沿碎
    im = new(64, 64)
    paint_blob(im, 32, 33, 17, 33, 0.22, [(0.2, L1), (0.45, P3), (0.7, P2), (1.01, P1)],
               holes=0.3, hole_from=0.75, hseed=41, off=(-2, -2))
    _sparks(im, 32, 33, 18, 22, 5, 5, cols=(K1, K2))
    outline(im)
    out.append(im)
    # f3 碎成几片
    im = new(64, 64)
    paint_blob(im, 32, 34, 12, 34, 0.25, [(0.3, P2), (0.6, P1), (1.01, K2)], holes=0.5, hseed=42)
    outline(im)
    out.append(im)
    return out


# ═══════════════════════ 暗影俯冲 ②~④ 贴地火团(俯视 64×64 × 11) ═══════════════════════
PATCH_SEEDS = 11      # 第一版 7 格: 实录里格子太大, 读成龟甲花纹 / 彩色玻璃, 不像龟裂熔岩 ⇒ 加密到 11 格、裂缝 1 像素


def _crack_seeds():
    """裂纹芯的格点(黄金角螺线, 确定性)。"""
    pts = []
    for k in range(PATCH_SEEDS):
        rr = 14.0 * math.sqrt((k + 0.5) / PATCH_SEEDS)
        a = k * 2.39996 + 0.3
        pts.append((32 + math.cos(a) * rr, 32 + math.sin(a) * rr))
    return pts


def _core(img, r, lit, dim=0, holes=0.0, hseed=0):
    """网状裂纹芯: 按最近两个格点的距离差画裂缝(暗), 格子中心是亮块。
    lit: 第几组格子亮(轮换出「裂纹亮块闪动」, 不整块闪); dim: 0 正常 / 1 暗一档 / 2 再暗。"""
    px = img.load()
    seeds = _crack_seeds()
    bright = [L1, P3, M1] if dim == 0 else ([P3, M1, M1] if dim == 1 else [P2, P2, P1])
    base = M1 if dim == 0 else (P2 if dim == 1 else P1)
    for y in range(64):
        for x in range(64):
            f = blob_f(x, y, 32, 32, r, 61, 0.1)
            if f is None:
                continue
            if holes > 0.0 and h2(x, y, hseed) < holes:
                continue
            ds = sorted((math.hypot(x + 0.5 - sx, y + 0.5 - sy), i) for i, (sx, sy) in enumerate(seeds))
            (d1, i1), (d2, _i2) = ds[0], ds[1]
            if f > 0.84:
                col = P1 if dim < 2 else K2                         # 芯边一圈暗紫
            elif d2 - d1 < 0.95:
                col = K1                                            # 裂缝
            elif d1 < 2.1:
                col = bright[(i1 + lit) % 3]                        # 格子中心亮块(按组轮换)
            else:
                col = base
            px[x, y] = col


BAYER2 = ((0, 2), (3, 1))     # 2×2 抖点阈值: 留下阈值 < 密度×4 的像素
SMOKE_DITHER = ((0.5, 4), (0.68, 3), (0.84, 2), (1.01, 1))   # (归一半径上限, 2×2 里留几个): 里实心 → 3/4 → 1/2 → 1/4


def _smoke(img, r, holes=0.0, hseed=0):
    """烟晕: 近黑紫底 + 暗紫成团, 外沿不规则。
    ★11-09 软边(实机逐帧 docs/studies/20261108-龟壳特效实机逐帧.md 问题 1「火团太重」): 第一版整块实心 + 外沿描黑边,
      一块就是一个近黑紫硬饼; 库奇的烟晕是软边、半透、只比芯大一圈。像素画不许半透明 ⇒ 外沿用 2×2 抖点由密到疏
      (SMOKE_DITHER), 不描边; 外沿那圈稀点仍画到 r(可见宽 = 火道宽, 画面 = 判定不变)。"""
    px = img.load()
    for y in range(64):
        for x in range(64):
            f = blob_f(x, y, 32, 32, r, 62, 0.13)
            if f is None:
                continue
            if holes > 0.0 and h2(x, y, hseed) < holes:
                continue
            keep = 4
            for lim, k in SMOKE_DITHER:
                if f < lim:
                    keep = k
                    break
            if BAYER2[y % 2][x % 2] >= keep:
                continue
            n = (math.sin(x * 0.47 + 1.3) * math.sin(y * 0.53 + 0.4)
                 + 0.7 * math.sin((x + y) * 0.29 + 2.1) + 0.5 * math.sin((x - y) * 0.41 + 0.9))
            px[x, y] = K2 if (n > 0.55 and f < 0.68) else K1     # 暗紫成团(固定相位正弦叠加, 不是方块)


CORE_R = 14           # 裂纹芯半径(11-09 16 → 14: 「芯小而亮」, 烟晕只比芯大一圈抖点)


def _patch_frame(smoke_r, core_r, lit, dim=0, smoke_holes=0.0, smoke_seed=0, core_holes=0.0, core_seed=0):
    """一格火团: 软边烟晕在下(不描边), 裂纹芯单独描边后盖上去(芯边那圈近黑紫把亮芯和烟分开)。"""
    im = new(64, 64)
    if smoke_r > 0:
        _smoke(im, smoke_r, holes=smoke_holes, hseed=smoke_seed)
    core = new(64, 64)
    _core(core, core_r, lit, dim=dim, holes=core_holes, hseed=core_seed)
    outline(core)
    im.alpha_composite(core)
    return im


def patch_frames():
    out = []
    # 0 生成: 扁平亮紫火圈(边缘亮, 里面暗)。★11-09 里面那片暗紫改成 1/4 抖点: 实录里每块刚落下这一格是实心暗紫饼,
    #   龟壳飞行时最前面永远顶着一块(实机逐帧问题 1 的同一类)
    im = new(64, 64)
    paint_blob(im, 32, 32, 20, 64, 0.06, [(0.62, K2), (0.8, P2), (0.93, P3), (1.01, L1)])
    px = im.load()
    for y in range(64):
        for x in range(64):
            if px[x, y] == K2 and BAYER2[y % 2][x % 2] >= 1:
                px[x, y] = CLEAR
    ring = new(64, 64)
    rp = ring.load()
    for y in range(64):
        for x in range(64):
            if px[x, y] in (P2, P3, L1):
                rp[x, y] = px[x, y]
    outline(ring)
    im.alpha_composite(ring)
    out.append(im)
    # 1 暗紫细边圈 + 芯(圈和芯之间露地面)
    im = new(64, 64)
    px = im.load()
    for y in range(64):
        for x in range(64):
            d = math.hypot(x + 0.5 - 32, y + 0.5 - 32)
            if 23.0 <= d < 24.4:
                px[x, y] = P1
    paint_blob(im, 32, 32, 12, 66, 0.1, [(0.3, L1), (0.62, M1), (1.01, P2)], off=(-1, -1))
    outline(im)
    out.append(im)
    # 2 定型: 软边烟晕 + 网状裂纹芯
    out.append(_patch_frame(29, CORE_R, 0))
    # 3~6 持续循环: 裂纹亮块轮换 + 1~2 颗火星往上飘(俯视图里「上」= 远处, 镜头里就是往上)
    for i in range(4):
        im = _patch_frame(29, CORE_R, i)
        put(im, 27, 22 - 3 * i, L1)
        put(im, 27, 23 - 3 * i, P3)
        j = (i + 2) % 4
        put(im, 38, 24 - 3 * j, P3)
        out.append(im)
    # 7 消散: 烟开始散(挖掉近一半), 芯还亮但不再有最亮块
    out.append(_patch_frame(29, CORE_R, 0, dim=1, smoke_holes=0.45, smoke_seed=71))
    # 8 烟几乎散光, 芯变暗
    out.append(_patch_frame(28, CORE_R - 1, 1, dim=1, smoke_holes=0.86, smoke_seed=72))
    # 9 没有烟, 芯缩小
    out.append(_patch_frame(0, 9, 2, dim=2))
    # 10 一抹残芯
    im = new(64, 64)
    paint_blob(im, 32, 32, 5, 73, 0.2, [(0.5, P1), (1.01, K2)], holes=0.4, hseed=74)
    out.append(im)
    return out


# ═══════════════════════ 复制 ① 甩链月牙闪光(公告板 64×64 × 2, 朝右) ═══════════════════════
def _crescent(im, cx, cy, r0, wmax, span_deg, core, holes=0.0, hseed=0):
    px = im.load()
    for y in range(64):
        for x in range(64):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            th = math.degrees(math.atan2(dy, dx))
            if abs(th) > span_deg:
                continue
            w = wmax * (math.cos(math.radians(th / span_deg * 90.0)) ** 0.8)
            r = math.hypot(dx, dy)
            if w < 0.8 or not (r0 - w <= r <= r0):
                continue
            if holes > 0.0 and abs(th) > span_deg * 0.6 and h2(x, y, hseed) < holes:
                continue
            f = (r0 - r) / w
            if f < 0.18 or f > 0.82:
                col = P1
            elif f < 0.35 or f > 0.65:
                col = P3
            else:
                col = core
            px[x, y] = col


def crescent_frames():
    a = new(64, 64)
    _crescent(a, 18, 32, 26, 8.0, 70.0, W)
    outline(a)
    b = new(64, 64)
    _crescent(b, 16, 32, 30, 5.0, 80.0, L1, holes=0.35, hseed=81)
    outline(b)
    return [a, b]


# ═══════════════════════ 复制 ② 分节锁链(10×6 × 12) ═══════════════════════
LINK_TIERS = [(K0, P1, P2), (K0, P2, P3), (K1, P3, L1), (P1, L1, W)]   # (描边, 本体, 高光): 龟壳端 → 原主端
LINK_THICK = [
    ".OOOOO....",
    "OHHHHHO...",
    "OB...BOOOO",
    "OB...BBHHB",
    "OBBBBBOOOO",
    ".OOOOO....",
]
LINK_THIN = [
    "..........",
    ".HHHH.....",
    "B....B....",
    "B....BBBBB",
    ".BBBB.....",
    "..........",
]


def link_frames():
    out = []
    for state in range(3):
        for tier in range(4):
            o, b, hl = LINK_TIERS[tier]
            im = new(10, 6)
            px = im.load()
            if state == 2:
                for x in range(10):
                    px[x, 3] = K2 if tier < 2 else P1             # 只剩一条暗紫细线
            else:
                rows = LINK_THICK if state == 0 else LINK_THIN
                for y, row in enumerate(rows):
                    for x, ch in enumerate(row):
                        if ch == "O":
                            px[x, y] = o
                        elif ch == "B":
                            px[x, y] = b
                        elif ch == "H":
                            px[x, y] = hl
            out.append(im)
    return out


# ═══════════════════════ 复制 ② 原主身上的紫色小旋涡(公告板 32×32 × 2) ═══════════════════════
def _spiral(im, rot, scale, outer):
    for arm in (0.0, math.pi):
        steps = 90
        for k in range(steps):
            t = k / (steps - 1) * 2.2 * math.pi
            r = (1.5 + 4.2 * t / math.pi) * scale
            a = t + arm + rot
            x = 16 + math.cos(a) * r
            y = 16 + math.sin(a) * r * 0.85
            col = L1 if r < 4.5 else (P3 if r < 8.5 else outer)
            put(im, int(x), int(y), col)
            put(im, int(x + 0.5), int(y), col)


def vortex_frames():
    a = new(32, 32)
    _spiral(a, 0.0, 1.0, P2)
    outline(a)
    b = new(32, 32)
    _spiral(b, math.radians(50), 0.8, P1)
    outline(b)
    return [a, b]


# ═══════════════════════ 复制 ③ 抓住: 原主身后白色圆闪(公告板 64×64 × 2) ═══════════════════════
def _rays(im, n, r0, r_long, r_short, rot_deg, core_col, edge_col):
    """放射尖刺: n 道, 长短交替; 两像素粗(芯色 + 一侧边色)。"""
    for k in range(n):
        a = math.radians(rot_deg + k * 360.0 / n)
        rr = r_long if k % 2 == 0 else r_short
        x0, y0 = 32 + math.cos(a) * r0, 32 + math.sin(a) * r0
        x1, y1 = 32 + math.cos(a) * rr, 32 + math.sin(a) * rr
        line(im, x0 + 1, y0, x1 + 1, y1, edge_col)
        line(im, x0, y0, x1, y1, core_col)


def grab_frames():
    """★11-09 三格(实机逐帧问题 3「抓住的白闪只有 2 格, 读起来更像一个泡泡而不是一下爆闪」):
    0 爆闪(白芯 + 8 道放射尖刺) → 1 白环碎开、芯缩 → 2 碎光散点。原主立绘压在前面(身后那一层)。"""
    a = new(64, 64)
    _rays(a, 8, 10, 31, 22, 22.5, W, L1)
    paint_blob(a, 32, 32, 14, 91, 0.06, [(0.72, W), (1.01, L1)])
    outline(a, P1)
    b = new(64, 64)
    px = b.load()
    for y in range(64):
        for x in range(64):
            d = math.hypot(x + 0.5 - 32, y + 0.5 - 32)
            if 21.0 <= d < 25.5 and h2(x, y, 94) >= 0.3:
                px[x, y] = W if d < 23.5 else L1
    _rays(b, 8, 26, 30, 28, 0.0, L1, P3)
    paint_blob(b, 32, 32, 7, 92, 0.1, [(0.6, W), (1.01, L1)])
    outline(b, P1)
    c = new(64, 64)
    for k in range(10):
        ang = math.radians(k * 36 + 11 + 9 * h2(k, 3, 95))
        rr = 26 + 4 * h2(k, 4, 95)
        cx, cy = int(32 + math.cos(ang) * rr), int(32 + math.sin(ang) * rr)
        put(c, cx, cy, W if k % 2 == 0 else L1)
        put(c, cx + 1, cy, L1)
    paint_blob(c, 32, 32, 3, 96, 0.1, [(1.01, L1)])
    outline(c, P1)
    return [a, b, c]


# ═══════════════════════ 复制 ③ 「已被偷」小圈(贴地 32×32 × 4) ═══════════════════════
def _mark(im, r, dash=0.0, hseed=0, ring=P3, hl=L1, tail=True, edge=True):
    px = im.load()
    cx, cy = 14.0, 13.0
    for y in range(32):
        for x in range(32):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if r - 0.7 <= d < r + 0.7:
                if dash > 0.0 and h2(x, y, hseed) < dash:
                    continue
                px[x, y] = hl if (y + 0.5 < cy - r * 0.6) else ring
    if tail:
        a = math.radians(45)
        x0, y0 = cx + math.cos(a) * (r + 1), cy + math.sin(a) * (r + 1)
        x1, y1 = cx + math.cos(a) * (r + 6), cy + math.sin(a) * (r + 6)
        tmp = new(32, 32)
        line(tmp, x0, y0, x1, y1, ring)
        ex, ey = x1 + 2.0, y1 + 2.0
        tp = tmp.load()
        for y in range(32):
            for x in range(32):
                if 1.3 <= math.hypot(x + 0.5 - ex, y + 0.5 - ey) < 2.5:
                    tp[x, y] = ring
        for y in range(32):
            for x in range(32):
                if tp[x, y][3] and not (dash > 0.0 and h2(x, y, hseed + 1) < dash):
                    px[x, y] = tp[x, y]
    if edge:
        outline(im)


def mark_frames():
    out = []
    a = new(32, 32)
    _mark(a, 6.0, tail=False)
    out.append(a)
    b = new(32, 32)
    _mark(b, 10.0)
    out.append(b)
    c = new(32, 32)
    _mark(c, 10.0, dash=0.5, hseed=101, ring=P2, hl=P3)
    out.append(c)
    d = new(32, 32)
    _mark(d, 10.0, dash=0.75, hseed=102, ring=P1, hl=P1, edge=False)
    out.append(d)
    return out


# ═══════════════════════ 复制 ④ 抽能量紫流(16×12 × 3, 沿线平铺, 周期 16 首尾相接) ═══════════════════════
def drain_frames():
    out = []
    for fi in range(2):
        im = new(16, 12)
        px = im.load()
        for x in range(16):
            top = 2 + (1 if (x // 4) % 2 == 0 else 0)           # 上下沿电纹(锯齿)
            bot = 9 - (1 if ((x + 2) // 4) % 2 == 0 else 0)
            for y in range(top, bot + 1):
                dy = abs(y + 0.5 - 6.0)
                ## 第一版白芯 2 行 + 淡紫白 2 行, 实录里整条读成「白色拉链」⇒ 白芯只留中间 1 行、淡紫白只在第 2 帧, 其余是紫
                if y == top or y == bot:
                    col = K0
                elif dy < 1.0:
                    col = W if (y == 6 or fi == 1) else L1
                elif dy < 2.0:
                    col = M1 if (x + fi * 8 + y) % 6 < 2 else P3       # 流纹(第 2 帧错开半段)
                elif dy < 3.0:
                    col = P2 if (x + fi * 8 + y) % 5 else M1
                else:
                    col = P1
                px[x, y] = col
        out.append(im)
    # 细锯齿闪电
    im = new(16, 12)
    zig = [0, 0, -1, -2, -3, -2, -1, 0, 1, 2, 3, 2, 1, 0, 0, 0]
    for x in range(16):
        y = 6 + zig[x]
        put(im, x, y, L1)
        put(im, x, y + 1, P3)
    outline(im)
    out.append(im)
    return out


# ═══════════════════════ 复制 ⑤ 头顶图标底框(公告板 32×32 × 6) ═══════════════════════
def _badge(im, s, perim_keep=1.0, corners_only=False):
    px = im.load()
    x0 = (32 - s) // 2
    x1 = x0 + s - 1
    for y in range(x0, x1 + 1):
        for x in range(x0, x1 + 1):
            ring = min(x - x0, x1 - x, y - x0, x1 - y)        # 离外沿几格
            if corners_only:
                near_c = (min(x - x0, x1 - x) < 5) and (min(y - x0, x1 - y) < 5)
                if not near_c or ring > 2:
                    continue
            if ring == 0:
                col = W                                        # 1 像素白外发光
            elif ring == 1:
                col = P1                                       # 2 像素暗紫描边(外)
            elif ring == 2:
                col = K2                                       # (内)
            else:
                continue                                       # 中间留空: 图标原图露出来(第一版垫了近黑紫底, 深色图标看不清)
            if ring <= 2 and perim_keep < 1.0 and ((x + y) % 2 == 1):
                continue                                       # 描边断成虚线
            px[x, y] = col


def badge_frames():
    out = []
    for s in (10, 20, 32, 28):
        im = new(32, 32)
        _badge(im, s)
        out.append(im)
    im = new(32, 32)
    _badge(im, 28, perim_keep=0.5)
    out.append(im)
    im = new(32, 32)
    _badge(im, 28, corners_only=True)
    out.append(im)
    return out


# ═══════════════════════ 复制 ⑥ 持有态碎电弧(公告板 48×48 × 4) ═══════════════════════
def arc_frames():
    """★11-09 提对比(实机逐帧问题 4「龟壳本体就是暗紫, 紫色碎电弧对比度低」): 第一版亮紫 + 淡紫白两像素,
    贴在暗紫龟壳上一抽帧就没了。改成 白芯 + 淡紫白 + 亮紫 三像素粗、外描近黑紫, 弧更长(5 → 6 节), 两端白火星。"""
    out = []
    for fi in range(4):
        im = new(48, 48)
        for k in range(4):
            a0 = math.radians(k * 90 + fi * 37 + 20 * h2(k, fi, 121))
            pts = []
            for j in range(6):
                a = a0 + math.radians(j * 9)
                jit = 2.0 if j % 2 else -1.0
                pts.append((24 + math.cos(a) * (19 + jit), 25 + math.sin(a) * (14 + jit * 0.7)))
            for j in range(5):                                   # 三像素粗: 下沿亮紫 / 中间淡紫白 / 上沿白芯
                line(im, pts[j][0], pts[j][1] + 2, pts[j + 1][0], pts[j + 1][1] + 2, P3)
            for j in range(5):
                line(im, pts[j][0], pts[j][1] + 1, pts[j + 1][0], pts[j + 1][1] + 1, L1)
            for j in range(5):
                line(im, pts[j][0], pts[j][1], pts[j + 1][0], pts[j + 1][1], W)
            put(im, int(pts[0][0]) - 1, int(pts[0][1]), W)
            put(im, int(pts[-1][0]) + 1, int(pts[-1][1]), W)
        for k in range(3):
            a = math.radians(k * 120 + fi * 53 + 40)
            put(im, int(24 + math.cos(a) * 22), int(25 + math.sin(a) * 17), W)
        outline(im)
        out.append(im)
    return out


# ═══════════════════════ 复制 ② 锁链链头(16×10 × 2, 朝右) ═══════════════════════
## ★11-09(实机逐帧问题 3「塞拉斯的链甩出去有链头在飞; 我们没有链头飞行的动作」): 链头 = 尾环 + 白刃尖, 朝右画,
##   摆法同链节(rotation.z 转到连线方向)。0 飞行中(白刃) / 1 扎中(刃尖一闪更亮、尾环亮紫)。
HEAD_ROWS = [
    "......OOOO......",
    "....OOWWLLOO....",
    "OOOOOLWWWLLLOO..",
    "OHHOOLWWWWLLLLOO",
    "OB.BOLWWWWWWWWWO",
    "OHHOOLLLLLLLLLOO",
    "OOOOOLLLLLPPOO..",
    "....OOPPPPOO....",
    "......OOOO......",
    "................",
]


def head_frames():
    out = []
    for fi in range(2):
        im = new(16, 10)
        px = im.load()
        for y, row in enumerate(HEAD_ROWS):
            for x, ch in enumerate(row):
                col = {"O": K0, "W": W, "L": L1, "P": P3, "H": P3 if fi == 1 else P2, "B": P2 if fi == 1 else P1}.get(ch)
                if fi == 1 and ch == "L" and y in (3, 4, 5) and x >= 9:
                    col = W                                          # 扎中: 刃尖一段全白
                if col is not None:
                    px[x, y] = col
        out.append(im)
    return out


# ═══════════════════════ 潜影 ① 进入: 黑紫烟球炸开 + 紫色光丝(公告板 64×64 × 6) ═══════════════════════
## Twitch Q: 一团黑烟球(约 2.5 倍身宽)炸开, 球里窜出本色光丝, 0.8 秒后散成几团往上飘。我们: 本色 = 紫。
def _streaks(im, cx, cy, r0, r1, n, seed, cols):
    """从烟球边缘往外窜的弯火舌(Twitch Q 那种): 根在 r0, 尖到 r1, 每条弯向不同、长短不一; 根部 2 像素宽、尖 1 像素。"""
    for k in range(n):
        a = math.radians(k * (360.0 / n) + 35 * h2(k, seed, 3))
        bend = (h2(k, seed, 7) - 0.5) * 1.1
        ln = 0.55 + 0.45 * h2(k, seed, 5)
        steps = 18
        for i in range(steps + 1):
            t = i / float(steps)
            rr = r0 + (r1 - r0) * ln * t
            aa = a + bend * t * t
            x = cx + math.cos(aa) * rr
            y = cy + math.sin(aa) * rr * 0.9
            col = cols[-1] if t > 0.8 else cols[0]
            put(im, int(round(x)), int(round(y)), col)
            if t < 0.45:
                put(im, int(round(x + math.sin(aa))), int(round(y - math.cos(aa))), cols[0])


def enter_frames():
    out = []
    smoke = [(0.5, K1), (0.78, K2), (1.01, K1)]
    # f0 小黑核 + 四道短光丝
    im = new(64, 64)
    paint_blob(im, 32, 36, 9, 71, 0.18, smoke, off=(-2, -2))
    outline(im)
    _streaks(im, 32, 36, 7, 15, 4, 1, (P3, L1))
    out.append(im)
    # f1 烟球胀大, 光丝从球里窜出
    im = new(64, 64)
    paint_blob(im, 32, 35, 19, 72, 0.15, smoke, off=(-3, -3))
    outline(im)
    _streaks(im, 32, 35, 14, 27, 5, 2, (M1, L1))
    out.append(im)
    # f2 最满: 烟球最大, 光丝最亮
    im = new(64, 64)
    paint_blob(im, 32, 34, 24, 73, 0.14, smoke, off=(-3, -3))
    outline(im)
    _streaks(im, 32, 34, 17, 31, 6, 3, (P3, W))
    paint_blob(im, 32, 34, 6, 70, 0.2, [(0.5, L1), (1.01, P3)])
    out.append(im)
    # f3 外沿开始碎, 光丝变暗
    im = new(64, 64)
    paint_blob(im, 32, 33, 22, 74, 0.16, smoke, holes=0.3, hole_from=0.72, hseed=75, off=(-3, -3))
    outline(im)
    _streaks(im, 32, 33, 16, 26, 5, 5, (P2, P3))
    out.append(im)
    # f4 散成三团往上飘
    im = new(64, 64)
    for (cx, cy, r, sd) in ((22, 30, 9, 76), (41, 27, 8, 77), (32, 18, 7, 78)):
        paint_blob(im, cx, cy, r, sd, 0.2, [(0.6, K2), (1.01, K1)], holes=0.35, hole_from=0.6, hseed=sd)
    outline(im)
    out.append(im)
    # f5 只剩几缕
    im = new(64, 64)
    for (cx, cy, r, sd) in ((20, 24, 5, 79), (43, 20, 5, 80), (32, 10, 4, 81)):
        paint_blob(im, cx, cy, r, sd, 0.25, [(1.01, K2)], holes=0.5, hseed=sd)
    out.append(im)
    return out


# ═══════════════════════ 潜影 ② 破隐: 紫闪 + 一圈暗烟往外散(公告板 64×64 × 5) ═══════════════════════
def break_frames():
    out = []
    puffs = 7

    def ring(im, r, size, holes, hs):
        for k in range(puffs):
            a = math.radians(k * (360.0 / puffs) + 10)
            cx, cy = 32 + math.cos(a) * r, 34 + math.sin(a) * r * 0.8
            paint_blob(im, cx, cy, size, 90 + k, 0.22, [(0.55, K2), (1.01, K1)], holes=holes, hole_from=0.5, hseed=hs + k)

    # f0 亮紫闪 + 贴身一圈烟
    im = new(64, 64)
    ring(im, 13, 7, 0.0, 100)
    paint_blob(im, 32, 34, 12, 91, 0.12, [(0.35, W), (0.6, L1), (0.85, P3), (1.01, M1)])
    outline(im)
    out.append(im)
    # f1 闪收小, 烟往外
    im = new(64, 64)
    ring(im, 19, 6, 0.1, 110)
    paint_blob(im, 32, 34, 7, 92, 0.15, [(0.5, L1), (1.01, P3)])
    outline(im)
    out.append(im)
    # f2
    im = new(64, 64)
    ring(im, 24, 5, 0.3, 120)
    put(im, 32, 34, P3)
    outline(im)
    out.append(im)
    # f3
    im = new(64, 64)
    ring(im, 27, 4, 0.5, 130)
    outline(im)
    out.append(im)
    # f4 只剩碎点
    im = new(64, 64)
    ring(im, 29, 3, 0.7, 140)
    out.append(im)
    return out


# ═══════════════════════ 潜影 ③ 脚下暗影池(俯视 64×64 × 4, 循环) ═══════════════════════
## Twitch 隐身时脚下一团黑影跟着走。俯视画一个圆, 躺平后镜头压扁; 里面三条暗紫旋臂, 每帧转 30° (三条臂 120° 一周期 ⇒ 4 帧无缝)。
def pool_frames():
    out = []
    for f in range(4):
        im = new(64, 64)
        px = im.load()
        rot = math.radians(30 * f)
        for y in range(64):
            for x in range(64):
                d = blob_f(x, y, 32, 32, 27, 150, 0.08)
                if d is None:
                    continue
                if d > 0.8 and ((x + y) % 2 == 0):          # 外沿棋盘点: 边缘是虚的, 不是一圈硬边
                    continue
                if d > 0.92:
                    continue
                dx, dy = x + 0.5 - 32, y + 0.5 - 32
                th = math.atan2(dy, dx) - rot
                arm = math.sin(3 * th + d * 7.0)            # 三条旋臂
                if d < 0.3:
                    col = K0
                elif arm > 0.55 and d < 0.78:
                    col = K2
                else:
                    col = K1 if d < 0.65 else K0
                px[x, y] = col
        out.append(im)
    return out


# ═══════════════════════ 潜影 ④ 身上暗影往上飘(公告板 48×64 × 6, 循环) ═══════════════════════
## 伊芙琳进伪装时一圈黑紫烟往上升; 持续时只留几缕。三缕错开相位, 每缕从下往上飘、越往上越小, 6 帧一圈无缝。
def wisp_frames():
    out = []
    cols = [(14, 0), (34, 2), (24, 4)]                       # (x, 相位偏移)
    for f in range(6):
        im = new(48, 64)
        for i, (x0, off) in enumerate(cols):
            ph = ((f + off) % 6) / 6.0                      # 0 底 → 1 顶
            y = 56 - ph * 46
            x = x0 + 2.5 * math.sin(ph * math.tau + i)
            r = 3.6 * (1.0 - 0.55 * ph)
            for j, (k, dy) in enumerate(((1.0, 0.0), (0.66, -1.6), (0.36, -2.9))):   # 一缕 = 三颗往上收尖
                ramp = [(0.45, P1), (1.01, K2)] if (j == 0 and ph < 0.5) else [(1.01, K2)]
                paint_blob(im, x + 0.6 * j * math.sin(ph * 9 + i), y + dy * r, r * k, 160 + i * 3 + j, 0.2, ramp,
                           holes=0.3 * ph, hseed=170 + f * 7 + i * 3 + j)
        outline(im)
        out.append(im)
    return out


SHEETS = [
    ("shell-dive-launch.png", launch_frames),
    ("shell-dive-patch.png", patch_frames),
    ("shell-dive-hit.png", hit_frames),
    ("shell-copy-crescent.png", crescent_frames),
    ("shell-copy-link.png", link_frames),
    ("shell-copy-head.png", head_frames),
    ("shell-copy-vortex.png", vortex_frames),
    ("shell-copy-grab.png", grab_frames),
    ("shell-copy-mark.png", mark_frames),
    ("shell-copy-drain.png", drain_frames),
    ("shell-copy-badge.png", badge_frames),
    ("shell-copy-arc.png", arc_frames),
    ("shell-shade-enter.png", enter_frames),
    ("shell-shade-break.png", break_frames),
    ("shell-shade-pool.png", pool_frames),
    ("shell-shade-wisp.png", wisp_frames),
]


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="")
    args = ap.parse_args()
    built = []
    for name, fn in SHEETS:
        frames = fn()
        s = sheet(frames)
        semi = sum(1 for p in s.get_flattened_data() if 0 < p[3] < 255)
        if semi:
            raise SystemExit("%s 有 %d 个半透明像素" % (name, semi))
        s.save(os.path.join(OUT, name), optimize=False)
        built.append((name, frames, s))
        print("%-26s %d 帧 %d×%d → assets/sprites/vfx/%s" % (name, len(frames), frames[0].size[0], frames[0].size[1], name))
    if args.preview:
        k = 4
        rows = []
        for name, frames, s in built:
            sc = 4 if frames[0].size[0] >= 32 else 8
            rows.append(s.resize((s.width * sc, s.height * sc), Image.NEAREST))
        W_ = max(r.width for r in rows) + 16
        H_ = sum(r.height + 8 for r in rows) + 8
        bg = Image.new("RGBA", (W_ * 2, H_), (40, 46, 56, 255))
        bg.paste(Image.new("RGBA", (W_, H_), (120, 124, 128, 255)), (W_, 0))
        y = 8
        for r in rows:
            bg.alpha_composite(r, (8, y))
            bg.alpha_composite(r, (W_ + 8, y))
            y += r.height + 8
        bg.save(args.preview)
        print("预览 → %s" % args.preview)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
