# -*- coding: utf-8 -*-
"""summon_icons_all.py —— 图鉴「角色」栏其余召唤物 / 战场单位的攻击 · 技能 · 被动图标(2026-11-27, 用户「全部都搞好吧」)。

质量线 = 百夫长 / 炮台第三版(用户 11-27「可以过了」; 参考研究 docs/studies/20261127-参考-召唤物技能图标.md):
  背后光晕 halo + 左上亮边 rim + 一个最亮焦点 sparkle + 大块动势(刀光弧 / 尾焰 / 放射光 / 冲击环) + 主体占满。
形状库 tools/assetgen/icon_kit.py。每个单位的配色取自它自己的立绘(骷髅鬼火绿 / 礼盒粉 / 急救塔珊瑚与翡翠 …)。
做法(如实): 逐像素按几何判层上色, 分层 PNG → tools/assetgen/ase/png_layers_to_ase.lua 拼成 .aseprite(源文件 tools/assetgen/ase/summon_icons/)。
不是手画、不是 AI 生成; 不用随机数, 重跑逐字节相同。
用法: python tools/assetgen/summon_icons_all.py [名字前缀…]   (不给 = 全部; 输出 .out/summon_icons_all/, 成品由 --install 拷进 assets)
"""
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from icon_kit import *  # noqa: F401,F403
import icon_kit as K

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, ".out", "summon_icons_all")
REG = {}   # 名字 → (函数, 资源相对路径)


def icon(name, dest):
	def deco(fn):
		REG[name] = (fn, dest)
		return fn
	return deco


def P(name):   # 被动
	return "passive/summon-%s-icon.png" % name


def A(name):   # 攻击 / 技能
	return "skills/summon-%s.png" % name


# ════════════ 032 亡灵骷髅 ════════════
@icon("skel-strike", A("skel-strike"))
def _():
	ic = Icon()
	## 骨棒抡过去: 刀光弧跟着棒头走过的那段圆弧(圆心在握手处), 不贴着棒身(第一稿贴着像镰刀, 11-27 自检)
	crescent(ic, "back", 12, 56, 54, 14, -1.66, -0.84, [WHITE, GHOST[0], GHOST[1], GHOST[2], GHOST[3]])
	bone(ic, "body", (10, 56), (34, 24), 3.4, BONE)
	ellipse(ic, "body", 37, 19, 9, 8, BONE)            # 骨棒粗头
	ellipse(ic, "body", 33, 23, 6, 5, BONE)
	ic.rim()
	ic.halo([GHOST[3]])
	sparkle(ic, 50, 12, 6, (WHITE, GHOST[0], GHOST[1]))
	return ic


@icon("skel-bone", P("skel-bone"))
def _():
	ic = Icon()
	burst(ic, 32, 30, 14, 31, 8, [GHOST[2], GHOST[3]], phase=0.39, width=0.22)
	bone(ic, "body", (10, 54), (54, 10), 3.0, BONE)
	bone(ic, "body", (10, 10), (54, 54), 3.0, BONE)
	skull(ic, "body", 32, 28, 15, BONE, eye=GHOST)
	ic.rim()
	ic.halo([GHOST[3]])
	sparkle(ic, 26, 31, 3, (WHITE, GHOST[0], GHOST[1]))
	sparkle(ic, 38, 31, 3, (WHITE, GHOST[0], GHOST[1]))
	return ic


@icon("skel-boom", P("skel-boom"))
def _():
	ic = Icon()
	burst(ic, 32, 32, 14, 32, 9, [GHOST[1], GHOST[2], GHOST[3]], width=0.42)
	puff(ic, "back", 32, 33, 19, [GHOST[0], GHOST[1], GHOST[2], GHOST[3]], n=6, phase=0.3)   # 爆开的一团鬼火(第一稿是圈 + 辐条, 像靶子)
	skull(ic, "body", 32, 28, 12, BONE, eye=GHOST)
	for (a, b) in (((6, 10), (14, 16)), ((52, 8), (58, 15)), ((8, 52), (15, 46)), ((50, 50), (57, 56))):
		bone(ic, "body", a, b, 1.6, BONE)
	ic.rim()
	ic.halo([GHOST[3]])
	sparkle(ic, 32, 30, 4, (WHITE, GHOST[0], GHOST[1]))
	return ic


# ════════════ 033 海螺虫 ════════════
@icon("worm-bite", A("worm-bite"))
def _():
	ic = Icon()
	def head(x, y, px, py):     # 张嘴的虫头(嘴朝右, 吃豆形)
		dx, dy = px - 28, py - 34
		d = math.hypot(dx, dy)
		a = math.atan2(dy, dx)
		if d <= 24 and abs(a) > 0.62:
			ic.put("body", x, y, LEAF[lit_idx(dx, dy, 24, 4, 0.15)])
	each(head)
	for k in range(5):          # 上下两排牙
		t = k / 4.0
		for sgn in (-1, 1):
			a = sgn * 0.62
			bx = 28 + math.cos(a) * (8 + t * 15)
			by = 34 + math.sin(a) * (8 + t * 15)
			K.poly(ic, "body", [(bx - 2, by), (bx + 2, by), (bx + 1.0 * -sgn * 0 + 0.5, by - sgn * 4.5)], BONE, flat=BONE[0])
	ellipse(ic, "body", 24, 20, 4.5, 4.5, [WHITE, WHITE, BONE[1], BONE[2]])
	ellipse(ic, "body", 25, 21, 2, 2, [OUTLINE] * 4)
	ellipse(ic, "body", 12, 38, 3, 2.2, [PINK[1]] * 4)   # 腮红
	for (bx, tx, ty) in ((18, 10, 4), (28, 26, 2)):        # 触角(第一稿光一个圆头像吃豆, 补成虫)
		thick_line(ic, "body", (bx, 14), (tx, ty + 4), 1.2, [LEAF[1], LEAF[2], LEAF[3]])
		ellipse(ic, "body", tx, ty + 3, 3, 3, LEAF)
	ic.rim()
	ic.halo([LEAF[2]])
	sparkle(ic, 56, 34, 6, (WHITE, LEAF[0], LEAF[1]))
	for (a, b) in (((50, 22), (56, 16)), ((50, 46), (56, 52)), ((58, 26), (62, 24))):
		bline(ic, "fx", a, b, LEAF[0], 2)
	return ic


@icon("worm-gift", P("worm-gift"))
def _():
	ic = Icon()
	burst(ic, 30, 36, 12, 31, 8, [GOLD[1], GOLD[2]], width=0.22)
	ellipse(ic, "body", 28, 40, 19, 15, CORAL, rot=-0.45)
	K.poly(ic, "body", [(36, 26), (50, 12), (46, 30)], CORAL, 0.2)     # 螺尖
	for i in range(60):                                                 # 螺纹
		t = i / 59.0
		a = t * 4.2 * math.pi
		r = 2 + t * 15
		ic.put("body", 28 + math.cos(a) * r * 1.0, 40 + math.sin(a) * r * 0.75, CORAL[4])
	ellipse(ic, "body", 22, 46, 6, 4, [CREAM[0], CREAM[1], CREAM[2], CREAM[3]], rot=-0.45)   # 螺口
	star(ic, "body", 52, 44, 7, 3, 4, VIOLET)                           # 三件装备: 宝石 / 小剑 / 金币
	thick_line(ic, "body", (8, 20), (20, 8), 1.6, [STEEL[1], STEEL[2], STEEL[3]])
	thick_line(ic, "body", (8, 14), (14, 20), 1.4, [GOLD[1], GOLD[2], GOLD[3]])
	ellipse(ic, "body", 52, 20, 5.5, 5.5, GOLD)
	ic.rim()
	ic.halo([GOLD[2]])
	sparkle(ic, 50, 12, 5)
	return ic


# ════════════ 034 大熊 ════════════
@icon("bear-paw", A("bear-paw"))
def _():
	ic = Icon()
	for k in range(3):                               # 三道爪痕(背后光)
		o = k * 8
		crescent(ic, "back", 8 + o, 60 + o, 54, 7, -1.45, -0.35, [WHITE, FIRE[1], FIRE[2], FIRE[3]])
	paw(ic, "body", 28, 34, 19, FUR)
	ellipse(ic, "body", 28, 41, 8, 6, [EARTH[1], EARTH[2], EARTH[2], EARTH[3]])
	ic.rim()
	ic.halo([GOLD[2]])
	sparkle(ic, 54, 12, 6, (WHITE, FIRE[1], FIRE[2]))
	return ic


