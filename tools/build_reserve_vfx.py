# -*- coding: utf-8 -*-
"""build_reserve_vfx.py — 援军小将·四面合围 的演出专用逐帧像素素材(2026-10-29)。

方案书 docs/plans/20261029-终极战场援军小将.md; 代码 scripts/systems/skills/reserve_vfx.gd(ReserveVfx)。
旧弹体 reserve-wave.png 是 tools/build_reserve_wave.py 画的, 本脚本**不碰它**; 这里画有方向的新弹体 reserve-wave-dir 与弹体以外的六层演出。

★分段表(t = 施法那一刻; 气波 380 码/秒, 出生点离目标 260 码 ⇒ 0.684 秒合拢; 判定半宽 55 码):

| 段 | 这一段在说什么 | 多长 | 形状 / 亮暗怎么变 | 素材 |
|---|---|---|---|---|
| 锁定 | 「这个人被盯上了, 四道会冲这儿合拢」 | 0 ~ 0.68 + 0.14 秒 | 目标脚下贴地: 四角括号 + 前后左右四个朝内箭头; 箭头随气波逼近逐帧收拢, 合拢那一刻括号收紧再散掉 | reserve-lock 10 帧 88² 贴地 |
| 凝聚 | 「气在这四个点凝成气团」 | 0 ~ 0.20 秒 | 立着: 8 颗光点拖着尾向内汇聚 → 白热成团 + 十字尖芒 → 小环弹开碎掉 | reserve-gather 6 帧 32² 立牌 |
| 出现印 | 「气团从这儿出发, 有这么宽」 | 0 ~ 0.22 秒 | 贴地: 一圈由小到大的环, 末帧外沿 = 气波判定半宽 55 码, 然后碎成短弧 | reserve-ring 5 帧 40² 贴地 |
| 拖尾 | 「气团在高速往中间冲」 | 飞行全程 | 立着: 每 2 个 sim 步在气团位置留一团, 一团 6 帧: 气团残影 → 缩小起缺口 → 抖散 → 散点 → 无 | reserve-trail 6 帧 16² 立牌 |
| 散去 | 「飞满射程没打中, 散了」 | 0.20 秒 | 立着: 气团起缺口 → 裂成 4 缕往外飘 → 散点 | reserve-fizzle 5 帧 16² 立牌 |
| 命中 | 「打中了」(用户问过「有命中特效吗」: 必须一眼看到) | 0.245 秒 | 立着、不被地面 / 立绘挡: 一下亮闪(白热团 + 八向长尖芒) → 粗冲击环外扩、变细、断开 + 8 颗碎屑放射并下坠 → 散点 | reserve-hit 7 帧 × 2 套变体 56² 立牌 |
| 弹体 | 「一道有方向的气波在追人」(用户:「得动态的、有方向的气波」) | 飞行全程循环 | 非立牌、机头朝 +X、由主会话按飞行方向转: 弯月冲击波(前沿白热) + 渐细气焰尾 + 往后飘的火星, 6 帧呼吸 / 抖尾循环 | reserve-wave-dir 6 帧 40×20 |

画风: 与弹体同一族青蓝(INK/DEEP/MID/HI/CORE 五色, 同一个技能的同一种气)、硬边、**零半透明**、逐帧(不靠缩放, pixel_size 恒定只切帧)。
  第一帧要「满」(实心白热团 / 粗环), 散的时候靠**像素数掉**而不是变暗变透明(memory fb-vfx-defect-families ① 淡出病)。
  贴地两张(锁定 / 出现印)外沿描一圈 INK: 亮沙地上青色发虚, 有暗边才读得出来。
密度: 立牌一个像素 = 3 码(与弹体 48 码 / 16 像素相同); 贴地出现印按「末帧外沿 = 55 码」换算。
★全部确定性(没有随机数): 抖动用整数哈希, 重跑逐字节相同。

跑法:  python tools/build_reserve_vfx.py                       # 写进 assets/sprites/vfx/
       python tools/build_reserve_vfx.py --preview <目录>       # 另出放大接触印相(暗底 / 沙底两张, 不进仓库)
"""
import argparse
import io
import math
import os
import sys

from PIL import Image

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx")

