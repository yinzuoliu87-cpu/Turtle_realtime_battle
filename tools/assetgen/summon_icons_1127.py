# -*- coding: utf-8 -*-
"""summon_icons_1127.py —— 图鉴「角色」栏召唤物的被动 / 攻击 / 技能图标(64×64 硬边像素画, 透明底, 深色描边; 同现有 skills/ passive/ 图标规格)。

参考研究 docs/studies/20261127-参考-召唤物技能图标.md(潘森 / 黑默丁格技能图标的构图与动势表达)。
做法(如实): 逐像素按几何判层上色(本体 / 高光 / 暗部 / 特效 / 描边), 分层 PNG 由 tools/assetgen/ase/png_layers_to_ase.lua 拼成 .aseprite。
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


# 百夫长(立绘取色)
RED = [hx(c) for c in ("#ee4931", "#d72d21", "#c7221c", "#a2141e", "#840b1f", "#5e0818")]
STEEL_HI, STEEL, STEEL_MID, STEEL_DK = hx("#eef3f8"), hx("#b9c4d2"), hx("#6a7b8f"), hx("#3e4556")
GOLD_HI, GOLD, GOLD_DK = hx("#f6c870"), hx("#c1812f"), hx("#8a4a18")
WOOD_HI, WOOD, WOOD_DK = hx("#b26a2c"), hx("#7a3e1c"), hx("#4a2312")
OUTLINE = hx("#160a0c")
FX_HI, FX_MID, FX_LO = hx("#ffffff"), hx("#ffe9a8"), hx("#ffb84a")
SPEED_HI, SPEED_LO = hx("#f2f6fb"), hx("#9fb0c8")
EARTH_HI, EARTH, EARTH_DK = hx("#9a6a44"), hx("#6b4428"), hx("#3d2414")


class Icon:
	"""分层画布: body(描边算它) / fx(发光、速度线, 不描边) / outline。"""

	def __init__(self):
		self.body = Image.new("RGBA", (N, N), (0, 0, 0, 0))
		self.fx = Image.new("RGBA", (N, N), (0, 0, 0, 0))
		self.back = Image.new("RGBA", (N, N), (0, 0, 0, 0))   # 主体后面的光(放射光 / 冲击环), 不描边

	def put(self, layer, x, y, c):
		if 0 <= x < N and 0 <= y < N:
			getattr(self, layer).putpixel((int(x), int(y)), c)

	def solid(self):
		return {(x, y) for y in range(N) for x in range(N) if self.body.getpixel((x, y))[3] == 255}

	def finish(self, name):
		sol = self.solid()
		ring = []
		for y in range(N):
			for x in range(N):
				if (x, y) in sol:
					continue
				if any(q in sol for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))):
					ring.append((x, y))
		outline = Image.new("RGBA", (N, N), (0, 0, 0, 0))
		for (x, y) in ring:   # 先算完再画(边画边算会让描边自己也算实心)
			outline.putpixel((x, y), OUTLINE)
		comp = Image.new("RGBA", (N, N), (0, 0, 0, 0))
		layers = [("back", self.back), ("body", self.body), ("outline", outline), ("fx", self.fx)]
		d = os.path.join(OUT, name)
		os.makedirs(d, exist_ok=True)
		for nm, im in layers:
			comp.alpha_composite(im)
			im.save(os.path.join(d, "layer-%s.png" % nm))
		comp.save(os.path.join(d, "%s.png" % name))
		return comp


def seg(p, a, b):
	ab = (b[0] - a[0], b[1] - a[1]); ap = (p[0] - a[0], p[1] - a[1])
	L2 = ab[0] ** 2 + ab[1] ** 2
	t = max(0.0, min(1.0, (ap[0] * ab[0] + ap[1] * ab[1]) / L2))
	c = (a[0] + ab[0] * t, a[1] + ab[1] * t)
	side = ab[0] * ap[1] - ab[1] * ap[0]
	return math.hypot(p[0] - c[0], p[1] - c[1]), t, side


def shaft(ic, a, b, w=1.6):
	"""木杆: 亮面 / 本色 / 暗面三档。"""
	for y in range(N):
		for x in range(N):
			d, t, side = seg((x + 0.5, y + 0.5), a, b)
			if d <= w:
				ic.put("body", x, y, WOOD_HI if (side < 0 and d > w * 0.35) else (WOOD_DK if side > 0 and d > w * 0.45 else WOOD))


def blade(ic, base, tip, half_w=4.2):
	"""叶形矛头: 中脊白亮, 一侧亮钢一侧暗钢, 两端收尖。"""
	L = math.hypot(tip[0] - base[0], tip[1] - base[1])
	for y in range(N):
		for x in range(N):
			d, t, side = seg((x + 0.5, y + 0.5), base, tip)
			w = half_w * math.sin(math.pi * min(1.0, t * 1.15 + 0.06)) ** 0.75 * (1.0 - 0.55 * t)
			if t <= 0.0 or t >= 1.0 or d > w + 0.4:
				continue
			if d < 0.7:
				c = STEEL_HI
			elif side < 0:
				c = STEEL if d < w * 0.75 else STEEL_MID
			else:
				c = STEEL_MID if d < w * 0.6 else STEEL_DK
			ic.put("body", x, y, c)
	ic.put("body", int(tip[0]), int(tip[1]), STEEL_HI)


def tassel(ic, cx, cy, r=2.6):
	for y in range(N):
		for x in range(N):
			d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
			if d <= r:
				ic.put("body", x, y, RED[0] if (x + 0.5 < cx and y + 0.5 < cy) else (RED[2] if d < r * 0.7 else RED[4]))


def bline(ic, layer, a, b, c, w=1):
	"""直线(按长度取样, 宽 w 像素沿法线加厚)。"""
	L = max(1.0, math.hypot(b[0] - a[0], b[1] - a[1]))
	nx, ny = -(b[1] - a[1]) / L, (b[0] - a[0]) / L
	for s10 in range(int(L * 3) + 1):
		t = s10 / (L * 3)
		x = a[0] + (b[0] - a[0]) * t; y = a[1] + (b[1] - a[1]) * t
		for j in range(w):
			o = j - (w - 1) / 2.0
			ic.put(layer, round(x + nx * o), round(y + ny * o), c)


# ─── 1 突刺(攻击): 斜向矛尖 + 身后速度线(参考潘森 Q) ───
def icon_thrust():
	ic = Icon()
	shaft(ic, (5, 59), (33, 31), 2.0)
	blade(ic, (31, 33), (59, 5), 6.2)
	tassel(ic, 31.5, 33.5, 3.0)
	ic.put("body", 29, 36, RED[3]); ic.put("body", 28, 37, RED[4]); ic.put("body", 30, 37, RED[3])
	## 速度线: 两道粗的贴着矛头两侧往后拖 + 一道细的, 前亮后淡
	bline(ic, "fx", (22, 30), (34, 18), SPEED_LO, 2); bline(ic, "fx", (34, 18), (40, 12), SPEED_HI, 2)
	bline(ic, "fx", (34, 46), (44, 36), SPEED_LO, 2); bline(ic, "fx", (44, 36), (50, 30), SPEED_HI, 2)
	bline(ic, "fx", (16, 28), (24, 20), SPEED_LO, 1)
	## 矛尖闪光(四角星)
	for (dx, dy, c) in ((0, 0, FX_HI), (1, 0, FX_MID), (-1, 0, FX_MID), (0, 1, FX_MID), (0, -1, FX_MID), (2, 0, FX_LO), (0, -2, FX_LO)):
		ic.put("fx", 60 + dx, 4 + dy, c)
	return ic.finish("cent-thrust")


# ─── 2 龟甲阵(技能): 红色大盾正面 + 金边金翼纹 + 背光(参考潘森 E) ───
def icon_shield():
	ic = Icon()
	cx, cy, hw, hh, rr = 32.0, 33.0, 16.0, 23.0, 5.0
	def inside(x, y, shrink=0.0):
		qx = max(abs(x - cx) - (hw - shrink - rr), 0.0); qy = max(abs(y - cy) - (hh - shrink - rr), 0.0)
		return math.hypot(qx, qy) <= rr
	# 背光: 八道直的放射光(斜向四道长、左右上下四道短), 只画在盾外
	for k in range(8):
		ang = k * math.pi / 4
		far = 31.0 if k % 2 == 1 else 27.0
		for r10 in range(120, int(far * 10)):
			r = r10 / 10.0
			x = cx + math.cos(ang) * r; y = cy + math.sin(ang) * r
			if inside(x, y) or not inside(x, y, -8.0):
				continue
			c = FX_MID if r < far - 4 else FX_LO
			ic.put("back", round(x), round(y), c)
			if k % 2 == 1 and r < far - 3:
				ic.put("back", round(x - math.sin(ang)), round(y + math.cos(ang)), FX_LO)
	for y in range(N):
		for x in range(N):
			px, py = x + 0.5, y + 0.5
			if not inside(px, py):
				continue
			if not inside(px, py, 2.0):   # 金边(左上亮, 右下暗)
				ic.put("body", x, y, GOLD_HI if (px - cx) + (py - cy) < -6 else (GOLD_DK if (px - cx) + (py - cy) > 10 else GOLD))
				continue
			# 盾面: 桶形弧面, 左亮右暗
			u = (px - cx) / hw
			k = min(len(RED) - 2, max(0, int((u + 1.0) / 2.0 * 5.0)))
			ic.put("body", x, y, RED[k])
	# 盾心金钉
	for y in range(N):
		for x in range(N):
			d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
			if d <= 4.6:
				ic.put("body", x, y, GOLD_HI if (x + 0.5 < cx - 1 and y + 0.5 < cy - 1) else (GOLD if d < 3.4 else GOLD_DK))
	# 金翼纹: 盾心往四角的折线(立绘盾面的闪电翼)
	for sx in (-1, 1):
		for sy in (-1, 1):
			pts = [(cx + sx * 5, cy + sy * 3), (cx + sx * 9, cy + sy * 9), (cx + sx * 7, cy + sy * 12), (cx + sx * 11, cy + sy * 17)]
			for i in range(len(pts) - 1):
				a, b = pts[i], pts[i + 1]
				for s in range(12):
					t = s / 11.0
					ic.put("body", round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t), GOLD_HI if sy < 0 else GOLD)
	return ic.finish("cent-guard")


# ─── 3 军团天降(被动): 长矛竖直插进地面 + 爆光 + 裂纹 + 冲击环 + 下落拖影(参考潘森 R) ───
def icon_land():
	ic = Icon()
	gx, gy = 32.0, 50.0
	## 冲击环(扁椭圆两圈)
	for y in range(N):
		for x in range(N):
			e = math.hypot((x + 0.5 - gx) / 27.0, (y + 0.5 - gy) / 8.0)
			if 0.80 <= e <= 1.0:
				ic.put("back", x, y, FX_LO if y + 0.5 > gy else FX_MID)
			elif 0.48 <= e <= 0.58:
				ic.put("back", x, y, FX_MID)
	## 落点土堆 + 粗裂纹
	for y in range(N):
		for x in range(N):
			e = math.hypot((x + 0.5 - gx) / 9.0, (y + 0.5 - gy - 2) / 4.0)
			if e <= 1.0 and y + 0.5 >= gy - 1:
				ic.put("body", x, y, EARTH_HI if x + 0.5 < gx - 2 else (EARTH if x + 0.5 < gx + 4 else EARTH_DK))
	for (ex, ey) in ((6, 55), (12, 46), (58, 56), (52, 45), (20, 61), (45, 61)):
		bline(ic, "body", (gx, gy + 2), (ex, ey), EARTH_DK, 2)
	## 长矛: 粗杆 + 大矛头朝下、尖插进土堆
	shaft(ic, (32, 2), (32, 28), 2.2)
	blade(ic, (32, 26), (32, 50), 7.0)
	tassel(ic, 32.5, 27.5, 3.2)
	## 落点爆光(盖在矛尖两侧)
	for (dx, dy, c) in ((-1, -1, FX_HI), (1, -1, FX_HI), (-3, -1, FX_MID), (3, -1, FX_MID), (-5, -2, FX_LO), (5, -2, FX_LO), (-2, -3, FX_MID), (2, -3, FX_MID),
			(-7, 0, FX_LO), (7, 0, FX_LO), (-4, -4, FX_LO), (4, -4, FX_LO)):
		ic.put("fx", int(gx) + dx, int(gy) + dy, c)
	## 下落拖影: 杆两侧两道粗的 + 两道细的
	bline(ic, "fx", (23, 2), (23, 18), SPEED_LO, 2); bline(ic, "fx", (23, 18), (23, 24), SPEED_HI, 2)
	bline(ic, "fx", (41, 4), (41, 20), SPEED_LO, 2); bline(ic, "fx", (41, 20), (41, 26), SPEED_HI, 2)
	bline(ic, "fx", (17, 10), (17, 22), SPEED_LO, 1); bline(ic, "fx", (47, 12), (47, 24), SPEED_LO, 1)
	## 飞溅碎石
	for (x, y) in ((11, 38), (12, 37), (53, 37), (52, 36), (16, 33), (48, 32), (8, 44), (56, 43)):
		ic.put("body", x, y, EARTH_HI if x < 32 else EARTH)
	return ic.finish("cent-land")


# ─── 4 众矛之力(被动): 两支长矛交叉成 X、中间一支竖着, 交叉处一颗大金星(星级加成) ───
def icon_spears():
	ic = Icon()
	for (a, b) in (((54.0, 60.0), (10.0, 12.0)), ((10.0, 60.0), (54.0, 12.0)), ((32.0, 62.0), (32.0, 3.0))):
		dx, dy = b[0] - a[0], b[1] - a[1]
		L = math.hypot(dx, dy); ux, uy = dx / L, dy / L
		hb = (b[0] - ux * 15.0, b[1] - uy * 15.0)
		shaft(ic, a, (hb[0] + ux * 1.5, hb[1] + uy * 1.5), 1.7)
		blade(ic, hb, b, 4.8)
		tassel(ic, hb[0] + ux * 0.5, hb[1] + uy * 0.5, 2.5)
	cx, cy, R, r = 32.0, 38.0, 12.5, 5.4
	poly = []
	for k in range(10):
		ang = -math.pi / 2 + k * math.pi / 5
		rad = R if k % 2 == 0 else r
		poly.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
	def in_poly(x, y):
		c = False
		for q in range(len(poly)):
			x1, y1 = poly[q]; x2, y2 = poly[(q + 1) % len(poly)]
			if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
				c = not c
		return c
	for y in range(N):
		for x in range(N):
			px, py = x + 0.5, y + 0.5
			if in_poly(px, py):
				v = (px - cx) + (py - cy)
				ic.put("body", x, y, GOLD_HI if v < -3 else (GOLD if v < 6 else GOLD_DK))
	for (dx, dy, c) in ((0, 0, FX_HI), (-1, 1, FX_MID), (1, -1, FX_MID)):
		ic.put("fx", 29 + dx, 33 + dy, c)
	return ic.finish("cent-spears")


# ─── 炮台(立绘取色) ───
TEAL = [hx(c) for c in ("#7fd8c4", "#53ac9b", "#3c8778", "#1b4644", "#0f2a29")]
GRAY_HI, GRAY, GRAY_DK = hx("#8a8d9e"), hx("#575969"), hx("#32323e")
CREAM = hx("#fadfad")
FIRE = [hx(c) for c in ("#fff6d0", "#ffd25a", "#ff9a2e", "#e8531e", "#a82a14")]
ENERGY = [hx(c) for c in ("#ffe0e0", "#ff6a5a", "#e0242c", "#8c0f1e")]


def disc(ic, layer, cx, cy, r, shade):
	"""实心圆; shade(dx, dy, d) 返回颜色。"""
	for y in range(N):
		for x in range(N):
			dx, dy = x + 0.5 - cx, y + 0.5 - cy
			d = math.hypot(dx, dy)
			if d <= r:
				ic.put(layer, x, y, shade(dx, dy, d))


# ─── 5 炮击(攻击): 一颗炮弹 + 身后火光尾焰(参考黑默丁格 W) ───
def icon_shell():
	ic = Icon()
	## 尾焰: 从左下往右上, 越往后越宽越暗
	ux, uy = 0.7071, -0.7071
	hx0, hy0 = 40.0, 24.0   # 弹头中心
	for y in range(N):
		for x in range(N):
			px, py = x + 0.5 - hx0, y + 0.5 - hy0
			along = -(px * ux + py * uy)          # 往后为正
			side = abs(px * uy - py * ux)
			if along <= 2.0 or along >= 34.0:
				continue
			## 宽度: 贴着弹身最宽(同弹径), 往后收成尖; 边缘按沿程起伏, 像火苗
			f = along / 34.0
			w = 8.0 * (1.0 - f) ** 0.9 + 1.2 * math.sin(along * 0.9) * (1.0 - f)
			if side > w:
				continue
			## 颜色: 芯白黄 → 橙 → 红, 越往后越暗; 越靠边越暗
			k = min(len(FIRE) - 1, int(f * 3.2 + side / max(w, 1.0) * 1.6))
			ic.put("fx", x, y, FIRE[k])
	## 尾端火星
	for (dx, dy, c) in ((-26, 25, FIRE[2]), (-29, 22, FIRE[3]), (-23, 29, FIRE[3]), (-31, 28, FIRE[4]), (-27, 31, FIRE[4])):
		ic.put("fx", int(hx0) + dx, int(hy0) + dy, c)
	## 炮弹: 钢灰圆弹 + 前端铜色弹头带
	disc(ic, "body", hx0, hy0, 8.5, lambda dx, dy, d: GRAY_HI if dx + dy < -6 else (GRAY if dx + dy < 4 else GRAY_DK))
	disc(ic, "body", hx0 + 3.0, hy0 - 3.0, 4.2, lambda dx, dy, d: CREAM if dx + dy < -2 else hx("#c49846"))
	ic.put("fx", 37, 20, hx("#ffffff")); ic.put("fx", 36, 21, CREAM)
	## 弹前一圈冲击亮点
	for (dx, dy) in ((11, -11), (12, -9), (9, -12), (13, -12)):
		ic.put("fx", int(hx0) + dx, int(hy0) + dy, FIRE[1])
	return ic.finish("turret-shell")


# ─── 6 护卫(被动): 青绿盾牌 + 炮台齿轮徽记 ───
def icon_ward():
	ic = Icon()
	cx, cy = 32.0, 30.0
	def in_shield(x, y, shrink=0.0):
		## 上半圆角方、下半收成尖(盾形)
		hw = 21.0 - shrink
		if y < cy - 22 + shrink or y > cy + 26 - shrink:
			return False
		if y <= cy + 2:
			return abs(x - cx) <= hw
		t = (y - (cy + 2)) / (24.0 - shrink)
		return abs(x - cx) <= hw * (1.0 - t ** 1.6)
	for y in range(N):
		for x in range(N):
			px, py = x + 0.5, y + 0.5
			if not in_shield(px, py):
				continue
			if not in_shield(px, py, 2.6):
				ic.put("body", x, y, CREAM if (px - cx) < -4 and py < cy else (GRAY if px > cx else GRAY_HI))
				continue
			u = (px - cx) / 21.0
			k = min(3, max(0, int((u + 1.0) / 2.0 * 4.0)))
			ic.put("body", x, y, TEAL[k])
	## 齿轮徽记(米白): 外圈 8 齿 + 内圈空心
	gcx, gcy = cx, cy + 1
	for y in range(N):
		for x in range(N):
			dx, dy = x + 0.5 - gcx, y + 0.5 - gcy
			d = math.hypot(dx, dy)
			ang = math.atan2(dy, dx)
			tooth = (math.cos(ang * 8) > 0.35)
			outer = 9.0 + (2.4 if tooth else 0.0)
			if 4.0 <= d <= outer:
				ic.put("body", x, y, CREAM if dx + dy < 0 else hx("#c49846"))
	disc(ic, "body", gcx, gcy, 2.0, lambda dx, dy, d: TEAL[3])
	return ic.finish("turret-ward")


# ─── 7 火力同调(被动): 剑(携带者的攻击力)与炮管之间一道红色能量线 ───
def icon_link():
	ic = Icon()
	## 剑: 左下斜向上
	for y in range(N):
		for x in range(N):
			d, t, side = seg((x + 0.5, y + 0.5), (8.0, 44.0), (24.0, 18.0))
			if d <= 2.4 * (1.0 - 0.75 * t) + 0.5:
				ic.put("body", x, y, STEEL_HI if d < 0.8 else (STEEL if side < 0 else STEEL_MID))
	bline(ic, "body", (2.0, 41.0), (13.0, 48.0), GOLD, 3)       # 护手
	bline(ic, "body", (8.0, 50.0), (4.0, 57.0), WOOD, 3)        # 握柄
	ic.put("body", 3, 59, GOLD); ic.put("body", 4, 58, GOLD)
	## 炮管: 右上, 青绿炮身 + 灰炮口
	for y in range(N):
		for x in range(N):
			d, t, side = seg((x + 0.5, y + 0.5), (40.0, 46.0), (58.0, 30.0))
			if d <= 5.2:
				if t > 0.82:
					ic.put("body", x, y, GRAY_HI if side < 0 else GRAY_DK)
				else:
					ic.put("body", x, y, TEAL[0] if side < -2 else (TEAL[1] if side < 2 else TEAL[2]))
	disc(ic, "body", 40.0, 47.0, 6.5, lambda dx, dy, d: GRAY if dx + dy < 0 else GRAY_DK)
	## 能量线: 剑尖 → 炮身, 弧形, 芯亮外暗, 中间一颗能量球
	pts = []
	for k in range(41):
		t = k / 40.0
		x = 24.0 + (40.0 - 24.0) * t
		y = 18.0 + (40.0 - 18.0) * t - math.sin(t * math.pi) * 10.0
		pts.append((x, y))
	for i in range(len(pts) - 1):
		bline(ic, "fx", pts[i], pts[i + 1], ENERGY[2], 3)
	for i in range(len(pts) - 1):
		bline(ic, "fx", pts[i], pts[i + 1], ENERGY[1], 1)
	disc(ic, "fx", 31.5, 19.5, 3.2, lambda dx, dy, d: ENERGY[0] if d < 1.4 else ENERGY[1])
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
