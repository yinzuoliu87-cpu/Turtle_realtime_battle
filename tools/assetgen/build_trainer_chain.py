# -*- coding: utf-8 -*-
"""build_trainer_chain.py — 训龟大师钩锁新锁链的像素贴图(脚本按规则逐格算, 不是手画)。

学锤石 Q / 诺提勒斯 Q 的做法(docs/studies/20261120d-训龟大师锁链参考-锤石诺提勒斯逐帧.md):
  ① 绷紧的链子 = 固定大小的链节**横向重复铺**(UV 按长度平铺, 不拉长)。真铁链是「正面环」与「侧面扁环」交替,
     侧面那节两头各穿进前后两个正面环的孔里 —— 第一版画成「环 + 一根接在右边的杆」, 平铺出来读成一串 o-o-o(不像链)。
     ⇒ 这里按「平铺后接得上」逐格算: 侧面节从本环孔右半一直伸到下一个环孔左半(跨图块边界取模), 环压在侧面节上、孔里露出侧面节。
  ② 甩出去时的拖影带不用贴图: 在 assets/shaders/trainer_chain.gdshader 里按四档硬边直接算。
★确定性: 重跑逐字节相同。仓库根 = 往上三层。OUT_DIR 环境变量可改输出目录(预览用)。
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.environ.get("OUT_DIR") or os.path.join(ROOT, "assets", "sprites", "vfx")

K = (16, 14, 18, 255)       # 描边
D = (58, 64, 76, 255)       # 暗铁
M = (112, 122, 138, 255)    # 铁
L = (200, 214, 228, 255)    # 高光

P = 14                      # 一个循环的宽(正面环 + 侧面节)
H = 9


def link_tile():
	img = Image.new("RGBA", (P, H), (0, 0, 0, 0))
	px = img.load()
	cy = 4
	# ── 侧面扁环(先画, 被正面环压住): 从 x=5(本环孔里) 到下一个环孔里, 取模铺满。
	#   侧着看的一节链 = 一个压扁的环: 上下描边 + 上下两条金属边 + 中间一条暗缝(环的孔侧着看成一条缝)
	#   —— 第二版画成实心杆, 平铺读成「珠子串在一根杆上」。
	for i in range(5, 5 + 12):
		x = i % P
		end = (i == 5 or i == 5 + 11)                  # 两头圆角: 收成 3 行
		if not end:
			px[x, cy - 2] = K
			px[x, cy + 2] = K
		px[x, cy - 1] = L if not end else K
		px[x, cy] = D if not end else M
		px[x, cy + 1] = M if not end else K
	# ── 正面环: 中心 (3.5, 4), 外径 4×4.5, 内孔 2×2.5 —— 环带压在侧面节上, 孔里露出侧面节
	cx = 3.0
	for y in range(H):
		for x in range(-1, 9):
			xx = x % P
			dx = (x - cx) / 3.6
			dy = (y - cy) / 4.2
			r = dx * dx + dy * dy
			if r <= 1.0:
				ix = (x - cx) / 1.6
				iy = (y - cy) / 2.2
				if ix * ix + iy * iy <= 1.0:
					continue                              # 孔: 不画(露出后面的侧面节 / 透明)
				edge = r > 0.62 or (ix * ix + iy * iy) <= 1.6
				if edge and (r > 0.62):
					px[xx, y] = K
				elif y < cy:
					px[xx, y] = L if x < cx else M        # 上半受光
				else:
					px[xx, y] = D if x > cx else M        # 下半背光
	return img


def build_link():
	img = link_tile()
	img.save(os.path.join(OUT_DIR, "trainer-chain-link.png"), optimize=False)
	return img.size


if __name__ == "__main__":
	print("link", build_link())