# ── 锁定调色板(与弹体 reserve-wave 同一族: 同一个技能的同一种气) ──
CLEAR = (0, 0, 0, 0)
INK = (12, 30, 48, 255)       # 最暗(描边)
DEEP = (24, 112, 168, 255)    # 暗青
MID = (64, 186, 232, 255)     # 青
HI = (168, 236, 255, 255)     # 亮青
CORE = (250, 255, 255, 255)   # 白热


def h2(x, y, s=0):
    """整数哈希 → [0,1)。确定性噪声。"""
    n = (x * 374761393 + y * 668265263 + s * 2147483647) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return (n & 0xFFFF) / 65536.0


class Cell:
    def __init__(self, size):
        self.s = size
        self.im = Image.new("RGBA", (size, size), CLEAR)
        self.px = self.im.load()
        self.c = (size - 1) / 2.0

    def put(self, x, y, col):
        x, y = int(x), int(y)
        if 0 <= x < self.s and 0 <= y < self.s:
            self.px[x, y] = col

    def get(self, x, y):
        return self.px[x, y]

    def _each(self):
        for y in range(self.s):
            for x in range(self.s):
                yield x, y, x - self.c, y - self.c

    def blob(self, layers, cx=0.0, cy=0.0):
        """同心实心圆, layers = [(半径, 色), …] 由外到内。cx/cy 是相对中心的偏移。"""
        for r, col in layers:
            for x, y, dx, dy in self._each():
                if math.hypot(dx - cx, dy - cy) <= r:
                    self.px[x, y] = col

    def ring(self, r0, r1, col, keep=None):
        """r0 ≤ 距离 ≤ r1 的一圈; keep(角度°) 返回 False 的地方挖空(断环)。"""
        for x, y, dx, dy in self._each():
            d = math.hypot(dx, dy)
            if r0 <= d <= r1:
                a = math.degrees(math.atan2(dy, dx)) % 360.0
                if keep is None or keep(a):
                    self.px[x, y] = col

    def spike(self, ang_deg, r0, r1, w0, cols):
        """从半径 r0 到 r1 的尖芒: 根部宽 w0, 到尖端收成 1 像素; cols 由根到尖分段上色。"""
        a = math.radians(ang_deg)
        ux, uy = math.cos(a), math.sin(a)
        for x, y, dx, dy in self._each():
            u = dx * ux + dy * uy
            v = -dx * uy + dy * ux
            if r0 <= u <= r1:
                t = (u - r0) / max(0.001, r1 - r0)
                if abs(v) <= w0 * 0.5 * (1.0 - t) + 0.5:
                    self.px[x, y] = cols[min(len(cols) - 1, int(t * len(cols)))]

    def outline(self, col=INK):
        """给不透明区域外沿描 1 像素边(4 邻接)。"""
        add = []
        for y in range(self.s):
            for x in range(self.s):
                if self.px[x, y][3] != 0:
                    continue
                for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + ox, y + oy
                    if 0 <= nx < self.s and 0 <= ny < self.s and self.px[nx, ny][3] != 0 and self.px[nx, ny] != col:
                        add.append((x, y))
                        break
        for x, y in add:
            self.px[x, y] = col

    def opaque(self):
        return sum(1 for y in range(self.s) for x in range(self.s) if self.px[x, y][3])


def sheet(rows):
    """rows: 每行一串 Cell(同尺寸)。"""
    w = rows[0][0].s
    n = len(rows[0])
    s = Image.new("RGBA", (w * n, w * len(rows)), CLEAR)
    for r, row in enumerate(rows):
        for i, f in enumerate(row):
            s.paste(f.im, (i * w, r * w))
    return s


# ═══════════════════════ ① 凝聚(立牌, 32² × 6 帧) ═══════════════════════
# 8 颗光点从外圈拖着尾向内汇聚(帧 0~2), 汇成白热团 + 十字尖芒(帧 3, 团的大小 ≈ 弹体), 团被弹体带走、小环弹开(帧 4), 环碎(帧 5)。
GATHER_N = 8


