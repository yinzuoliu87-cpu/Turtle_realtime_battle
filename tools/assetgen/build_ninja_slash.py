# -*- coding: utf-8 -*-
"""tools/assetgen/build_ninja_slash.py — 忍者龟普攻帧条: 抬刀 → 举过头 → 拉到右肩蓄力 → 过头顶 → 劈到左下弓步 → 慢慢起身(2026-11-11 第三版)。

用户 11-11 下午(看完第二版):「你给我的感觉就是相当于拿个教鞭，然后上下挥动」「从你的背上拔出刀，从右上角一路砍到左下角…」
  「别偷懒了呀，会到你整个身体都不动的吗？」—— 前两版身体只有 4 张关键姿势、刀是程序画的一根线在转, 身体基本不动。
看了第三版的姿势稿后:「第三针什么鬼？…第七针怎么突然变成站起来了？…收刀、拔刀这个动作…第二针、第八针，其实没必要」
  ⇒ 不画拔刀 / 收刀; 劈完分两格慢慢起身, 不一下子站直; 蓄力重出(大跨步、身体往后拧)。

做法: 全身姿势都由 PixelLab 以待机为源出(edit_image_pro_flash, 源 = 待机 64 画布四边补 16 再放大 2 倍的 192 图, 锁待机色板;
  2×2 取众数缩回 96), 刀是 AI 画在手里的那把(不再程序画), 每格身体都在动:
  pose_q1_raise    双手握刀往右肩抬, 身体开始往后转
  pose_q2_windA    大跨步, 双手把刀举过头、刀尖指右上
  pose_q3_windB    刀拉到右肩后, 身体往后拧、重心压在后腿(蓄力)
  pose_p4_over     往前转身踏步, 刀到正头顶
  pose_p5_follow   劈到底: 大弓步往左前冲, 后腿蹬直, 刀尖斜指左下地面
  pose_q4_low      劈完还蹲着, 刀垂在左前下方, 后腿收回一点
  pose_q5_half     半站起, 刀垂在身前
  弓步那张背上还画着两个刀柄 + 手里一把 = 三把刀 ⇒ 擦掉头左边那个刀柄(ERASE 框, 逐像素放大核过)。
  逐张核过: 与待机同一个人、两手两脚、脚底对齐到第 74 行。
挥刀两格画刀尖扫过的残影(参考 Katana ZERO 出刀逐帧 docs/studies/20261111c): 第 5 格右上 → 头顶一小段、第 6 格(命中)头顶 → 前方 → 左下整道,
  第 7 格定格、残影从起手端收。外沿白、中间浅金、内沿金, 实心无半透明。
画布 128 方帧(待机 64 画布四边各补 32; 四边对称 ⇒ 脚底与待机同一条贴地线, 游戏里 _art_px / _art_offy 沿用待机值)。
身体横移(SLOTS 第二项): 蓄力后仰 +1 / +2, 踏步 -4, 弓步前冲 -10, 起身 -8 → -5 → -3 → -1 → 0。
13 格 / 命中第 6 格不变(scripts/gamedata/attack_hits.gd), 前摇 6 格、后摇 6 格(verify_attack_rhythm)。
★第四版(看完第三版用户:「这个刀上一针在上面，下一针就在下面的吗？」「第三、四针，你的刀都没有任何的动…手都错位了」
  「你里面还有几针都根本没动…根本没区别」): 补出刀在身后 / 前上方 / 水平三张中间姿势(r1_back / r2_fwdup / r3_horizA)、
  收势加站直刀垂下(r4_relax), 去掉手错位的 q3_windB 和所有重复格 ⇒ 12 格每格一个姿势, 刀角 159° → 176° → 107° → 45° → 0°(命中) → -47°,
  每一格都比上一格往前走一段; 命中改第 5 格(scripts/gamedata/attack_hits.gd 同步)。
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
POSE_PAD = 16            # AI 姿势图(缩回后 96)本身是 64 画布四边补 16
FEET = 74                # 待机脚底行(96 坐标)
POSES = ["q1_raise", "q2_windA", "r1_back", "p4_over", "r2_fwdup", "r3_horizA", "p5_follow", "q4_low", "q5_half", "p6_rise", "r4_relax"]
## 多出来的刀柄(96 坐标): 姿势 → [(x0, y0, x1, y1), …], 框里不透明像素全部擦掉
ERASE = {
	"p5_follow": [(0, 31, 23, 44)],
	"p6_rise": [(0, 23, 20, 35)],
	"r4_relax": [(0, 27, 22, 41)],
}
## 12 格(11-11 第四版: 每格一个不同姿势、刀每格都往前走; 命中第 5 格): (身体, 横移像素)
SLOTS = [
	("q1_raise", 0),      # 0 双手握刀往右肩抬
	("q2_windA", 1),      # 1 大跨步, 刀举过头、刀尖指右上(约 159°)
	("r1_back", 3),       # 2 刀拉到身后、几乎水平指右(约 176°), 身体往后拧到底
	("p4_over", -2),      # 3 往前踏步, 刀甩到头顶(约 107°)    + 残影 176° → 107°
	("r2_fwdup", -5),     # 4 刀往前上方挥(约 45°)            + 残影 107° → 45°
	("r3_horizA", -8),    # 5 ★命中: 弓步, 刀水平砍过目标(约 0°) + 残影 45° → 0°
	("p5_follow", -10),   # 6 劈到左下大弓步(约 -47°)          + 残影 0° → -47°
	("q4_low", -8),       # 7 还蹲着, 刀垂在左前下方
	("q5_half", -5),      # 8 半站起, 刀垂在身前
	("r4_relax", -3),     # 9 站直, 刀垂在前脚边
	("p6_rise", -1),      # 10 刀从身前收到身侧往后(下一格刀回背上, 刀一路往后走不来回摆)
	("idle", 0),          # 11 站姿(刀回背上)
]
HIT = 5
## 残影: 格 → (圆心 = 这一格握刀的手(96 坐标, 不含横移), 外半径 = 这一格刀长, 内半径比例, 上一格刀角, 这一格刀角, 留下的那段 [a0, a1])
## 刀根 / 刀尖逐格量(.out/ninja_redo3/blade_marks.png 标回图上核过)。角度口径: 0 = 画面左, 90 = 正上, 180 = 画面右。
SMEAR = {
	3: ((22.0, 40.0), 40.0, 0.5, 176.0, 107.0, (0.0, 1.0)),
	4: ((24.0, 23.0), 26.0, 0.45, 107.0, 45.0, (0.0, 1.0)),
	5: ((30.0, 46.0), 30.0, 0.45, 45.0, -3.0, (0.0, 1.0)),
	6: ((20.0, 63.0), 23.0, 0.4, 0.0, -47.0, (0.0, 1.0)),
}
C_EDGE = (255, 255, 255)
C_MID = (255, 236, 168)
C_IN = (236, 178, 84)


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


def load_pose(name):
	im = down2(Image.open(os.path.join(SRC, "pose_%s_192.png" % name)))
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
	return im


def load_idle():
	im = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
	im.paste(Image.open(os.path.join(SRC, "idle0.png")).convert("RGBA"), (POSE_PAD, POSE_PAD))
	return im


def draw_smear(layer, spec, dx):
	(cx, cy), r_out, k_in, a_from, a_to, (a0, a1) = spec
	cx += PAD - POSE_PAD + dx
	cy += PAD - POSE_PAD
	r_in = r_out * k_in
	span = a_from - a_to
	p = layer.load()
	for y in range(FW):
		for x in range(FW):
			vx, vy = x + 0.5 - cx, y + 0.5 - cy
			r = math.hypot(vx, vy)
			if r < r_in or r > r_out:
				continue
			ang = math.degrees(math.atan2(-vy, -vx))
			while ang < a_to:
				ang += 360.0
			while ang > a_to + 360.0:
				ang -= 360.0
			if ang > a_from:
				continue
			t = (a_from - ang) / span                       # 0 起手端 → 1 收尾端
			if t < a0 or t > a1:
				continue
			k = (t - a0) / max(0.001, a1 - a0)
			## 收尾端(刚挥过)最厚, 起手端变薄 + 参差
			inner = r_out - (r_out - r_in) * (0.2 + 0.8 * k)
			jag = ((x * 7 + y * 13) % 5) * 0.7
			if r < inner + (jag if k < 0.4 else 0.0):
				continue
			rr = (r - r_in) / (r_out - r_in)
			c = C_EDGE if rr > 0.72 else (C_MID if rr > 0.4 else C_IN)
			p[x, y] = c + (255,)


def build():
	bodies = {"idle": load_idle()}
	for n in POSES:
		bodies[n] = load_pose(n)
	sheet = Image.new("RGBA", (FW * len(SLOTS), FW), (0, 0, 0, 0))
	for i, (bn, dx) in enumerate(SLOTS):
		canvas = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
		if i in SMEAR:
			sm = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
			draw_smear(sm, SMEAR[i], dx)
			canvas.alpha_composite(sm)
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
	for n in POSES:
		print("%-10s 脚底行 %d" % (n, feet_row(bodies[n])))
	print("写好", OUT, sheet.size)


if __name__ == "__main__":
	main()
