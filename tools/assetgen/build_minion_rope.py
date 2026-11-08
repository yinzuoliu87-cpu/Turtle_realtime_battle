# -*- coding: utf-8 -*-
"""tools/assetgen/build_minion_rope.py — 近战小将「人体浪板」铁索的一节(2026-11-08)。

用户 11-08:「近战小将的这个动画和特效，我们检查一下…放出那个绳索拉向对面…」。
逐帧查(11-08): 原绳索是一条现画的线(ImmediateMesh), 射出 0.42 秒后就淡掉, 而拉人第 1.28 秒才开始 ⇒ 整段拉人看不到绳子;
  线又是整条一次画死的, 没法随小将前进逐段收。改成沿线摆一节节小图(同精英铁锁的链节做法, 但不借它的图),
  拉的途中小将经过的那几节收掉 ⇒ 看起来是顺着绳子被拽过去。
画法: 16×8 横向一节, 两股麻绳拧成(斜纹交错), 深红褐 + 亮面 + 暗面 + 1 像素黑描边; 零半透明。
确定性: 重跑逐字节相同。用法: python tools/assetgen/build_minion_rope.py
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx", "minion-rope-link.png")

W, H = 16, 8
INK = (26, 10, 10, 255)
DARK = (92, 24, 22, 255)
MID = (153, 38, 38, 255)
LITE = (214, 92, 70, 255)
GLINT = (240, 170, 130, 255)


def main() -> int:
	im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	px = im.load()
	## 绳身: 第 1~6 行(上下各留 1 行描边)
	for x in range(W):
		px[x, 1] = INK
		px[x, 6] = INK
		for y in range(2, 6):
			## 两股拧成: 每 4 像素一个斜纹周期, 斜纹上半亮、下半暗
			k = (x + (5 - y)) % 4
			if k == 0:
				c = INK if y in (2, 5) else DARK
			elif k == 1:
				c = LITE if y <= 3 else MID
			elif k == 2:
				c = MID
			else:
				c = DARK
			px[x, y] = c
		if x % 4 == 1:
			px[x, 2] = GLINT
	im.save(OUT, optimize=False)
	print("铁索一节 %d×%d → %s" % (W, H, os.path.relpath(OUT, ROOT)))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