def _mote(c, ang, r_head, tail, head_col):
    """一颗光点: 2×2 亮头 + 往外拖的尾(越外越暗)。"""
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    hx, hy = c.c + ux * r_head, c.c + uy * r_head
    for i in range(int(tail * 2) + 1, -1, -1):
        r = i * 0.5
        col = MID if r < tail * 0.5 else DEEP
        c.put(round(hx + ux * r), round(hy + uy * r), col)
    for ox, oy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        c.put(int(math.floor(hx)) + ox, int(math.floor(hy)) + oy, head_col if (ox, oy) != (1, 1) else HI)


def gather_frames():
    out = []
    angs = [k * 45.0 + 22.5 + (h2(k, 1, 7) - 0.5) * 18.0 for k in range(GATHER_N)]
    offs = [h2(k, 2, 7) * 2.5 for k in range(GATHER_N)]
    # 帧 0~2: 光点汇聚(越近越快 ⇒ 尾越长), 中心的种子一帧比一帧大
    for f, (rh, tail, seed) in enumerate([(11.2, 2.0, []), (8.0, 4.5, [(2.2, DEEP), (1.2, MID)]),
                                          (4.6, 5.5, [(3.4, DEEP), (2.4, MID), (1.2, HI)])]):
        c = Cell(32)
        c.blob(seed)
        for k in range(GATHER_N):
            _mote(c, angs[k], rh + offs[k] * (1.0 - f * 0.35), tail, HI if f == 0 else CORE)
        out.append(c)
    # 帧 3: 白热团(≈ 弹体大小, 同样一圈 INK 暗边) + 十字长尖芒 + 斜向短尖芒
    c = Cell(32)
    for a in (0.0, 90.0, 180.0, 270.0):
        c.spike(a, 4.0, 14.5, 3.2, [CORE, HI, HI, MID])
    for a in (45.0, 135.0, 225.0, 315.0):
        c.spike(a, 4.0, 9.0, 2.2, [HI, MID])
    c.blob([(6.2, INK), (5.2, DEEP), (4.2, MID), (3.0, HI), (1.8, CORE)])
    out.append(c)
    # 帧 4: 团被弹体带走只剩一点, 小环弹开(两像素粗), 尖芒只剩断头
    c = Cell(32)
    c.ring(7.0, 9.2, MID)
    c.ring(7.0, 8.0, HI)
    c.blob([(1.6, HI)])
    for a in (0.0, 90.0, 180.0, 270.0):
        c.spike(a, 10.5, 14.0, 2.0, [HI, MID])
    out.append(c)
    # 帧 5: 环碎成 8 段弧, 外飘 4 颗散点
    c = Cell(32)
    c.ring(10.2, 11.4, MID, keep=lambda a: (a % 45.0) < 20.0)
    c.ring(10.2, 10.8, DEEP, keep=lambda a: 12.0 <= (a % 45.0) < 20.0)
    for a in (45.0, 135.0, 225.0, 315.0):
        ar = math.radians(a)
        c.put(round(c.c + math.cos(ar) * 13.5), round(c.c + math.sin(ar) * 13.5), DEEP)
    out.append(c)
    return out


# ═══════════════════════ ② 出现印(贴地, 40² × 5 帧) ═══════════════════════
# 末帧外沿半径 = RING_LAST_R 像素 —— 代码按它换算 pixel_size, 外沿 = 气波判定半宽(55 码)。
RING_LAST_R = 18.0


def ring_frames():
    out = []
    # (内半径, 外半径, 外圈色, 内沿色, 断环)
    spec = [
        (2.5, 5.5, HI, CORE, None),
        (8.0, 11.0, MID, HI, None),
        (12.6, 15.0, MID, HI, None),
        (15.8, 17.3, DEEP, MID, lambda a: (a % 30.0) < 20.0),
        (16.6, RING_LAST_R - 1.0, DEEP, DEEP, lambda a: (a % 60.0) < 14.0),
    ]
    for r0, r1, col, inner, keep in spec:
        c = Cell(40)
        c.ring(r0, r1, col, keep=keep)
        c.ring(r0, r0 + 1.0, inner, keep=keep)
        c.outline(INK)
        out.append(c)
    return out