@icon("bear-wave", P("bear-wave"))
def _():
	ic = Icon()
	for r, c in ((60, GOLD[2]), (48, GOLD[1]), (36, FIRE[1])):
		crescent(ic, "back", 14, 52, r, 6, -1.45, -0.05, [WHITE, c, GOLD[3]])
	ellipse(ic, "body", 18, 56, 17, 6, EARTH)                       # 被砸裂的地面(第一稿是整条横带, 太平)
	paw(ic, "body", 16, 38, 13, FUR)
	for (x, y, r) in ((34, 50, 3), (42, 44, 2.5), (28, 46, 2), (50, 40, 2)):
		ellipse(ic, "body", x, y, r, r, STONE)
	ic.rim()
	ic.halo([GOLD[3]])
	sparkle(ic, 16, 54, 6, (WHITE, FIRE[1], FIRE[2]))
	return ic


# ════════════ 072 蛋糕礼盒 ════════════
def _gift(ic, layer, cx, cy, s, rot=0.0):
	ca, sa = math.cos(rot), math.sin(rot)
	def R(px, py):
		return (cx + px * ca - py * sa, cy + px * sa + py * ca)
	poly(ic, layer, [R(-s, -s * 0.55), R(s, -s * 0.55), R(s, s), R(-s, s)], PINK, 0.15)                  # 盒身
	poly(ic, layer, [R(-s * 1.12, -s * 0.95), R(s * 1.12, -s * 0.95), R(s * 1.12, -s * 0.5), R(-s * 1.12, -s * 0.5)], CANDY, 0.25)   # 盒盖
	poly(ic, layer, [R(-s * 0.2, -s * 0.95), R(s * 0.2, -s * 0.95), R(s * 0.2, s), R(-s * 0.2, s)], CORAL, 0.0, flat=CORAL[3])   # 缎带竖
	for sgn in (-1, 1):                                                                                  # 蝴蝶结
		bx, by = R(sgn * s * 0.42, -s * 1.22)
		ellipse(ic, layer, bx, by, s * 0.42, s * 0.26, CORAL, rot=rot + sgn * 0.5)
	kx, ky = R(0, -s * 1.05)
	ellipse(ic, layer, kx, ky, s * 0.18, s * 0.18, CORAL)


@icon("cake-bump", A("cake-bump"))
def _():
	ic = Icon()
	burst(ic, 54, 30, 4, 18, 7, [WHITE, PINK[1], PINK[2]], width=0.3)
	_gift(ic, "body", 30, 36, 17, rot=0.28)
	ic.rim()
	ic.halo([PINK[2]])
	for k in range(3):
		bline(ic, "fx", (2, 22 + k * 10), (10, 22 + k * 10), PINK[1], 2)
	sparkle(ic, 54, 30, 6, (WHITE, PINK[0], PINK[1]))
	return ic


@icon("cake-lure", P("cake-lure"))
def _():
	ic = Icon()
	burst(ic, 32, 32, 12, 32, 12, [PINK[1], PINK[2], PINK[3]], width=0.25)
	heart(ic, "body", 32, 32, 17, CANDY)
	ellipse(ic, "body", 25, 24, 4, 3, [WHITE, PINK[0], PINK[0], PINK[1]], rot=-0.6)
	ic.rim()
	ic.halo([PINK[3]])
	for (a, b) in (((4, 4), (14, 14)), ((60, 4), (50, 14)), ((4, 60), (14, 50)), ((60, 60), (50, 50))):
		bline(ic, "fx", a, b, PINK[0], 2)
		bline(ic, "fx", b, (b[0] + (3 if a[0] < 32 else -3) * -1, b[1]), PINK[0], 2)
		bline(ic, "fx", b, (b[0], b[1] + (3 if a[1] < 32 else -3) * -1), PINK[0], 2)
	sparkle(ic, 32, 30, 5, (WHITE, PINK[0], PINK[1]))
	return ic


@icon("cake-field", P("cake-field"))
def _():
	ic = Icon()
	ellipse(ic, "back", 32, 46, 30, 13, [PINK[1], PINK[2], PINK[2], PINK[3]], hollow=0.72)
	ellipse(ic, "back", 32, 46, 20, 8, [PINK[2]] * 4, hollow=0.8)
	poly(ic, "body", [(18, 34), (46, 34), (46, 46), (18, 46)], CREAM, 0.1)          # 蛋糕坯
	poly(ic, "body", [(16, 28), (48, 28), (48, 35), (16, 35)], PINK, 0.2)           # 奶油
	for x in (20, 28, 36, 44):
		ellipse(ic, "body", x, 36, 2.5, 3, PINK)                                     # 奶油滴
	ellipse(ic, "body", 32, 23, 4, 4, RED)                                          # 樱桃
	plus(ic, "body", 52, 14, 8, 3, JADE)
	plus(ic, "body", 10, 18, 5, 2, JADE)
	ic.rim()
	ic.halo([PINK[3]])
	sparkle(ic, 30, 21, 4)
	for (x, y) in ((44, 22), (20, 14), (56, 30)):
		ic.put("fx", x, y, JADE[0]); ic.put("fx", x, y - 1, JADE[1])
	return ic


@icon("cake-split", P("cake-split"))
def _():
	ic = Icon()
	burst(ic, 32, 34, 4, 30, 8, [WHITE, PINK[1], PINK[2]], phase=0.2, width=0.18)
	_gift(ic, "body", 17, 38, 11, rot=-0.35)
	_gift(ic, "body", 47, 38, 11, rot=0.35)
	ic.rim()
	ic.halo([PINK[3]])
	bline(ic, "fx", (32, 4), (28, 18), WHITE, 2); bline(ic, "fx", (28, 18), (34, 30), WHITE, 2); bline(ic, "fx", (34, 30), (30, 44), WHITE, 2)
	sparkle(ic, 32, 30, 6, (WHITE, PINK[0], PINK[1]))
	return ic


# ════════════ 077 小手枪 ════════════
def _pistol(ic, cx, cy, s):
	thick_line(ic, "body", (cx - s * 0.2, cy), (cx + s * 1.3, cy - s * 0.65), s * 0.2, [STEEL[1], STEEL[2], STEEL[4]])   # 枪管
	poly(ic, "body", [(cx - s * 0.45, cy - s * 0.18), (cx + s * 0.2, cy - s * 0.38), (cx + s * 0.3, cy + s * 0.05), (cx - s * 0.1, cy + s * 0.32)], GRAY, 0.2)   # 机匣
	poly(ic, "body", [(cx - s * 0.45, cy - s * 0.1), (cx - s * 0.05, cy + s * 0.25), (cx - s * 0.55, cy + s * 1.05), (cx - s * 1.0, cy + s * 0.85)],
		[CREAM[0], CREAM[1], CREAM[2], CREAM[3]], 0.2)   # 象牙握把
	ellipse(ic, "body", cx - s * 0.05, cy + s * 0.32, s * 0.18, s * 0.14, [GRAY[1], GRAY[2], GRAY[3], GRAY[4]], hollow=0.5)   # 扳机护圈


@icon("pistol-shot", A("pistol-shot"))
def _():
	ic = Icon()
	flame(ic, "back", (44, 20), (63, 9), 9, [WHITE, FIRE[1], FIRE[2], FIRE[3]], wob=1.4)
	burst(ic, 46, 19, 3, 16, 6, [FIRE[1], FIRE[2]], width=0.3)
	_pistol(ic, 22, 38, 18)
	ic.rim()
	ic.halo([FIRE[3]])
	sparkle(ic, 47, 18, 6, (WHITE, FIRE[1], FIRE[2]))
	for (x, y) in ((58, 4), (61, 16), (52, 4)):
		ic.put("fx", x, y, FIRE[2])
	return ic


