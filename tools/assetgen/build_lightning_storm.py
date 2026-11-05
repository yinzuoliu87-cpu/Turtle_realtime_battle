# -*- coding: utf-8 -*-
"""tools/assetgen/build_lightning_storm.py — 闪电龟·雷暴的两张像素素材(2026-11-05)。
由来: 用户 11-05 夜「闪电龟的技能清楚，清楚在哪里？你为什么觉得清楚？」—— 实查雷暴的「风暴云」是技能图标 lightning-2.png(一朵云 + 黄色 ⚡ 符号),
  落雷是图标 lightning-0.png 竖着放、爆点是 lightning-3.png: 看上去是往敌人头上盖表情图标, 不是闪电。
  参考 LoL 凯南 R(官网演示 0085_R1): 从天上劈下的是细长、带分叉、白芯蓝边的锯齿闪电, 落点一团白蓝闪光。
产物(重跑逐字节相同, 硬边、零半透明):
  assets/sprites/vfx/lightning-bolt-6.png    竖直闪电 6 种(每格 40×192): 白芯 2 像素 + 浅蓝 + 外蓝边, 锯齿主干 + 1~2 条分叉
  assets/sprites/vfx/lightning-storm-cloud.png  风暴云 2 格(每格 192×96): 第 0 格暗云, 第 1 格云里打闪(云底亮一片)
用法: python tools/assetgen/build_lightning_storm.py
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
CORE = (255, 255, 255, 255)
INNER = (196, 236, 255, 255)
OUTER = (92, 170, 255, 255)
BW, BH, NB = 40, 192, 6


def _plot(px, w, h, x, y, c, over=True):
	if 0 <= x < w and 0 <= y < h:
		if over or px[x, y][3] == 0:
			px[x, y] = c


def _stroke(px, w, h, pts, thick):
	"""折线: 外蓝(thick+2) → 浅蓝(thick) → 白芯(thick-1) 三层叠, 硬边。"""
	for layer, (c, t) in enumerate([(OUTER, thick + 2), (INNER, thick), (CORE, max(1, thick - 1))]):
		for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
			n = max(abs(x1 - x0), abs(y1 - y0), 1)
			for i in range(n + 1):
				x = x0 + (x1 - x0) * i / n
				y = y0 + (y1 - y0) * i / n
				for dx in range(-(t // 2), t - t // 2):
					_plot(px, w, h, int(round(x)) + dx, int(round(y)), c)


def bolt(seed: int) -> Image.Image:
	rnd = random.Random(seed)
	img = Image.new("RGBA", (BW, BH), (0, 0, 0, 0))
	px = img.load()
	x = BW // 2
	pts = [(x, 0)]
	y = 0
	while y < BH - 1:
		y = min(BH - 1, y + rnd.randint(10, 22))
		x = max(6, min(BW - 7, x + rnd.randint(-9, 9)))
		pts.append((x, y))
	## 分叉: 从主干中段岔出去 1~2 条, 细一号、往下斜着收
	for _ in range(rnd.randint(1, 2)):
		k = rnd.randint(2, max(2, len(pts) - 3))
		bx, by = pts[k]
		br = [(bx, by)]
		d = rnd.choice([-1, 1])
		for _ in range(rnd.randint(2, 3)):
			bx = max(2, min(BW - 3, bx + d * rnd.randint(4, 9)))
			by = min(BH - 1, by + rnd.randint(8, 16))
			br.append((bx, by))
		_stroke(px, BW, BH, br, 2)
	_stroke(px, BW, BH, pts, 3)
	return img


def cloud(lit: bool) -> Image.Image:
	W, H = 192, 96
	img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	px = img.load()
	rnd = random.Random(1105)
	puffs = [(rnd.uniform(30, W - 30), rnd.uniform(34, 60), rnd.uniform(18, 34)) for _ in range(11)]
	puffs += [(W * 0.5, 58, 40), (W * 0.3, 60, 30), (W * 0.7, 60, 30)]
	TOP = (86, 98, 128, 255)
	MID = (58, 66, 92, 255)
	LOW = (38, 42, 62, 255)
	EDGE = (24, 26, 40, 255)
	GLOW = (170, 210, 255, 255)
	GLOW2 = (120, 170, 245, 255)
	for y in range(H):
		for x in range(W):
			inside = None
			for cx, cy, r in puffs:
				d = math.hypot((x - cx), (y - cy) * 1.25)
				if d <= r:
					inside = (cx, cy, r, d) if inside is None or (cy - r) < (inside[1] - inside[2]) else inside
			if inside is None:
				continue
			cx, cy, r, d = inside
			## 上亮下暗三阶(硬边色阶, 不渐变): 顶部受光, 底部压暗
			c = TOP if y < cy - r * 0.45 else (MID if y < cy + r * 0.25 else LOW)
			if lit:   # 第 1 格: 云里打闪 —— 云团下半部一个椭圆范围里, 原有三阶色整体换成亮一套(保留云的层次, 不画硬边几何形)
				e = ((x - W * 0.5) / 62.0) ** 2 + ((y - 66) / 26.0) ** 2
				if e < 1.0:
					c = {TOP: (150, 178, 228, 255), MID: GLOW2, LOW: GLOW}[c] if e < 0.45 else {TOP: (118, 136, 182, 255), MID: (96, 118, 176, 255), LOW: (110, 150, 220, 255)}[c]
			px[x, y] = c
	## 1 像素深色描边
	src = img.copy().load()
	for y in range(H):
		for x in range(W):
			if src[x, y][3] == 0:
				for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
					xx, yy = x + dx, y + dy
					if 0 <= xx < W and 0 <= yy < H and src[xx, yy][3] != 0:
						px[x, y] = EDGE
						break
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
	sheet = Image.new("RGBA", (BW * NB, BH), (0, 0, 0, 0))
	for i in range(NB):
		sheet.paste(bolt(2026110500 + i), (i * BW, 0))
	save(sheet, "lightning-bolt-6.png")
	cs = Image.new("RGBA", (192 * 2, 96), (0, 0, 0, 0))
	cs.paste(cloud(False), (0, 0))
	cs.paste(cloud(True), (192, 0))
	save(cs, "lightning-storm-cloud.png")
	return 0


if __name__ == "__main__":
	sys.exit(main())
