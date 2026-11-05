# -*- coding: utf-8 -*-
"""tools/assetgen/build_elite_passive_combo.py — 精英小将「被动」格的三合一图标(2026-11-05)。

由来: 用户 11-05「对局内…信息面板这个被动这里，嗯，该怎么去画？因为我们现在已经有三个图标嘛，你就可以用两个斜杠的方式给它，
  就是在一个图里面两个斜杠，然后就最左边展示第一个图标的左部分，然后第二个图标的中部分就放中间。三个图标放在右边」。
  战斗信息面板只放得下「被动 | 攻击 | 技能」三格, 精英小将的三条被动(旋刃 / 铁锁 / 吞噬)合在一格 ⇒ 这一格的图标 =
  两道「/」斜杠切成三段: 左段取旋刃图标的左边、中段取铁锁图标的中间、右段取吞噬图标的右边; 斜杠是深色描边 + 一道亮紫芯。
输入: assets/sprites/passive/elite-whirl-icon.png / elite-whip-icon.png / elite-consume-icon.png(都是 64×64)
输出: assets/sprites/passive/elite-passive-combo.png(64×64, 零半透 —— 像素画规矩, pixel_art_audit 守)
确定性: 纯逐像素运算, 重跑逐字节相同。仓库根目录 = 本文件往上三层(tools/README.md)。
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = [os.path.join(ROOT, "assets", "sprites", "passive", n) for n in ("elite-whirl-icon.png", "elite-whip-icon.png", "elite-consume-icon.png")]
OUT = os.path.join(ROOT, "assets", "sprites", "passive", "elite-passive-combo.png")
N = 64
SLANT = 0.45                 # 斜杠倾斜: 每往上 1 像素, 分界往右挪 0.45 像素(「/」)
CUTS = (N / 3.0, N * 2.0 / 3.0)   # 两道斜杠在图中线高度处的横坐标
LINE = (14, 12, 30, 255)     # 斜杠描边(与三张图标外描边同一个深色量级)
CORE = (196, 160, 255, 255)  # 斜杠中间一道亮紫芯(三张图标的紫色高光)


def band(x: int, y: int) -> float:
	"""这个像素到「第几段」的连续坐标: 以图中线为基准、按斜杠倾斜修正后的横坐标。"""
	return x + 0.5 - SLANT * ((N / 2.0) - (y + 0.5))


def main() -> int:
	ims = [Image.open(p).convert("RGBA") for p in SRC]
	for im in ims:
		assert im.size == (N, N), im.size
	out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
	po = out.load()
	px = [im.load() for im in ims]
	for y in range(N):
		for x in range(N):
			b = band(x, y)
			seg = 0 if b < CUTS[0] else (1 if b < CUTS[1] else 2)
			r, g, bl, a = px[seg][x, y]
			po[x, y] = (r, g, bl, 255) if a >= 128 else (0, 0, 0, 0)
			## 斜杠: 离分界 1.5 像素内画深色描边, 0.5 像素内画亮紫芯(整格不透明, 斜杠贯穿整张图)
			d = min(abs(b - CUTS[0]), abs(b - CUTS[1]))
			if d < 0.5:
				po[x, y] = CORE
			elif d < 1.5:
				po[x, y] = LINE
	out.save(OUT, optimize=False)
	print("写出", os.path.relpath(OUT, ROOT))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