# ════════════ 096 斧头 ════════════
def _axe(ic, a, b, hs, head, edge=None, layer="body"):
	"""斧子: a→b 木柄, b 端垂直装斧刃(朝柄的右侧)。head = 刃色 5 档。"""
	thick_line(ic, layer, a, b, 2.6, [WOOD[0], WOOD[1], WOOD[2]])
	L = math.hypot(b[0] - a[0], b[1] - a[1])
	ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
	nx, ny = uy, -ux
	T = (b[0] - ux * hs * 0.5, b[1] - uy * hs * 0.5)
	def Q(su, sn):
		return (T[0] + ux * su * hs + nx * sn * hs, T[1] + uy * su * hs + ny * sn * hs)
	pts = [Q(0.55, -0.35), Q(0.55, 0.3), Q(1.05, 1.15), Q(0.6, 1.55), Q(0.0, 1.7), Q(-0.6, 1.55), Q(-1.05, 1.15), Q(-0.55, 0.3), Q(-0.55, -0.35)]
	poly(ic, layer, pts, head, 0.15)
	e = edge or head[0]
	for k in range(5):
		bline(ic, layer, Q(1.05 - k * 0.0, 1.15), Q(0.6, 1.55), e)
	bline(ic, layer, Q(1.0, 1.2), Q(0.55, 1.58), e, 2)
	bline(ic, layer, Q(0.55, 1.58), Q(0.0, 1.72), e, 2)
	bline(ic, layer, Q(0.0, 1.72), Q(-0.55, 1.58), e, 2)
	return Q(0.0, 1.7)


@icon("axe-chop", A("axe-chop"))
def _():
	ic = Icon()
	crescent(ic, "back", 14, 58, 52, 11, -1.7, -0.45, [WHITE, STEEL[1], STEEL[2], STEEL[3]])
	_axe(ic, (12, 56), (34, 22), 11, STEEL)
	poly(ic, "body", [(50, 40), (60, 36), (58, 48)], ICE, 0.1)          # 窃来的护盾碎片
	poly(ic, "body", [(44, 50), (52, 50), (46, 58)], ICE, 0.1)
	ic.rim()
	ic.halo([STEEL[3]])
	sparkle(ic, 56, 30, 6, (WHITE, ICE[1], ICE[2]))
	return ic


@icon("axe-guard", A("axe-guard"))
def _():
	ic = Icon()
	ellipse(ic, "back", 32, 34, 29, 29, [ICE[1], ICE[2], ICE[2], ICE[3]], hollow=0.86)
	_axe(ic, (22, 58), (30, 14), 10, STEEL)
	plus(ic, "body", 46, 44, 10, 3.6, JADE)
	ic.rim()
	ic.halo([ICE[3]])
	sparkle(ic, 14, 14, 5, (WHITE, ICE[1], ICE[2]))
	return ic


@icon("axe-grow", P("axe-grow"))
def _():
	ic = Icon()
	ellipse(ic, "body", 30, 46, 24, 12, [WOOD[0], WOOD[1], WOOD[2], WOOD[3]])            # 树桩
	for r in (6, 11, 16, 20):
		ellipse(ic, "body", 30, 44, r, r * 0.45, [EARTH[0]] * 4, hollow=(r - 1.4) / r)
	ellipse(ic, "body", 30, 44, 21, 9.5, [EARTH[0], EARTH[0], EARTH[1], EARTH[1]], hollow=0.92)
	_axe(ic, (10, 14), (26, 40), 8, STEEL)
	for k in range(3):
		chevrons(ic, "fx", (54, 34 - k * 10), (54, 26 - k * 10), 1, 6, LEAF[0 if k == 2 else 1])
	ic.rim()
	ic.halo([LEAF[2]])
	sparkle(ic, 54, 6, 5, (WHITE, LEAF[0], LEAF[1]))
	return ic


@icon("axe-smash", P("axe-smash"))
def _():
	ic = Icon()
	burst(ic, 40, 52, 6, 30, 9, [WHITE, GOLD[1], GOLD[2]], phase=-1.57, width=0.3)
	ellipse(ic, "body", 40, 58, 20, 5, EARTH)
	_axe(ic, (8, 10), (34, 44), 11, STONE, edge=STONE[0])
	for (x, y, r) in ((54, 44, 3.5), (60, 36, 2.5), (22, 52, 2.5), (48, 34, 2)):
		ellipse(ic, "body", x, y, r, r, STONE)
	ic.rim()
	ic.halo([GOLD[3]])
	sparkle(ic, 42, 50, 6)
	return ic


@icon("axe-cleave", P("axe-cleave"))
def _():
	ic = Icon()
	thick_line(ic, "back", (44, 2), (44, 62), 3.5, [WHITE, RED[1], RED[3]])            # 竖劈刀光
	_axe(ic, (14, 58), (22, 14), 12, STEEL)
	for (x, y) in ((52, 22), (55, 34), (50, 46)):
		ellipse(ic, "body", x, y, 2.6, 3.6, RED)                                       # 流血
	ic.rim()
	ic.halo([RED[4]])
	sparkle(ic, 44, 30, 6, (WHITE, RED[0], RED[1]))
	return ic


@icon("axe-sweep", P("axe-sweep"))
def _():
	ic = Icon()
	crescent(ic, "back", 32, 40, 30, 10, -3.14, 0.0, [WHITE, GOLD[0], GOLD[1], GOLD[2]])   # 180° 横扫
	_axe(ic, (30, 60), (32, 22), 10, GOLD, edge=GOLD[0])
	for k in range(2):
		chevrons(ic, "fx", (50 + k * 5, 58), (58 + k * 5, 58), 1, 4, GOLD[0])
	ic.rim()
	ic.halo([GOLD[3]])
	sparkle(ic, 6, 36, 5)
	return ic


@icon("axe-undead", P("axe-undead"))
def _():
	ic = Icon()
	ellipse(ic, "back", 32, 34, 30, 30, [GHOST[1], GHOST[2], GHOST[3], GHOST[4]], hollow=0.78)
	for k in range(6):
		a = k * math.pi / 3 + 0.3
		flame(ic, "back", (32 + math.cos(a) * 20, 34 + math.sin(a) * 20), (32 + math.cos(a + 0.5) * 30, 34 + math.sin(a + 0.5) * 30), 4, [GHOST[0], GHOST[1], GHOST[2]], wob=0.6)
	_axe(ic, (20, 58), (30, 16), 11, INK, edge=GHOST[1])
	skull(ic, "body", 46, 46, 7, BONE, eye=GHOST)
	ic.rim()
	ic.halo([GHOST[3]])
	sparkle(ic, 46, 46, 3, (WHITE, GHOST[0], GHOST[1]))
	return ic


@icon("axe-seraph", P("axe-seraph"))
def _():
	ic = Icon()
	for sgn in (-1, 1):                                                                   # 天使翼
		for k in range(4):
			ellipse(ic, "back", 32 + sgn * (10 + k * 5), 26 + k * 4, 11 - k * 1.5, 4.5, [WHITE, CREAM[0], GOLD[0], GOLD[1]], rot=sgn * (0.5 + k * 0.18))
	flame(ic, "back", (32, 40), (32, 2), 9, [WHITE, FIRE[1], FIRE[2], FIRE[3]])
	_axe(ic, (32, 62), (32, 24), 10, GOLD, edge=WHITE)
	ic.rim()
	ic.halo([GOLD[2]])
	sparkle(ic, 32, 8, 6, (WHITE, FIRE[1], FIRE[2]))
	return ic


@icon("axe-holo", P("axe-holo"))
def _():
	ic = Icon()
	for k in range(3):
		ellipse(ic, "back", 32, 54, 14 + k * 8, 4 + k * 2.4, [HOLO[1 + k % 2]] * 4, hollow=0.84)
	for x in (10, 54):
		thick_line(ic, "back", (x, 52), (x, 18), 1.2, [HOLO[1], HOLO[2], HOLO[2]])
	_axe(ic, (30, 54), (30, 14), 11, HOLO, edge=WHITE)
	plus(ic, "body", 50, 14, 6, 2.2, JADE)
	ic.rim()
	ic.halo([HOLO[3]])
	sparkle(ic, 50, 14, 4, (WHITE, HOLO[0], HOLO[1]))
	return ic


@icon("axe-ember", P("axe-ember"))
def _():
	ic = Icon()
	flame(ic, "back", (32, 56), (30, 0), 16, [EMBER[0], EMBER[1], EMBER[2], EMBER[3]], wob=2.2)
	_axe(ic, (22, 60), (30, 22), 11, INK, edge=EMBER[1])
	for (x, y, r) in ((50, 46, 3.4), (56, 36, 2.4), (12, 40, 2.6), (46, 56, 2.0)):
		ellipse(ic, "body", x, y, r, r * 1.2, EMBER)                                   # 余烬种子
	ic.rim()
	ic.halo([EMBER[3]])
	sparkle(ic, 31, 10, 6, (WHITE, EMBER[0], EMBER[1]))
	return ic


