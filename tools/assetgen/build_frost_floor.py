# -*- coding: utf-8 -*-
"""build_frost_floor.py — 寒冰龟「冰霜」地面冰层 frost-floor.png 的后处理(2026-11-05)。

来源: PixelLab pixflux 400×400 生成(job 3ee5ab3f-2cca-42c0-a692-5716c63a2400, seed 2205; 描述见
docs/studies/20261105-冰霜参考-艾尼维亚大招逐帧.md)。它要了透明底但回来的是不透明白底 ⇒ 这里把圆外的底色抠掉:
从四个角做洪水填充, 和角上颜色相差 ≤ TOL 的连通像素 alpha 置 0(圆里面的浅色不和角连通, 不会被抠)。
产物只有全透明 / 全不透明两种 alpha(像素画硬边, pixel_art_audit 要求零半透明)。
确定性: 同一张源图重跑逐字节相同。

用法: python tools/assetgen/build_frost_floor.py <源 png> [输出, 默认 assets/sprites/vfx/frost-floor.png]
"""
import os
import sys
from collections import deque

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOL = 24


def main() -> int:
	src = sys.argv[1]
	dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "assets", "sprites", "vfx", "frost-floor.png")
	im = Image.open(src).convert("RGBA")
	w, h = im.size
	px = im.load()
	seen = bytearray(w * h)
	q = deque()
	for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
		q.append((x, y, px[x, y][:3]))
	cleared = 0
	while q:
		x, y, ref = q.popleft()
		if x < 0 or y < 0 or x >= w or y >= h or seen[y * w + x]:
			continue
		r, g, b, a = px[x, y]
		if a != 0 and max(abs(r - ref[0]), abs(g - ref[1]), abs(b - ref[2])) > TOL:
			continue
		seen[y * w + x] = 1
		px[x, y] = (0, 0, 0, 0)
		cleared += 1
		for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			q.append((x + dx, y + dy, ref))
	for y in range(h):
		for x in range(w):
			r, g, b, a = px[x, y]
			if 0 < a < 255:
				px[x, y] = (r, g, b, 255 if a >= 128 else 0)
	im.save(dst, optimize=False)
	print("抠底 %d / %d 像素 → %s" % (cleared, w * h, os.path.relpath(dst, ROOT)))
	return 0


if __name__ == "__main__":
	sys.exit(main())
