# -*- coding: utf-8 -*-
"""tools/assetgen/build_bamboo_spikes.py — 竹刺阵(竹叶龟技能 3)的两张像素素材(2026-11-05)。
由来: 用户 11-05「竹叶龟的这个第三个技能，这很明显是不合格的。这个参考对象是大虫子的 Q 啊，你这也没有参考啊」。
  原来竹刺借的是冰刺贴图(ice-spike-vfx.png)染绿 —— 看上去是一排小圣诞树, 也违反「素材不复用」。
  参考 LoL 科加斯 Q(逐帧记录 docs/studies/20261105-竹刺阵参考-科加斯Q逐帧.md): 爆开那一刻沿圆周一圈弯刺破土向外翘 + 圈内几根 + 地面裂开。
产物(重跑逐字节相同, 硬边、零半透明):
  assets/sprites/vfx/bamboo-stake.png   竹桩 3 格(向左倾 / 直 / 向右倾), 每格 32×64(竿粗 12 像素: 第一版 8 像素实拍像一地草): 斜切尖口(浅黄绿切面) + 两道竹节 + 左高光右暗面 + 1 像素深绿描边
  assets/sprites/vfx/bamboo-quake-crack.png  地面裂纹 96×96: 从圆心放射的 12 道折线裂缝(深褐, 近心 3 像素宽), 隔一道透一线嫩绿光, 圆心一个碎土坑
用法: python tools/assetgen/build_bamboo_spikes.py
"""
import io
import math
import os
import random
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx")

OUTLINE = (24, 66, 30, 255)
BODY = (63, 163, 77, 255)
HI = (143, 211, 106, 255)
SHADE = (40, 118, 52, 255)
NODE = (30, 92, 40, 255)
NODE_HI = (178, 228, 128, 255)
CUT = (232, 240, 176, 255)
CUT_IN = (196, 220, 132, 255)
CW, CH = 32, 64


def stake(lean: int) -> Image.Image:
	img = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
	px = img.load()
	w = 12
	top = 3
	base = CH - 1
	h = base - top
	for y in range(top, base + 1):
		k = (base - y) / h                       # 0 = 底, 1 = 顶
		x0 = int(round((CW - w) / 2 + lean * 8 * k * k))
		## 斜切尖口: 顶上 14 行, 右边往下削(左高右低)
		cut_rows = 13
		dy = y - top
		xl, xr = x0, x0 + w - 1
		if dy < cut_rows:
			xr = x0 + int(round((w - 1) * dy / cut_rows))
		for x in range(xl, xr + 1):
			c = BODY
			if xl + 1 <= x <= xl + 3:
				c = HI
			elif x >= xr - 2:
				c = SHADE
			if dy < cut_rows and x >= xr - 3:
				c = CUT if x >= xr - 1 else CUT_IN       # 切面(斜口)
			px[x, y] = c
		## 竹节: 离底 22 / 44 行一道深色环 + 上面一线亮
		for ny in (20, 40):
			if y == base - ny:
				for x in range(xl, xr + 1):
					px[x, y] = NODE
			if y == base - ny - 1:
				for x in range(xl + 1, xr):
					px[x, y] = NODE_HI
	## 1 像素描边(外扩)
	src = img.copy().load()
	for y in range(CH):
		for x in range(CW):
			if src[x, y][3] == 0:
				for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
					xx, yy = x + dx, y + dy
					if 0 <= xx < CW and 0 <= yy < CH and src[xx, yy][3] != 0:
						px[x, y] = OUTLINE
						break
	return img


def crack() -> Image.Image:
	n = 96
	img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
	px = img.load()
	rnd = random.Random(1105)
	c = (n - 1) / 2.0
	DARK = (42, 29, 18, 255)
	GLOW = (155, 224, 90, 255)
	for i in range(12):
		a = 2 * math.pi * i / 12 + rnd.uniform(-0.2, 0.2)
		r = 6.0
		x, y = c + math.cos(a) * r, c + math.sin(a) * r
		glow = i % 2 == 0
		L = rnd.uniform(30, 44)
		while r < L:
			a += rnd.uniform(-0.35, 0.35)
			step = 3.0
			nx, ny = x + math.cos(a) * step, y + math.sin(a) * step
			for t in range(4):
				px_x = int(round(x + (nx - x) * t / 3))
				px_y = int(round(y + (ny - y) * t / 3))
				wdt = 3 if r < L * 0.35 else (2 if r < L * 0.75 else 1)
				for ox in range(wdt):
					for oy in range(wdt):
						if 0 <= px_x + ox < n and 0 <= px_y + oy < n:
							px[px_x + ox, px_y + oy] = DARK
				if glow and r < L * 0.7 and 0 <= px_x < n and 0 <= px_y < n:
					px[px_x, px_y] = GLOW
			x, y = nx, ny
			r += step
	## 圆心一小块碎土(深褐)
	for yy in range(n):
		for xx in range(n):
			d2 = (xx - c) ** 2 + (yy - c) ** 2
			if d2 <= 100 + 30 * math.sin(math.atan2(yy - c, xx - c) * 5):
				px[xx, yy] = DARK
			elif d2 <= 150 + 30 * math.sin(math.atan2(yy - c, xx - c) * 5) and (xx + yy) % 3 == 0:
				px[xx, yy] = GLOW
	return img


def save(img: Image.Image, name: str) -> None:
	buf = io.BytesIO()
	img.save(buf, "PNG", optimize=False)
	p = os.path.join(OUT, name)
	data = buf.getvalue()
	if os.path.exists(p) and open(p, "rb").read() == data:
		print("不变", name)
		return
	open(p, "wb").write(data)
	print("写出", name, img.size)


def main() -> int:
	sheet = Image.new("RGBA", (CW * 3, CH), (0, 0, 0, 0))
	for i, lean in enumerate((-1, 0, 1)):
		sheet.paste(stake(lean), (i * CW, 0))
	save(sheet, "bamboo-stake.png")
	save(crack(), "bamboo-quake-crack.png")
	return 0


if __name__ == "__main__":
	sys.exit(main())
