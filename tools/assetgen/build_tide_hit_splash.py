# -*- coding: utf-8 -*-
"""tools/assetgen/build_tide_hit_splash.py —— 043 海浪护符「打中水花」: 手画灰度 2×2 水花 → 上水色的 4 帧横条(2026-11-14)。

做法照 LoL 娜美大招的水花(CommunityDragon 解包实测: 2×2 = 4 帧、灰度图、引擎里按颜色渐变条上色):
  源图 = Aseprite 里用鼠标逐笔画的 128×128 灰度图(四格各 64×64, 地面在格内第 56 行),
  本脚本只做两件机械的事: ① 2×2 排成 1×4 横条; ② 五档灰按固定对照表换成水色(不加任何新像素)。
用法: python tools/assetgen/build_tide_hit_splash.py assets/sprites/vfx/src/tide_hit_splash_gs.png [输出 png]
源文件: assets/sprites/vfx/src/tide_hit_splash_gs.aseprite(鼠标画的原稿) / .png(它导出的灰度图)
重跑逐字节相同。
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx", "tide-hit.png")
## 灰度 → 水色(深 → 浅; 同一张灰度图的五档, 对应 LoL 的 color ramp)
RAMP = {
	56: (29, 77, 128),     # 最深边
	88: (38, 104, 160),    # 底部阴影
	120: (52, 150, 204),   # 水体
	184: (150, 226, 246),  # 亮芯
	255: (255, 255, 255),  # 高光 / 水滴
}


def main():
	src = sys.argv[1]
	out = sys.argv[2] if len(sys.argv) > 2 else OUT
	im = Image.open(src).convert("RGBA")
	assert im.size == (128, 128), im.size
	strip = Image.new("RGBA", (256, 64), (0, 0, 0, 0))
	for k in range(4):
		cell = im.crop(((k % 2) * 64, (k // 2) * 64, (k % 2) * 64 + 64, (k // 2) * 64 + 64))
		strip.paste(cell, (k * 64, 0))
	px = strip.load()
	bad = set()
	for y in range(64):
		for x in range(256):
			r, g, b, a = px[x, y]
			if a == 0:
				px[x, y] = (0, 0, 0, 0)
				continue
			if r not in RAMP or not (r == g == b) or a != 255:
				bad.add((r, g, b, a))
				continue
			px[x, y] = RAMP[r] + (255,)
	assert not bad, "源图里有对照表以外的颜色: %s" % sorted(bad)[:5]
	strip.save(out, optimize=False)
	print("ok", out, strip.size)


if __name__ == "__main__":
	main()
