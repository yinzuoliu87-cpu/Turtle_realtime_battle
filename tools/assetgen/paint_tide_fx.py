# -*- coding: utf-8 -*-
"""tools/assetgen/paint_tide_fx.py —— 043 海浪护符第三版特效贴图(2026-11-14, 照娜美大招配方分层)。

做法(如实): 每一笔的路径(点坐标)是我逐条定的, 写在下面; 脚本用**软笔刷沿路径盖章**(像 Photoshop 软笔刷),
圆形气泡用 `circle()` 取点(相当于椭圆工具)。全是灰度图(RGB = 亮度, A = 覆盖), 颜色在引擎里上 —— 同娜美配方。
11-14 用户同意: 特效可以柔边 / 半透明 / 叠加发光(龟、界面、地图仍是像素硬边)。
  tide-streak.png   64×64 无缝  浪身流动水纹(底灰 + 亮暗水纹)          ↔ 娜美 R_WaterAdd
  tide-caustic.png  64×64 无缝  浪身叠加发光的焦散网纹                 ↔ AberraticCaustic
  tide-edge.png     64×24 横向无缝 浪前沿: 亮带 + 往上甩的水刺 + 水珠  ↔ R_Water02
  tide-foam.png     32×32       泡沫团(往后飘、变大、变淡)              ↔ common_smoke_02
  tide-mist.png     16×48       往上冒的水雾刺                          ↔ common_waterspike32
  tide-crescent.png 64×64 = 2×2 浪身上的小卷浪 4 帧                     ↔ R_WaterCrescent_2x2
  tide-glow.png     32×32       软光晕(打中 / 起手)                     ↔ Cirlcle_01
  tide-star.png     32×32       星形闪光(打中 0.2 秒)                   ↔ Flare-Omnimax
  tide-bubble.png   64×64 = 2×2 气泡 4 个                               ↔ R_Bubble01
  tide-dropsoft.png 32×32 = 2×2 软水珠 4 个                             ↔ BlurDrops
重跑逐字节相同。
"""
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx")


class Canvas:
	def __init__(s, w, h, base_v=0.0, base_a=0.0, wrap_x=False, wrap_y=False):
		s.w, s.h = w, h
		s.v = [base_v] * (w * h)
		s.a = [base_a] * (w * h)
		s.wx, s.wy = wrap_x, wrap_y

	def _dab1(s, cx, cy, r, val, alpha, hard):
		x0, x1 = int(math.floor(cx - r - 1)), int(math.ceil(cx + r + 1))
		y0, y1 = int(math.floor(cy - r - 1)), int(math.ceil(cy + r + 1))
		for y in range(y0, y1 + 1):
			if not (0 <= y < s.h):
				continue
			for x in range(x0, x1 + 1):
				if not (0 <= x < s.w):
					continue
				d = math.hypot(x + 0.5 - cx, y + 0.5 - cy) / max(0.35, r)
				if d >= 1.0:
					continue
				f = 1.0 if d <= hard else (1.0 - (d - hard) / (1.0 - hard))
				f = f * f * (3 - 2 * f)
				k = f * alpha
				i = y * s.w + x
				s.v[i] = s.v[i] + (val - s.v[i]) * k
				s.a[i] = s.a[i] + (1.0 - s.a[i]) * k

	def dab(s, cx, cy, r, val=1.0, alpha=1.0, hard=0.0):
		xs = [cx] + ([cx - s.w, cx + s.w] if s.wx else [])
		ys = [cy] + ([cy - s.h, cy + s.h] if s.wy else [])
		for x in xs:
			for y in ys:
				s._dab1(x, y, r, val, alpha, hard)

	def stroke(s, pts, r0, r1=None, val=1.0, alpha=1.0, hard=0.0):
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
				s.dab(a[0] + (b[0] - a[0]) * q, a[1] + (b[1] - a[1]) * q, r, val, alpha * 0.55, hard)
			run += L

	def save(s, name):
		im = Image.new("RGBA", (s.w, s.h))
		px = im.load()
		for y in range(s.h):
			for x in range(s.w):
				i = y * s.w + x
				g = int(round(max(0.0, min(1.0, s.v[i])) * 255))
				px[x, y] = (g, g, g, int(round(max(0.0, min(1.0, s.a[i])) * 255)))
		p = os.path.join(OUT, name)
		im.save(p, optimize=False)
		print("ok", p, im.size)


