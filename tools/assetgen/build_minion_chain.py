# -*- coding: utf-8 -*-
"""tools/assetgen/build_minion_chain.py — 近战小将「人体浪板」铁链的一节(2026-11-08 第二版)。

用户 11-08:「你这个小将他丢出这个锁链的时候，什么是锁链？是一个个正方形的像素块。」
第一版画成 16×8 的红褐麻绳小段, 缩到战场大小就是一串方块, 认不出是链子(技能本来写的就是「射铁链」)。
第二版: 一节 = 一个平放的椭圆链环(中间透空, 看得见环孔) + 一节侧立的链环(细条), 横竖交替相扣; 铁灰 + 顶部高光 + 1 像素深描边;
  沿线平铺时下一节的平放环接在侧立环末端 ⇒ 一眼是一串铁链。零半透明。
确定性: 重跑逐字节相同。用法: python tools/assetgen/build_minion_chain.py
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx", "minion-chain-link.png")

W, H = 26, 12
INK = (22, 24, 30, 255)
DARK = (70, 76, 88, 255)
MID = (118, 126, 140, 255)
LITE = (178, 186, 198, 255)
GLINT = (232, 238, 244, 255)


def _ring(px):
	"""平放的长椭圆链环: 中心 (7.5, 6.0), 外半径 7.5 × 5.0, 内孔 4.2 × 1.6(真实链环是长圈, 不是正圆)。"""
	cx, cy = 7.5, 6.0
	for y in range(H):
		for x in range(16):
			dx, dy = (x + 0.5 - cx), (y + 0.5 - cy)
			o = (dx / 7.5) ** 2 + (dy / 5.0) ** 2
			i = (dx / 4.2) ** 2 + (dy / 1.6) ** 2
			if o > 1.0 or i < 1.0:
				continue
			edge_o = (dx / 6.4) ** 2 + (dy / 3.9) ** 2 > 1.0       # 外缘一圈
			edge_i = (dx / 5.2) ** 2 + (dy / 2.6) ** 2 < 1.0       # 内孔一圈
			if edge_o or edge_i:
				c = INK
			elif dy < -1.0:
				c = LITE                                              # 上半受光
			elif dy > 1.5:
				c = DARK                                              # 下半背光
			else:
				c = MID
			px[x, y] = c
	px[5, 2] = GLINT
	px[6, 2] = GLINT


def _bar(px):
	"""侧立的链环(看到的是厚度): 从环孔右沿穿出到这一节末端, 4 像素高。"""
	for x in range(12, W):
		for y in range(4, 8):
			if y in (4, 7) or x in (12, W - 1):
				c = INK
			elif y == 5:
				c = LITE
			else:
				c = MID
			px[x, y] = c
	px[18, 5] = GLINT


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	px = im.load()
	_bar(px)
	_ring(px)          # 环压在条的左端上(条穿进环孔的那一截被环挡住)
	im.save(OUT, optimize=False)
	print("铁链一节 %d×%d → %s" % (W, H, os.path.relpath(OUT, ROOT)))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