# ════════════ 105 炮筒 ════════════
def _cannon(ic, cx, cy, s):
	thick_line(ic, "body", (cx - s * 0.9, cy + s * 0.25), (cx + s * 0.9, cy - s * 0.45), s * 0.36, [GRAY[1], GRAY[2], GRAY[4]])   # 炮管
	ellipse(ic, "body", cx + s * 0.95, cy - s * 0.48, s * 0.22, s * 0.36, [GRAY[2], GRAY[3], GRAY[4], GRAY[4]], rot=-0.35)   # 炮口
	ellipse(ic, "body", cx - s * 0.95, cy + s * 0.27, s * 0.24, s * 0.24, GRAY)
	poly(ic, "body", [(cx - s * 0.7, cy + s * 0.35), (cx + s * 0.4, cy + s * 0.2), (cx + s * 0.3, cy + s * 0.75), (cx - s * 0.8, cy + s * 0.8)], WOOD + [WOOD[3]], 0.1)   # 炮架
	for wx in (-0.45, 0.2):
		ellipse(ic, "body", cx + wx * s, cy + s * 0.82, s * 0.3, s * 0.3, [WOOD[0], WOOD[1], WOOD[2], WOOD[3]])
		ellipse(ic, "body", cx + wx * s, cy + s * 0.82, s * 0.09, s * 0.09, [GRAY[2]] * 4)


@icon("cannon-fire", A("cannon-fire"))
def _():
	ic = Icon()
	puff(ic, "back", 50, 18, 10, SMOKE + [SMOKE[2]], n=4)
	burst(ic, 46, 22, 3, 14, 7, [WHITE, FIRE[1], FIRE[2]], width=0.4)
	_cannon(ic, 26, 38, 20)
	ellipse(ic, "body", 57, 8, 5, 5, GRAY)                                                # 飞出的炮弹
	ic.rim()
	ic.halo([FIRE[3]])
	sparkle(ic, 46, 22, 6, (WHITE, FIRE[1], FIRE[2]))
	return ic


@icon("cannon-heavy", A("cannon-heavy"))
def _():
	ic = Icon()
	flame(ic, "back", (40, 26), (0, 50), 11, [WHITE, FIRE[1], FIRE[2], FIRE[3], FIRE[4]], wob=1.5)
	ellipse(ic, "body", 44, 24, 11, 11, GRAY)
	ellipse(ic, "body", 40, 20, 3, 3, [GRAY[0]] * 4)
	for (x, y) in ((52, 46), (58, 38), (46, 54)):
		ellipse(ic, "body", x, y, 2.6, 3.6, RED)                                       # 流血
	chevrons(ic, "fx", (54, 10), (64, 4), 2, 4, WHITE)
	ic.rim()
	ic.halo([FIRE[4]])
	sparkle(ic, 52, 18, 6, (WHITE, FIRE[1], FIRE[2]))
	return ic


# ════════════ 106 遥控炸弹 ════════════
def _bomb(ic, cx, cy, r):
	ellipse(ic, "body", cx, cy, r, r, INK)
	poly(ic, "body", [(cx - r * 0.35, cy - r * 1.05), (cx + r * 0.35, cy - r * 1.05), (cx + r * 0.3, cy - r * 0.8), (cx - r * 0.3, cy - r * 0.8)], GRAY, 0.1)
	thick_line(ic, "body", (cx + r * 0.2, cy - r * 1.0), (cx + r * 0.6, cy - r * 1.6), 1.0, [GRAY[1], GRAY[2], GRAY[3]])   # 天线
	ellipse(ic, "body", cx + r * 0.62, cy - r * 1.65, r * 0.2, r * 0.2, RED)
	ellipse(ic, "body", cx - r * 0.38, cy - r * 0.38, r * 0.22, r * 0.16, [INK[0]] * 4, rot=-0.7)


@icon("remote-chase", P("remote-chase"))
def _():
	ic = Icon()
	ring(ic, "back", 32, 34, 25, 28, RED[2])
	ring(ic, "back", 32, 34, 15, 16.5, RED[3])
	for (a, b) in (((32, 2), (32, 14)), ((32, 54), (32, 64)), ((0, 34), (12, 34)), ((52, 34), (64, 34))):
		thick_line(ic, "back", a, b, 1.6, [RED[1], RED[2], RED[3]])
	_bomb(ic, 32, 38, 13)
	ic.rim()
	ic.halo([RED[4]])
	sparkle(ic, 40, 16, 5, (WHITE, RED[0], RED[1]))
	return ic


@icon("remote-boom", P("remote-boom"))
def _():
	ic = Icon()
	burst(ic, 32, 34, 10, 32, 11, [FIRE[1], FIRE[2], FIRE[3]], width=0.36)
	puff(ic, "body", 32, 34, 21, [FIRE[0], FIRE[1], FIRE[2], FIRE[3]], n=6, phase=0.4)
	puff(ic, "body", 32, 36, 11, [WHITE, FIRE[0], FIRE[1], FIRE[1]], n=4)
	for (x, y, r) in ((8, 10, 3.5), (56, 8, 3), (6, 54, 3), (58, 56, 3.5)):
		ellipse(ic, "body", x, y, r, r, INK)                                           # 弹片
	ic.rim()
	ic.halo([FIRE[4]])
	sparkle(ic, 32, 34, 7, (WHITE, FIRE[0], FIRE[1]))
	return ic


# ════════════ 107 武士刀小将 ════════════
def _katana(ic, a, b, layer="body"):
	"""武士刀: a = 柄尾, b = 刀尖; 刀身微弯。"""
	L = math.hypot(b[0] - a[0], b[1] - a[1])
	ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
	nx, ny = -uy, ux
	g = (a[0] + ux * L * 0.24, a[1] + uy * L * 0.24)
	thick_line(ic, layer, a, g, 2.4, [INK[0], INK[1], INK[2]])                                     # 柄(缠绳)
	for k in range(4):
		t = 0.05 + k * 0.05
		ic.put(layer, a[0] + ux * L * t, a[1] + uy * L * t, GOLD[1])
	thick_line(ic, layer, (g[0] + nx * 5, g[1] + ny * 5), (g[0] - nx * 5, g[1] - ny * 5), 1.6, [GOLD[0], GOLD[2], GOLD[3]])   # 护手
	def f(x, y, px, py):
		d, t, side = seg((px, py), g, b)
		if t <= 0.0 or t >= 1.0:
			return
		bow = math.sin(t * math.pi) * 2.2
		off = side / max(1e-6, math.hypot(b[0] - g[0], b[1] - g[1]))
		w = 2.6 * (1.0 - t ** 3)
		dd = off - bow * -1
		if -w <= dd <= w * 0.6:
			ic.put(layer, x, y, STEEL[0] if dd > w * 0.1 else (STEEL[2] if dd > -w * 0.4 else STEEL[3]))
	each(f)


@icon("katana-slash", A("katana-slash"))
def _():
	ic = Icon()
	crescent(ic, "back", 8, 60, 54, 10, -1.75, -0.4, [WHITE, ICE[0], ICE[1], ICE[2]])
	_katana(ic, (8, 58), (54, 10))
	ic.rim()
	ic.halo([ICE[3]])
	sparkle(ic, 54, 10, 6, (WHITE, ICE[0], ICE[1]))
	return ic


@icon("katana-iai", A("katana-iai"))
def _():
	ic = Icon()
	## 三道龙卷风: 叠环画法(第一 / 二稿竖条纹看着像冰锥, 11-27 自检)
	WIND = [WHITE, ICE[1], ICE[2], ICE[3], ICE[4]]
	tornado(ic, "back", 12, 60, 8, 24, 2.0, 9, WIND, rings=11, sway=1.5)
	tornado(ic, "back", 52, 60, 56, 24, 2.0, 9, WIND, rings=11, sway=-1.5)
	tornado(ic, "body", 32, 62, 31, 10, 2.5, 14, WIND, rings=15, sway=2.5)
	_katana(ic, (6, 40), (58, 30), layer="fx")
	ic.rim()
	ic.halo([ICE[3]])
	sparkle(ic, 58, 30, 6, (WHITE, ICE[0], ICE[1]))
	return ic


@icon("pistol-tiny", P("pistol-tiny"))
def _():
	ic = Icon()
	## 小手枪缩在一圈护罩里, 子弹撞上护罩被弹开(第一稿只有一面圆盾, 像靶子 11-27 自检)
	ellipse(ic, "back", 30, 36, 26, 26, [ICE[1], ICE[2], ICE[2], ICE[3]], hollow=0.84)
	_pistol(ic, 28, 34, 11)
	ellipse(ic, "body", 53, 12, 5, 3.2, GOLD, rot=-0.8)          # 撞扁的子弹
	ic.rim()
	ic.halo([ICE[3]])
	for (a, b) in (((47, 18), (40, 24)), ((49, 21), (46, 29)), ((44, 16), (36, 18))):
		bline(ic, "fx", a, b, ICE[0], 1)
	sparkle(ic, 47, 19, 5, (WHITE, ICE[1], ICE[2]))
	return ic


