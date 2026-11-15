# -*- coding: utf-8 -*-
"""tools/assetgen/paint_candy_fx.py —— 糖果龟特效里引擎叠加发光用的两张灰度小图(2026-11-15)。

糖果龟普攻【横扫大锤】/ 技能【糖果锤】的主体是 Blender 渲的序列帧(tools/assetgen/blender_candy_fx.py → build_candy_sheets.py);
序列帧画不出叠加发光, 命中 / 落地那一下的亮芯在引擎里用这两张图叠加:
  candy-glow.png     32×32  软光晕(灰度)   ↔ 咖啡甜心 ba_glow_02 / q_mis_ground_hit2_glow
  candy-star.png     32×32  四芒星闪(灰度) ↔ 咖啡甜心 flash2 / q_hit_01
  candy-swirl.png    128×32 = 4 帧  糖果锤锤头能量漩涡(灰度, 每帧转 45°; 用户 11-15「锤子能不能加什么那种特效发光…这一股能量砸下去」)
做法(如实, 不是手画): 形状由我定的笔路决定, 脚本用软笔刷沿路径盖章。颜色在引擎里上。重跑逐字节相同。
(第一版的风车闪光 / 碎屑 / 圆环 / 放射线 / 判定框 / 糖浆渍 / 烟团是平面小图, 用户 11-15「像一个图片贴在那儿」, 已删。)
"""
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx")

RED = (0.73, 0.25, 0.29)        # #ba4149 锤头薄荷红
RED_HI = (0.90, 0.38, 0.42)
CREAM = (0.97, 0.94, 0.89)      # #e4dbd0 提亮
PINK = (0.86, 0.56, 0.60)       # #dc909a 身体粉
PINK_HI = (1.0, 0.80, 0.84)
PINK_DK = (0.64, 0.34, 0.48)    # #a4567b
BLUE = (0.62, 0.84, 0.95)
BLUE_HI = (0.90, 0.97, 1.0)
YEL = (1.0, 0.88, 0.55)
WHITE = (1.0, 1.0, 1.0)


class Canvas:
	"""RGB + A 软笔刷画布。盖章 = 按覆盖率把颜色往笔色拉(同 paint_tide_fx 的灰度版)。"""

	def __init__(s, w, h):
		s.w, s.h = w, h
		s.c = [(0.0, 0.0, 0.0)] * (w * h)
		s.a = [0.0] * (w * h)

	def dab(s, cx, cy, r, col, alpha=1.0, hard=0.0, ox=0, oy=0, cw=None, ch=None):
		cw = s.w if cw is None else cw
		ch = s.h if ch is None else ch
		x0, x1 = int(math.floor(cx - r - 1)), int(math.ceil(cx + r + 1))
		y0, y1 = int(math.floor(cy - r - 1)), int(math.ceil(cy + r + 1))
		for y in range(max(0, y0), min(ch - 1, y1) + 1):
			for x in range(max(0, x0), min(cw - 1, x1) + 1):
				d = math.hypot(x + 0.5 - cx, y + 0.5 - cy) / max(0.35, r)
				if d >= 1.0:
					continue
				f = 1.0 if d <= hard else (1.0 - (d - hard) / (1.0 - hard))
				f = f * f * (3 - 2 * f)
				s._over((y + oy) * s.w + (x + ox), col, f * alpha)

	def _over(s, i, col, k):
		## 「叠在上面」合成(颜料盖在已有颜色上, 不透明度 k): 透明处直接取笔色, 不从黑色混起
		a0 = s.a[i]
		a1 = a0 + (1.0 - a0) * k
		if a1 <= 1e-6:
			return
		c0 = s.c[i]
		w0 = a0 * (1.0 - k) / a1
		w1 = k / a1
		s.c[i] = (c0[0] * w0 + col[0] * w1, c0[1] * w0 + col[1] * w1, c0[2] * w0 + col[2] * w1)
		s.a[i] = a1

	def stroke(s, pts, r0, r1, col, alpha=1.0, hard=0.0, **cell):
		r1 = r0 if r1 is None else r1
		segs = list(zip(pts[:-1], pts[1:]))
		total = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in segs) or 1.0
		run = 0.0
		for a, b in segs:
			L = math.hypot(b[0] - a[0], b[1] - a[1])
			n = max(1, int(L / 0.5))
			for k in range(n + 1):
				q = k / n
				r = r0 + (r1 - r0) * ((run + L * q) / total)
				s.dab(a[0] + (b[0] - a[0]) * q, a[1] + (b[1] - a[1]) * q, r, col, alpha * 0.55, hard, **cell)
			run += L

	def fill_poly(s, pts, col, alpha=1.0, ox=0, oy=0, feather=0.8):
		"""凸 / 凹多边形实心填色(扫描线 + 边缘按距离羽化 feather 像素)。"""
		xs = [p[0] for p in pts]
		ys = [p[1] for p in pts]
		for y in range(int(math.floor(min(ys))) - 1, int(math.ceil(max(ys))) + 2):
			for x in range(int(math.floor(min(xs))) - 1, int(math.ceil(max(xs))) + 2):
				px, py = x + 0.5, y + 0.5
				inside = _in_poly(px, py, pts)
				dist = _dist_poly(px, py, pts)
				if inside:
					k = min(1.0, 0.5 + dist / max(0.01, feather) * 0.5)
				else:
					k = max(0.0, 0.5 - dist / max(0.01, feather) * 0.5)
				if k <= 0.0:
					continue
				X, Y = x + ox, y + oy
				if not (0 <= X < s.w and 0 <= Y < s.h):
					continue
				s._over(Y * s.w + X, col, k * alpha)

	def save(s, name, gray=False):
		im = Image.new("RGBA", (s.w, s.h))
		px = im.load()
		for y in range(s.h):
			for x in range(s.w):
				i = y * s.w + x
				c = s.c[i]
				if gray:
					g = int(round(max(0.0, min(1.0, c[0])) * 255))
					rgb = (g, g, g)
				else:
					rgb = tuple(int(round(max(0.0, min(1.0, v)) * 255)) for v in c)
				px[x, y] = rgb + (int(round(max(0.0, min(1.0, s.a[i])) * 255)),)
		p = os.path.join(OUT, name)
		im.save(p, optimize=False)
		print("ok", p, im.size)


