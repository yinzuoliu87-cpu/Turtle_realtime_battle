# -*- coding: utf-8 -*-
"""tools/assetgen/build_ninja_slash.py — 忍者龟普攻帧条整段重做(2026-11-11)。

用户 11-11:「忍者龟，你赶紧做！」(方案书 docs/plans/20261111-忍者普攻与小将铁链与灵物统计.md §2.1 / B)。
旧帧条(build_attack_rhythm.py 的 ninja 段)量出来的毛病: AI 补帧把身体画小两成(高 56 → 45、脚底 59 → 55)、
  第 1 → 2 帧刀瞬移 62 像素、命中后刀往回抬、第 9 / 10 帧刀凭空消失 —— 而且 AI 关键姿势跟现在的待机不是同一个人(头小、背上没刀)。
根子: 64 像素画布被身体占满(宽 62), 前伸的刀没地方放, AI 只能把人画小。

做法(与 11-11 三只小将同一标准):
  ① 画布 96×96 = 待机 64 像素画布四边各补 16 像素, 身体像素密度与待机完全相同, 刀伸进补出来的地方
     (游戏里忍者 u["_art_px"] / u["_art_offy"] = 待机的值 ⇒ 动作帧与待机同一像素尺寸、同一条贴地线, battle_spawn)。
  ② 身体 4 个关键姿势(后举 / 举过头顶 / 前刺 / 劈下): PixelLab edit_image_pro_flash 以待机 2 倍图为源、锁待机色板出 128 图,
     2×2 取众数缩回 64(素材 tools/assetgen/ai_src/ninja_slash/k*_128.png)。逐张核过: 与待机同一个人、两手两脚、脚底同一行。
  ③ AI 画的刀一律擦掉(沿刀身一条带 + 护手框里非身体色的像素; 擦到的身体描边按原图补回),
     每一格按握刀拳头的位置用程序画同一把刀 —— 刀长 / 样子每格一致, 角度按挥砍路线单调走(命中前、命中后都不倒回)。
  ④ 刀光单独一层画在人物后面: 刀尖从上一格到这一格扫过的那片(第 5 / 6 / 7 格), 浅金外沿白, 接命中后原有的金色斩击特效。
  ⑤ 帧序 13 格、命中第 6 格不变(scripts/gamedata/attack_hits.gd), 节拍按代码: 前摇 6 格、后摇 6 格。
★11-11 下午改节奏(用户「一个挥刀的感觉，你展现不出来」; 参考 Katana ZERO 出刀逐帧 docs/studies/20261111c):
  原来刀从后举到劈下用 6 格匀速转 = 在「转刀」; 现在第 1~5 格往后拉到底并定住(身体后仰 0~3 像素),
  第 6 格(命中)一格挥完 + 整道大月牙残影(draw_smear, 刀尖扫过的路, 以前肩为圆心) + 身体前冲 8 像素,
  第 6~9 格同一张身体定格、月牙从起手端一段段收, 第 10~12 格收刀。SLOTS 第三项 = 身体横移像素。
确定性: 重跑逐字节相同。用法: python tools/assetgen/build_ninja_slash.py [--check]
"""
import math
import os
import sys
from collections import Counter

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(HERE, "ai_src", "ninja_slash")
OUT = os.path.join(ROOT, "assets", "sprites", "pets", "animations", "ninja", "slash.png")
PAD = 16
FW = 64 + 2 * PAD
SHOULDER = (17.0, 30.0)                     # 前冲出刀那张(k4)的前肩(64 像素坐标): 大月牙残影的圆心
FEET = 59                                   # 待机脚底行(64 像素坐标): 关键姿势按本体最下一行对齐到这里

