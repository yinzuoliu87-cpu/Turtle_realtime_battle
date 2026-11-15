# -*- coding: utf-8 -*-
"""build_candy_sheets.py —— 把 blender_candy_fx.py 渲出的帧拼成精灵表(2026-11-15)。

先跑 Blender(见 blender_candy_fx.py 头注)渲到 .out/candy_blend/<段>/f_XX.png, 再:
  python tools/assetgen/build_candy_sheets.py
产出(assets/sprites/vfx/; 每段两张: 立着的 + 贴地的 `-gnd`, 帧数 / 排法相同):
  candy-slam(-gnd).png   糖果锤落点 27 帧 × 256(9 列 × 3 行)
  candy-erupt(-gnd).png  沿线迸发两种 × 21 帧 × 160(7 列 × 6 行; 第 0~20 帧一种、21~41 另一种)
  candy-sweep(-gnd).png  横扫命中 16 帧 × 192(8 列 × 2 行; 挥向画面右, 往左挥时游戏里水平翻转)
唯一的后期: 贴地层的影子(纯黑像素)不透明度 × SHADOW_K —— 影子是 Blender 只接影子的地面渲出来的全黑, 压在游戏草地上太重。
宽度都不超过 4096(手机 GPU 上限)。重跑逐字节相同(输入帧不变时)。
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, ".out", "candy_blend")
OUT = os.path.join(ROOT, "assets", "sprites", "vfx")
SHADOW_K = 0.5

## 2.5D 分层(用户 11-15「修层次，画风不变」): 立着那遍 → 公告板(画在龟前面); 贴地那遍 → 平铺在地上(压在龟脚下)
SHEETS = [
	("candy-slam.png", ["slam_up"], 9),
	("candy-slam-gnd.png", ["slam_gnd"], 9),
	("candy-erupt.png", ["erupt_up", "erupt2_up"], 7),
	("candy-erupt-gnd.png", ["erupt_gnd", "erupt2_gnd"], 7),
	("candy-sweep.png", ["sweep_up"], 8),
	("candy-sweep-gnd.png", ["sweep_gnd"], 8),
]


def _frames(seg):
	d = os.path.join(SRC, seg)
	fs = sorted(f for f in os.listdir(d) if f.startswith("f_") and f.endswith(".png"))
	return [os.path.join(d, f) for f in fs]


def _soften_shadow(im):
	px = im.load()
	w, h = im.size
	for y in range(h):
		for x in range(w):
			r, g, b, a = px[x, y]
			if a > 0 and r < 10 and g < 10 and b < 10:
				px[x, y] = (0, 0, 0, int(round(a * SHADOW_K)))
	return im


def main():
	for name, segs, cols in SHEETS:
		paths = []
		for s in segs:
			paths += _frames(s)
		ims = [_soften_shadow(Image.open(p).convert("RGBA")) for p in paths]
		cw, ch = ims[0].size
		rows = (len(ims) + cols - 1) // cols
		sheet = Image.new("RGBA", (cw * cols, ch * rows), (0, 0, 0, 0))
		for i, im in enumerate(ims):
			sheet.paste(im, ((i % cols) * cw, (i // cols) * ch))
		assert sheet.size[0] <= 4096 and sheet.size[1] <= 4096
		p = os.path.join(OUT, name)
		sheet.save(p, optimize=False)
		print("ok", p, sheet.size, "%d 帧" % len(ims))


if __name__ == "__main__":
	main()
