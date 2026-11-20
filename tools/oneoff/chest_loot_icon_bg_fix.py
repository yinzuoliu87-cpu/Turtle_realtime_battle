# -*- coding: utf-8 -*-
"""chest_loot_icon_bg_fix.py —— 宝箱龟战利品图标抠掉没去干净的底(2026-11-20, 一次性)。

由来: 图鉴装备栏列出 15 件战利品(用户 11-20)后实拍看到 3 张图标带着生成时的底:
  王者之冠 / 星际龟的星辉 = 整张不透明深紫方块底, 坚固木盾 = 上下各 4 行黑条(2026-07-15 PixelLab 出图时没去底)。
  开箱时头顶弹的图标、背包、对局面板、图鉴都会露出这块深色。
做法: ① 从四条边往里漫水, 只抠「颜色离左上角底色 < 16、且与边连通」的像素(物件自己的深色描边颜色不同、不连到边 ⇒ 不碰)。
  ② 抠完后王者之冠 / 木盾的外沿没有深色描边(原来靠那块深底当边; tools/icon_art_audit.py 量出描边闭合 0.00 / 0.09, 门槛 0.45)
     ⇒ 照项目像素图标的规矩补一圈 1 像素描边: 王者之冠用它原来底的颜色(贴在深底上时的边缘观感不变), 木盾用深褐。星辉自带深紫描边, 不补。
  抠完的图左上角已透明 ⇒ 再跑一遍什么都不改(幂等)。
  python tools/oneoff/chest_loot_icon_bg_fix.py
"""
import os
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TIDS = ["crown", "starlight", "wood_shield"]
TOL = 16.0
OUTLINE = {"crown": (17, 7, 27), "wood_shield": (38, 26, 20)}

for tid in TIDS:
	p = os.path.join(ROOT, "assets", "sprites", "equip", "chest-t-%s.png" % tid)
	im = Image.open(p).convert("RGBA")
	px = im.load()
	w, h = im.size
	c0 = px[0, 0]
	n = 0
	if c0[3] > 0:
		seen = set()
		q = deque([(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)])
		while q:
			x, y = q.popleft()
			if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
				continue
			seen.add((x, y))
			c = px[x, y]
			if c[3] == 0 or sum((c[i] - c0[i]) ** 2 for i in range(3)) ** 0.5 >= TOL:
				continue
			px[x, y] = (0, 0, 0, 0)
			n += 1
			q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
		col = OUTLINE.get(tid)
		if col is not None:
			ring = [(x, y) for y in range(h) for x in range(w) if px[x, y][3] == 0 and any(
				0 <= x + dx < w and 0 <= y + dy < h and px[x + dx, y + dy][3] > 0 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
			for x, y in ring:
				px[x, y] = (*col, 255)
		im.save(p, optimize=False)
	print(tid, "抠掉", n, "格")
