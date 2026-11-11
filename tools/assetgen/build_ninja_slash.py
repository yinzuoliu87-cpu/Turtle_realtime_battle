# -*- coding: utf-8 -*-
"""tools/assetgen/build_ninja_slash.py — 忍者龟普攻帧条: 一刀从右上斜斩到左下(2026-11-11 第七版, 9 格, 第 5 格命中)。

用户 11-11 定的节奏(原话):「在第二针的时候，他已经把剑扛到自己的右肩的这个上方…第四针起手斩，第五针命中，第六针斩到底，然后第七针去收」
  「我从头到尾一直在说是右上角往左下角的一个斜砍」「收势…到底是多少？说清楚」(定 3 针)。
  之前几版的毛病(用户逐条指出): 刀从头顶一格跳到底 / 同一张图重复凑格 / 刀在头顶绕圈不是斜砍 / 身体姿势前后错位(头上下乱跳、脚乱滑、朝向乱翻)。
第七版改的(用户看第六版:「第二张…整个手臂和脑袋连起来了」「第六针，手和脑袋一样连在一起」「第七针到第八针…是一样的角色吗？」):
  第六版每格以上一格为源接力出图, 细节一格比一格丢(红眼、米黄腹甲、腰带扣、黑描边), 到第 7 格已经不像同一只龟;
  第 3~6 格改成「姿势取第六版那格、长相以待机原图为参照重画」(PixelLab edit_image_pro_flash method=reference, 参照 = 待机);
  第 2 格换成双手在胸前握刀、刀斜过右肩指右上(脸完全露出来, 手臂在下巴以下);
  第 4 格双手整个举到头顶以上(不再挡在额头前), 角色大小与脚位一像素不动(PixelLab edit_image_pixen)。
  刀身: 重画的几格刀身被画成米黄, 在刀所在的框里改回待机那把刀的钢色(BLADE_BOX, 只认低饱和的亮色, 不碰腹甲的黄)。

9 格(96 坐标, 待机: 前脚 23 / 后脚 64 / 头顶 22 / 脚底第 74 行; 实测, 眼睛高度 52 53 62 62 51 51 52 52 52 = 压低蓄力 → 出刀弹起):
  1 c1_lift      抬刀: 双手握刀到胸前、刀竖直                         前脚 23 后脚 64 头顶 22
  2 c2_shoulder  双手胸前握刀、刀斜过右肩指右上                       前脚 23 后脚 64 头顶 25(腰以上下沉 2 像素, SINK)
  3 c3_coil      再往后压: 下蹲、双手到右肩、刀拉到身后水平指右         前脚 19 后脚 64 头顶 29
  4 c4_start     起手斩: 前脚踏出、双手举过头顶、刀尖指右上高处         前脚 14 后脚 64(头顶 17 是举起的手)
  5 c5_hit       ★命中: 弓步、双手到胸前、刀水平朝左砍过               前脚 13 后脚 72 头顶 24(放大 9/8)
  6 c6_end       斩到底: 双手到腰前、刀斜指左下贴地                     前脚 13 后脚 70 头顶 24(放大 9/8)
  7 c7_rise      收: 起身一半(还屈膝)、右手握刀斜指左下                前脚 20 后脚 64 头顶 23
  8 c8_stand     收: 站直、刀垂在前脚边(身体 = 待机)                     前脚 25 后脚 63 头顶 22
  9 待机原图     收: 站姿, 刀回背上                                     前脚 23 后脚 64 头顶 22
源图: c1 / c2 / c7 / c8 是 192 的 PixelLab 原图(2×2 取众数缩回 96; c2 / c7 是第四版以待机为源出的姿势), c3~c6 是 96 的 PixelLab 原图(直接用)。
  第 7 格不用重画的那张: 它沿用了接力出图缩小的身体(头宽 22 像素, 待机 29), 接第 8 格会一下变大。
横向按钉住的那只脚对齐(SLOTS 第二项)。对照图在 .out/ninja_fix/。
刀光(SWEEP): 沿刀尖实际走过的路画一条带 —— 第 4 格刀尖在右上(98, 22) → 第 5 格到身前胸口高度(3, 57) → 第 6 格到左下贴地(13, 82)
  (128 坐标, 逐格量刀尖), 是从右上往左下的斜线, 不在头顶绕圈; 第 5 格画右上 → 胸前那一段, 第 6 格画整条(老的一端变细), 第 7 格只剩末梢。
  外沿金、里面浅金、中心白, 实心无半透明, 画在人物后面。
画布 128 方帧(待机 64 画布四边各补 32; 四边对称 ⇒ 脚底与待机同一条贴地线, 游戏里 _art_px / _art_offy 沿用待机值)。
命中第 5 格(下标 4, scripts/gamedata/attack_hits.gd); 命中前 4 格、命中后 4 格(用户定, verify_attack_rhythm 按这个查)。
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
FW = 128
PAD = 32                 # 64 画布四边补 32 = 128
POSE_PAD = 16            # AI 图(96)本身是 64 画布四边补 16
FEET = 74                # 待机脚底行(96 坐标)
SINK_ROW = 60            # 下沉: 这一行以上整体往下挪(大腿被压短 = 屈膝)
POSES = ["c1_lift", "c2_shoulder", "c3_coil", "c4_start", "c5_hit", "c6_end", "c7_rise", "c8_stand"]
SINK = {"c2_shoulder": 2}
## 擦掉(96 坐标): 第 7、8 格垂下的刀尖穿过了地面线
ERASE = {
	"c7_rise": [(0, 76, 30, 96)],
	"c8_stand": [(14, 76, 32, 96)],
}
## 刀身改回钢色(96 坐标框, 只在框里改): 重画的几格把刀画成了米黄
BLADE_BOX = {
	"c3_coil": (38, 18, 96, 36),
	"c4_start": (48, 0, 96, 25),
	"c5_hit": (0, 38, 30, 52),
	"c6_end": (0, 50, 25, 80),
}
STEEL_LIGHT = (221, 209, 182)   # 第 1 格(待机那把刀)刀身的亮色
STEEL_MID = (210, 197, 169)     # 同上, 次亮色
## 放大 9/8(每 8 行 / 8 列复制 1 行 / 列, (列相位, 行相位) 挑复制线压到描边 / 红眼最少的): 第六版接力出图一路缩小,
## 第 5、6 格身体只有待机的七成面积(头宽约 26 / 24 像素, 待机 29), 不放大接第 7 格会一下变大一圈。
## 以脚底行 + 前脚为锚点: 前脚从第 4 格起踩住不动, 放大多出来的步幅落在后脚(往后蹬约 6 像素);
## 钉后脚的话前脚和刀会往左长出去, 第 5 格刀尖顶出帧边被截。
UPSCALE = {
	"c5_hit": (5, 2),
	"c6_end": (7, 6),
}
## 9 格: (身体, 横移像素 —— 第 1~4 格后脚钉在 64; 第 5、6 格前脚钉在 13(第 4 格前脚 14); 第 7~9 格收脚回站姿)
SLOTS = [
	("c1_lift", 0),
	("c2_shoulder", -2),
	("c3_coil", 0),
	("c4_start", 0),
	("c5_hit", -12),
	("c6_end", -5),
	("c7_rise", -13),
	("c8_stand", -1),
	("idle", 0),
]
HIT = 4
## 刀光: 格 → [(x, y, 宽度), …](128 坐标), 沿折线画带, 宽度按点插值、两端收尖
T4 = (98.0, 22.0)        # 第 4 格刀尖(右上高处)
M45 = (50.0, 34.0)       # 第 4 → 5 格之间(略往上拱, 从头顶前上方掠过)
T5 = (3.0, 57.0)         # 第 5 格刀尖(身前胸口高度)
M56 = (5.0, 70.0)
T6 = (13.0, 82.0)        # 第 6 格刀尖(左下贴地)
SWEEP = {
	4: [(T4, 1.0), (M45, 5.0), (T5, 9.0)],
	5: [(T4, 0.5), (M45, 2.5), (T5, 6.0), (M56, 9.0), (T6, 7.0)],
	6: [(T5, 1.0), (M56, 4.0), (T6, 3.5)],
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


def sink(im, n):
	if n <= 0:
		return im
	w, h = im.size
	out = Image.new("RGBA", im.size, (0, 0, 0, 0))
	out.paste(im.crop((0, 0, w, SINK_ROW)), (0, n))
	out.paste(im.crop((0, SINK_ROW + n, w, h)), (0, SINK_ROW + n))
	return out


def upscale98(im, phase):
	"""im 是 128 画布(身体在 (16, 16) 起的 96 区里); 9/8 最近邻放大后按「脚底行 + 前脚」对回原位, 仍是 128 画布。"""
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
	p96 = os.path.join(SRC, "%s_96.png" % name)
	if os.path.exists(p96):
		im = Image.open(p96).convert("RGBA")
	else:
		im = down2(Image.open(os.path.join(SRC, "%s_192.png" % name)))
	px = im.load()
	for (x0, y0, x1, y1) in ERASE.get(name, []):
		for y in range(y0, y1):
			for x in range(x0, x1):
				px[x, y] = (0, 0, 0, 0)
	if name in BLADE_BOX:
		x0, y0, x1, y1 = BLADE_BOX[name]
		for y in range(y0, y1):
			for x in range(x0, x1):
				c = px[x, y]
				if is_blade(c):
					lum = 0.30 * c[0] + 0.59 * c[1] + 0.11 * c[2]
					px[x, y] = (STEEL_LIGHT if lum >= 160.0 else STEEL_MID) + (255,)
	dy = FEET - feet_row(im)
	if dy:
		moved = Image.new("RGBA", im.size, (0, 0, 0, 0))
		moved.paste(im, (0, dy))
		im = moved
	im = sink(im, SINK.get(name, 0))
	c = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
	c.paste(im, (PAD - POSE_PAD, PAD - POSE_PAD))
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
	bodies = {"idle": load_idle()}
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