# ═══════════════════════ ③ 锁定(贴地, 88² × 10 帧) ═══════════════════════
# 四角括号(半边长 s) + 4 个朝内的实心箭头(尖端离中心 rc), 箭头在 ±x / ±y 轴上 —— 代码把 +x 转到「施法者 → 目标」方向,
# 于是四个箭头正好指着四道气波来的方向。帧 1~6 箭头逐帧收拢(与气波合拢同步, 时长由代码按 260/380 算),
# 帧 7 括号收紧, 帧 8~9 散掉。不画整圈: 圈会被读成「这里有个范围」(memory fb-vfx-defect-families ④), 这里没有范围。
LOCK_SPEC = [
    # (括号半边长, 箭头尖端半径, 档: 0 常态 / 1 亮 / 2 收紧 / 3 碎 / 4 散点)
    (17, 33, 1),
    (13, 30, 0),
    (13, 27, 0),
    (13, 24, 0),
    (13, 21, 0),
    (13, 18, 0),
    (13, 15, 1),
    (11, 0, 2),
    (14, 0, 3),
    (16, 0, 4),
]
LOCK_ARROW_LEN = 7.0
LOCK_CELL = 88          # 帧 0 箭头尖端 33 + 箭身 7 + 描边 1 = 41 < 43.5(半格), 不出格


def _bracket(c, s, arm, col_out, col_in):
    """四角括号: 每角一个 L, 臂长 arm, 两像素粗(外圈 col_out, 内圈 col_in)。中心在 (c.c, c.c)。"""
    m = int(round(c.c + 0.5))   # 偶数格: 中心在两像素之间(88 格 = 43.5) ⇒ 左上象限从 43 往左, 右下从 44 往右
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx = m + sx * s - (1 if sx < 0 else 0)   # 角点(外)
            cy = m + sy * s - (1 if sy < 0 else 0)
            for i in range(arm):
                for w in (0, 1):
                    col = col_out if w == 0 else col_in
                    c.put(cx - sx * i, cy - sy * w, col)
                    c.put(cx - sx * w, cy - sy * i, col)


def _arrow(c, rc, axis, fill, tip):
    """尖端在轴上半径 rc 处、尖朝中心的实心箭头(带后缘凹口)。axis: 0=+x 1=+y 2=-x 3=-y。"""
    ux, uy = [(1, 0), (0, 1), (-1, 0), (0, -1)][axis]
    L = LOCK_ARROW_LEN
    for x, y, dx, dy in c._each():
        u = dx * ux + dy * uy - rc          # 从尖端往外量
        v = -dx * uy + dy * ux
        if 0.0 <= u <= L and abs(v) <= u * 0.8 + 0.5:
            notch = u - L * 0.5
            if notch > 0.0 and abs(v) < notch * 1.3:
                continue
            c.px[x, y] = tip if u < 2.0 else fill


def lock_frames():
    out = []
    for s, rc, tone in LOCK_SPEC:
        c = Cell(LOCK_CELL)
        if tone in (0, 1):
            _bracket(c, s, 6, HI if tone == 1 else MID, CORE if tone == 1 else HI)
            for ax in range(4):
                _arrow(c, rc, ax, HI if tone == 1 else MID, CORE if tone == 1 else HI)
        elif tone == 2:
            _bracket(c, s, 7, HI, CORE)
        elif tone == 3:
            _bracket(c, s, 3, DEEP, MID)       # 括号只剩四个角尖
        else:
            m = int(round(c.c + 0.5))
            for sx in (-1, 1):
                for sy in (-1, 1):
                    c.put(m + sx * s - (1 if sx < 0 else 0), m + sy * s - (1 if sy < 0 else 0), DEEP)
        c.outline(INK)
        out.append(c)
    return out


# ═══════════════════════ ④ 拖尾(立牌, 16² × 6 帧) ═══════════════════════
def trail_frames():
    out = []
    for f in range(6):
        c = Cell(16)
        if f == 0:
            c.blob([(4.4, DEEP), (3.4, MID), (1.7, HI)])
        elif f == 1:
            c.blob([(3.7, DEEP), (2.6, MID)])
            c.put(7, 7, HI)
            c.put(8, 8, HI)
            for (x, y) in [(4, 7), (11, 9), (7, 4), (9, 11)]:
                c.put(x, y, CLEAR)
        elif f == 2:
            c.blob([(3.0, DEEP), (1.4, MID)])
            for y in range(16):
                for x in range(16):
                    if c.get(x, y)[3] and h2(x, y, 31) < 0.3:
                        c.put(x, y, CLEAR)
        elif f == 3:
            for y in range(16):
                for x in range(16):
                    if math.hypot(x - c.c, y - c.c) <= 2.9 and (x + y) % 2 == 0:
                        c.put(x, y, DEEP)
            c.put(8, 7, MID)
        elif f == 4:
            for (x, y) in [(6, 8), (9, 6), (8, 10)]:
                c.put(x, y, DEEP)
        else:
            c.put(8, 7, DEEP)
        out.append(c)
    return out


