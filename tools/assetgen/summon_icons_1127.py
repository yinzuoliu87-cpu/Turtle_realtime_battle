# -*- coding: utf-8 -*-
"""summon_icons_1127.py —— 图鉴「角色」栏召唤物的被动 / 攻击 / 技能图标(64×64 硬边像素画, 透明底, 深色描边; 同现有 skills/ passive/ 图标规格)。

参考研究 docs/studies/20261127-参考-召唤物技能图标.md(潘森 / 黑默丁格技能图标: 光源 + 亮边、背后光、一个最亮焦点、大块动势特效、占满)。
第三版(用户 11-27「你自己看你跟参考的差距有多大嘛，然后你去多多设计好」): 三件通用手法 ——
  ① 背后发光 halo(): 本体轮廓往外扩 2~3 圈硬边光晕 + 放射光块(参考里「背后整片光」, 我们是透明底单物件所以只做轮廓光);
  ② 亮边 rim(): 本体靠左上光源一侧边缘提亮、右下压暗(立体感);
  ③ 焦点 sparkle(): 每张一个最亮的四角星闪点。
做法(如实): 逐像素按几何判层上色(背后光 / 本体 / 描边 / 前景特效), 分层 PNG 由 tools/assetgen/ase/png_layers_to_ase.lua 拼成 .aseprite。
不是逐笔手画, 也不是 AI 生成。不用随机数, 重跑逐字节相同。颜色从角色立绘取(百夫长 eq-centurion-idle / 炮台 pets/turret)。
用法: python tools/assetgen/summon_icons_1127.py [输出目录]   (默认 .out/summon_icons/; 成品拷到 assets/sprites/skills/ 或 passive/)
"""
import math, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".out", "summon_icons")
N = 64


def hx(s):
	s = s.lstrip("#")
	return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


def mix(a, b, t):
	return (round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t), round(a[2] + (b[2] - a[2]) * t), 255)


# 百夫长(立绘取色)
RED = [hx(c) for c in ("#ff7a52", "#ee4931", "#d72d21", "#c7221c", "#a2141e", "#840b1f", "#5e0818")]
STEEL = [hx(c) for c in ("#ffffff", "#e3eaf2", "#b9c4d2", "#8794a8", "#5d6880", "#3b4256")]
GOLD = [hx(c) for c in ("#fff2c0", "#ffd36a", "#e0a03c", "#c1812f", "#8a4a18", "#5a2a0e")]
WOOD = [hx(c) for c in ("#c47a36", "#8f4a22", "#6a3418", "#45200e")]
EARTH = [hx(c) for c in ("#b88a5e", "#8a6040", "#5e3c24", "#3a2214")]
OUTLINE = hx("#160a0c")
WHITE = hx("#ffffff")
# 炮台(立绘取色)
TEAL = [hx(c) for c in ("#c9f5ea", "#8ee0cd", "#53ac9b", "#3c8778", "#1b4644", "#0f2a29")]
GRAY = [hx(c) for c in ("#c6c9d6", "#8a8d9e", "#575969", "#383746", "#22212c")]
CREAM = [hx(c) for c in ("#fff6dc", "#fadfad", "#d8b26a", "#a87c32")]
FIRE = [hx(c) for c in ("#ffffff", "#fff2a8", "#ffc83c", "#ff8a24", "#e8471a", "#a82412")]
SMOKE = [hx(c) for c in ("#9a96a6", "#6c6878", "#47434f")]
ENERGY = [hx(c) for c in ("#ffffff", "#ffc8c0", "#ff6a5a", "#e0242c", "#8c0f1e")]


