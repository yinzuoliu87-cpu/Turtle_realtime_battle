# -*- coding: utf-8 -*-
"""build_chest_sheets.py —— 渲染 + 拼表: blender_chest_fx.py 的各段各遍 → assets/sprites/vfx/chest-*.png(2026-11-20)。

  python tools/assetgen/build_chest_sheets.py            # 先渲(已有帧的段跳过; --rerender 全重渲)再拼表
  python tools/assetgen/build_chest_sheets.py --sheets-only
帧在 .out/chest_blend/<段>_<遍>/f_XX.png。产出(每段两张: 立着的 + 贴地的 `-gnd`, 帧数 / 排法相同; 裂光只有贴地):
  chest-slam(-gnd).png  砸点 18 帧 × 192(9 列 × 2 行)
  chest-pop(-gnd).png   沿线迸出两种 × 15 帧 × 128(10 列 × 3 行; 第 0~14 帧一种、15~29 另一种)
  chest-hit.png         命中 14 帧 × 128(7 列 × 2 行; 没有贴地层: 金币溅开时离地高, 影子散在别人脚下读不出)
  chest-wave-gnd.png    裂光 22 帧 × 256×48(2 列 × 11 行; 图右 = 砸出去的方向)
唯一的后期: 贴地层的影子(纯黑像素)不透明度 × SHADOW_K(同 build_candy_sheets)。宽高都不超过 4096。重跑逐字节相同(输入帧不变时)。
"""
import os
import subprocess
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, ".out", "chest_blend")
OUT = os.path.join(ROOT, "assets", "sprites", "vfx")
BLENDER = "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
SCRIPT = os.path.join(ROOT, "tools", "assetgen", "blender_chest_fx.py")
SHADOW_K = 0.5

JOBS = [("slam", "up"), ("slam", "gnd"), ("pop", "up"), ("pop", "gnd"), ("pop2", "up"), ("pop2", "gnd"), ("hit", "up"), ("wave", "gnd")]
SHEETS = [
	("chest-slam.png", ["slam_up"], 9),
	("chest-slam-gnd.png", ["slam_gnd"], 9),
	("chest-pop.png", ["pop_up", "pop2_up"], 10),
	("chest-pop-gnd.png", ["pop_gnd", "pop2_gnd"], 10),
	("chest-hit.png", ["hit_up"], 7),
	("chest-wave-gnd.png", ["wave_gnd"], 2),
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


def render(rerender):
	for which, pas in JOBS:
		out = os.path.join(SRC, "%s_%s" % (which, pas))
		if not rerender and os.path.isdir(out) and any(f.startswith("f_") for f in os.listdir(out)):
			print("跳过(已有帧)", which, pas)
			continue
		r = subprocess.run([BLENDER, "--background", "--python", SCRIPT, "--", "--which", which, "--pass", pas, "--out", out],
			capture_output=True, text=True, encoding="utf-8", errors="replace")
		tail = [l for l in r.stdout.splitlines() if "[blender_chest_fx]" in l or "Error" in l]
		print(which, pas, "exit", r.returncode, tail[-1] if tail else r.stderr[-300:])
		if r.returncode != 0:
			sys.exit(1)


def sheets():
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
	if "--sheets-only" not in sys.argv:
		render("--rerender" in sys.argv)
	sheets()