# ═══════════════════════ ⑤ 散去(立牌, 16² × 5 帧) ═══════════════════════
def fizzle_frames():
    out = []
    diag = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
    for f in range(5):
        c = Cell(16)
        if f == 0:
            c.blob([(5.2, INK), (4.4, DEEP), (3.4, MID), (1.7, HI)])
            for (dx, dy) in [(1, 0), (0, 1), (-1, 0), (0, -1)]:   # 四道缺口: 气团开始散
                for r in range(2, 7):
                    c.put(round(c.c + dx * r), round(c.c + dy * r), CLEAR)
                    c.put(round(c.c + dx * r + dy), round(c.c + dy * r + dx), CLEAR)
        else:
            r = [0, 3.8, 5.2, 6.2, 7.0][f]
            lift = [0, 0, 1, 2, 3][f]
            for k, (dx, dy) in enumerate(diag):
                x = round(c.c + dx * r * 0.72)
                y = round(c.c + dy * r * 0.72 - lift)
                if f == 1:
                    for (ox, oy) in [(0, 0), (1, 0), (0, 1), (1, 1)]:
                        c.put(x + ox - 1, y + oy - 1, HI if (ox + oy) == 0 else MID)
                elif f == 2:
                    c.put(x, y, MID)
                    c.put(x + (1 if dx > 0 else -1), y, DEEP)
                elif f == 3:
                    c.put(x, y, DEEP)
                elif k % 2 == 0:
                    c.put(x, y, DEEP)
        out.append(c)
    return out


# ═══════════════════════ ⑥ 命中(立牌, 56² × 7 帧 × 2 套变体) ═══════════════════════
# 用户 2026-10-29 看试录问「有命中特效吗」⇒ 必须在 1280×720 下一眼看到: 格子从 40² 放到 56²(同一像素密度, 画面上大 1.4 倍)。
# 一下亮闪(帧 0: 实心白热团 + 八向长尖芒) → 粗冲击环外扩、变细、断开(帧 1~5) + 8 颗碎屑放射并下坠(帧 2~6)。
# 两套变体只差碎屑方向(哈希种子不同) —— 四道同时打在一个人身上时轮流用, 叠出来不是同一张。
HIT_FRAMES = 7
HIT_CELL = 56