class Icon:
	"""分层: back(背后光, 不描边) / body(本体, 描边按它) / fx(前景特效, 不描边)。"""

	def __init__(self):
		self.back = Image.new("RGBA", (N, N), (0, 0, 0, 0))
		self.body = Image.new("RGBA", (N, N), (0, 0, 0, 0))
		self.fx = Image.new("RGBA", (N, N), (0, 0, 0, 0))

	def put(self, layer, x, y, c):
		x, y = int(round(x)), int(round(y))
		if 0 <= x < N and 0 <= y < N:
			getattr(self, layer).putpixel((x, y), c)

	def solid(self):
		return {(x, y) for y in range(N) for x in range(N) if self.body.getpixel((x, y))[3] == 255}

	def rim(self, k_lit=0.38, k_dark=0.28):
		"""亮边: 光从左上来 —— 左 / 上邻是空的那一圈提亮, 右 / 下邻是空的那一圈压暗。"""
		sol = self.solid()
		out = {}
		for (x, y) in sol:
			c = self.body.getpixel((x, y))
			lit = (x - 1, y) not in sol or (x, y - 1) not in sol
			dark = (x + 1, y) not in sol or (x, y + 1) not in sol
			if lit and not dark:
				out[(x, y)] = mix(c, WHITE, k_lit)
			elif dark and not lit:
				out[(x, y)] = mix(c, OUTLINE, k_dark)
		for (x, y), c in out.items():
			self.body.putpixel((x, y), c)

	def halo(self, cols, gap=1):
		"""背后发光: 本体(含前景)轮廓往外扩 len(cols) 圈, 由里到外按 cols 上色; gap = 描边那一圈留出来。"""
		occ = self.solid() | {(x, y) for y in range(N) for x in range(N) if self.fx.getpixel((x, y))[3] == 255}
		dist = {}
		frontier = set(occ)
		seen = set(occ)
		for step in range(1, gap + len(cols) + 1):
			nxt = set()
			for (x, y) in frontier:
				for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
					if q not in seen and 0 <= q[0] < N and 0 <= q[1] < N:
						seen.add(q); nxt.add(q); dist[q] = step
			frontier = nxt
		for (x, y), d in dist.items():
			if d > gap and self.back.getpixel((x, y))[3] == 0:
				self.back.putpixel((x, y), cols[d - gap - 1])

	def finish(self, name):
		sol = self.solid()
		ring = [(x, y) for y in range(N) for x in range(N)
				if (x, y) not in sol and any(q in sol for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))]
		outline = Image.new("RGBA", (N, N), (0, 0, 0, 0))
		for (x, y) in ring:   # 先算完再画(边画边算会让描边自己也算实心)
			outline.putpixel((x, y), OUTLINE)
		comp = Image.new("RGBA", (N, N), (0, 0, 0, 0))
		d = os.path.join(OUT, name)
		os.makedirs(d, exist_ok=True)
		for nm, im in (("back", self.back), ("body", self.body), ("outline", outline), ("fx", self.fx)):
			comp.alpha_composite(im)
			im.save(os.path.join(d, "layer-%s.png" % nm))
		comp.save(os.path.join(d, "%s.png" % name))
		return comp


# ─── 几何小工具 ───
def seg(p, a, b):
	ab = (b[0] - a[0], b[1] - a[1]); ap = (p[0] - a[0], p[1] - a[1])
	L2 = ab[0] ** 2 + ab[1] ** 2
	t = max(0.0, min(1.0, (ap[0] * ab[0] + ap[1] * ab[1]) / L2))
	c = (a[0] + ab[0] * t, a[1] + ab[1] * t)
	return math.hypot(p[0] - c[0], p[1] - c[1]), t, ab[0] * ap[1] - ab[1] * ap[0]


def each(fn):
	for y in range(N):
		for x in range(N):
			fn(x, y, x + 0.5, y + 0.5)


def bline(ic, layer, a, b, c, w=1):
	L = max(1.0, math.hypot(b[0] - a[0], b[1] - a[1]))
	nx, ny = -(b[1] - a[1]) / L, (b[0] - a[0]) / L
	for s in range(int(L * 3) + 1):
		t = s / (L * 3)
		x = a[0] + (b[0] - a[0]) * t; y = a[1] + (b[1] - a[1]) * t
		for j in range(w):
			o = j - (w - 1) / 2.0
			ic.put(layer, x + nx * o, y + ny * o, c)