def _in_poly(x, y, pts):
	inside = False
	n = len(pts)
	j = n - 1
	for i in range(n):
		xi, yi = pts[i]
		xj, yj = pts[j]
		if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-9) + xi:
			inside = not inside
		j = i
	return inside


def _dist_poly(x, y, pts):
	best = 1e9
	n = len(pts)
	for i in range(n):
		ax, ay = pts[i]
		bx, by = pts[(i + 1) % n]
		dx, dy = bx - ax, by - ay
		L2 = dx * dx + dy * dy or 1e-9
		t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / L2))
		best = min(best, math.hypot(x - (ax + dx * t), y - (ay + dy * t)))
	return best


def _rot(pts, cx, cy, ang):
	ca, sa = math.cos(ang), math.sin(ang)
	return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for (x, y) in pts]


# ─────────────────────────────────────────────────────────────────────────────
#  糖浆渍 2×2(每格 32, 贴地): 一摊主糖浆(不规则圆, 边上 5~7 个鼓包) + 外溅小滴 + 一道白高光。
#  四格鼓包位置 / 小滴方向各不同(我逐个定的角度表)。
# ─────────────────────────────────────────────────────────────────────────────


# ─────────────────────────────────────────────────────────────────────────────
#  软光晕(灰度): 一笔 15 像素全软大圆 + 一笔 6 像素亮芯。
# ─────────────────────────────────────────────────────────────────────────────
def glow():
	c = Canvas(32, 32)
	c.dab(16, 16, 15.5, (0.85, 0.85, 0.85), 0.9, 0.0)
	c.dab(16, 16, 9.0, WHITE, 0.8, 0.0)
	c.dab(16, 16, 4.5, WHITE, 1.0, 0.2)
	c.save("candy-glow.png", gray=True)


# ─────────────────────────────────────────────────────────────────────────────
#  四芒星闪(灰度): 上下左右 4 根长芒(从中心往外由粗到尖)+ 4 根斜向短芒 + 亮芯。
# ─────────────────────────────────────────────────────────────────────────────
def star():
	c = Canvas(32, 32)
	for (dx, dy, L) in ((0, -1, 14.5), (0, 1, 14.5), (-1, 0, 14.5), (1, 0, 14.5)):
		c.stroke([(16, 16), (16 + dx * L * 0.5, 16 + dy * L * 0.5), (16 + dx * L, 16 + dy * L)], 2.4, 0.3, WHITE, 1.0, 0.4)
	for (dx, dy) in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
		c.stroke([(16, 16), (16 + dx * 6.5, 16 + dy * 6.5)], 1.4, 0.3, WHITE, 0.85, 0.4)
	c.dab(16, 16, 5.0, WHITE, 0.9, 0.0)
	c.dab(16, 16, 2.4, WHITE, 1.0, 0.6)
	c.save("candy-star.png", gray=True)


# ─────────────────────────────────────────────────────────────────────────────
#  糖粉烟团 2 格(灰度): 左格 = 5 个圆鼓包叠成一团(上亮下暗, 像奶油 / 糖粉往上鼓);
#  右格 = 扁一点、散一点的 6 个小鼓包(落地扬起的那种)。各撒几粒亮点(糖晶反光)。
# ─────────────────────────────────────────────────────────────────────────────
PUFF_GRAINS = [[(12, 9), (24, 12), (18, 6)], [(40, 14), (56, 15), (49, 10)]]


# ─────────────────────────────────────────────────────────────────────────────
#  糖果锤锤头能量漩涡 4 帧(灰度, 每帧 32×32): 两条从中心往外旋的软笔画(对数螺线取点)+ 亮芯;
#  每帧整体转 45°(两条臂 180° 对称 ⇒ 4 帧转满一圈的一半, 循环起来就是一直在转)。叠加发光用, 颜色在引擎里上。
# ─────────────────────────────────────────────────────────────────────────────
def swirl():
	c = Canvas(128, 32)
	for k in range(4):
		ox = k * 32 + 16.0
		spin = math.radians(45.0 * k)
		for arm in range(2):
			a0 = spin + math.pi * arm
			pts = []
			for j in range(16):
				t = j / 15.0
				r = 2.0 + t * 11.5
				a = a0 + t * 2.4
				pts.append((ox + r * math.cos(a), 16.0 + r * math.sin(a)))
			c.stroke(pts, 2.6, 0.6, (0.85, 0.85, 0.85), 0.85, 0.2)
			c.stroke(pts[:9], 1.2, 0.5, WHITE, 0.9, 0.4)
		c.dab(ox, 16.0, 5.0, WHITE, 0.9, 0.1)
		c.dab(ox, 16.0, 2.2, WHITE, 1.0, 0.6)
	c.save("candy-swirl.png", gray=True)


if __name__ == "__main__":
	glow()
	star()
	swirl()