# ════════════ 079 急救塔 ════════════
@icon("tower-shot", A("tower-shot"))
def _():
	ic = Icon()
	flame(ic, "back", (24, 38), (62, 4), 10, [WHITE, JADE[0], JADE[1], JADE[2]], wob=1.0)
	crescent(ic, "body", 24, 38, 17, 7, 0.15, 2.95, CORAL)                 # 珊瑚托座(兜住宝珠; 第一稿是几根乱枝)
	for (a, b) in (((9, 40), (4, 28)), ((39, 40), (44, 30))):
		thick_line(ic, "body", a, b, 2.4, [CORAL[1], CORAL[2], CORAL[3]])
	ellipse(ic, "body", 24, 38, 11, 11, JADE)
	ellipse(ic, "body", 20, 34, 3.5, 3.5, [WHITE] * 4)
	plus(ic, "body", 50, 46, 9, 3.2, JADE)
	ic.rim()
	ic.halo([JADE[2]])
	sparkle(ic, 56, 10, 6, (WHITE, JADE[0], JADE[1]))
	return ic


@icon("tower-sync", P("tower-sync"))
def _():
	ic = Icon()
	crescent(ic, "body", 32, 32, 27, 8, -2.9, -0.35, [JADE[0], JADE[1], JADE[2], JADE[3]])
	crescent(ic, "body", 32, 32, 27, 8, 0.25, 2.8, [CORAL[0], CORAL[1], CORAL[2], CORAL[3]])
	poly(ic, "body", [(50, 4), (62, 18), (46, 22)], JADE, 0.1)          # 箭头
	poly(ic, "body", [(14, 60), (2, 46), (18, 42)], CORAL, 0.1)
	gear(ic, "body", 32, 32, 11, 8, [CREAM[0], CREAM[1], CREAM[2], CREAM[3]], hole=0.3)
	ic.rim()
	ic.halo([JADE[3]])
	sparkle(ic, 32, 32, 3)
	return ic


@icon("tower-gold", P("tower-gold"))
def _():
	ic = Icon()
	burst(ic, 32, 32, 10, 32, 10, [GOLD[1], GOLD[2]], width=0.24)
	plus(ic, "back", 32, 32, 22, 7, [JADE[1], JADE[2], JADE[2], JADE[3]])
	ux, uy = 0.7071, -0.7071
	base = (32 - ux * 16, 32 - uy * 16)
	def bullet(x, y, px, py):
		rx, ry = px - base[0], py - base[1]
		a = rx * ux + ry * uy
		sd = rx * -uy + ry * ux
		if a < 0 or a > 30:
			return
		r = 7 if a < 18 else 7 * math.cos((a - 18) / 12 * math.pi / 2) ** 0.8
		if abs(sd) <= r:
			ic.put("body", x, y, GOLD[0] if sd < -r * 0.4 else (GOLD[1] if sd < r * 0.3 else GOLD[3]))
	each(bullet)
	ic.rim()
	ic.halo([GOLD[3]])
	sparkle(ic, 50, 14, 6)
	return ic


# ════════════ 130 舞狮 ════════════
def _lion(ic, cx, cy, s, mouth=True):
	for k in range(9):                                                                   # 鬃毛绒球
		a = -math.pi * 0.95 + k * math.pi * 1.9 / 8
		ellipse(ic, "body", cx + math.cos(a) * s * 1.05, cy + math.sin(a) * s * 0.95, s * 0.3, s * 0.3, [WHITE, CREAM[0], PINK[1], PINK[2]])
	ellipse(ic, "body", cx, cy, s, s * 0.9, RED)
	thick_line(ic, "body", (cx - s * 0.8, cy - s * 0.42), (cx + s * 0.8, cy - s * 0.42), s * 0.1, [GOLD[0], GOLD[1], GOLD[3]])
	for ex in (-1, 1):
		ellipse(ic, "body", cx + ex * s * 0.4, cy - s * 0.12, s * 0.27, s * 0.25, [WHITE, WHITE, BONE[1], BONE[2]])
		ellipse(ic, "body", cx + ex * s * 0.36, cy - s * 0.1, s * 0.12, s * 0.12, [OUTLINE] * 4)
	ellipse(ic, "body", cx, cy + s * 0.12, s * 0.2, s * 0.14, GOLD)                    # 鼻
	if mouth:
		ellipse(ic, "body", cx, cy + s * 0.52, s * 0.55, s * 0.3, [RED[5], RED[6], RED[6], RED[6]])
		for k in range(5):
			x = cx - s * 0.4 + k * s * 0.2
			K.poly(ic, "body", [(x - 1.5, cy + s * 0.3), (x + 1.5, cy + s * 0.3), (x, cy + s * 0.44)], BONE, flat=WHITE)


@icon("lion-bite", A("lion-bite"))
def _():
	ic = Icon()
	burst(ic, 32, 34, 12, 31, 10, [GOLD[1], GOLD[2]], width=0.26)
	_lion(ic, 32, 32, 17)
	ic.rim()
	ic.halo([GOLD[3]])
	sparkle(ic, 32, 50, 6, (WHITE, GOLD[0], GOLD[1]))
	return ic


@icon("lion-charge", A("lion-charge"))
def _():
	ic = Icon()
	for k in range(4):
		thick_line(ic, "back", (2, 18 + k * 9), (22, 18 + k * 9), 1.6, [WHITE, GOLD[1], GOLD[2]])
	puff(ic, "back", 14, 54, 9, [CREAM[0], CREAM[1], CREAM[2], CREAM[3]], n=4)
	_lion(ic, 38, 32, 16)
	for (x, y) in ((58, 10), (54, 4), (62, 18)):
		star(ic, "body", x, y, 4, 1.6, 5, GOLD)                                          # 眩晕星
	ic.rim()
	ic.halo([GOLD[3]])
	sparkle(ic, 56, 36, 6)
	return ic


# ════════════ 115 暗影忍者 ════════════
def _hood(ic, cx, cy, s, pal, eye=RED):
	ellipse(ic, "body", cx, cy, s, s * 1.05, pal)
	poly(ic, "body", [(cx - s * 0.8, cy - s * 0.12), (cx + s * 0.8, cy - s * 0.12), (cx + s * 0.7, cy + s * 0.22), (cx - s * 0.7, cy + s * 0.22)],
		[BONE[1], BONE[2], BONE[2], BONE[3]], 0.1)                                     # 露眼的一条
	for ex in (-1, 1):
		K.poly(ic, "body", [(cx + ex * s * 0.15, cy + s * 0.02), (cx + ex * s * 0.58, cy - s * 0.04), (cx + ex * s * 0.5, cy + s * 0.12)], pal, flat=eye[2])
	thick_line(ic, "body", (cx + s * 0.6, cy - s * 0.55), (cx + s * 1.35, cy - s * 0.95), s * 0.12, [VIOLET[1], VIOLET[2], VIOLET[3]])   # 头巾飘带


@icon("ninja-blade", A("ninja-blade"))
def _():
	ic = Icon()
	crescent(ic, "back", 52, 54, 46, 10, -3.0, -1.65, [WHITE, SHADOW[0], SHADOW[1], SHADOW[2]])
	_katana(ic, (8, 56), (46, 18))
	ic.rim()
	ic.halo([SHADOW[3]])
	sparkle(ic, 46, 18, 6, (WHITE, SHADOW[0], SHADOW[1]))
	return ic


@icon("ninja-strike", A("ninja-strike"))
def _():
	ic = Icon()
	puff(ic, "back", 24, 28, 20, SHADOW + [SHADOW[4]], n=6, phase=0.2)
	burst(ic, 42, 46, 4, 20, 8, [WHITE, RED[1], RED[3]], width=0.4)
	_katana(ic, (14, 10), (44, 48))
	ic.rim()
	ic.halo([SHADOW[3]])
	sparkle(ic, 44, 48, 7, (WHITE, RED[0], RED[1]))
	return ic


