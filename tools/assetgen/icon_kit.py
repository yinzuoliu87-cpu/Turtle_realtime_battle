# -*- coding: utf-8 -*-
"""icon_kit.py —— 召唤物技能图标的形状库(接 summon_icons_1127.py 第三版的做法, 用户 11-27 认可)。

规格同第三版: 64×64 硬边像素画、透明底、深色描边、零半透明像素; 分层 back(背后光) / body(本体, 描边按它) / fx(前景特效)。
光从左上来: 每个形状按「像素相对形状中心的方向 · 左上光向」分 4 档明暗(亮 / 中 / 暗 / 最暗), 再由 Icon.rim() 勾亮边、压暗边。
做法(如实): 逐像素按几何判层上色, 不是手画、不是 AI 生成; 不用随机数, 重跑逐字节相同。
"""
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import summon_icons_1127 as S1  # noqa: E402
from summon_icons_1127 import Icon, N, hx, mix, each, seg, bline, disc, sparkle, burst, WHITE, OUTLINE  # noqa: E402,F401

# ── 调色(每组 4~6 档, 亮 → 暗) ──
GOLD = S1.GOLD
FIRE = S1.FIRE
STEEL = S1.STEEL
WOOD = S1.WOOD
EARTH = S1.EARTH
SMOKE = S1.SMOKE
RED = S1.RED
TEAL = S1.TEAL
GRAY = S1.GRAY
CREAM = S1.CREAM
BONE = [hx(c) for c in ("#fffbe8", "#ece3c4", "#c9bc94", "#97875e", "#5c4f34")]
GHOST = [hx(c) for c in ("#e8fff0", "#9cffb9", "#4fe08a", "#22a35e", "#0f5c3a")]       # 骷髅 / 亡魂的鬼火绿
VIOLET = [hx(c) for c in ("#f3e4ff", "#c99bff", "#9a5cf0", "#6a32c0", "#3d1a78")]
PINK = [hx(c) for c in ("#fff0f5", "#ffb3cd", "#ff6f9e", "#d8336e", "#8e1846")]
LEAF = [hx(c) for c in ("#e9ffb8", "#b9ef5e", "#7fc935", "#4b8f1f", "#27530f")]
FUR = [hx(c) for c in ("#e2b07a", "#b57a45", "#8a5530", "#5c341a", "#33190a")]
SEA = [hx(c) for c in ("#d8f6ff", "#7fd6ff", "#2f9fe0", "#1b62a8", "#0d3361")]
JADE = [hx(c) for c in ("#e2fff1", "#7cf0b6", "#22c47d", "#12844f", "#0a4a2c")]
CORAL = [hx(c) for c in ("#ffe4e4", "#ffa8a8", "#f06d78", "#b83a4f", "#6e1d2c")]
CANDY = [hx(c) for c in ("#fff5f8", "#ff9ec4", "#ff4f8b", "#c21e5b", "#6e0e33")]
INK = [hx(c) for c in ("#8f86b8", "#5d5487", "#3b3460", "#231d3d", "#120e22")]
SHADOW = [hx(c) for c in ("#d9c7ff", "#9c84e0", "#6650b0", "#3f2f78", "#211744")]
ICE = [hx(c) for c in ("#ffffff", "#d6f4ff", "#8fd8ff", "#4aa6e8", "#2465a8")]
STONE = [hx(c) for c in ("#d8d2c4", "#a9a191", "#7c7466", "#544d43", "#322d27")]
HOLO = [hx(c) for c in ("#f0ffff", "#9ffcff", "#3fd8f0", "#1e8fc0", "#13497a")]
EMBER = [hx(c) for c in ("#fff6d6", "#ffc45c", "#ff7a24", "#c8361a", "#6e1408")]

LX, LY = -0.70710678, -0.70710678


def lit_idx(dx, dy, r, n=4, bias=0.0):
	"""方向明暗: 越朝左上越亮。返回 0(最亮) .. n-1(最暗)。"""
	if r <= 0:
		return 1
	t = (dx * LX + dy * LY) / r + bias      # -1 .. 1
	k = int((1.0 - max(-1.0, min(1.0, t))) / 2.0 * n)
	return max(0, min(n - 1, k))


def ellipse(ic, layer, cx, cy, rx, ry, pal, rot=0.0, bias=0.15, hollow=0.0):
	ca, sa = math.cos(rot), math.sin(rot)
	def f(x, y, px, py):
		dx, dy = px - cx, py - cy
		u = (dx * ca + dy * sa) / rx
		v = (-dx * sa + dy * ca) / ry
		e = u * u + v * v
		if e <= 1.0 and e >= hollow * hollow:
			ic.put(layer, x, y, pal[lit_idx(dx, dy, max(rx, ry), 4, bias + 0.35 * (1 - e))])
	each(f)


