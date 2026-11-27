# -*- coding: utf-8 -*-
"""eq010_icon.py —— 010 激光长刃图标 64×64(用户 11-27「图标和技能特效都全部再重新做一遍」; 方案书 docs/plans/20261127c-激光长刃重做.md)。

做法(如实): 逐像素按几何判层上色 —— 握柄(枪灰 + 防滑纹 + 红色导能灯) / 金色十字护手(两端翘鳍、中间红宝石) /
激光刃(白热芯 → 粉 → 红 → 深红, 刃根白芯更宽) / 刃尖十字闪光与火花 / 描边(刃边暗红、其余深色; 发光层不描边)。
★装备图标一律硬边零半透(tools/pixel_art_audit.py): 初版刃外一圈半透光晕(136 像素)被它拦下, 已去掉; 发光感靠刃身分阶色 + 暗红描边。
不用随机数, 重跑逐字节相同。分层 PNG 由 tools/assetgen/ase/png_layers_to_ase.lua 在 Aseprite 里按层拼成 .aseprite。
用法: python tools/assetgen/eq010_icon.py [输出目录]   (默认 .out/eq010/icon/; 成品拷到 assets/sprites/equip/eq010-icon.png)
"""
import math, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".out", "eq010", "icon")
os.makedirs(OUT, exist_ok=True)
N = 64
# 方向: 握柄在左下, 刃尖在右上
A = (9.0, 55.0)      # 柄头
G = (22.5, 41.5)     # 护手中心
T = (57.0, 7.0)      # 刃尖
def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def dot(a, b): return a[0] * b[0] + a[1] * b[1]
def seg_dist(p, a, b):
	ab = sub(b, a); ap = sub(p, a)
	t = max(0.0, min(1.0, dot(ap, ab) / dot(ab, ab)))
	c = (a[0] + ab[0] * t, a[1] + ab[1] * t)
	return math.hypot(p[0] - c[0], p[1] - c[1]), t
AX = sub(T, A); L = math.hypot(*AX); U = (AX[0] / L, AX[1] / L)       # 沿刃方向
V = (-U[1], U[0])                                                       # 垂直方向(指向左上为正 ⇒ 亮面)
if V[0] + V[1] > 0: V = (-V[0], -V[1])

C = {
	"core": (255, 250, 244, 255), "pink": (255, 164, 172, 255), "red": (246, 52, 72, 255), "deep": (168, 18, 42, 255),
	"rim": (74, 8, 22, 255), "halo": (255, 60, 80),
	"metal_hi": (150, 160, 178, 255), "metal": (92, 100, 118, 255), "metal_dk": (52, 56, 70, 255), "metal_dd": (30, 32, 42, 255),
	"gold_hi": (255, 226, 130, 255), "gold": (222, 164, 52, 255), "gold_dk": (140, 88, 22, 255),
	"gem_hi": (255, 200, 200, 255), "gem": (230, 40, 60, 255), "gem_dk": (120, 10, 30, 255),
	"outline": (20, 12, 20, 255),
}
layers = [Image.new("RGBA", (N, N), (0, 0, 0, 0)) for _ in range(6)]
solid = set()

def put(li, x, y, col):
	if 0 <= x < N and 0 <= y < N:
		layers[li].putpixel((x, y), col)
		if li not in (0, 4) and col[3] == 255:      # 光晕 / 火花是发光, 不描边
			solid.add((x, y))

blade_a = (G[0] + U[0] * 1.5, G[1] + U[1] * 1.5)
for y in range(N):
	for x in range(N):
		p = (x + 0.5, y + 0.5)
		# ── 激光刃: 宽度沿刃方向收尖(最后 10 像素收成一点)
		d, t = seg_dist(p, blade_a, T)
		along = t * math.hypot(*sub(T, blade_a))
		remain = math.hypot(*sub(T, blade_a)) - along
		w = 3.2 * min(1.0, remain / 10.0 + 0.15)
		side = dot(sub(p, blade_a), V)          # >0 亮面(左上)
		if d <= w + 0.6:
			core_k = 0.30 + 0.25 * max(0.0, 1.0 - along / 7.0)    # 刃根 7 像素内白芯更宽: 从护手里射出来
			if d < w * core_k: put(1, x, y, C["core"])
			elif d < w * 0.55: put(1, x, y, C["pink"])
			elif d < w * 0.85: put(1, x, y, C["red"] if side > 0 else C["deep"])
			else: put(1, x, y, C["deep"])
		# ── 握柄: 柄头 → 护手, 半宽 2.6, 防滑纹每 3 像素一道
		d2, t2 = seg_dist(p, A, G)
		if d2 <= 2.7:
			s2 = dot(sub(p, A), V)
			ridge = int(t2 * math.hypot(*sub(G, A))) % 3 == 0 and 0.15 < t2 < 0.85
			col = C["metal_hi"] if s2 > 1.2 else (C["metal"] if s2 > -0.6 else C["metal_dk"])
			if ridge: col = C["metal_dd"] if s2 < 0.8 else C["metal_dk"]
			if 0.18 < t2 < 0.88 and -0.4 < s2 < 0.6 and not ridge:      # 握柄上一道红色能量线(激光武器的导能槽)
				col = C["red"] if int(t2 * 20) % 2 else C["pink"]
			put(2, x, y, col)