def circle(cx, cy, r, n=16):
	return [(cx + r * math.cos(2 * math.pi * k / n), cy + r * math.sin(2 * math.pi * k / n)) for k in range(n + 1)]


def streak():
	c = Canvas(64, 64, 0.42, 1.0, True, True)
	for pts, r0, r1, val, al in [
		([(4, 0), (6, 10), (3, 22), (5, 34), (8, 46), (5, 58), (4, 64)], 2.2, 1.4, 0.95, 0.7),
		([(10, 0), (11, 12), (13, 24), (11, 36), (9, 48), (11, 60), (10, 64)], 2.8, 2.8, 0.18, 0.45),
		([(17, 0), (15, 9), (18, 20), (21, 31), (19, 43), (16, 55), (17, 64)], 1.6, 1.6, 1.0, 0.8),
		([(27, 0), (29, 13), (26, 27), (28, 40), (31, 52), (27, 64)], 3.0, 2.0, 0.85, 0.6),
		([(35, 0), (33, 11), (35, 25), (37, 38), (35, 50), (35, 64)], 2.5, 2.5, 0.2, 0.45),
		([(42, 0), (44, 10), (46, 22), (43, 35), (41, 47), (44, 57), (42, 64)], 1.4, 1.4, 1.0, 0.85),
		([(52, 0), (50, 14), (53, 26), (55, 39), (52, 51), (52, 64)], 2.4, 1.6, 0.9, 0.65),
		([(59, 0), (60, 12), (58, 25), (57, 37), (60, 50), (59, 64)], 2.2, 2.2, 0.15, 0.4),
	]:
		c.stroke(pts, r0, r1, val, al, 0.2)
	for pts in ([(20, 30), (21, 36)], [(44, 12), (45, 17)], [(6, 48), (7, 53)], [(28, 41), (29, 45)]):
		c.stroke(pts, 1.0, 0.6, 1.0, 1.0, 0.5)
	c.save("tide-streak.png")


def caustic():
	c = Canvas(64, 64, 0.0, 0.0, True, True)
	lines = [
		[(0, 8), (10, 5), (20, 10), (28, 6), (40, 9), (52, 4), (64, 8)],
		[(0, 30), (9, 26), (18, 31), (30, 27), (39, 33), (50, 28), (64, 30)],
		[(0, 50), (12, 47), (22, 52), (33, 48), (44, 53), (55, 49), (64, 50)],
		[(10, 5), (8, 16), (9, 26)], [(28, 6), (31, 17), (30, 27)], [(52, 4), (49, 16), (50, 28)],
		[(18, 31), (15, 40), (12, 47)], [(39, 33), (41, 42), (44, 53)], [(57, 29), (59, 39), (55, 49)],
		[(22, 52), (21, 58), (20, 64)], [(20, 0), (20, 10)], [(44, 53), (46, 59), (45, 64)], [(45, 0), (40, 9)],
	]
	for i, pts in enumerate(lines):
		c.stroke(pts, 1.3 if i % 3 == 0 else 0.9, None, 1.0, 0.85, 0.45)
	for (x, y) in [(10, 5), (30, 27), (44, 53), (18, 31), (52, 4)]:
		c.dab(x, y, 1.8, 1.0, 0.9, 0.3)
	c.save("tide-caustic.png")


def edge():
	c = Canvas(64, 24, 0.0, 0.0, True, False)
	c.stroke([(0, 20), (64, 20)], 3.6, None, 0.8, 1.0, 0.6)
	c.stroke([(0, 16.5), (64, 16.5)], 1.3, None, 1.0, 1.0, 0.5)
	for a, b in [((5, 17), (4, 9)), ((13, 17), (15, 6)), ((22, 17), (21, 11)), ((30, 17), (33, 3)),
	             ((39, 17), (38, 10)), ((47, 17), (49, 7)), ((56, 17), (55, 12)), ((62, 17), (63, 9))]:
		c.stroke([a, b], 2.2, 0.6, 1.0, 0.95, 0.4)
	for (x, y, r) in [(15, 2, 1.2), (34, 0.8, 1.0), (49, 2.5, 1.1), (8, 5, 0.9), (26, 6, 0.9), (58, 5, 1.0)]:
		c.dab(x, y, r, 1.0, 1.0, 0.4)
	c.save("tide-edge.png")