def disc(ic, layer, cx, cy, r, shade):
	def f(x, y, px, py):
		dx, dy = px - cx, py - cy
		d = math.hypot(dx, dy)
		if d <= r:
			ic.put(layer, x, y, shade(dx, dy, d))
	each(f)


def sparkle(ic, cx, cy, size, cols=(WHITE, GOLD[0], GOLD[1])):
	"""四角星闪点: 十字长臂 + 斜向短臂, 芯白。"""
	cx, cy = int(cx), int(cy)
	for k in range(-size, size + 1):
		c = cols[0] if abs(k) <= 1 else (cols[1] if abs(k) <= size * 0.6 else cols[2])
		ic.put("fx", cx + k, cy, c); ic.put("fx", cx, cy + k, c)
	for k in range(1, max(2, size // 2)):
		for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
			ic.put("fx", cx + sx * k, cy + sy * k, cols[1] if k == 1 else cols[2])


def burst(ic, cx, cy, r0, r1, n, cols, phase=0.0, width=0.18):
	"""放射光块(画在 back): n 道楔形, 根宽梢尖, 由里到外按 cols 上色。"""
	def f(x, y, px, py):
		dx, dy = px - cx, py - cy
		d = math.hypot(dx, dy)
		if d < r0 or d > r1 or ic.back.getpixel((x, y))[3]:
			return
		a = math.atan2(dy, dx) - phase
		k = (a / (2 * math.pi / n)) % 1.0
		half = width * (1.0 - (d - r0) / (r1 - r0)) * 0.5
		if abs(k - 0.5) <= half:
			ic.put("back", x, y, cols[min(len(cols) - 1, int((d - r0) / (r1 - r0) * len(cols)))])
	each(f)


def shaft(ic, a, b, w=1.8):
	def f(x, y, px, py):
		d, t, side = seg((px, py), a, b)
		if d <= w:
			k = 0 if (side < 0 and d > w * 0.4) else (2 if side > 0 and d > w * 0.45 else 1)
			ic.put("body", x, y, WOOD[k])
	each(f)


def blade(ic, base, tip, half_w, fuller=True):
	"""叶形矛头: 亮刃边 / 本体 / 暗面 / 中脊(血槽)。"""
	def f(x, y, px, py):
		d, t, side = seg((px, py), base, tip)
		if t <= 0.0 or t >= 1.0:
			return
		w = half_w * math.sin(math.pi * min(1.0, t * 1.12 + 0.07)) ** 0.7 * (1.0 - 0.5 * t)
		if d > w + 0.4:
			return
		if fuller and d < 0.75 and 0.12 < t < 0.8:
			c = STEEL[4]
		elif d < 1.4:
			c = STEEL[1] if side < 0 else STEEL[2]
		elif side < 0:
			c = STEEL[1] if d > w - 1.0 else STEEL[2]
		else:
			c = STEEL[3] if d < w - 1.0 else STEEL[4]
		ic.put("body", x, y, c)
	each(f)


def tassel(ic, cx, cy, r, tail_dir=None, tail_len=0):
	"""红缨: 一团 + 往 tail_dir 飘的三缕。"""
	disc(ic, "body", cx, cy, r, lambda dx, dy, d: RED[1] if dx + dy < -1 else (RED[3] if d < r * 0.7 else RED[5]))
	if tail_dir:
		tx, ty = tail_dir
		for k, off in enumerate((-1.6, 0.0, 1.6)):
			nx, ny = -ty, tx
			for s in range(tail_len - k * 2):
				wav = math.sin(s * 0.55 + k) * 0.9
				x = cx + tx * s + nx * (off + wav)
				y = cy + ty * s + ny * (off + wav)
				ic.put("body", x, y, RED[2] if s < tail_len * 0.5 else RED[4])


# ─── 1 突刺(攻击): 金色速度光带 + 大矛头(血槽 / 亮刃) + 后飘红缨 + 矛尖焦点(参考潘森 Q) ───
def icon_thrust():
	ic = Icon()
	A, B = (4.0, 60.0), (60.0, 4.0)
	L = math.hypot(B[0] - A[0], B[1] - A[1])
	ux, uy = (B[0] - A[0]) / L, (B[1] - A[1]) / L
	nx, ny = -uy, ux
	## 速度光带: 与矛平行的四道, 越靠矛头越亮
	for off, s0, s1, w in ((-7.0, 18, 44, 3), (7.5, 14, 46, 3), (-12.5, 24, 40, 2), (12.0, 22, 38, 2)):
		for s10 in range(int(s0 * 3), int(s1 * 3)):
			s = s10 / 3.0
			f = (s - s0) / (s1 - s0)
			for j in range(w):
				o = off + (j - (w - 1) / 2.0)
				ic.put("back", A[0] + ux * s + nx * o, A[1] + uy * s + ny * o, GOLD[0] if f > 0.75 else (GOLD[1] if f > 0.4 else GOLD[2]))
	shaft(ic, (5.0, 59.0), (31.0, 33.0), 2.1)
	blade(ic, (28.0, 36.0), (60.0, 4.0), 8.0)
	bline(ic, "body", (24.0, 36.0), (32.0, 44.0), GOLD[2], 3)   # 护手
	tassel(ic, 28.5, 37.5, 3.2, (-ux, -uy), 13)                  # 红缨往矛尾方向飘
	ic.rim()
	ic.halo([GOLD[1], GOLD[2]])
	sparkle(ic, 59, 5, 6)
	return ic.finish("cent-thrust")


# ─── 2 龟甲阵(技能): 背后放射光块 + 厚盾(侧边暗面 / 铆钉 / 翼纹) + 发光盾心(参考潘森 E) ───
def icon_shield():
	ic = Icon()
	cx, cy, hw, hh, rr = 31.0, 33.0, 15.5, 23.5, 5.0
	def inside(x, y, shrink=0.0, dx=0.0):
		qx = max(abs(x - cx - dx) - (hw - shrink - rr), 0.0); qy = max(abs(y - cy) - (hh - shrink - rr), 0.0)
		return math.hypot(qx, qy) <= rr
	burst(ic, cx, cy, 14.0, 31.0, 12, [GOLD[0], GOLD[1], GOLD[2]], phase=math.pi / 12, width=0.34)
	def thick(x, y, px, py):   # 盾的厚度: 右侧往外 3 像素的暗面
		if inside(px, py, 0.0, 3.0) and not inside(px, py):
			ic.put("body", x, y, RED[6] if py > cy - hh + 4 else GOLD[4])
	each(thick)
	def face(x, y, px, py):
		if not inside(px, py):
			return
		if not inside(px, py, 2.4):
			v = (px - cx) + (py - cy)
			ic.put("body", x, y, GOLD[1] if v < -8 else (GOLD[3] if v > 10 else GOLD[2]))
			return
		u = (px - cx) / hw
		k = min(len(RED) - 2, max(1, int((u + 1.0) / 2.0 * 5.0) + 1))
		ic.put("body", x, y, RED[k])
	each(face)
	for sx in (-1, 1):   # 金翼纹(两像素宽的折线, 四向)
		for sy in (-1, 1):
			pts = [(cx + sx * 5, cy + sy * 4), (cx + sx * 10, cy + sy * 9), (cx + sx * 7, cy + sy * 13), (cx + sx * 11, cy + sy * 18)]
			for i in range(len(pts) - 1):
				bline(ic, "body", pts[i], pts[i + 1], GOLD[1] if sy < 0 else GOLD[2], 2)
	for (px, py) in ((cx - 12, cy - 20), (cx, cy - 21), (cx + 12, cy - 20), (cx - 13, cy), (cx + 13, cy), (cx - 12, cy + 20), (cx, cy + 21), (cx + 12, cy + 20)):
		ic.put("body", px, py, GOLD[0])   # 铆钉
	disc(ic, "body", cx, cy, 5.2, lambda dx, dy, d: GOLD[1] if dx + dy < -2 else (GOLD[3] if d > 4.0 else GOLD[2]))
	disc(ic, "body", cx - 0.8, cy - 0.8, 2.2, lambda dx, dy, d: GOLD[0])
	ic.rim(0.30, 0.25)
	ic.halo([GOLD[1], GOLD[2], GOLD[3]])
	sparkle(ic, cx - 1, cy - 1, 5)
	return ic.finish("cent-guard")


# ─── 3 军团天降(被动): 长矛斜着俯冲砸地 + 彗尾火焰(画面内收尖) + 落点爆光 + 冲击环 + 飞石(参考潘森 R) ───
## 地面(土堆 / 裂纹 / 飞石)在光晕之后画 —— 第三版初稿光晕把裂纹包成一堆柴火(11-27 自检)。
def icon_land():
	ic = Icon()
	tip = (42.0, 50.0)
	top = (16.0, 8.0)
	L = math.hypot(tip[0] - top[0], tip[1] - top[1])
	ux, uy = (tip[0] - top[0]) / L, (tip[1] - top[1]) / L
	nx, ny = -uy, ux
	def ring(x, y, px, py):   # 冲击环(扁椭圆两圈)
		e = math.hypot((px - tip[0]) / 24.0, (py - tip[1] - 2) / 7.0)
		if 0.84 <= e <= 1.0:
			ic.put("back", x, y, GOLD[2] if py > tip[1] + 2 else GOLD[1])
		elif 0.52 <= e <= 0.62:
			ic.put("back", x, y, GOLD[1])
	each(ring)
	def trail(x, y, px, py):   # 彗尾: 贴着矛身起, 中段最宽, 末端收尖(全在画面内), 边缘起伏
		rx, ry = px - tip[0], py - tip[1]
		back = -(rx * ux + ry * uy)
		side = rx * nx + ry * ny
		if back < 10.0 or back > 58.0:
			return
		f = (back - 10.0) / 48.0
		w = 9.0 * math.sin(math.pi * min(1.0, f * 1.25 + 0.05)) ** 0.7 * (1.0 - 0.35 * f) + 1.3 * math.sin(back * 0.75) * f
		if abs(side - 2.0 * f) > w:
			return
		k = int(abs(side - 2.0 * f) / max(w, 1.0) * 3.0 + f * 2.0)
		ic.put("back", x, y, FIRE[min(len(FIRE) - 1, k)])
	each(trail)
	shaft(ic, top, (tip[0] - ux * 17, tip[1] - uy * 17), 2.3)
	blade(ic, (tip[0] - ux * 19, tip[1] - uy * 19), tip, 7.4)
	tassel(ic, tip[0] - ux * 18.5, tip[1] - uy * 18.5, 3.2, (-ux * 0.6 - nx * 0.8, -uy * 0.6 - ny * 0.8), 9)
	ic.rim()
	ic.halo([GOLD[1]])
	def mound(x, y, px, py):   # 土堆(光晕之后画, 不被包边)
		e = math.hypot((px - tip[0]) / 10.0, (py - tip[1] - 3) / 4.0)
		if e <= 1.0 and py >= tip[1] - 1 and ic.body.getpixel((x, y))[3] == 0:
			ic.put("body", x, y, EARTH[0] if px < tip[0] - 3 else (EARTH[1] if px < tip[0] + 4 else EARTH[2]))
	each(mound)
	for (ex, ey) in ((16, 58), (26, 62), (60, 58), (54, 62), (28, 53), (59, 50)):
		bline(ic, "body", (tip[0], tip[1] + 3), (ex, ey), EARTH[2], 1)   # 裂纹(细)
	for (x, y, k) in ((22, 42, 0), (23, 41, 1), (57, 40, 1), (56, 39, 0), (27, 36, 1), (53, 34, 0), (61, 45, 1), (18, 47, 0)):
		ic.put("body", x, y, EARTH[k])   # 飞石
	sparkle(ic, tip[0], tip[1] - 1, 8, (WHITE, FIRE[1], FIRE[2]))   # 落点爆光(焦点)
	return ic.finish("cent-land")


# ─── 4 众矛之力(被动): 两支交叉 + 一支竖着, 交叉处带刻面的大金星 + 背后放射光(星级加成) ───
def icon_spears():
	ic = Icon()
	cx, cy = 32.0, 38.0
	burst(ic, cx, cy, 11.0, 29.0, 10, [GOLD[0], GOLD[1], GOLD[2]], phase=-math.pi / 2, width=0.30)
	for (a, b) in (((54.0, 61.0), (9.0, 11.0)), ((10.0, 61.0), (55.0, 11.0)), ((32.0, 63.0), (32.0, 2.0))):
		L = math.hypot(b[0] - a[0], b[1] - a[1]); ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
		hb = (b[0] - ux * 16.0, b[1] - uy * 16.0)
		shaft(ic, a, (hb[0] + ux * 1.5, hb[1] + uy * 1.5), 1.8)
		blade(ic, hb, b, 5.2)
		tassel(ic, hb[0] + ux * 0.5, hb[1] + uy * 0.5, 2.6)
	R, r = 13.0, 5.6   # 刻面金星: 每个角分亮半 / 暗半
	pts = []
	for k in range(10):
		ang = -math.pi / 2 + k * math.pi / 5
		pts.append((cx + math.cos(ang) * (R if k % 2 == 0 else r), cy + math.sin(ang) * (R if k % 2 == 0 else r), ang))
	def tri(p, a, b, c):
		def s(p1, p2, p3):
			return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
		d1, d2, d3 = s(p, a, b), s(p, b, c), s(p, c, a)
		return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))
	def star(x, y, px, py):
		for k in range(10):
			a = pts[k]; b = pts[(k + 1) % 10]
			if tri((px, py), (cx, cy), (a[0], a[1]), (b[0], b[1])):
				lit = math.cos(((a[2] + b[2]) / 2) - (-3 * math.pi / 4)) > 0.0
				ic.put("body", x, y, (GOLD[0] if k % 2 == 0 else GOLD[1]) if lit else (GOLD[2] if k % 2 == 0 else GOLD[3]))
				return
	each(star)
	ic.rim(0.30, 0.25)
	ic.halo([GOLD[1], GOLD[2]])
	sparkle(ic, cx - 3, cy - 5, 4)
	for (x, y) in ((9, 11), (55, 11), (32, 2)):
		sparkle(ic, x, y, 2)
	return ic.finish("cent-spears")


