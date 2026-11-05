# -*- coding: utf-8 -*-
"""tools/assetgen/fetch_keyframe.py — 下载 PixelLab 像素化定稿并抠底(2026-11-05; build_pet_actions.py 的上一步)。

image_to_pixelart 的结果是不透明底(糖果龟实测: 四角透明、其余一片 (131,131,132) 灰) ⇒
  背景色 = 边缘上最常见的不透明颜色; 从所有边缘像素出发, 与背景色差 ≤ TOL 且连通的像素抠成透明; 透明度二值。
输出: tools/assetgen/pet_src/<龟>/pixel_keyframe.png(原样)+ keyframe.png(抠底后)。
用法: python tools/assetgen/fetch_keyframe.py <龟id> <job_id>
"""
import os
import sys
import time
import urllib.error
import urllib.request
from collections import Counter, deque

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
TOL = 8


def cut(a: np.ndarray) -> tuple:
	h, w = a.shape[:2]
	border = [tuple(a[y, x, :3]) for y in range(h) for x in (0, w - 1) if a[y, x, 3] > 0]
	border += [tuple(a[y, x, :3]) for x in range(w) for y in (0, h - 1) if a[y, x, 3] > 0]
	if not border:
		return a, 0
	## 只有「真有一圈底色」才抠: 边缘最常见的不透明色要占边长 ≥ 20%(image_to_pixelart 的灰底: 四角透明、其余两百多格同一灰)。
	##   Pro Flash 改出来的透明底图边缘只有几个描边点 ⇒ 不抠; 拿它当背景色会把整圈深色描边 / 深色身体抠掉
	##   (11-05 晚猎人「朝天拉弓」: 边缘只有 6 个黑点 ⇒ 按黑色抠掉, 腿断了; 海盗阵亡姿势整圈描边被抠, 返工)
	if Counter(border).most_common(1)[0][1] < 0.2 * 2 * (h + w):
		out = a.copy()
		out[..., 3] = np.where(out[..., 3] >= 128, 255, 0)
		out[out[..., 3] == 0] = 0
		return out, 0
	bg = np.array(Counter(border).most_common(1)[0][0], dtype=int)

	def isbg(y, x):
		return a[y, x, 3] == 0 or int(np.abs(a[y, x, :3].astype(int) - bg).max()) <= TOL
	seen = np.zeros((h, w), bool)
	q = deque()
	for y in range(h):
		for x in (0, w - 1):
			if not seen[y, x] and isbg(y, x):
				seen[y, x] = True
				q.append((y, x))
	for x in range(w):
		for y in (0, h - 1):
			if not seen[y, x] and isbg(y, x):
				seen[y, x] = True
				q.append((y, x))
	while q:
		y, x = q.popleft()
		for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			ny, nx = y + dy, x + dx
			if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx] and isbg(ny, nx):
				seen[ny, nx] = True
				q.append((ny, nx))
	out = a.copy()
	out[seen] = 0
	out[..., 3] = np.where(out[..., 3] >= 128, 255, 0)
	out[out[..., 3] == 0] = 0
	return out, int(seen.sum())


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	tid, job = sys.argv[1], sys.argv[2]
	d = os.path.join(HERE, "pet_src", tid)
	os.makedirs(d, exist_ok=True)
	url = "https://api.pixellab.ai/mcp/images/%s/download" % job
	t0 = time.time()
	while True:
		try:
			data = OPENER.open(url, timeout=60).read()
			break
		except urllib.error.HTTPError as e:
			if e.code != 423 or time.time() - t0 > 360:
				raise SystemExit("%s 下载失败 HTTP %d" % (job, e.code))
			time.sleep(6)
	raw = os.path.join(d, "pixel_keyframe.png")
	open(raw, "wb").write(data)
	a = np.asarray(Image.open(raw).convert("RGBA"))
	out, n = cut(a)
	Image.fromarray(out, "RGBA").save(os.path.join(d, "keyframe.png"), optimize=False)
	print("%-9s 定稿 %d×%d · 抠底 %d 像素" % (tid, a.shape[1], a.shape[0], n))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