def hit_frames(seed):
    out = []
    deb = []
    for k in range(8):
        a = k * 45.0 + 8.0 + h2(k, seed, 3) * 30.0
        sp = 0.85 + h2(k, seed, 5) * 0.35
        deb.append((a, sp))
    for f in range(HIT_FRAMES):
        c = Cell(HIT_CELL)
        if f == 0:
            for a in (45.0, 135.0, 225.0, 315.0):
                c.spike(a, 6.0, 26.5, 6.0, [CORE, CORE, HI, MID])
            for a in (0.0, 90.0, 180.0, 270.0):
                c.spike(a, 6.0, 17.5, 4.6, [CORE, HI, MID])
            c.blob([(9.6, MID), (8.4, HI), (6.8, CORE)])
        elif f == 1:
            c.ring(5.4, 12.8, MID)
            c.ring(5.4, 11.2, HI)
            c.ring(5.4, 8.8, CORE)
            for a in (45.0, 135.0, 225.0, 315.0):
                c.spike(a, 13.6, 21.5, 3.6, [HI, MID])
            for a in (0.0, 90.0, 180.0, 270.0):
                c.spike(a, 13.6, 17.0, 2.4, [MID])
        elif f == 2:
            c.ring(11.6, 16.6, MID)
            c.ring(11.6, 14.4, HI)
            c.ring(11.6, 12.6, CORE)
        elif f == 3:
            k3 = lambda a: (a % 90.0) < 72.0
            c.ring(15.8, 19.6, DEEP, keep=k3)
            c.ring(15.8, 18.4, MID, keep=k3)
            c.ring(15.8, 16.8, HI, keep=k3)
        elif f == 4:
            c.ring(19.4, 21.6, MID, keep=lambda a: (a % 45.0) < 24.0)
            c.ring(19.4, 20.4, DEEP, keep=lambda a: 16.0 <= (a % 45.0) < 24.0)
        elif f == 5:
            c.ring(21.0, 22.6, DEEP, keep=lambda a: (a % 90.0) < 14.0)
        # 碎屑: 放射 + 下坠(纹理 y 向下 = 画面向下)
        if f >= 2:
            dist = [0, 0, 18.0, 21.5, 24.0, 25.4, 26.2][f]
            drop = [0, 0, 0, 1, 3, 6, 9][f]
            for k, (a, sp) in enumerate(deb):
                if f == 6 and k % 3 != 0:
                    continue
                if f == 5 and k % 2 == 1:
                    continue
                ar = math.radians(a)
                x = round(c.c + math.cos(ar) * dist * min(1.0, sp))
                y = round(c.c + math.sin(ar) * dist * min(1.0, sp) + drop)
                if f <= 3:
                    for (ox, oy) in ((0, 0), (1, 0), (0, 1), (1, 1)):
                        col = (CORE if f == 2 else HI) if (ox, oy) == (0, 0) else (HI if f == 2 else MID)
                        c.put(x + ox, y + oy, col)
                    c.put(round(x - math.cos(ar) * 2.0), round(y - math.sin(ar) * 2.0), MID if f == 2 else DEEP)
                else:
                    c.put(x, y, MID if f == 4 else DEEP)
                    c.put(x + 1, y, DEEP)
        out.append(c)
    return out


# ═══════════════════════ ⑦ 有方向的气波弹体(非立牌, 40×20 × 6 帧循环, 机头朝 +X) ═══════════════════════
# 用户 2026-10-29 看试录:「气波做的不行，得动态的、有方向的气波」⇒ 弹体改成追踪目标、按飞行方向转(同远程小将导弹 rocket-missile)。
# 形状: 前端一道弯月形冲击波(外沿白热 → 亮青 → 青, 两角收尖) + 月弯里拖出一条渐细的气焰尾(亮 → 暗, 边缘逐帧抖动) + 尾后 3 颗往后飘的火星。
# 动起来靠: 月牙外沿逐帧胀缩(呼吸) / 尾焰边缘逐帧换哈希 / 火星逐帧往后挪 —— 6 帧循环无跳帧。描一圈 INK(和旧弹体一样压得住亮地面)。
WD_W, WD_H = 40, 20
WD_FRAMES = 6


def _wd_cell():
    c = Cell(WD_W)          # Cell 是正方形; 只用上面 WD_H 行, 出图时裁掉
    c.cy = (WD_H - 1) / 2.0
    return c


def wave_dir_frames():
    out = []
    pulse = [0.0, 0.35, 0.6, 0.35, 0.0, -0.25]
    for f in range(WD_FRAMES):
        c = _wd_cell()
        cy = c.cy
        # 尾焰: x 从 2 到 25, 半宽由 0.4 张到 5(贴着月弯最粗, 像从冲击波里喷出来的), 上下边缘各自按帧抖(火焰感)
        for x in range(2, 26):
            t = (x - 2) / 23.0
            base = 0.4 + 4.6 * (t ** 1.7)
            hw_up = base + (h2(x, f, 11) - 0.5) * 1.6
            hw_dn = base + (h2(x, f, 13) - 0.5) * 1.6
            for y in range(WD_H):
                dy = y - cy
                hw = hw_up if dy < 0 else hw_dn
                if abs(dy) <= hw:
                    if x >= 21:
                        col = HI if abs(dy) <= hw * 0.5 else MID
                    elif x >= 12:
                        col = MID if abs(dy) <= hw * 0.5 else DEEP
                    else:
                        col = DEEP if abs(dy) <= hw * 0.7 or h2(x, y, f + 17) < 0.5 else CLEAR
                    c.put(x, y, col)
        # 弯月冲击波: 外圆(圆心 25, 半径 8.2 + 呼吸) 减去 偏后的内圆(圆心 21.6, 半径 8.0)
        ro = 8.2 + pulse[f]
        for y in range(WD_H):
            for x in range(WD_W):
                do = math.hypot(x - 25.0, y - cy)
                di = math.hypot(x - 21.6, y - cy)
                if do <= ro and di > 8.0:
                    edge = ro - do
                    if abs(y - cy) > ro * 0.78:
                        col = MID              # 两角收尖处暗一档
                    elif edge < 1.0:
                        col = CORE             # 前沿白热
                    elif edge < 2.2:
                        col = HI
                    else:
                        col = MID
                    c.put(x, y, col)
        # 月弯里的亮芯(气团的「头」)
        for (x, y) in [(27, int(cy)), (27, int(cy) + 1), (28, int(cy)), (28, int(cy) + 1), (26, int(cy)), (26, int(cy) + 1)]:
            c.put(x, y, CORE if x >= 27 else HI)
        # 尾后火星: 3 颗, 每帧往后挪 3 像素, 循环
        for j in range(3):
            x = 16 - ((f * 3 + j * 6) % 16)
            y = int(round(cy + [-3.0, 2.0, -1.0][j] + (0.5 if (f + j) % 2 else -0.5)))
            c.put(x, y, HI if j == 0 else MID)
        c.outline(INK)
        out.append(c)
    return out