# ─── 5 炮击(攻击): 顺着飞行方向的长弹(圆柱弹体 + 尖头 + 铜带) + 彗尾火焰 + 烟团 + 火星(参考黑默丁格 W) ───
## 第三版初稿是圆球 + 金带, 看着像话筒(11-27 自检) ⇒ 改成长弹。
def icon_shell():
	ic = Icon()
	ux, uy = 0.7071, -0.7071
	nx, ny = -uy, ux
	nose_tip = (56.0, 8.0)
	base = (nose_tip[0] - ux * 26.0, nose_tip[1] - uy * 26.0)   # 弹尾
	R = 7.2
	def trail(x, y, px, py):
		rx, ry = px - base[0], py - base[1]
		back = -(rx * ux + ry * uy)
		side = abs(rx * nx + ry * ny)
		if back < -2.0 or back > 36.0:
			return
		f = max(0.0, back) / 36.0
		w = R * (1.0 - f) ** 0.8 + 1.5 * math.sin(back * 0.8) * (1.0 - f)
		if side > w:
			return
		k = int(side / max(w, 1.0) * 2.4 + f * 3.0)
		ic.put("back", x, y, FIRE[min(len(FIRE) - 1, k)])
	each(trail)
	for (bx, by, r) in ((-6, 15, 3.4), (-13, 9, 2.8), (2, 20, 2.6), (-17, 18, 2.2)):   # 烟团(相对弹尾)
		disc(ic, "back", base[0] + bx, base[1] + by, r, lambda dx, dy, d, r=r: SMOKE[0] if dx + dy < -1 else (SMOKE[1] if d < r * 0.75 else SMOKE[2]))
	def shell(x, y, px, py):
		rx, ry = px - base[0], py - base[1]
		a = rx * ux + ry * uy           # 沿弹轴, 0 = 弹尾, 26 = 尖
		sd = rx * nx + ry * ny          # 横向(负 = 左上亮面)
		if a < 0.0 or a > 26.0:
			return
		r = R if a < 15.0 else R * math.cos((a - 15.0) / 11.0 * math.pi / 2) ** 0.8
		if abs(sd) > r:
			return
		if a < 15.0:
			if 3.0 < a < 5.5:
				c = CREAM[1] if sd < 0 else CREAM[3]          # 铜带
			else:
				c = GRAY[0] if sd < -r * 0.45 else (GRAY[1] if sd < r * 0.3 else GRAY[2])
		else:
			c = CREAM[0] if sd < -r * 0.3 else (CREAM[1] if sd < r * 0.4 else CREAM[2])   # 尖头
		ic.put("body", x, y, c)
	each(shell)
	ic.rim(0.35, 0.3)
	ic.halo([FIRE[2], FIRE[3]])
	sparkle(ic, nose_tip[0] - 2, nose_tip[1] + 2, 5, (WHITE, FIRE[1], FIRE[2]))
	for (x, y) in ((6, 52), (3, 58), (12, 60), (2, 47)):
		ic.put("fx", x, y, FIRE[3])   # 尾端火星
	return ic.finish("turret-shell")


