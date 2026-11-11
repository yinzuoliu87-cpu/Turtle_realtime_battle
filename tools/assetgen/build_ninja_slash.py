# -*- coding: utf-8 -*-
"""tools/assetgen/build_ninja_slash.py — 忍者龟普攻帧条: 一刀从右上斜斩到左下(2026-11-11 第六版, 9 格, 第 5 格命中)。

用户 11-11 定的节奏(原话):「在第二针的时候，他已经把剑扛到自己的右肩的这个上方…第四针起手斩，第五针命中，第六针斩到底，然后第七针去收」
  「我从头到尾一直在说是右上角往左下角的一个斜砍」「收势…到底是多少？说清楚」(定 3 针)。
  之前几版的毛病(用户逐条指出): 刀从头顶一格跳到底 / 同一张图重复凑格 / 刀在头顶绕圈不是斜砍 / 身体姿势前后错位(头上下乱跳、脚乱滑、朝向乱翻)。

9 格(96 坐标, 待机: 前脚 23 / 后脚 64 / 头顶 22 / 脚底第 74 行; 实测见下, 偏离骨架表 ≤ 2 像素):
  1 c1_lift      抬刀: 双手握刀到胸前、刀竖直                 前脚 23 后脚 64 头顶 22(双脚钉住)
  2 c2_shoulder  刀扛到右肩上方、刀尖指右上                   前脚 23 后脚 64 头顶 25(腰以上下沉 3 像素, SINK)
  3 c3_coil      再往后压: 下蹲、刀拉到身后几乎水平指右         前脚 20 后脚 64 头顶 29
  4 c4_start     起手斩: 前脚踏出、双手抡到额头上方、刀尖右上高处 前脚 14 后脚 64 头顶 27
  5 c5_hit       ★命中: 双手到胸前、刀水平朝左砍过               前脚 13 后脚 64 头顶 30
  6 c6_end       斩到底: 双手到腰前、刀斜指左下贴地             前脚 13 后脚 64 头顶 31
  7 c7_rise      收: 起身一半、后脚收回、刀垂身前               前脚 13 后脚 59 头顶 26
  8 c8_stand     收: 站直、刀垂在前脚边(身体 = 待机)             前脚 22 后脚 60 头顶 22
  9 待机原图     收: 站姿, 刀回背上                             前脚 23 后脚 64 头顶 22
做法(接力出图, 不再每格单独从待机出): PixelLab edit_image_pro_flash, 每一格以上一格为源, 提示只改手 / 刀 / 该动的那条腿
  (第 1、8 格以待机为源, 身体与待机逐像素重合); 锁源图色板; 2×2 取众数缩回 96。每格出两版, 挑与骨架表最接近、前后叠影接得上的那版
  (对照图 .out/ninja_chain/cmp_*.png)。横向按钉住的那只脚对齐(SLOTS 第二项), 不再拍脑袋给偏移。
刀光(SWEEP): 沿刀尖实际走过的路画一条带 —— 第 4 格刀尖在右上(85, 19) → 第 5 格到身前胸口高度(4, 61) → 第 6 格到左下贴地(14, 84)
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
POSE_PAD = 16            # AI 图(缩回后 96)本身是 64 画布四边补 16
FEET = 74                # 待机脚底行(96 坐标)
SINK_ROW = 60            # 下沉: 这一行以上整体往下挪(大腿被压短 = 屈膝)
POSES = ["c1_lift", "c2_shoulder", "c3_coil", "c4_start", "c5_hit", "c6_end", "c7_rise", "c8_stand"]
SINK = {"c2_shoulder": 3}
## 擦掉(96 坐标): 第 8 格垂下的刀尖穿过了地面线
ERASE = {
	"c8_stand": [(14, 76, 32, 96)],
}
## 9 格: (身体, 横移像素 —— 按钉住的那只脚对齐到骨架表)
SLOTS = [
	("c1_lift", 0),
	("c2_shoulder", 0),
	("c3_coil", 1),
	("c4_start", 0),
	("c5_hit", -13),
	("c6_end", -5),
	("c7_rise", -3),
	("c8_stand", -4),
	("idle", 0),
]
HIT = 4
## 刀光: 格 → [(x, y, 宽度), …](128 坐标), 沿折线画带, 宽度按点插值、两端收尖
T4 = (85.0, 19.0)        # 第 4 格刀尖(右上高处)
M45 = (44.0, 35.0)       # 第 4 → 5 格之间(略往上拱, 从头顶前上方掠过)
T5 = (4.0, 61.0)         # 第 5 格刀尖(身前胸口高度)
M56 = (6.0, 74.0)
T6 = (14.0, 84.0)        # 第 6 格刀尖(左下贴地)
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


def load_pose(name):
	im = down2(Image.open(os.path.join(SRC, "%s_192.png" % name)))
	px = im.load()
	for (x0, y0, x1, y1) in ERASE.get(name, []):
		for y in range(y0, y1):
			for x in range(x0, x1):
				px[x, y] = (0, 0, 0, 0)
	dy = FEET - feet_row(im)
	if dy:
		moved = Image.new("RGBA", im.size, (0, 0, 0, 0))
		moved.paste(im, (0, dy))
		im = moved
	return sink(im, SINK.get(name, 0))


def load_idle():
	im = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
	im.paste(Image.open(os.path.join(SRC, "idle0.png")).convert("RGBA"), (POSE_PAD, POSE_PAD))
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
		body.paste(bodies[bn], (PAD - POSE_PAD + dx, PAD - POSE_PAD))
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