## 关键姿势(64 像素坐标): 握刀点(刀柄穿过拳头的地方) / 要擦的 AI 刀身(两端 + 半宽) / 要擦的护手框
KEYS = {
	"k1": {"src": "k1_wind_128.png", "grip": (10.0, 10.0), "blade": ((13.0, 9.0), (56.0, 1.0), 3.2), "guard": (12, 4, 17, 13)},
	"k2": {"src": "k2_up_128.png", "grip": (8.0, 14.0), "blade": ((8.0, 10.5), (8.0, -1.0), 1.8), "guard": (4, 10, 12, 12)},
	"k3": {"src": "k3_slash_128.png", "grip": (11.0, 27.0), "blade": ((8.0, 27.0), (-1.0, 26.0), 2.4), "guard": (6, 22, 10, 32)},
	"k4": {"src": "k4_follow_128.png", "grip": (13.0, 46.0), "blade": ((11.0, 49.0), (-1.0, 62.0), 2.4), "guard": (8, 44, 15, 51)},
}
## 13 格: (身体, 刀角度°: 0 = 正前方(画面左), 90 = 正上, 180 = 正后; None = 刀在背上(待机原图))
SLOTS = [
	("idle", None, 0),      # 0 站姿
	("k1", 130.0, 0),       # 1 拔刀后举
	("k1", 150.0, 1),       # 2 往后蓄, 身体微后仰
	("k1", 160.0, 2),       # 3 蓄到底
	("k1", 160.0, 2),       # 4 停(同一张)
	("k1", 168.0, 3),       # 5 最后再往后压一下(出刀前最大蓄力)
	("k4", -48.0, -8),      # 6 ★命中: 一格挥完(后上 → 头顶 → 正前 → 前下), 身体往前冲 8 像素 + 大月牙残影
	("k4", -52.0, -8),      # 7 保持前冲, 残影从尾端收
	("k4", -52.0, -8),      # 8 停(同一张身体, 残影再收)
	("k4", -52.0, -7),      # 9 残影只剩末梢
	("k2", 95.0, -3),       # 10 收刀上提, 往回退
	("k1", 165.0, 0),       # 11 插回背上
	("idle", None, 0),      # 12 站姿
]
## 大月牙残影(出刀那一格起): 格 → 留下刀路的哪一段(0 = 起手端 SMEAR_FROM, 1 = 收尾端 SMEAR_TO)
SMEAR = {6: (0.0, 1.0), 7: (0.35, 1.0), 8: (0.62, 1.0), 9: (0.85, 1.0)}
SMEAR_FROM, SMEAR_TO = 168.0, -48.0
HIT = 6
TRAIL = {}   # 格 → (从哪一格扫过来, 刀光内沿占刀长的比例): 只贴着刀尖那一截(第一版 0.4~0.5 像一面白旗)
L_BLADE = 19.0
C_HI = (232, 236, 242)
C_MID = (141, 150, 163)
C_DARK = (28, 28, 28)
C_HANDLE = (50, 50, 48)
C_GOLD = (220, 177, 86)
C_TRAIL = (255, 236, 168)                   # 浅金: 接命中后游戏原有的金色斩击特效(ninja-slash), 两段同一个色系
C_TRAIL_EDGE = (255, 255, 255)