# ── 护手: 垂直刃的一条金环, 长 13 厚 3, 正中红宝石
for k in range(-7, 8):
	for j in range(-1, 2):
		px = G[0] + V[0] * k + U[0] * j; py = G[1] + V[1] * k + U[1] * j
		xi, yi = int(math.floor(px)), int(math.floor(py))
		col = C["gold_hi"] if j == 1 else (C["gold"] if j == 0 else C["gold_dk"])   # j=+1 朝刃那沿亮
		put(3, xi, yi, col)
		put(3, int(math.floor(px + 0.5)), yi, col)
for k in (-7, -6, 6, 7):          # 两端鳍: 朝刃方向多翘 2 格
	for j in (2, 3):
		if abs(k) == 6 and j == 3: continue
		px = G[0] + V[0] * k + U[0] * j; py = G[1] + V[1] * k + U[1] * j
		put(3, int(math.floor(px)), int(math.floor(py)), C["gold_hi"] if j == 2 else C["gold"])
for (dx, dy, c) in [(0, 0, "gem"), (1, 0, "gem_dk"), (0, -1, "gem_hi"), (-1, 0, "gem"), (0, 1, "gem_dk"), (1, -1, "gem")]:
	put(3, int(G[0]) + dx, int(G[1]) + dy, C[c])
# 柄头: 圆帽 + 红指示灯
for y in range(N):
	for x in range(N):
		if math.hypot(x + 0.5 - (A[0] - U[0] * 1.5), y + 0.5 - (A[1] - U[1] * 1.5)) <= 3.0:
			put(2, x, y, C["metal"] if (x + y) % 5 else C["metal_hi"])
put(4, int(A[0] - U[0] * 1.5), int(A[1] - U[1] * 1.5), C["gem"])
# ── 刃尖十字闪光 + 火花
tx, ty = int(T[0]), int(T[1])
for k in range(-3, 4):
	put(4, tx + k, ty, C["core"] if abs(k) < 2 else C["pink"])
	put(4, tx, ty + k, C["core"] if abs(k) < 2 else C["pink"])
for (sx, sy, c) in [(47, 22, "pink"), (52, 25, "core"), (38, 22, "red"), (60, 17, "pink"), (34, 32, "pink")]:
	put(4, sx, sy, C[c])
# 刃脊一道高光(亮面那侧, 中段)
for t in [i / 40.0 for i in range(6, 30)]:
	px = blade_a[0] + (T[0] - blade_a[0]) * t + V[0] * 1.0; py = blade_a[1] + (T[1] - blade_a[1]) * t + V[1] * 1.0
	put(4, int(px), int(py), C["core"])
# ── 描边: 实心像素外一圈(4 邻接); 刃的描边用暗红, 其余用深色
ring = []
for y in range(N):
	for x in range(N):
		if (x, y) in solid: continue
		nb = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
		if any(q in solid for q in nb):
			blade_nb = any(layers[1].getpixel(q)[3] == 255 for q in nb if 0 <= q[0] < N and 0 <= q[1] < N)
			ring.append((x, y, C["rim"] if blade_nb else C["outline"]))
for (x, y, c) in ring:      # 先算完再画: 边画边算会让描边自己也算「实心」, 一路蔓延
	layers[5].putpixel((x, y), c)
comp = Image.new("RGBA", (N, N), (0, 0, 0, 0))
names = ["glow", "blade", "hilt", "guard", "spark", "outline"]
order = [1, 2, 3, 5, 4]          # 第 0 层(原半透光晕)不再画, 也不进 .aseprite
for k, li in enumerate(order):
	comp.alpha_composite(layers[li])
	comp.save(os.path.join(OUT, "step%d-%s.png" % (k + 1, names[li])))
for li, nm in enumerate(names):
	if li in order:
		layers[li].save(os.path.join(OUT, "layer-%s.png" % nm))
comp.save(os.path.join(OUT, "eq010-icon.png"))
# 预览: 8 倍 + 实际尺寸(深底 / 浅底)
pv = Image.new("RGBA", (N * 8 + 64 * 3 + 60, N * 8 + 20), (22, 28, 40, 255))
pv.alpha_composite(comp.resize((N * 8, N * 8), Image.NEAREST), (10, 10))
pv.alpha_composite(comp, (N * 8 + 30, 20))
pv.alpha_composite(comp.resize((44, 44), Image.NEAREST), (N * 8 + 30, 100))
lb = Image.new("RGBA", (64, 64), (200, 190, 170, 255)); lb.alpha_composite(comp); pv.alpha_composite(lb, (N * 8 + 110, 20))
pv.save(os.path.join(OUT, "preview.png"))
print("ok")