# ─── 6 护卫(被动): 背后青色放射光 + 斜面盾(左亮右暗、内斜边) + 立体齿轮徽记 ───
def icon_ward():
	ic = Icon()
	cx, cy = 32.0, 30.0
	burst(ic, cx, cy, 16.0, 31.0, 8, [TEAL[0], TEAL[1], TEAL[2]], phase=math.pi / 8, width=0.28)
	def in_shield(x, y, shrink=0.0):
		hw = 21.0 - shrink
		if y < cy - 23 + shrink or y > cy + 28 - shrink:
			return False
		if y <= cy + 3:
			return abs(x - cx) <= hw
		t = (y - (cy + 3)) / (25.0 - shrink)
		return abs(x - cx) <= hw * (1.0 - t ** 1.5)
	def face(x, y, px, py):
		if not in_shield(px, py):
			return
		left = px < cx
		if not in_shield(px, py, 2.6):          # 外框(金属)
			ic.put("body", x, y, CREAM[1] if left else GRAY[2])
		elif not in_shield(px, py, 4.0):        # 内斜边
			ic.put("body", x, y, TEAL[0] if left else TEAL[4])
		else:                                    # 盾面: 左亮右暗两大块
			ic.put("body", x, y, TEAL[2] if left else TEAL[3])
	each(face)
	gcx, gcy = cx, cy + 2
	def gear(x, y, px, py):   # 齿轮: 8 齿, 左上亮右下暗
		dx, dy = px - gcx, py - gcy
		d = math.hypot(dx, dy)
		tooth = math.cos(math.atan2(dy, dx) * 8) > 0.3
		if 4.2 <= d <= 9.2 + (2.6 if tooth else 0.0):
			ic.put("body", x, y, CREAM[0] if dx + dy < -4 else (CREAM[1] if dx + dy < 4 else CREAM[2]))
	each(gear)
	disc(ic, "body", gcx, gcy, 2.2, lambda dx, dy, d: TEAL[4])
	ic.rim(0.25, 0.25)
	ic.halo([TEAL[1], TEAL[2]])
	sparkle(ic, cx - 12, cy - 16, 4, (WHITE, TEAL[0], TEAL[1]))
	return ic.finish("turret-ward")


