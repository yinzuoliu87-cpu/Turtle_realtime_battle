# -*- coding: utf-8 -*-
"""paint_chest_fx.py —— 宝箱龟普攻的两张叠加发光小图(2026-11-20; 脚本按公式画的灰度图, 不是手画)。

  python tools/assetgen/paint_chest_fx.py
产出 assets/sprites/vfx/:
  chest-glow.png   64×64  软圆光晕(中心实、往外按平方衰减), 引擎里叠加发光 + 按用途上色(砸地亮芯 / 波头 / 命中)
  chest-glint.png  48×48  宝石星闪: 一横一竖两道细长光芒 + 两道短斜芒 + 小亮芯(参考奥恩 Q 第 6 帧爆闪的放射纹, 换成宝石反光的四角星)
都是白色 + 透明度, 颜色在游戏里给。重跑逐字节相同。
"""
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx")


def glow(n=64):
	im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
	px = im.load()
	c = (n - 1) / 2.0
	for y in range(n):
		for x in range(n):
			d = math.hypot(x - c, y - c) / (n / 2.0)
			a = max(0.0, 1.0 - d) ** 2
			px[x, y] = (255, 255, 255, int(round(255 * a)))
	return im


def glint(n=48):
	im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
	px = im.load()
	c = (n - 1) / 2.0
	for y in range(n):
		for x in range(n):
			dx, dy = (x - c) / (n / 2.0), (y - c) / (n / 2.0)
			r = math.hypot(dx, dy)
			## 一横一竖长芒(宽 0.05, 长到边) + 两道斜短芒(宽 0.04, 长 0.45) + 亮芯(半径 0.18)
			a = 0.0
			for (u, v, w, ln) in ((dx, dy, 0.05, 1.0), (dy, dx, 0.05, 1.0)):
				if abs(v) < w * (1.0 - abs(u)):
					a = max(a, (1.0 - abs(u) / ln) ** 1.5)
			q = (dx + dy) / math.sqrt(2.0)
			p = (dx - dy) / math.sqrt(2.0)
			for (u, v) in ((q, p), (p, q)):
				if abs(v) < 0.04 * (1.0 - abs(u) / 0.45) and abs(u) < 0.45:
					a = max(a, 0.7 * (1.0 - abs(u) / 0.45))
			a = max(a, max(0.0, 1.0 - r / 0.18) ** 1.2)
			px[x, y] = (255, 255, 255, int(round(255 * min(1.0, a))))
	return im


if __name__ == "__main__":
	for name, im in (("chest-glow.png", glow()), ("chest-glint.png", glint())):
		p = os.path.join(OUT, name)
		im.save(p, optimize=False)
		print("ok", p, im.size)
