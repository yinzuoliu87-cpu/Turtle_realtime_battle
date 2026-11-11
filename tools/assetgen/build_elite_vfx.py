# -*- coding: utf-8 -*-
"""tools/assetgen/build_elite_vfx.py — 精英小将特效贴图(巨拳 / 长刃 / 三种地刺)按深渊精英重画(2026-11-11)。

11-11 凌晨只把旧红紫精英的黑红贴图逐像素换成紫光(形状还是旧精英的灰黑肉质拳头 / 灰刀 / 黑触手),
白天重画: PixelLab create_image_pro_flash, 锁深渊精英自己的色板(深蓝盔甲 + 紫光 + 骨白珊瑚尖, 从 elite/idle.png 取),
巨拳以精英 whip.png 第 1 格的拳头那一块当风格参考。原图在 tools/assetgen/ai_src/elite_vfx/<名>_ai.png。
这里只做确定性的后处理: alpha 二值化(≥ 128 实心)、裁到内容(四周留 1 像素) —— 游戏按贴图高度(长刃按宽度)缩放,
画布留空边会让东西看着变小。尺寸 / 用法见 scripts/systems/skills/elite_system.gd(_elite_whirl / _elite_spike / 铁锤)。
确定性: 重跑逐字节相同。用法: python tools/assetgen/build_elite_vfx.py [--check]
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(HERE, "ai_src", "elite_vfx")
OUT = os.path.join(ROOT, "assets", "sprites", "vfx")
NAMES = ["bio-fist", "bio-blade", "bio-spike-a", "bio-spike-b", "bio-spike-c"]


def build(name):
	im = Image.open(os.path.join(SRC, name + "_ai.png")).convert("RGBA")
	px = im.load()
	w, h = im.size
	for y in range(h):
		for x in range(w):
			r, g, b, a = px[x, y]
			px[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0)
	x0, y0, x1, y1 = im.getbbox()
	x0, y0 = max(0, x0 - 1), max(0, y0 - 1)
	x1, y1 = min(w, x1 + 1), min(h, y1 + 1)
	return im.crop((x0, y0, x1, y1))


def main():
	check = "--check" in sys.argv
	bad = []
	for n in NAMES:
		im = build(n)
		p = os.path.join(OUT, n + ".png")
		if check:
			cur = Image.open(p).convert("RGBA")
			if cur.size != im.size or cur.tobytes() != im.tobytes():
				bad.append(n)
		else:
			im.save(p, optimize=False)
			print("%-12s %s" % (n, im.size))
	if check:
		print("ALL OK" if not bad else "不一致: %s(重跑 build_elite_vfx.py)" % bad)
		sys.exit(1 if bad else 0)


if __name__ == "__main__":
	main()