def down2(im):
	im = im.convert("RGBA")
	w, h = im.size
	out = Image.new("RGBA", (w // 2, h // 2), (0, 0, 0, 0))
	p = im.load()
	q = out.load()
	for y in range(h // 2):
		for x in range(w // 2):
			px = [p[2 * x + i, 2 * y + j] for j in range(2) for i in range(2)]
			op = [c for c in px if c[3] >= 128]
			if len(op) >= 2:
				c = Counter((c[0], c[1], c[2]) for c in op).most_common()
				c.sort(key=lambda kv: (-kv[1], kv[0]))
				q[x, y] = c[0][0] + (255,)
	return out


def is_body(c):
	r, g, b = c[0], c[1], c[2]
	green = g > r + 12 and g > b + 12
	red = r > 120 and g < 60 and b < 60
	return green or red


def seg_dist(px, py, a, b):
	ax, ay = a
	bx, by = b
	dx, dy = bx - ax, by - ay
	l2 = dx * dx + dy * dy
	t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
	return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def strip_sword(im, k):
	"""擦掉 AI 画的刀(刀身带 + 护手框里不是身体色的像素), 擦到的身体描边按原图补回。"""
	orig = im.copy()
	p = im.load()
	o = orig.load()
	a, b, hw = k["blade"]
	gx0, gy0, gx1, gy1 = k["guard"]
	gone = []
	for y in range(64):
		for x in range(64):
			c = p[x, y]
			if c[3] == 0 or is_body(c):
				continue
			if seg_dist(x + 0.5, y + 0.5, a, b) <= hw or (gx0 <= x < gx1 and gy0 <= y < gy1):
				p[x, y] = (0, 0, 0, 0)
				gone.append((x, y))
	for x, y in gone:                                   # 身体描边: 挨着身体色的深色像素补回
		c = o[x, y]
		if c[0] + c[1] + c[2] > 150:
			continue
		for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			nx, ny = x + dx, y + dy
			if 0 <= nx < 64 and 0 <= ny < 64 and p[nx, ny][3] > 0 and is_body(p[nx, ny]):
				p[x, y] = c
				break
	return im


def dvec(theta):
	r = math.radians(theta)
	return (-math.cos(r), -math.sin(r))


def put(p, x, y, c):
	if 0 <= x < FW and 0 <= y < FW:
		p[x, y] = c + (255,)


def line_px(a, b):
	x0, y0 = a
	x1, y1 = b
	n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
	out = []
	for i in range(n + 1):
		t = i / max(1, n)
		pt = (int(math.floor(x0 + (x1 - x0) * t + 0.5)), int(math.floor(y0 + (y1 - y0) * t + 0.5)))
		if not out or out[-1] != pt:
			out.append(pt)
	return out


def draw_sword(layer, grip, theta):
	p = layer.load()
	d = dvec(theta)
	n = (-d[1], d[0])                                   # 刀背一侧
	if n[1] > 0 or (abs(n[1]) < 1e-6 and n[0] > 0):
		n = (-n[0], -n[1])                              # 刀背朝上 / 朝后, 刀刃朝下
	gx, gy = grip[0] + PAD, grip[1] + PAD
	for q in line_px((gx - d[0] * 2.0, gy - d[1] * 2.0), (gx + d[0] * 2.0, gy + d[1] * 2.0)):
		put(p, q[0], q[1], C_HANDLE)
	cx, cy = gx + d[0] * 3.0, gy + d[1] * 3.0
	for q in line_px((cx - n[0] * 1.5, cy - n[1] * 1.5), (cx + n[0] * 1.5, cy + n[1] * 1.5)):
		put(p, q[0], q[1], C_GOLD)
	s = (gx + d[0] * 4.0, gy + d[1] * 4.0)
	e = (gx + d[0] * (4.0 + L_BLADE), gy + d[1] * (4.0 + L_BLADE))
	back = line_px((s[0] + n[0], s[1] + n[1]), (e[0] + n[0] * 0.4, e[1] + n[1] * 0.4))
	edge = line_px((s[0] - n[0] * 0.6, s[1] - n[1] * 0.6), (e[0] - n[0] * 0.6, e[1] - n[1] * 0.6))
	core = line_px(s, e)
	for q in back:
		put(p, q[0], q[1], C_DARK)
	for q in edge:
		put(p, q[0], q[1], C_MID)
	for q in core:
		put(p, q[0], q[1], C_HI)


def draw_trail(layer, g0, t0, g1, t1, inner):
	"""刀尖从 (g0, t0) 扫到 (g1, t1) 那一片: 外沿白、里面浅金, 实心无半透明。"""
	p = layer.load()
	pts_out, pts_in = [], []
	for i in range(25):
		t = i / 24.0
		gx = g0[0] + (g1[0] - g0[0]) * t + PAD
		gy = g0[1] + (g1[1] - g0[1]) * t + PAD
		th = t0 + (t1 - t0) * t
		d = dvec(th)
		pts_out.append((gx + d[0] * (4.0 + L_BLADE), gy + d[1] * (4.0 + L_BLADE)))
		pts_in.append((gx + d[0] * (4.0 + L_BLADE * inner), gy + d[1] * (4.0 + L_BLADE * inner)))
	poly = pts_out + pts_in[::-1]
	for y in range(FW):
		for x in range(FW):
			if _inside(x + 0.5, y + 0.5, poly):
				put(p, x, y, C_TRAIL)
	for a, b in zip(pts_out, pts_out[1:]):
		for q in line_px(a, b):
			put(p, q[0], q[1], C_TRAIL_EDGE)


def _inside(x, y, poly):
	c = False
	j = len(poly) - 1
	for i in range(len(poly)):
		xi, yi = poly[i]
		xj, yj = poly[j]
		if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
			c = not c
		j = i
	return c


def draw_smear(layer, pivot, a0, a1):
	"""出刀一格挥完的大月牙: 刀尖扫过 SMEAR_FROM → SMEAR_TO 的整条路, 只留 [a0, a1] 这一段(0 起手端 / 1 收尾端)。
	外沿白(刀尖最快)、中间浅金、内沿金; 起手那端参差碎开。"""
	p = layer.load()
	cx, cy = pivot[0] + PAD, pivot[1] + PAD
	r_out = 4.0 + L_BLADE + 3.0
	r_in = r_out * 0.30
	span = SMEAR_FROM - SMEAR_TO
	for y in range(FW):
		for x in range(FW):
			vx, vy = x + 0.5 - cx, y + 0.5 - cy
			r = math.hypot(vx, vy)
			if r < r_in or r > r_out:
				continue
			ang = math.degrees(math.atan2(-vy, -vx))
			while ang < SMEAR_TO:
				ang += 360.0
			while ang > SMEAR_TO + 360.0:
				ang -= 360.0
			if ang > SMEAR_FROM:
				continue
			t = (SMEAR_FROM - ang) / span
			if t < a0 or t > a1:
				continue
			k = (t - a0) / max(0.001, a1 - a0)
			thick = r_out - (r_out - r_in) * (0.25 + 0.75 * k)
			jag = ((x * 7 + y * 13) % 5) * 0.6
			if r < thick + (jag if k < 0.35 else 0.0):
				continue
			rr = (r - r_in) / (r_out - r_in)
			if rr > 0.70:
				c = C_TRAIL_EDGE
			elif rr > 0.38:
				c = C_TRAIL
			else:
				c = (236, 178, 84)
			put(p, x, y, c)


def pad(im, dx=0):
	c = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
	c.paste(im, (PAD + dx, PAD))
	return c


def build():
	idle = Image.open(os.path.join(SRC, "idle0.png")).convert("RGBA")
	bodies = {"idle": idle}
	grips = {}
	for kn, k in KEYS.items():
		body = strip_sword(down2(Image.open(os.path.join(SRC, k["src"]))), k)
		dy = FEET - (body.getbbox()[3] - 1)                # 脚底对齐待机(AI 图有的低 1 像素)
		if dy != 0:
			moved = Image.new("RGBA", body.size, (0, 0, 0, 0))
			moved.paste(body, (0, dy))
			body = moved
		bodies[kn] = body
		grips[kn] = (k["grip"][0], k["grip"][1] + dy)
	frames = []
	for i, (bn, th, dx) in enumerate(SLOTS):
		canvas = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
		if i in SMEAR:
			a0, a1 = SMEAR[i]
			sm = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
			draw_smear(sm, (SHOULDER[0] + dx, SHOULDER[1]), a0, a1)
			canvas.alpha_composite(sm)
		if th is not None:
			sw = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
			draw_sword(sw, (grips[bn][0] + dx, grips[bn][1]), th)
			canvas.alpha_composite(sw)
		canvas.alpha_composite(pad(bodies[bn], dx))      # 身体压在刀上: 刀柄藏进拳头, 护手 / 刀身从拳头里伸出来
		frames.append(canvas)
	sheet = Image.new("RGBA", (FW * len(frames), FW), (0, 0, 0, 0))
	for i, f in enumerate(frames):
		sheet.paste(f, (i * FW, 0))
	return sheet, bodies


def main():
	sheet, bodies = build()
	if "--check" in sys.argv:
		cur = Image.open(OUT).convert("RGBA")
		same = cur.size == sheet.size and cur.tobytes() == sheet.tobytes()
		print("ALL OK" if same else "不一致: 重跑 build_ninja_slash.py")
		sys.exit(0 if same else 1)
	sheet.save(OUT, optimize=False)
	for kn in ("k1", "k2", "k3", "k4"):
		bb = bodies[kn].getbbox()
		print("%s 本体包围盒 %s 高 %d 脚底行 %d" % (kn, bb, bb[3] - bb[1], bb[3] - 1))
	print("写好", OUT, sheet.size)


if __name__ == "__main__":
	main()