def wave_dir_sheet():
    frames = wave_dir_frames()
    s = Image.new("RGBA", (WD_W * WD_FRAMES, WD_H), CLEAR)
    for i, f in enumerate(frames):
        s.paste(f.im.crop((0, 0, WD_W, WD_H)), (i * WD_W, 0))
    return s


SHEETS = {
    "reserve-gather.png": lambda: sheet([gather_frames()]),
    "reserve-ring.png": lambda: sheet([ring_frames()]),
    "reserve-lock.png": lambda: sheet([lock_frames()]),
    "reserve-trail.png": lambda: sheet([trail_frames()]),
    "reserve-fizzle.png": lambda: sheet([fizzle_frames()]),
    "reserve-hit.png": lambda: sheet([hit_frames(1), hit_frames(2)]),
    "reserve-wave-dir.png": wave_dir_sheet,
}

def _png_bytes(im):
    bio = io.BytesIO()
    im.save(bio, "PNG", optimize=False)
    return bio.getvalue()


def build():
    out = {}
    for name, fn in SHEETS.items():
        im = fn()
        alphas = set(im.getchannel("A").tobytes())
        assert alphas <= {0, 255}, "%s 有半透明像素 %s" % (name, sorted(alphas - {0, 255}))
        raw = im.tobytes()
        cols = set(raw[i:i + 3] for i in range(0, len(raw), 4) if raw[i + 3] == 255)
        assert len(cols) <= 6, "%s 色数 %d" % (name, len(cols))
        data = _png_bytes(im)
        path = os.path.join(OUT, name)
        if not (os.path.exists(path) and open(path, "rb").read() == data):
            with open(path, "wb") as fh:
                fh.write(data)
        out[name] = im
        print("ok %-20s %dx%d  %d 色  零半透明" % (name, im.width, im.height, len(cols)))
    return out


def preview(ims, outdir):
    """放大接触印相: 每张表放大 6 倍, 铺在深灰 / 沙地两种底上(看暗底、亮底都读不读得出)。"""
    os.makedirs(outdir, exist_ok=True)
    Z = 6
    for bgname, bg in (("dark", (40, 44, 52, 255)), ("sand", (196, 170, 120, 255))):
        rows = []
        for name, im in ims.items():
            big = im.resize((im.width * Z, im.height * Z), Image.NEAREST)
            canvas = Image.new("RGBA", big.size, bg)
            canvas.alpha_composite(big)
            rows.append(canvas)
        W = max(r.width for r in rows)
        H = sum(r.height + 12 for r in rows)
        sh = Image.new("RGBA", (W, H), (20, 20, 24, 255))
        y = 0
        for r in rows:
            sh.paste(r, (0, y))
            y += r.height + 12
        sh.save(os.path.join(outdir, "reserve-vfx-contact-%s.png" % bgname))
    print("preview →", outdir)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    ims = build()
    if a.preview:
        preview(ims, a.preview)
