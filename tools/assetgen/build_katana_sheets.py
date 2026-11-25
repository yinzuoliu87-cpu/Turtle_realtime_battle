# -*- coding: utf-8 -*-
"""build_katana_sheets.py —— 把 blender_katana_tornado.py 渲出的帧拼成精灵表(2026-11-25)。

先跑 Blender(见 blender_katana_tornado.py 头注)渲到 .out/katana_blend/tornado/f_XX.png, 再:
  python tools/assetgen/build_katana_sheets.py
产出: assets/sprites/vfx/katana-tornado.png —— 16 帧 × 192 横排一行(3072 宽, 不超手机 GPU 上限 4096)。
不做任何后期(帧原样拼)。重跑逐字节相同(输入帧不变时)。
锚点 = 漏斗底(地面)在帧里的位置: 正交相机俯角 51°、对准高 1.26 米处、画布 4.4 米 / 192 像素
  ⇒ 地面原点在画面中心下方 1.26 × cos51° = 0.79 米 = 34.6 像素 ⇒ (96, 131)。
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, ".out", "katana_blend")
OUT = os.path.join(ROOT, "assets", "sprites", "vfx")

SHEETS = [("katana-tornado.png", "tornado")]


def main():
	for name, seg in SHEETS:
		d = os.path.join(SRC, seg)
		fs = sorted(f for f in os.listdir(d) if f.startswith("f_") and f.endswith(".png"))
		ims = [Image.open(os.path.join(d, f)).convert("RGBA") for f in fs]
		cw, ch = ims[0].size
		sheet = Image.new("RGBA", (cw * len(ims), ch), (0, 0, 0, 0))
		x0, x1 = cw, 0
		for i, im in enumerate(ims):
			sheet.paste(im, (i * cw, 0))
			bb = im.getbbox()
			if bb:
				x0, x1 = min(x0, bb[0]), max(x1, bb[2])
		assert sheet.size[0] <= 4096
		p = os.path.join(OUT, name)
		sheet.save(p, optimize=False)
		print("ok", p, sheet.size, "%d 帧" % len(ims), "内容横跨 x %d..%d (%d 像素)" % (x0, x1, x1 - x0))


if __name__ == "__main__":
	main()
