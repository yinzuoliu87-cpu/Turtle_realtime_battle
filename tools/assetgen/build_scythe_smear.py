# -*- coding: utf-8 -*-
"""build_scythe_smear.py — 骰子龟「孤注一掷」月牙刀光帧表 dice-scythe-smear.png(2026-11-05)。

由来: 用户 11-05「孤注一掷这个问题是你整个镰刀都是一个平滑运动，这是确定是你学到的东西吗？这个得改呀」。
  参考德莱厄斯 Q 逐帧(docs/studies/20261105-镰刀参考-德莱厄斯Q逐帧.md): 挥出约 0.1 秒扫过并命中(先快后慢),
  刀后一条连续月牙, 刀头最宽最亮、往后变细变淡, 扫完约 0.2 秒收掉。
  第一版用 ImmediateMesh 每帧现画 —— 直播(S3 逐帧直播)录不进流(verify_stream_coverage 判「新出处」),
  ⇒ 改成和共享地面环同一条路: 逐帧烤成帧表, 运行时 pixel_size 恒定、只切帧(走游戏时钟 _anim_fx), 直播按贴图路径重放。

几何(与运行时常量一一对应, dice_system.gd SCYTHE_*):
  画布中心 = 施法者脚下; +X = 扇形中线(朝目标); 扇形半角 60°(ALLIN_ARC_DEG 120 的一半); 外缘 = 射程(画布半径 - 2 像素)。
  第 f 帧对应 t = (f+1)/30 秒: 刀头进度 = 三次缓出(t / 0.11), 尾巴在 0.35×0.11 秒后开始追刀头, 0.11 秒后整体淡出 0.22 秒。
  每格(30 段 × 3 条色带)只有一个颜色: 外缘亮边 / 红色主体 / 内缘暗边; 不透明度 6 级台阶从尾到头递增; 刀头最后一格往白里提。
  ⇒ 硬边色带, 像素画风; 没有逐像素的软渐变。
确定性: 纯算术, 重跑逐字节相同。

用法: python tools/assetgen/build_scythe_smear.py [输出, 默认 assets/sprites/vfx/dice-scythe-smear.png]
"""
import math
import os
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CELL = 256
FRAMES = 7          # 第 8 帧起尾巴已追上刀头(全空), 只留有内容的 7 帧
FPS = 30.0
SWEEP = 0.11
FADE = 0.22
HALF = math.radians(60.0)
SEGS = 30
PAL = [(255, 219, 219, 242), (242, 41, 61, 217), (115, 10, 31, 179)]   # 外缘亮边 / 主体 / 内缘暗边(alpha = 该带最大不透明度)


def ease_out(x: float) -> float:
	c = min(max(x, 0.0), 1.0)
	return 1.0 - (1.0 - c) ** 3


def frame(f: int) -> Image.Image:
	t = (f + 1) / FPS
	p_lead = ease_out(t / SWEEP)
	p_tail = ease_out((t - SWEEP * 0.35) / (SWEEP * 0.65 + FADE * 0.8))
	fade = 1.0 if t <= SWEEP else min(max(1.0 - (t - SWEEP) / FADE, 0.0), 1.0)
	a_lead = -HALF + 2.0 * HALF * p_lead
	a_tail = -HALF + 2.0 * HALF * min(p_tail, p_lead)
	im = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
	if a_lead - a_tail < 0.004 or fade <= 0.0:
		return im
	px = im.load()
	c = (CELL - 1) / 2.0
	R = CELL / 2.0 - 2.0
	for y in range(CELL):
		for x in range(CELL):
			dx, dy = (x - c) / R, (y - c) / R
			r = math.hypot(dx, dy)
			if r > 1.0 or r < 0.3:
				continue
			a = math.atan2(dy, dx)
			if a < a_tail or a > a_lead:
				continue
			s = (a - a_tail) / (a_lead - a_tail)
			sm = (min(int(s * SEGS), SEGS - 1) + 0.5) / SEGS
			w = 0.16 + 0.46 * sm ** 1.4
			if r < 1.0 - w:
				continue
			band = 0 if r >= 1.0 - w * 0.14 else (1 if r >= 1.0 - w * 0.62 else 2)
			col = PAL[band]
			bright = 0.45 if sm > 0.9 else 0.0
			lvl = (math.floor(sm * 6.0) + 1.0) / 6.0
			rgb = [round(col[k] + (255 - col[k]) * bright) for k in range(3)]
			alpha = round(col[3] * lvl * fade)
			if alpha > 0:
				px[x, y] = (rgb[0], rgb[1], rgb[2], alpha)
	return im


def main() -> int:
	out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "sprites", "vfx", "dice-scythe-smear.png")
	sheet = Image.new("RGBA", (CELL * FRAMES, CELL), (0, 0, 0, 0))
	counts = []
	for f in range(FRAMES):
		fr = frame(f)
		counts.append(sum(1 for p in fr.getdata() if p[3] > 0))
		sheet.paste(fr, (f * CELL, 0))
	sheet.save(out, optimize=False)
	print("帧表 %d×%d → %s · 逐帧不透明像素 %s" % (CELL * FRAMES, CELL, os.path.relpath(out, ROOT), counts))
	return 0


if __name__ == "__main__":
	sys.exit(main())