@icon("ninja-stealth", P("ninja-stealth"))
def _():
	ic = Icon()
	puff(ic, "back", 32, 40, 24, SHADOW + [SHADOW[4]], n=7, phase=0.5)
	_hood(ic, 32, 30, 15, INK, eye=[VIOLET[0], VIOLET[1], VIOLET[1]])
	ic.rim()
	ic.halo([SHADOW[3]])
	sparkle(ic, 24, 30, 3, (WHITE, VIOLET[0], VIOLET[1]))
	sparkle(ic, 40, 30, 3, (WHITE, VIOLET[0], VIOLET[1]))
	return ic


@icon("ninja-clone", P("ninja-clone"))
def _():
	ic = Icon()
	_hood(ic, 40, 30, 14, SHADOW, eye=[VIOLET[0], VIOLET[1], VIOLET[1]])
	_hood(ic, 22, 38, 14, INK)
	ic.rim()
	ic.halo([SHADOW[3]])
	sparkle(ic, 31, 10, 5, (WHITE, VIOLET[0], VIOLET[1]))
	return ic


@icon("ninja-shuriken", P("ninja-shuriken"))
def _():
	ic = Icon()
	for r in (30, 24):
		crescent(ic, "back", 30, 34, r, 4, -2.6, -0.6, [VIOLET[1], VIOLET[2], VIOLET[3]])
	star(ic, "body", 30, 34, 20, 6, 4, STEEL, rot=-0.4)
	ellipse(ic, "body", 30, 34, 4, 4, [INK[2]] * 4)
	ic.rim()
	ic.halo([VIOLET[3]])
	sparkle(ic, 48, 18, 6, (WHITE, VIOLET[0], VIOLET[1]))
	return ic


# ════════════ 123 亡者之书 · 三种骷髅 ════════════
@icon("skelw-axe", A("skelw-axe"))
def _():
	ic = Icon()
	crescent(ic, "back", 12, 56, 54, 14, -1.66, -0.84, [WHITE, GHOST[0], GHOST[1], GHOST[2]])
	_axe(ic, (12, 56), (34, 22), 11, [STONE[0], STONE[1], EARTH[1], EARTH[2], EARTH[3]], edge=STONE[0])
	thick_line(ic, "body", (12, 56), (26, 34), 2.6, [BONE[1], BONE[2], BONE[3]])        # 骨柄
	ic.rim()
	ic.halo([GHOST[3]])
	sparkle(ic, 50, 12, 6, (WHITE, GHOST[0], GHOST[1]))
	return ic


@icon("skelw-rage", A("skelw-rage"))
def _():
	ic = Icon()
	for k in range(5):
		a = -math.pi / 2 + (k - 2) * 0.5
		flame(ic, "back", (32 + math.cos(a) * 8, 34 + math.sin(a) * 8), (32 + math.cos(a) * 31, 34 + math.sin(a) * 31), 8, [FIRE[1], RED[1], RED[3], RED[5]])
	skull(ic, "body", 32, 30, 15, BONE, eye=[WHITE, RED[1], RED[3]])
	ellipse(ic, "body", 52, 50, 4, 5.5, RED)                                             # 吸血
	ic.rim()
	ic.halo([RED[4]])
	sparkle(ic, 32, 8, 6, (WHITE, FIRE[1], RED[1]))
	return ic


@icon("skelm-bolt", A("skelm-bolt"))
def _():
	ic = Icon()
	flame(ic, "back", (40, 24), (2, 62), 13, [VIOLET[0], VIOLET[1], VIOLET[2], VIOLET[3]], wob=1.6)
	ellipse(ic, "body", 42, 22, 13, 13, VIOLET)
	skull(ic, "body", 42, 20, 7, [VIOLET[0], VIOLET[0], VIOLET[1], VIOLET[2], VIOLET[4]], eye=[WHITE, VIOLET[0], VIOLET[1]])
	ic.rim()
	ic.halo([VIOLET[3]])
	sparkle(ic, 50, 12, 6, (WHITE, VIOLET[0], VIOLET[1]))
	return ic


@icon("skelm-blast", A("skelm-blast"))
def _():
	ic = Icon()
	burst(ic, 32, 34, 8, 32, 12, [VIOLET[0], VIOLET[1], VIOLET[2]], width=0.4)
	puff(ic, "body", 32, 34, 18, VIOLET, n=6, phase=0.3)
	puff(ic, "body", 32, 35, 9, [WHITE, VIOLET[0], VIOLET[1], VIOLET[1]], n=4)
	for (a, b) in (((4, 8), (12, 14)), ((54, 6), (60, 13)), ((6, 56), (13, 50)), ((52, 52), (59, 58))):
		bone(ic, "body", a, b, 1.5, BONE)
	ic.rim()
	ic.halo([VIOLET[3]])
	sparkle(ic, 32, 34, 7, (WHITE, VIOLET[0], VIOLET[1]))
	return ic


@icon("skelp-soul", A("skelp-soul"))
def _():
	ic = Icon()
	## 一团鬼火(第一稿窄长一条像笔尖): 圆底 + 三条往上蹿的火舌 + 一双眼
	for (bx, tx, w) in ((24, 14, 9), (40, 50, 9), (32, 30, 13)):
		flame(ic, "back", (bx, 46), (tx, 4), w, [GHOST[0], GHOST[1], GHOST[2], GHOST[3]], wob=1.8)
	ellipse(ic, "body", 32, 44, 15, 14, [WHITE, GHOST[0], GHOST[1], GHOST[2]])
	flame(ic, "body", (32, 40), (30, 14), 11, [WHITE, GHOST[0], GHOST[1], GHOST[2]], wob=1.0)
	for ex in (-1, 1):
		ellipse(ic, "body", 32 + ex * 5, 44, 2.4, 3.4, [GHOST[4]] * 4)
	ic.rim()
	ic.halo([GHOST[3]])
	sparkle(ic, 32, 20, 5, (WHITE, GHOST[0], GHOST[1]))
	return ic


@icon("skelp-wave", A("skelp-wave"))
def _():
	ic = Icon()
	def wave(x, y, px, py):                                                               # 往右推的浪(浪头卷起)
		top = 34 + math.sin(px * 0.22) * 4 - max(0.0, px - 30) * 0.5
		bot = 60 - ((px - 32) / 32.0) ** 2 * 10
		if py >= top and py <= bot and 2 <= px <= 62:
			k = 0 if py - top < 3 else (1 if py - top < 9 else (2 if py - top < 18 else 3))
			ic.put("body", x, y, GHOST[k])
	each(wave)
	crescent(ic, "body", 46, 26, 14, 7, -1.9, 1.2, [WHITE, GHOST[0], GHOST[1], GHOST[2]])   # 浪头
	for (x, y) in ((14, 30), (26, 26)):
		skull(ic, "body", x, y, 5, BONE, eye=GHOST)
	ic.rim()
	ic.halo([GHOST[3]])
	sparkle(ic, 54, 14, 6, (WHITE, GHOST[0], GHOST[1]))
	return ic


@icon("skel123-pact", P("skel123-pact"))
def _():
	ic = Icon()
	burst(ic, 32, 30, 10, 31, 8, [GHOST[2], GHOST[3]], width=0.24)
	poly(ic, "body", [(4, 44), (31, 36), (31, 58), (6, 62)], INK, 0.1)                   # 书(摊开)
	poly(ic, "body", [(60, 44), (33, 36), (33, 58), (58, 62)], INK, 0.1)
	poly(ic, "body", [(8, 44), (31, 38), (31, 55), (9, 58)], BONE, 0.2)
	poly(ic, "body", [(56, 44), (33, 38), (33, 55), (55, 58)], BONE, 0.3)
	skull(ic, "body", 32, 18, 11, BONE, eye=GHOST)
	hourglass(ic, "body", 52, 16, 7, GOLD, GHOST)
	ic.rim()
	ic.halo([GHOST[3]])
	sparkle(ic, 32, 18, 3, (WHITE, GHOST[0], GHOST[1]))
	return ic


# ════════════ 糖果龟 · 糖果炸弹 ════════════
def _candybomb(ic, cx, cy, r):
	def f(x, y, px, py):                                                                 # 糖果条纹圆球
		dx, dy = px - cx, py - cy
		d = math.hypot(dx, dy)
		if d > r:
			return
		band = int(((dx + dy) / r * 2.2 + 10) % 2)
		pal = CANDY if band == 0 else [WHITE, PINK[0], PINK[1], PINK[2]]
		ic.put("body", x, y, pal[lit_idx(dx, dy, r, 4, 0.2)])
	each(f)
	for sgn in (-1, 1):                                                                   # 两头的糖纸
		K.poly(ic, "body", [(cx + sgn * r * 0.9, cy - r * 0.2), (cx + sgn * r * 1.55, cy - r * 0.65), (cx + sgn * r * 1.5, cy + r * 0.55), (cx + sgn * r * 0.9, cy + r * 0.2)],
			[GOLD[0], GOLD[1], GOLD[2], GOLD[3]], 0.1)
	thick_line(ic, "body", (cx + r * 0.2, cy - r * 0.95), (cx + r * 0.55, cy - r * 1.45), 1.2, [WOOD[0], WOOD[1], WOOD[2]])   # 引信