def foam():
	c = Canvas(32, 32)
	for (x, y, r, v, a) in [(12, 16, 8, 0.95, 1.0), (19, 13, 7, 1.0, 1.0), (21, 21, 6, 0.9, 0.9),
	                        (8, 22, 5, 0.85, 0.8), (16, 8, 5, 1.0, 0.8), (26, 15, 4, 1.0, 0.7)]:
		c.dab(x, y, r, v, a, 0.25)
	c.save("tide-foam.png")


def mist():
	c = Canvas(16, 48)
	c.stroke([(8, 46), (8, 24), (7, 4)], 5.0, 0.7, 1.0, 0.55, 0.0)
	c.stroke([(8, 44), (8, 12)], 1.5, 0.6, 1.0, 0.6, 0.2)
	c.save("tide-mist.png")


def crescent():
	c = Canvas(64, 64)
	cells = [
		[([(8, 22), (12, 17), (16, 15)], 0.6, 2.0, 1.0), ([(16, 15), (20, 17), (24, 22)], 2.0, 0.6, 1.0)],
		[([(5, 24), (10, 16), (16, 12)], 0.6, 2.6, 1.0), ([(16, 12), (22, 16), (27, 24)], 2.6, 0.6, 1.0), ([(16, 9), (16, 9)], 1.0, 1.0, 1.0)],
		[([(5, 24), (12, 15)], 0.6, 2.4, 1.0), ([(19, 13), (27, 22)], 2.2, 0.6, 1.0), ([(15, 10), (15, 10)], 1.0, 1.0, 1.0), ([(20, 8), (20, 8)], 1.0, 1.0, 1.0)],
		[([(6, 25), (11, 19)], 0.5, 1.2, 0.6), ([(21, 18), (26, 24)], 1.2, 0.5, 0.6), ([(16, 14), (16, 14)], 0.8, 0.8, 0.5)],
	]
	for k, strokes in enumerate(cells):
		ox, oy = (k % 2) * 32, (k // 2) * 32
		for pts, r0, r1, al in strokes:
			c.stroke([(x + ox, y + oy) for x, y in pts], r0, r1, 1.0, al, 0.3)
	c.save("tide-crescent.png")


def glow():
	c = Canvas(32, 32)
	c.dab(16, 16, 15, 0.85, 1.0, 0.0)
	c.dab(16, 16, 6, 1.0, 1.0, 0.3)
	c.save("tide-glow.png")


def star():
	c = Canvas(32, 32)
	for e in [(16, 1), (16, 31), (1, 16), (31, 16)]:
		c.stroke([(16, 16), e], 1.8, 0.3, 1.0, 1.0, 0.4)
	for e in [(7, 7), (25, 25), (25, 7), (7, 25)]:
		c.stroke([(16, 16), e], 1.2, 0.3, 1.0, 0.9, 0.4)
	c.dab(16, 16, 3.5, 1.0, 1.0, 0.4)
	c.save("tide-star.png")


def bubble():
	c = Canvas(64, 64)
	for k, R in enumerate([9, 11, 7, 12]):
		cx, cy = (k % 2) * 32 + 16, (k // 2) * 32 + 16
		c.dab(cx, cy, R * 0.85, 0.8, 0.15, 0.0)
		c.stroke(circle(cx, cy, R), 0.8, None, 1.0, 0.85, 0.5)
		c.dab(cx - R * 0.4, cy - R * 0.45, 1.6, 1.0, 1.0, 0.5)
	c.save("tide-bubble.png")


def dropsoft():
	c = Canvas(32, 32)
	for k, (a, b, rr) in enumerate([((8, 2), (8, 10), 3.0), ((4, 3), (9, 10), 2.6), ((12, 3), (7, 10), 2.6), ((8, 6), (8, 11), 2.0)]):
		ox, oy = (k % 2) * 16, (k // 2) * 16
		c.stroke([(a[0] + ox, a[1] + oy), (b[0] + ox, b[1] + oy)], 0.4, rr, 0.9, 0.9, 0.3)
		c.dab(b[0] + ox, b[1] + oy, rr, 0.9, 0.9, 0.3)
		c.dab(b[0] + ox - 1, b[1] + oy - 1.5, 0.8, 1.0, 1.0, 0.5)
	c.save("tide-dropsoft.png")


if __name__ == "__main__":
	streak(); caustic(); edge(); foam(); mist(); crescent(); glow(); star(); bubble(); dropsoft()
