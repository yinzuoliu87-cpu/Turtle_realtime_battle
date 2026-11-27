# -*- coding: utf-8 -*-
"""eq010_laser_tex.py —— 010 激光长刃特效的灰度形状贴图(颜色在引擎里上, 照永恩 Q / W 的做法: 贴图几乎全是灰度)。

参考研究 docs/studies/20261127-参考-永恩斩击特效配方.md。做法(如实): 按公式算出来的灰度形状, 不用随机数, 重跑逐字节相同。
  spindle.png    128×32  纺锤光条(中间亮两头尖, 中线一道更亮的芯) —— 命中横斩光 / 波前刃 / 火花拉丝
  spindle_v.png  32×128  同上竖放 —— 直线追斩出手那一下的竖剑光
  flare.png      64×64   四角星(十字两道细长光 + 斜向两道短光 + 中心光球) —— 命中星光 / 刃尖闪光
  ring.png       128×128 细冲击环(带四个亮点) —— 命中冲击环
用法: python tools/assetgen/eq010_laser_tex.py   (输出到 assets/sprites/vfx/eq010/; 仓库根目录按往上三层算)
"""
import math
import os
from PIL import Image

ROOT = os.environ.get("EQ010_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx", "eq010")


def save(img, name):
	os.makedirs(OUT, exist_ok=True)
	img.save(os.path.join(OUT, name))


def gray(w, h, fn):
	im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	px = im.load()
	for y in range(h):
		for x in range(w):
			v = max(0.0, min(1.0, fn(x + 0.5, y + 0.5)))
			a = int(round(v * 255))
			if a > 0:
				px[x, y] = (255, 255, 255, a)
	return im


def spindle(u, v):
	# u: 0..1 沿长, v: -1..1 横向。宽度剖面 = sin(πu)^0.8(两头尖), 横向高斯; 芯 = 更窄更亮
	w = math.sin(math.pi * u) ** 0.8
	if w <= 0.0:
		return 0.0
	body = math.exp(-(v / (0.55 * w + 1e-6)) ** 2 * 2.2)
	core = math.exp(-(v / (0.16 * w + 1e-6)) ** 2 * 2.0) * (w ** 0.6)
	return body * 0.75 + core * 0.6


def main():
	save(gray(128, 32, lambda x, y: spindle(x / 128.0, (y - 16.0) / 16.0)), "spindle.png")
	save(gray(32, 128, lambda x, y: spindle(y / 128.0, (x - 16.0) / 16.0)), "spindle_v.png")

	def flare(x, y):
		dx, dy = (x - 32.0) / 32.0, (y - 32.0) / 32.0
		r = math.hypot(dx, dy)
		ball = math.exp(-(r / 0.16) ** 2)
		cross = math.exp(-(abs(dy) / (0.035 + 0.05 * (1 - min(1, abs(dx))))) ** 2) * max(0.0, 1 - abs(dx)) ** 1.6 \
			+ math.exp(-(abs(dx) / (0.035 + 0.05 * (1 - min(1, abs(dy))))) ** 2) * max(0.0, 1 - abs(dy)) ** 1.6
		ux, uy = (dx + dy) / math.sqrt(2), (dx - dy) / math.sqrt(2)
		diag = (math.exp(-(abs(uy) / 0.03) ** 2) * max(0.0, 1 - abs(ux) / 0.55) ** 2
				+ math.exp(-(abs(ux) / 0.03) ** 2) * max(0.0, 1 - abs(uy) / 0.55) ** 2) * 0.5
		return ball + cross * 0.95 + diag
	save(gray(64, 64, flare), "flare.png")

	def ring(x, y):
		dx, dy = (x - 64.0) / 64.0, (y - 64.0) / 64.0
		r = math.hypot(dx, dy)
		band = math.exp(-((r - 0.78) / 0.045) ** 2)
		a = math.atan2(dy, dx)
		spark = 0.0
		for k in range(4):                     # 四个亮点(45° 起每 90°)
			da = math.atan2(math.sin(a - (math.pi / 4 + k * math.pi / 2)), math.cos(a - (math.pi / 4 + k * math.pi / 2)))
			spark += math.exp(-(da / 0.12) ** 2) * math.exp(-((r - 0.78) / 0.09) ** 2)
		inner = math.exp(-((r - 0.62) / 0.12) ** 2) * 0.18
		return band * 0.85 + spark * 0.7 + inner
	save(gray(128, 128, ring), "ring.png")
	print("ok", OUT)


if __name__ == "__main__":
	main()