@icon("candy-feed", P("candy-feed"))
def _():
	ic = Icon()
	burst(ic, 34, 36, 10, 31, 8, [JADE[1], JADE[2]], width=0.22)
	_candybomb(ic, 34, 38, 13)
	for (x, y, rot) in ((10, 12, 0.6), (22, 6, -0.3)):                                    # 投喂的两颗糖
		ellipse(ic, "body", x, y, 4.5, 3.2, CANDY, rot=rot)
	plus(ic, "body", 54, 14, 8, 3, JADE)
	ic.rim()
	ic.halo([JADE[3]])
	sparkle(ic, 54, 14, 3)
	return ic


@icon("candy-boom", P("candy-boom"))
def _():
	ic = Icon()
	burst(ic, 32, 32, 10, 32, 12, [PINK[0], PINK[1], PINK[2]], width=0.38)
	puff(ic, "body", 32, 33, 18, [WHITE, PINK[0], PINK[1], PINK[2]], n=6, phase=0.2)
	for (x, y, c) in ((8, 10, GOLD), (54, 8, SEA), (6, 50, LEAF), (56, 54, VIOLET), (30, 4, SEA), (60, 30, GOLD), (4, 30, CANDY)):
		K.poly(ic, "body", [(x - 3, y - 1), (x + 2, y - 3), (x + 3, y + 1), (x - 2, y + 3)], c, 0.1)   # 彩纸屑
	ic.rim()
	ic.halo([PINK[3]])
	sparkle(ic, 32, 32, 7, (WHITE, PINK[0], PINK[1]))
	return ic


# ════════════ 水晶龟 · 水晶球 ════════════
def _orb(ic, cx, cy, r):
	ellipse(ic, "body", cx, cy, r, r, VIOLET)
	swirl(ic, "body", cx, cy, r * 0.8, [VIOLET[0], VIOLET[1], VIOLET[1]], turns=0.8, arms=2, band=0.25)
	ellipse(ic, "body", cx - r * 0.4, cy - r * 0.4, r * 0.25, r * 0.18, [WHITE] * 4, rot=-0.7)
	K.poly(ic, "body", [(cx - r * 0.75, cy + r * 0.75), (cx + r * 0.75, cy + r * 0.75), (cx + r * 0.95, cy + r * 1.15), (cx - r * 0.95, cy + r * 1.15)], GOLD, 0.1)


@icon("crystal-ray", A("crystal-ray"))
def _():
	ic = Icon()
	thick_line(ic, "back", (22, 40), (64, 4), 6, [WHITE, VIOLET[0], VIOLET[1]])
	thick_line(ic, "back", (22, 40), (64, 4), 3, [WHITE, WHITE, VIOLET[0]])
	_orb(ic, 20, 40, 13)
	for (x, y) in ((44, 14), (52, 24), (38, 8)):
		star(ic, "fx", x, y, 3.5, 1.2, 4, [WHITE, VIOLET[0], VIOLET[1], VIOLET[2]])     # 水晶层
	ic.rim()
	ic.halo([VIOLET[3]])
	sparkle(ic, 58, 8, 6, (WHITE, VIOLET[0], VIOLET[1]))
	return ic


# ════════════ 海盗龟 · 海盗船 ════════════
def _hull(ic, cx, cy, s):
	K.poly(ic, "body", [(cx - s, cy - s * 0.25), (cx + s * 1.05, cy - s * 0.35), (cx + s * 0.75, cy + s * 0.45), (cx - s * 0.75, cy + s * 0.45)],
		[WOOD[0], WOOD[1], WOOD[2], WOOD[3]], 0.15)
	for k in range(3):
		thick_line(ic, "body", (cx - s * 0.85, cy - s * 0.05 + k * s * 0.15), (cx + s * 0.9, cy - s * 0.12 + k * s * 0.15), 0.5, [WOOD[2], WOOD[3], WOOD[3]])


@icon("ship-broadside", A("ship-broadside"))
def _():
	ic = Icon()
	flame(ic, "back", (36, 30), (64, 16), 10, [WHITE, FIRE[1], FIRE[2], FIRE[3]], wob=1.4)
	puff(ic, "back", 46, 34, 8, SMOKE + [SMOKE[2]], n=4)
	_hull(ic, 22, 40, 20)
	thick_line(ic, "body", (24, 32), (38, 28), 3.0, [GRAY[1], GRAY[2], GRAY[4]])           # 炮
	K.poly(ic, "body", [(16, 10), (16, 30), (4, 28)], [WHITE, CREAM[0], CREAM[1], CREAM[2]], 0.1)   # 帆
	thick_line(ic, "body", (17, 6), (17, 34), 1.2, [WOOD[1], WOOD[2], WOOD[3]])
	ic.rim()
	ic.halo([FIRE[3]])
	sparkle(ic, 42, 28, 6, (WHITE, FIRE[1], FIRE[2]))
	return ic


@icon("ship-ram", P("ship-ram"))
def _():
	ic = Icon()
	for r in (30, 22):
		crescent(ic, "back", 44, 52, r, 7, -2.9, -0.2, [WHITE, SEA[0], SEA[1], SEA[2]])   # 浪花
	_hull(ic, 30, 40, 22)
	K.poly(ic, "body", [(26, 6), (26, 32), (8, 30)], [WHITE, CREAM[0], CREAM[1], CREAM[2]], 0.1)
	thick_line(ic, "body", (27, 2), (27, 34), 1.2, [WOOD[1], WOOD[2], WOOD[3]])
	for (x, y) in ((56, 14), (50, 8), (60, 24)):
		star(ic, "body", x, y, 4, 1.6, 5, GOLD)                                          # 眩晕
	ic.rim()
	ic.halo([SEA[3]])
	sparkle(ic, 54, 40, 6, (WHITE, SEA[0], SEA[1]))
	return ic


# ════════════ 赛博龟 · 机甲 ════════════
@icon("mech-punch", A("mech-punch"))
def _():
	ic = Icon()
	burst(ic, 50, 26, 4, 18, 8, [WHITE, HOLO[1], HOLO[2]], width=0.4)
	thick_line(ic, "body", (2, 46), (18, 38), 7, [STEEL[2], STEEL[3], STEEL[4]])            # 前臂
	ellipse(ic, "body", 18, 38, 7, 10, [GRAY[1], GRAY[2], GRAY[3], GRAY[4]], rot=-0.4)      # 护腕
	ellipse(ic, "body", 32, 34, 15, 13, SEA)                                                 # 拳
	for k in range(4):
		ellipse(ic, "body", 44, 24 + k * 6, 5, 3.6, SEA)                                     # 指节
	ellipse(ic, "body", 28, 22, 8, 4.5, SEA, rot=-0.2)                                       # 拇指
	ellipse(ic, "body", 30, 36, 3, 3, HOLO)
	ic.rim()
	ic.halo([HOLO[3]])
	sparkle(ic, 52, 24, 7, (WHITE, HOLO[0], HOLO[1]))
	return ic


@icon("mech-blast", P("mech-blast"))
def _():
	ic = Icon()
	## 两发能量炮弹(第一稿带一截机械臂, 跟重拳像同一张)
	for (bx, by, hx_, hy_) in ((2, 50, 40, 22), (14, 62, 52, 34)):
		flame(ic, "back", (hx_, hy_), (bx, by), 8, [WHITE, HOLO[0], HOLO[1], HOLO[2]], wob=0.8)
		ellipse(ic, "body", hx_, hy_, 7, 7, HOLO)
	ring(ic, "fx", 52, 16, 9, 10.5, RED[1])
	for (a, b) in (((52, 2), (52, 8)), ((52, 24), (52, 30)), ((38, 16), (44, 16)), ((60, 16), (64, 16))):
		bline(ic, "fx", a, b, RED[1], 2)
	ic.rim()
	ic.halo([HOLO[3]])
	sparkle(ic, 46, 18, 5, (WHITE, HOLO[0], HOLO[1]))
	return ic