# ─── 7 火力同调(被动): 左下大剑 + 右上大炮管, 中间一道粗能量弧 + 沿线光粒 + 两端接触亮光 ───
def icon_link():
	ic = Icon()
	S_TIP, C_MID = (24.0, 22.0), (46.0, 33.0)
	pts = []
	for k in range(61):
		t = k / 60.0
		pts.append((S_TIP[0] + (C_MID[0] - S_TIP[0]) * t, S_TIP[1] + (C_MID[1] - S_TIP[1]) * t - math.sin(t * math.pi) * 14.0))
	for i in range(len(pts) - 1):
		bline(ic, "back", pts[i], pts[i + 1], ENERGY[3], 7)   # 能量弧外圈光
	for i in range(len(pts) - 1):
		bline(ic, "back", pts[i], pts[i + 1], ENERGY[2], 4)
	def sword(x, y, px, py):   # 剑: 左下斜向上, 剑身宽、带血槽
		d, t, side = seg((px, py), (8.0, 52.0), S_TIP)
		w = 3.4 * (1.0 - 0.7 * t) + 0.6
		if d <= w:
			ic.put("body", x, y, STEEL[4] if (d < 0.7 and t < 0.8) else (STEEL[1] if side < 0 else STEEL[3]))
	each(sword)
	bline(ic, "body", (1.0, 48.0), (14.0, 57.0), GOLD[2], 4)       # 护手
	bline(ic, "body", (6.0, 56.0), (2.0, 62.0), WOOD[1], 4)        # 握柄
	disc(ic, "body", 1.5, 63.0, 2.0, lambda dx, dy, d: GOLD[1])
	## 炮筒: 后粗前细 + 炮口喇叭口 + 两道铜箍 + 尾钮(第三版初稿后面一个大圆盖, 看着像电池 / 手电筒, 11-27 自检)
	CB, CM = (38.0, 47.0), (61.0, 20.0)
	def cannon(x, y, px, py):
		d, t, side = seg((px, py), CB, CM)
		r = 7.6 - 2.6 * t
		if t > 0.88:
			r = 7.0                                   # 炮口喇叭口
		if d > r or t <= 0.0:
			return
		if t > 0.88:
			c = GRAY[0] if side < -2 else (GRAY[1] if side < 2 else GRAY[3])
		elif 0.18 < t < 0.27 or 0.6 < t < 0.68:
			c = CREAM[1] if side < 0 else CREAM[3]   # 铜箍
		else:
			c = TEAL[1] if side < -2.5 else (TEAL[2] if side < 2.5 else TEAL[3])
		ic.put("body", x, y, c)
	each(cannon)
	disc(ic, "body", CB[0] - 2.0, CB[1] + 2.4, 3.2, lambda dx, dy, d: CREAM[1] if dx + dy < 0 else CREAM[3])   # 尾钮
	disc(ic, "body", CM[0] - 0.6, CM[1] + 0.6, 2.4, lambda dx, dy, d: GRAY[4])   # 炮口黑洞
	ic.rim(0.32, 0.28)
	for i in range(len(pts) - 1):
		bline(ic, "fx", pts[i], pts[i + 1], ENERGY[1], 2)   # 能量芯
	for k in (12, 24, 36, 48):
		x, y = pts[k]
		ic.put("fx", x + 2, y - 2, ENERGY[0]); ic.put("fx", x - 2, y + 3, ENERGY[2])   # 光粒
	sparkle(ic, S_TIP[0], S_TIP[1], 5, (WHITE, ENERGY[1], ENERGY[2]))
	sparkle(ic, C_MID[0], C_MID[1] - 1, 4, (WHITE, ENERGY[1], ENERGY[2]))
	return ic.finish("turret-link")


def main():
	os.makedirs(OUT, exist_ok=True)
	icons = [icon_thrust(), icon_shield(), icon_land(), icon_spears(), icon_shell(), icon_ward(), icon_link()]
	pv = Image.new("RGBA", (len(icons) * (N * 4 + 16) + 16, N * 4 + 32 + N + 16), (30, 36, 48, 255))
	for i, im in enumerate(icons):
		pv.alpha_composite(im.resize((N * 4, N * 4), Image.NEAREST), (16 + i * (N * 4 + 16), 16))
		pv.alpha_composite(im, (16 + i * (N * 4 + 16), N * 4 + 32))
	pv.save(os.path.join(OUT, "preview.png"))
	print("ok", OUT)


if __name__ == "__main__":
	main()