def inside_poly(px, py, pts):
	c = False
	j = len(pts) - 1
	for i in range(len(pts)):
		xi, yi = pts[i]; xj, yj = pts[j]
		if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi + 1e-9) + xi:
			c = not c
		j = i
	return c


def poly(ic, layer, pts, pal, bias=0.1, flat=None):
	cx = sum(p[0] for p in pts) / len(pts)
	cy = sum(p[1] for p in pts) / len(pts)
	r = max(math.hypot(p[0] - cx, p[1] - cy) for p in pts)
	def f(x, y, px, py):
		if inside_poly(px, py, pts):
			ic.put(layer, x, y, flat if flat else pal[lit_idx(px - cx, py - cy, r, 4, bias)])
	each(f)


def star(ic, layer, cx, cy, ro, ri, n, pal, rot=-math.pi / 2):
	"""刻面星: 每个尖角两半分亮暗(朝光的一半亮)。"""
	pts = []
	for k in range(n * 2):
		a = rot + k * math.pi / n
		r = ro if k % 2 == 0 else ri
		pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
	la = math.atan2(LY, LX)
	def f(x, y, px, py):
		if not inside_poly(px, py, pts):
			return
		a = math.atan2(py - cy, px - cx)
		k = ((a - rot) / (math.pi / n)) % (2 * n)
		spike = int((k + 1) // 2) % n
		axis = rot + spike * 2 * math.pi / n
		side = math.sin(a - axis)
		facet = axis + (0.5 if side > 0 else -0.5)
		c = math.cos(facet - la)
		ic.put(layer, x, y, pal[0] if c > 0.55 else (pal[1] if c > 0.0 else (pal[2] if c > -0.55 else pal[3])))
	each(f)


def flame(ic, layer, base, tip, width, cols, wob=1.2, phase=0.0):
	"""火舌 / 尾焰: 根宽梢尖, 边缘起伏; 芯 cols[0] → 外 cols[-1]。"""
	def f(x, y, px, py):
		d, t, side = seg((px, py), base, tip)
		if t <= 0.0 or t >= 1.0:
			return
		w = width * math.sin(math.pi * min(1.0, t * 0.9 + 0.1)) ** 0.6 * (1.0 - t) ** 0.55
		w += wob * math.sin(t * 13.0 + phase + (1 if side > 0 else 0) * 2.1) * (1 - t)
		if d > w:
			return
		k = int(d / max(w, 0.6) * (len(cols) - 1) + t * 1.3)
		ic.put(layer, x, y, cols[min(len(cols) - 1, k)])
	each(f)


def swirl(ic, layer, cx, cy, r, cols, turns=1.3, arms=3, band=0.5, r0=0.0):
	"""漩涡: arms 条旋臂, 由里到外 cols。"""
	def f(x, y, px, py):
		dx, dy = px - cx, py - cy
		d = math.hypot(dx, dy)
		if d > r or d < r0:
			return
		a = math.atan2(dy, dx) + d / r * turns * 2 * math.pi
		k = (a * arms / (2 * math.pi)) % 1.0
		if k < band:
			ic.put(layer, x, y, cols[min(len(cols) - 1, int(d / r * len(cols)))])
	each(f)


def funnel(ic, layer, cx_bot, y_bot, cx_top, y_top, w_bot, w_top, cols, stripes=5, lean=0.0):
	"""龙卷风漏斗: 下窄上宽(或反之), 斜条纹。"""
	def f(x, y, px, py):
		if py < y_top or py > y_bot:
			return
		t = (y_bot - py) / max(1.0, y_bot - y_top)
		cx = cx_bot + (cx_top - cx_bot) * t + math.sin(t * 5.0) * lean
		hw = w_bot + (w_top - w_bot) * t
		u = (px - cx) / max(hw, 0.8)
		if abs(u) > 1.0:
			return
		## 一圈圈往上旋的风带: 主要按高度分带, 带子随 u² 往上弯(看着是绕着轴转的环), 右侧背光压暗
		s = (t * stripes + u * u * 0.55 - u * 0.25) % 1.0
		edge = abs(u) > 0.82
		k = (0 if s < 0.22 else (1 if s < 0.55 else 2)) + (1 if edge else 0) + (1 if u > 0.35 else 0)
		ic.put(layer, x, y, cols[min(len(cols) - 1, k)])
	each(f)


def tornado(ic, layer, x_bot, y_bot, x_top, y_top, w_bot, w_top, cols, rings=8, sway=3.0):
	"""龙卷风: 从上到下一圈圈叠起来的扁环(上宽下窄, 左右摆), 每圈亮边在上。"""
	for i in range(rings):
		t = 1.0 - i / max(1, rings - 1)                       # 1 = 顶
		cy = y_bot + (y_top - y_bot) * t
		cx = x_bot + (x_top - x_bot) * t + math.sin(t * 6.0) * sway
		rx = w_bot + (w_top - w_bot) * t
		ry = max(1.6, rx * 0.32)
		ellipse(ic, layer, cx, cy, rx, ry, [cols[0], cols[1], cols[2], cols[3]], bias=0.2)
		ellipse(ic, layer, cx + rx * 0.12, cy + ry * 0.25, rx * 0.72, ry * 0.55, [cols[2], cols[3], cols[3], cols[-1]], bias=0.0)


def crescent(ic, layer, cx, cy, r, thick, a0, a1, cols):
	"""刀光弧: 外沿最亮, 两头收尖。角度为弧度, a0 < a1。"""
	def f(x, y, px, py):
		dx, dy = px - cx, py - cy
		d = math.hypot(dx, dy)
		a = math.atan2(dy, dx)
		while a < a0:
			a += 2 * math.pi
		if a > a1:
			return
		t = (a - a0) / (a1 - a0)
		th = thick * math.sin(math.pi * t) ** 0.7
		if r - th <= d <= r:
			k = int((r - d) / max(th, 0.6) * len(cols))
			ic.put(layer, x, y, cols[min(len(cols) - 1, k)])
	each(f)


def ring(ic, layer, cx, cy, r0, r1, col, sy=1.0):
	def f(x, y, px, py):
		d = math.hypot(px - cx, (py - cy) / sy)
		if r0 <= d <= r1:
			ic.put(layer, x, y, col)
	each(f)


def thick_line(ic, layer, a, b, w, pal, cap=True):
	def f(x, y, px, py):
		d, t, side = seg((px, py), a, b)
		if d <= w and (cap or 0.0 < t < 1.0):
			ic.put(layer, x, y, pal[0] if side < -w * 0.35 else (pal[1] if side < w * 0.35 else pal[2]))
	each(f)


def skull(ic, layer, cx, cy, s, pal, eye=None):
	"""骷髅头: 颅顶圆 + 颧骨 + 下颌 + 眼窝(可发光) + 鼻孔 + 牙缝。s ≈ 半宽。"""
	ellipse(ic, layer, cx, cy - s * 0.15, s, s * 0.92, pal)
	poly(ic, layer, [(cx - s * 0.62, cy + s * 0.45), (cx + s * 0.62, cy + s * 0.45), (cx + s * 0.5, cy + s * 1.05), (cx - s * 0.5, cy + s * 1.05)], pal, 0.0)
	for ex in (-1, 1):
		ellipse(ic, layer, cx + ex * s * 0.4, cy + s * 0.05, s * 0.26, s * 0.3, [pal[4]] * 4 if eye is None else [eye[0], eye[1], eye[2], eye[2]], bias=0.4)
	poly(ic, layer, [(cx, cy + s * 0.3), (cx - s * 0.13, cy + s * 0.52), (cx + s * 0.13, cy + s * 0.52)], pal, flat=pal[4])
	for k in (-2, -1, 0, 1, 2):
		bline(ic, layer, (cx + k * s * 0.2, cy + s * 0.68), (cx + k * s * 0.2, cy + s * 1.02), pal[4])


def bone(ic, layer, a, b, w, pal):
	"""骨头: 杆 + 两端各两个圆头。"""
	thick_line(ic, layer, a, b, w, [pal[1], pal[2], pal[3]], cap=False)
	L = math.hypot(b[0] - a[0], b[1] - a[1])
	nx, ny = -(b[1] - a[1]) / L, (b[0] - a[0]) / L
	for p in (a, b):
		for sgn in (-1, 1):
			ellipse(ic, layer, p[0] + nx * w * 0.9 * sgn, p[1] + ny * w * 0.9 * sgn, w * 1.15, w * 1.15, pal)


def heart(ic, layer, cx, cy, s, pal):
	def f(x, y, px, py):
		u = (px - cx) / s
		v = -(py - cy) / s + 0.25
		if (u * u + v * v - 1) ** 3 - u * u * v ** 3 <= 0:
			ic.put(layer, x, y, pal[lit_idx(px - cx, py - cy, s * 1.2, 4, 0.2)])
	each(f)


def plus(ic, layer, cx, cy, s, w, pal):
	poly(ic, layer, [(cx - w, cy - s), (cx + w, cy - s), (cx + w, cy - w), (cx + s, cy - w), (cx + s, cy + w), (cx + w, cy + w),
		(cx + w, cy + s), (cx - w, cy + s), (cx - w, cy + w), (cx - s, cy + w), (cx - s, cy - w), (cx - w, cy - w)], pal, 0.1)


def gear(ic, layer, cx, cy, r, teeth, pal, hole=0.35):
	def f(x, y, px, py):
		dx, dy = px - cx, py - cy
		d = math.hypot(dx, dy)
		a = math.atan2(dy, dx)
		rr = r * (0.78 if (a * teeth / (2 * math.pi)) % 1.0 < 0.5 else 1.0)
		if r * hole < d <= rr:
			ic.put(layer, x, y, pal[lit_idx(dx, dy, r, 4, 0.1)])
	each(f)


def paw(ic, layer, cx, cy, s, pal):
	ellipse(ic, layer, cx, cy + s * 0.35, s * 0.62, s * 0.5, pal)
	for k, (ox, oy) in enumerate(((-0.72, -0.25), (-0.28, -0.72), (0.28, -0.72), (0.72, -0.25))):
		ellipse(ic, layer, cx + ox * s, cy + oy * s, s * 0.24, s * 0.3, pal, rot=ox * 0.5)


def puff(ic, layer, cx, cy, r, pal, n=4, phase=0.0):
	"""一团烟 / 云: 几个圆叠在一起。"""
	for k in range(n):
		a = phase + k * 2 * math.pi / n
		ellipse(ic, layer, cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.4, r * 0.62, r * 0.55, pal, bias=0.2)
	ellipse(ic, layer, cx, cy, r * 0.6, r * 0.55, pal, bias=0.3)


def hourglass(ic, layer, cx, cy, s, frame, sand):
	poly(ic, layer, [(cx - s * 0.62, cy - s), (cx + s * 0.62, cy - s), (cx + s * 0.08, cy), (cx + s * 0.62, cy + s), (cx - s * 0.62, cy + s), (cx - s * 0.08, cy)],
		[sand[0], sand[1], sand[1], sand[2]], 0.0)
	for yy in (-1, 1):
		thick_line(ic, layer, (cx - s * 0.8, cy + yy * s * 1.02), (cx + s * 0.8, cy + yy * s * 1.02), s * 0.16, [frame[0], frame[1], frame[2]])
	for xx in (-1, 1):
		thick_line(ic, layer, (cx + xx * s * 0.72, cy - s), (cx + xx * s * 0.72, cy + s), s * 0.08, [frame[1], frame[2], frame[3]])


def bolt(ic, layer, pts, w, pal):
	for i in range(len(pts) - 1):
		thick_line(ic, layer, pts[i], pts[i + 1], w * (1.0 - 0.6 * i / max(1, len(pts) - 1)), pal)


def chevrons(ic, layer, a, b, n, w, col):
	"""速度线 / 箭头列: 沿 a→b 的 n 道 V 形。"""
	L = math.hypot(b[0] - a[0], b[1] - a[1])
	ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
	nx, ny = -uy, ux
	for k in range(n):
		t = (k + 0.5) / n
		px, py = a[0] + ux * L * t, a[1] + uy * L * t
		for s in (-1, 1):
			bline(ic, layer, (px, py), (px - ux * w + nx * w * s, py - uy * w + ny * w * s), col, 2)


def finish_all(icons, out):
	"""icons: [(name, Icon)] → 各自分层存盘 + 一张预览(4 倍放大 + 原大)。"""
	S1.OUT = out
	from PIL import Image
	ims = [(nm, ic.finish(nm)) for nm, ic in icons]
	cols = 8
	rows = (len(ims) + cols - 1) // cols
	pv = Image.new("RGBA", (cols * (N * 3 + 12) + 12, rows * (N * 3 + N + 28) + 12), (30, 36, 48, 255))
	for i, (nm, im) in enumerate(ims):
		x = 12 + (i % cols) * (N * 3 + 12)
		y = 12 + (i // cols) * (N * 3 + N + 28)
		pv.alpha_composite(im.resize((N * 3, N * 3), Image.NEAREST), (x, y))
		pv.alpha_composite(im, (x, y + N * 3 + 8))
	pv.save(os.path.join(out, "preview.png"))
	return ims