# ════════════ 灵物 · 亡魂 ════════════
@icon("wraith-claw", A("wraith-claw"))
def _():
	ic = Icon()
	puff(ic, "back", 14, 52, 12, GHOST, n=5)
	for o in (-10, 0, 10):                                                                # 三道爪痕(平行, 两头收尖)
		flame(ic, "body", (10 + o, 56 - o * 0.2 + 2), (50 + o, 8 + o * 0.2), 4.2, [WHITE, GHOST[0], GHOST[1], GHOST[2]], wob=0.0)
	ic.rim()
	ic.halo([GHOST[3]])
	sparkle(ic, 50, 14, 6, (WHITE, GHOST[0], GHOST[1]))
	return ic


def _ghost(ic, cx, cy, s, pal=GHOST):
	def f(x, y, px, py):                                                                  # 幽灵: 圆头 + 波浪下摆
		dx, dy = px - cx, py - cy
		if dy < 0:
			ok = dx * dx + dy * dy <= s * s
		else:
			ok = abs(dx) <= s and dy <= s * 1.1 + math.sin(dx / s * 7.0) * s * 0.18
		if ok:
			ic.put("body", x, y, pal[lit_idx(dx, dy, s * 1.3, 4, 0.25)])
	each(f)
	for ex in (-1, 1):
		ellipse(ic, "body", cx + ex * s * 0.35, cy - s * 0.05, s * 0.16, s * 0.24, [pal[4]] * 4)


@icon("wraith-rise", P("wraith-rise"))
def _():
	ic = Icon()
	flame(ic, "back", (32, 50), (32, 0), 22, [GHOST[1], GHOST[2], GHOST[3], GHOST[4]], wob=2.0)
	K.poly(ic, "body", [(10, 64), (10, 46), (16, 40), (26, 40), (32, 46), (32, 64)], STONE, 0.1)   # 墓碑
	_ghost(ic, 38, 26, 13)
	ic.rim()
	ic.halo([GHOST[3]])
	sparkle(ic, 50, 8, 5, (WHITE, GHOST[0], GHOST[1]))
	return ic


@icon("wraith-loop", P("wraith-loop"))
def _():
	ic = Icon()
	crescent(ic, "body", 32, 32, 28, 7, -2.8, 0.2, [GHOST[0], GHOST[1], GHOST[2], GHOST[3]])
	crescent(ic, "body", 32, 32, 28, 7, 0.4, 3.3, [GHOST[1], GHOST[2], GHOST[3], GHOST[4]])
	K.poly(ic, "body", [(58, 34), (64, 22), (48, 24)], GHOST, 0.1)
	K.poly(ic, "body", [(6, 30), (0, 42), (16, 40)], GHOST, 0.1)
	_ghost(ic, 32, 30, 11)
	ic.rim()
	ic.halo([GHOST[3]])
	sparkle(ic, 32, 8, 4, (WHITE, GHOST[0], GHOST[1]))
	return ic


# ════════════ 战场单位 · 龟蛋 ════════════
def _egg(ic, cx, cy, s, crack=False):
	def f(x, y, px, py):
		dx, dy = px - cx, py - cy
		ry = s * (1.25 if dy < 0 else 1.0)
		if (dx / (s * 0.92)) ** 2 + (dy / ry) ** 2 <= 1.0:
			ic.put("body", x, y, [WHITE, CREAM[0], CREAM[1], CREAM[2]][lit_idx(dx, dy, s, 4, 0.25)])
	each(f)
	for (ox, oy, r) in ((-0.4, -0.3, 0.2), (0.35, 0.2, 0.24), (-0.1, 0.55, 0.16), (0.3, -0.7, 0.14)):
		ellipse(ic, "body", cx + ox * s, cy + oy * s, r * s, r * s * 0.9, LEAF)           # 绿斑点
	if crack:
		pts = [(cx - s * 0.8, cy - s * 0.1), (cx - s * 0.4, cy + s * 0.15), (cx - s * 0.1, cy - s * 0.2), (cx + s * 0.25, cy + s * 0.2), (cx + s * 0.55, cy - s * 0.15), (cx + s * 0.85, cy + s * 0.05)]
		for i in range(len(pts) - 1):
			bline(ic, "body", pts[i], pts[i + 1], RED[4], 2)


@icon("egg-fence", P("egg-fence"))
def _():
	ic = Icon()
	burst(ic, 32, 30, 14, 31, 10, [GOLD[1], GOLD[2]], width=0.22)
	_egg(ic, 32, 26, 15)
	for x in (8, 20, 32, 44, 56):                                                          # 木栅栏
		K.poly(ic, "body", [(x - 4, 62), (x - 4, 40), (x, 34), (x + 4, 40), (x + 4, 62)], WOOD + [WOOD[3]], 0.1)
	for y in (44, 54):
		thick_line(ic, "body", (2, y), (62, y), 1.6, [WOOD[0], WOOD[1], WOOD[2]])
	ic.rim()
	ic.halo([GOLD[3]])
	sparkle(ic, 26, 14, 5)
	return ic


@icon("egg-shell", P("egg-shell"))
def _():
	ic = Icon()
	ellipse(ic, "back", 32, 34, 29, 29, [ICE[1], ICE[2], ICE[2], ICE[3]], hollow=0.84)
	_egg(ic, 32, 36, 16)
	ic.rim()
	ic.halo([ICE[3]])
	sparkle(ic, 20, 14, 6, (WHITE, ICE[1], ICE[2]))
	return ic


@icon("egg-grow", P("egg-grow"))
def _():
	ic = Icon()
	_egg(ic, 14, 50, 8)
	_egg(ic, 38, 36, 17)
	for k in range(3):
		chevrons(ic, "fx", (58, 40 - k * 11), (58, 32 - k * 11), 1, 6, LEAF[0 if k == 2 else 1])
	ic.rim()
	ic.halo([LEAF[3]])
	sparkle(ic, 58, 6, 5, (WHITE, LEAF[0], LEAF[1]))
	return ic


@icon("egg-final", P("egg-final"))
def _():
	ic = Icon()
	burst(ic, 32, 34, 12, 32, 12, [RED[1], RED[3], RED[5]], width=0.34)
	_egg(ic, 32, 36, 17, crack=True)
	ic.rim()
	ic.halo([RED[4]])
	sparkle(ic, 32, 36, 6, (WHITE, RED[0], RED[1]))
	return ic


# ════════════ 战场单位 · 训龟大师 ════════════
@icon("trainer-stone", A("trainer-stone"))
def _():
	ic = Icon()
	crescent(ic, "back", 48, 70, 49, 8, -2.6, -1.62, [WHITE, CREAM[0], CREAM[1], CREAM[2]])   # 抛物线(接到石头上)
	K.poly(ic, "body", [(40, 14), (52, 10), (60, 20), (56, 32), (42, 32), (36, 22)], STONE, 0.15)   # 石头
	ic.rim()
	ic.halo([STONE[3]])
	sparkle(ic, 58, 28, 5, (WHITE, CREAM[0], CREAM[1]))
	return ic


@icon("trainer-aloof", P("trainer-aloof"))
def _():
	ic = Icon()
	K.poly(ic, "back", [(32, 2), (60, 12), (56, 40), (32, 62), (8, 40), (4, 12)], [ICE[1], ICE[2], ICE[2], ICE[3]], 0.1)   # 护盾
	K.poly(ic, "body", [(32, 8), (54, 16), (51, 38), (32, 56), (13, 38), (10, 16)], STEEL, 0.15)
	ellipse(ic, "body", 32, 30, 14, 8, [WHITE, WHITE, BONE[0], BONE[1]])                    # 眼睛(只看不打)
	ellipse(ic, "body", 32, 30, 6, 6, SEA)
	ellipse(ic, "body", 32, 30, 2.6, 2.6, [OUTLINE] * 4)
	ic.rim()
	ic.halo([ICE[3]])
	sparkle(ic, 28, 27, 3)
	return ic


# ════════════════════════════════════════════
def main(argv):
	install = "--install" in argv
	pref = [a for a in argv if not a.startswith("--")]
	names = [n for n in REG if not pref or any(n.startswith(p) for p in pref)]
	icons = [(n, REG[n][0]()) for n in names]
	os.makedirs(OUT, exist_ok=True)
	finish_all(icons, OUT)
	if install:
		import shutil
		for n in names:
			shutil.copyfile(os.path.join(OUT, n, n + ".png"), os.path.join(ROOT, "assets", "sprites", REG[n][1]))
	print("ok", len(names), OUT)


if __name__ == "__main__":
	main(sys.argv[1:])
