# -*- coding: utf-8 -*-
"""tools/assetgen/build_ninja_slash.py — 忍者龟普攻帧条(2026-11-11 第八版, 7 帧, 第 4 帧命中)。

用户 11-11 挑的(原话, 按先后):「你把所有生成的这个忍者龟的图片都摆这里，然后选一些，干脆拼」
  「三到五版的第十二帧和第十三帧可以作为第一帧、第二帧」「三到五版的第十八帧，可以作为第三帧…第二十二帧，可以作为第四帧…也是收尾了…
  第五帧作为收刀」「第三到五版的第十五针，紧跟的插在我们命中针之后」「命中针还是用第三到五版的第十九针」
  「(第十二帧)把它多复制一份，放到我们第三帧」「可以了，这一份出刀光，然后给我个视频」
  「那还是把这第三帧给去掉吧…把一二的这个持续时间稍微拉长一点」;
  「只要嘛把每一帧慢点播放就可以了，播放这个时间你处理好每一帧的时间」⇒ 每帧停多久在 scripts/gamedata/attack_hits.gd 的 FRAME_W。
  编号 = 总图 .out/ninja_gallery/全部姿势_编号.png(生成过的全部姿势, 不出新图); 8 帧都是第三~五版以待机为源出的, 长相、大小与待机一致。

7 帧(96 坐标, 待机: 前脚 23 / 后脚 64 / 脚底第 74 行):
  1 f1_raise    12 号  双手握刀往右肩抬                 前脚 23 后脚 64(待机位)
  2 f2_step     13 号  大跨步、刀举过右肩               前脚 18 后脚 74
  3 f3_swing    18 号  刀往前上方挥                     前脚 18
  4 f4_hit      19 号  ★命中: 弓步、刀水平朝左砍过     前脚 20(刀尖贴帧边, 再往左就被截)
  5 f5_low      15 号  还蹲着、刀斜指左下               前脚 18
  6 f6_down     22 号  砍到底(收尾)                     前脚 18 后脚 64
  7 f7_sheath    5 号  收刀                             前脚 18 后脚 64
源图都是 192 的 PixelLab 原图, 2×2 取众数缩回 96; 横向按前脚对齐(SLOTS 第二项)。
刀光(SWEEP): 沿刀尖实际走过的路画一条带(128 坐标, 逐帧量刀尖): 第 2 帧刀尖(右上, 头后) → 头顶上方 → 第 3 帧刀尖(左上) → 第 4 帧刀尖(身前左边)
  = 过头顶往前劈的一道弧; 第 3 帧画到第 3 帧刀尖, 第 4 帧(命中)画整道(老的一端变细), 第 5 帧只剩前面那段末梢。
  外沿金、里面浅金、中心白, 实心无半透明, 画在人物后面。
画布 128 方帧(待机 64 画布四边各补 32; 四边对称 ⇒ 脚底与待机同一条贴地线, 游戏里 _art_px / _art_offy 沿用待机值)。
命中第 4 帧(下标 3, scripts/gamedata/attack_hits.gd)。确定性: 重跑逐字节相同。用法: python tools/assetgen/build_ninja_slash.py [--check]
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
FW = 128
PAD = 32                 # 64 画布四边补 32 = 128
POSE_PAD = 16            # AI 图(缩回后 96)本身是 64 画布四边补 16
FEET = 74                # 待机脚底行(96 坐标)
POSES = ["f1_raise", "f2_step", "f3_swing", "f4_hit", "f5_low", "f6_down", "f7_sheath"]
## 擦掉(96 坐标, 对齐脚底之前): 垂下的刀尖穿过了地面线
ERASE = {
	"f5_low": [(0, 76, 30, 96)],
}
## 放大(没有; 8 帧都是以待机为源出的, 大小一致)
UPSCALE = {}
## 7 帧: (身体, 横移像素)
SLOTS = [
	("f1_raise", -2),
	("f2_step", 3),
	("f3_swing", -10),
	("f4_hit", -16),
	("f5_low", -15),
	("f6_down", 0),
	("f7_sheath", -5),
]
HIT = 3
## 刀光: 格 → [(x, y, 宽度), …](128 坐标), 沿折线画带, 宽度按点插值、两端收尖
T2 = (106.0, 20.0)       # 第 2 帧刀尖(右上, 头后)
A1 = (82.0, 9.0)         # 过头顶的弧(第 3 帧头顶在 40 行)
A2 = (58.0, 5.0)
A3 = (34.0, 9.0)
T3 = (12.0, 21.0)        # 第 3 帧刀尖(左上)
A4 = (3.0, 40.0)
T4 = (2.0, 62.0)         # 第 4 帧刀尖(身前左边, 命中)
SWEEP = {
	2: [(T2, 1.0), (A1, 2.0), (A2, 4.0), (A3, 6.0), (T3, 8.0)],
	3: [(T2, 0.5), (A1, 1.5), (A2, 3.0), (A3, 5.0), (T3, 7.0), (A4, 9.0), (T4, 8.0)],
	4: [(A3, 0.5), (T3, 2.0), (A4, 4.0), (T4, 3.0)],
}
C_EDGE = (236, 178, 84)
C_MID = (255, 236, 168)
C_CORE = (255, 255, 255)


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


def is_green(c):
	return c[3] > 0 and c[1] > c[0] + 12 and c[1] > c[2] + 12


def is_blade(c):
	"""刀身: 不透明、不是绿、够亮(最大通道 > 140)、低饱和(最大 − 最小 < 75; 腹甲的黄 ≥ 100)。"""
	if c[3] == 0 or is_green(c):
		return False
	return max(c[:3]) > 140 and max(c[:3]) - min(c[:3]) < 75


def feet_row(im):
	px = im.load()
	w, h = im.size
	return max(y for y in range(h) for x in range(w) if is_green(px[x, y]))


def upscale98(im, phase):
	"""im 是 128 画布; 9/8 最近邻放大后按「脚底行 + 前脚」对回原位, 仍是 128 画布。"""
	fx, fy = phase
	px = im.load()
	xs = []
	for x in range(-16, 112):
		xs.extend([x, x] if x % 8 == fx else [x])
	ys = []
	for y in range(-16, 112):
		ys.extend([y, y] if y % 8 == fy else [y])
	big = Image.new("RGBA", (len(xs), len(ys)), (0, 0, 0, 0))
	bp = big.load()
	for j, y in enumerate(ys):
		for i, x in enumerate(xs):
			bp[i, j] = px[x + 16, y + 16]

	def anchor(img, p):
		w, h = img.size
		f = max(y for y in range(h) for x in range(w) if is_green(p[x, y]))
		b = min(x for x in range(w) for y in range(f - 3, f + 1) if is_green(p[x, y]))
		return f, b
	f0, b0 = anchor(im, px)
	f1, b1 = anchor(big, bp)
	out = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
	out.alpha_composite(big.crop((b1 - b0, f1 - f0, b1 - b0 + FW, f1 - f0 + FW)))
	return out


def load_pose(name):
	im = down2(Image.open(os.path.join(SRC, "%s_192.png" % name)))
	px = im.load()
	for (x0, y0, x1, y1) in ERASE.get(name, []):
		for y in range(y0, y1):
			for x in range(x0, x1):
				px[x, y] = (0, 0, 0, 0)
	dy = FEET - feet_row(im)
	c = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
	c.paste(im, (PAD - POSE_PAD, PAD - POSE_PAD + dy))
	if name in UPSCALE:
		c = upscale98(c, UPSCALE[name])
	return c


def load_idle():
	im = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
	im.paste(Image.open(os.path.join(SRC, "idle0.png")).convert("RGBA"), (PAD, PAD))
	return im


def draw_sweep(layer, pts):
	"""沿折线画实心带: 每个像素找最近的线段点, 宽度按两端点插值; 中心白、里面浅金、外沿金。"""
	p = layer.load()
	segs = list(zip(pts, pts[1:]))
	for y in range(FW):
		for x in range(FW):
			best = None
			for (a, wa), (b, wb) in segs:
				ax, ay = a
				bx, by = b
				dx, dy = bx - ax, by - ay
				l2 = dx * dx + dy * dy
				t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((x + 0.5 - ax) * dx + (y + 0.5 - ay) * dy) / l2))
				d = math.hypot(x + 0.5 - (ax + t * dx), y + 0.5 - (ay + t * dy))
				w = wa + (wb - wa) * t
				if best is None or d - w * 0.5 < best[0] - best[1] * 0.5:
					best = (d, w)
			d, w = best
			if w <= 0.0 or d > w * 0.5:
				continue
			k = d / max(0.001, w * 0.5)
			p[x, y] = (C_CORE if k < 0.35 else (C_MID if k < 0.75 else C_EDGE)) + (255,)


def build():
	bodies = {}
	for n in POSES:
		bodies[n] = load_pose(n)
	sheet = Image.new("RGBA", (FW * len(SLOTS), FW), (0, 0, 0, 0))
	for i, (bn, dx) in enumerate(SLOTS):
		canvas = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
		if i in SWEEP:
			sw = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
			draw_sweep(sw, SWEEP[i])
			canvas.alpha_composite(sw)
		body = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
		body.paste(bodies[bn], (dx, 0))
		canvas.alpha_composite(body)
		sheet.paste(canvas, (i * FW, 0))
	return sheet, bodies


def main():
	sheet, bodies = build()
	if "--check" in sys.argv:
		cur = Image.open(OUT).convert("RGBA")
		same = cur.size == sheet.size and cur.tobytes() == sheet.tobytes()
		print("ALL OK" if same else "不一致: 重跑 build_ninja_slash.py")
		sys.exit(0 if same else 1)
	sheet.save(OUT, optimize=False)
	print("写好", OUT, sheet.size)


if __name__ == "__main__":
	main()
