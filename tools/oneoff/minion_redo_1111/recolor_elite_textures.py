# -*- coding: utf-8 -*-
"""精英小将特效贴图: 红光 → 紫光(11-11 深渊精英换成深蓝 + 紫光; 巨拳 / 长刃 / 三种地刺还是旧红紫精英的黑底红光图)。
只动红 ~ 橙黄色系像素(色相 330° ~ 65°、饱和度 > 0.25): 色相换到 285°(与精英面罩缝的紫一致), 明度 / 饱和度 / 透明度不变;
黑 / 灰 / 透明不动。原地替换 assets/sprites/vfx/ 下 5 张(只有 elite_system.gd 用), 引用路径不变。
换完 285° 不在 330° ~ 65° 里 ⇒ 重跑不再改动(逐字节相同)。
同时撤掉 recolor_elite_vfx.py 当时给巨拳 / 地刺加的偏紫调色倍数(贴图已是紫的, 再乘会二次染色)。"""
import colorsys
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
VFX = os.path.join(ROOT, "assets", "sprites", "vfx")
NAMES = ["bio-fist.png", "bio-blade.png", "bio-spike-a.png", "bio-spike-b.png", "bio-spike-c.png"]
TARGET_H = 285.0 / 360.0


def recolor(im):
	im = im.convert("RGBA")
	px = im.load()
	w, h = im.size
	n = 0
	for y in range(h):
		for x in range(w):
			r, g, b, a = px[x, y]
			if a == 0:
				continue
			hh, ss, vv = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
			deg = hh * 360.0
			if ss > 0.25 and (deg >= 330.0 or deg <= 65.0):   # 含地刺底部的橙黄火光
				nr, ng, nb = colorsys.hsv_to_rgb(TARGET_H, ss, vv)
				px[x, y] = (int(round(nr * 255)), int(round(ng * 255)), int(round(nb * 255)), a)
				n += 1
	return im, n


for nm in NAMES:
	p = os.path.join(VFX, nm)
	im, n = recolor(Image.open(p))
	if n:
		im.save(p, optimize=False)
	print("%-16s 换色 %d 像素" % (nm, n))

P = os.path.join(ROOT, "scripts", "systems", "skills", "elite_system.gd")
b = open(P, "rb").read()
nl = b"\r\n" if b"\r\n" in b else b"\n"
TINT = "Color(0.8, 0.62, 1.2, 1.0)   # 11-11 深渊精英: 巨拳偏紫(贴图是旧红紫精英的黑红色)".encode("utf-8")
lines = b.split(nl)
kept = [ln for ln in lines if not (ln.strip().startswith((b"fs.modulate = ", b"fs2.modulate = ")) and TINT in ln)]
print("撤掉巨拳调色 %d 行" % (len(lines) - len(kept)))
b = nl.join(kept)
b = b.replace(b"spk.modulate = Color(1.05, 0.9, 1.35, 1.0)", b"spk.modulate = Color(1.25, 1.1, 1.1, 1.0)")
open(P, "wb").write(b)
print("ok")
