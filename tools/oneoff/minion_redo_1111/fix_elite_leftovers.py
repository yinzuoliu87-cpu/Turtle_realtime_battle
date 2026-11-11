# -*- coding: utf-8 -*-
"""精英小将源帧上三处 AI 残留按框删(11-11 逐帧看出来的; 框里只有残留, 放大网格量过)。"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
S = os.path.join(ROOT, "tools", "assetgen", "minion_seq", "elite")
FIX = [
	("whip/f_01.png", (135, 133, 163, 147), "all", "铁锁后拉: 拳头下方抠手臂带进来的海草碎片"),
	("hammer/f_04.png", (144, 154, 159, 167), "all", "铁锤砸地: 右侧粉灰碎石"),
	("attack/f_02.png", (62, 95, 76, 111), "grey", "普攻斜前上: 刃根处品红拖影删剩的浅灰"),
	("hammer/f_04.png", (26, 150, 44, 166), "grey", "铁锤砸地: 左侧灰色碎石(第一遍只看到右边那团)"),
]
for rel, (x0, y0, x1, y1), mode, why in FIX:
	p = os.path.join(S, rel)
	im = Image.open(p).convert("RGBA")
	px = im.load()
	n = 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			r, g, b, a = px[x, y]
			if a == 0:
				continue
			if mode == "all" or (max(r, g, b) - min(r, g, b) < 30 and r > 110):
				px[x, y] = (0, 0, 0, 0)
				n += 1
	im.save(p, optimize=False)
	print("%-18s 删 %3d 像素  %s" % (rel, n, why))
