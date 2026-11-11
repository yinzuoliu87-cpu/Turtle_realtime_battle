# -*- coding: utf-8 -*-
"""tools/assetgen/build_pierce_chain.py — 小将穿刺铁链的链环 + 尖链头(2026-11-11)。

用户 11-11「那你觉得这个商业游戏怎么做这个链子呢？不能说直接去把它拉伸吧」「我们的链头应该是那种尖的穿刺，就像一个尖的链头
穿刺过敌人的身体」; 逐帧参考 docs/studies/20261111-链子穿刺拉人参考-锤石Q与天蝎绳镖逐帧.md:
  · 链子 = 重复链段, 节数随长度变、不拉伸 ⇒ 两种链环交替: 正面椭圆环(看得到环洞) + 侧面扁环(一条带高光的扁条), 前后各压 2 像素
  · 链头 = 尖头绳镖(菱形刃 + 尾环), 扎进目标后尖端从另一侧透出
两套配色: 精英(深铁 + 紫刃, 对上精英紫色刃臂) / 近战(钢灰 + 金扣, 新形象定稿后可改)。
产出 assets/sprites/vfx/<名>-link-a.png(正面环)、-link-b.png(侧面环)、-head.png(链头, 尖朝右)。
逐像素手画(字符画), 零半透明、硬边; 重跑逐字节相同。用法: python tools/assetgen/build_pierce_chain.py [输出目录]
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "sprites", "vfx")

## 字符画: . 透明 / o 描边 / d 暗部 / m 中间 / l 亮部 / h 高光 / a 点缀(刃光 / 金扣)
LINK_A = [   # 正面椭圆环 12×8: 看得到环洞
	"...oooooo...",
	"..ommmmmmo..",
	".omlhhll.mo.",
	"oml.oooo.ldo",
	"odl.o..o.mdo",
	".odmmmmmmdo.",
	"..oddddddo..",
	"...oooooo...",
]
LINK_B = [   # 侧面扁环 12×8: 中间一条带高光的扁条, 上下透明(两种环交替 = 环环相扣)
	"............",
	"............",
	"oooooooooooo",
	"ohhllllllllo",
	"oddmmmmmmddo",
	"oooooooooooo",
	"............",
	"............",
]
## 尖链头 26×11, 尖朝右: 尾环(5×5) + 短柄 + 长菱形刃(最宽在刃根后 3 像素, 往前收成 1 像素尖)。程序画, 见 head_rows()。
HEAD_W, HEAD_H = 26, 11


def head_rows() -> list:
	g = [["." for _ in range(HEAD_W)] for _ in range(HEAD_H)]
	cy = HEAD_H // 2
	## 尾环: 5×5 方环(中间透)
	for y in range(cy - 2, cy + 3):
		for x in range(0, 5):
			edge = y in (cy - 2, cy + 2) or x in (0, 4)
			g[y][x] = "o" if edge else "."
	g[cy - 1][1] = "l"; g[cy - 1][2] = "l"; g[cy + 1][2] = "d"; g[cy + 1][3] = "d"
	## 短柄: x 5..8, 3 像素高
	for x in range(5, 9):
		g[cy - 1][x] = "o"; g[cy][x] = "a"; g[cy + 1][x] = "o"
	## 刃: x 8..25; 半宽 b(x): 刃根 8 → 4(x=11) → 0(x=25)
	for x in range(8, HEAD_W):
		if x <= 11:
			b = 1 + (x - 8)
		else:
			b = int(round(4.0 * (HEAD_W - 1 - x) / float(HEAD_W - 1 - 11)))
		for y in range(cy - b, cy + b + 1):
			if 0 <= y < HEAD_H:
				if y in (cy - b, cy + b) or x == HEAD_W - 1:
					g[y][x] = "o"
				elif y < cy:
					g[y][x] = "h" if y == cy - 1 and x < HEAD_W - 4 else "l"
				elif y == cy:
					g[y][x] = "m"
				else:
					g[y][x] = "d"
	return ["".join(r) for r in g]


HEAD = head_rows()
PALETTES = {
	## 精英: 深铁链 + 紫色刃(精英刃臂是紫的)
	"elite-chain": {"o": (14, 12, 24), "d": (46, 44, 66), "m": (78, 76, 102), "l": (124, 122, 150), "h": (196, 192, 220), "a": (168, 92, 232)},
	## 近战(11-11 珊瑚骑士): 与护手同一套深绿甲壳色; 链头不在这里画 —— 用手上那个三刺头原图(build_melee_minion.py 出 melee-chain-head.png)
	"melee-chain": {"o": (16, 26, 20), "d": (38, 60, 48), "m": (62, 92, 72), "l": (100, 132, 104), "h": (160, 190, 150), "a": (214, 168, 64)},
}


def draw(rows, pal) -> Image.Image:
	w, h = len(rows[0]), len(rows)
	im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	px = im.load()
	for y, r in enumerate(rows):
		if len(r) != w:
			raise SystemExit("字符画第 %d 行宽 %d ≠ %d" % (y, len(r), w))
		for x, ch in enumerate(r):
			if ch != ".":
				px[x, y] = pal[ch] + (255,)
	return im


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	os.makedirs(OUT, exist_ok=True)
	for name, pal in sorted(PALETTES.items()):
		for suf, rows in (("link-a", LINK_A), ("link-b", LINK_B), ("head", HEAD)):
			if name == "melee-chain" and suf == "head":
				continue   # 近战链头 = 三刺头原图, 由 build_melee_minion.py 出
			p = os.path.join(OUT, "%s-%s.png" % (name, suf))
			draw(rows, pal).save(p, optimize=False)
			print("写出", p)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
