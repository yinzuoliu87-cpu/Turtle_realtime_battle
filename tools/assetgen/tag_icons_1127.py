"""tag_icons_1127.py —— 旧 10 个羁绊图标重画成格子图(用户 11-27「旧的…羁绊图标全部都要重做…重做到有现在这个质量」)。

做法(如实写, CLAUDE.md §10 第 3 条):
  · 每个图标我逐块定形状(格子坐标 / 几何式), 按材质给 4 级色阶(暗 / 本色 / 亮 / 高光), 光从左上:
    区域里左上边沿取「亮」、右下边沿取「暗」、其余取本色; 高光点、徽记、细节逐像素手点。
  · 描边统一新 6 个(PixelLab 出的炸弹 / 匕首 / 魔法书 / 面具 / 长矛 / 筹码)量出来的深紫褐 #3b2531, 4 邻接一圈。
  · 参考 = Terraria 物品图标(docs/studies/20261127-参考-Terraria物品图标.md): 学色阶 / 光向 / 高光点 / 徽记的做法, 不照抄造型。
  · 输出: .out/icons/grid/<名>.txt(每格一个字符) + 各阶段过程图; 由 tools/assetgen/ase/tag_icons_1127.lua 在 Aseprite 后台
    按层(剪影 / 平涂 / 暗部 / 亮部 / 细节 / 描边)画出来, 存 .aseprite + 导出 assets/sprites/tags/tag-*.png。
  · 不用随机数, 重跑逐字节相同。
用法(仓库根目录, 两步):
  python tools/assetgen/tag_icons_1127.py      # 出格子图 + 预览 .out/icons/draft.png
  Aseprite.exe -b --script-param grid=.out/icons/grid --script-param out=.out/icons/ase --script tools/assetgen/ase/tag_icons_1127.lua
  然后把 .out/icons/ase/tag-<名>.png 拷到 assets/sprites/tags/, tag-<名>.aseprite 拷到 tools/assetgen/ase/tags/。
  (仓库根目录按往上三层算, 见 tools/README.md; TAG_ROOT 环境变量可覆盖)
"""
import math
import os

ROOT = os.environ.get("TAG_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, ".out", "icons", "grid")
N = 32
OUTLINE = (59, 37, 49)

# 材质色阶: 暗 / 本色 / 亮 / 高光
MAT = {
	"crimson": [(122, 30, 46), (196, 52, 62), (240, 104, 100), (255, 208, 196)],
	"gold":    [(150, 92, 22), (222, 160, 46), (252, 214, 98), (255, 246, 200)],
	"steel":   [(70, 80, 98), (122, 134, 152), (176, 188, 204), (236, 242, 250)],
	"leather": [(64, 36, 30), (104, 60, 44), (140, 88, 60), (176, 122, 86)],
	"wood":    [(98, 56, 34), (146, 90, 52), (190, 128, 74), (226, 170, 110)],
	"brass":   [(150, 74, 24), (218, 120, 40), (248, 168, 72), (255, 220, 150)],
	"violet":  [(74, 36, 110), (122, 64, 170), (168, 110, 214), (222, 184, 250)],
	"string":  [(170, 160, 140), (214, 206, 186), (240, 234, 216), (255, 255, 240)],
	"emerald": [(20, 110, 80), (40, 182, 120), (110, 232, 168), (220, 255, 236)],
	"octo":    [(92, 50, 140), (150, 96, 206), (192, 144, 236), (236, 214, 255)],
	"ink":     [(30, 20, 40), (40, 28, 52), (60, 44, 74), (255, 255, 255)],
	"blue":    [(30, 76, 150), (56, 128, 214), (110, 178, 246), (210, 236, 255)],
	"meat":    [(120, 50, 30), (180, 86, 46), (222, 128, 70), (255, 200, 140)],
	"bone":    [(170, 156, 136), (222, 212, 192), (244, 238, 222), (255, 255, 250)],
	"jade":    [(40, 112, 60), (88, 170, 70), (150, 214, 96), (222, 250, 180)],
	"glass":   [(110, 150, 170), (176, 214, 228), (220, 242, 250), (255, 255, 255)],
	"cyan":    [(16, 110, 140), (34, 180, 214), (100, 226, 244), (214, 250, 255)],
	"cork":    [(110, 72, 40), (170, 122, 76), (212, 168, 112), (240, 210, 160)],
}
# 格子字符: 每种材质 4 级 = 4 个字符
CHARS = {}
_letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-+=<>?/"
_i = 0
for _m in MAT:
	CHARS[_m] = _letters[_i:_i + 4]
	_i += 4


class Icon:
	def __init__(self, name):
		self.name = name
		self.reg = {}        # (x,y) -> 材质(后画的盖前面)
		self.tone = {}       # (x,y) -> 手点色阶(覆盖自动明暗)
		self.order = []

	def fill(self, mat, pts):
		for p in pts:
			x, y = p
			if 0 <= x < N and 0 <= y < N:
				self.reg[(x, y)] = mat

	def put(self, x, y, mat, t):
		self.reg[(x, y)] = mat
		self.tone[(x, y)] = t

	def erase(self, pts):
		for p in pts:
			self.reg.pop(p, None)
			self.tone.pop(p, None)

	def shaded(self):
		"""自动明暗: 同材质区域左上边沿亮(2), 右下边沿暗(0), 其余本色(1); 手点覆盖。"""
		g = {}
		for (x, y), m in self.reg.items():
			same = lambda q: self.reg.get(q) == m
			lit = (not same((x - 1, y))) or (not same((x, y - 1)))
			dark = (not same((x + 1, y))) or (not same((x, y + 1)))
			t = 1
			if lit and not dark:
				t = 2
			elif dark and not lit:
				t = 0
			t = self.tone.get((x, y), t)
			g[(x, y)] = (m, t)
		return g

	def grid(self):
		g = self.shaded()
		rows = []
		for y in range(N):
			r = ""
			for x in range(N):
				if (x, y) in g:
					m, t = g[(x, y)]
					r += CHARS[m][t]
				elif any((x + dx, y + dy) in g for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
					r += "~"
				else:
					r += "."
			rows.append(r)
		return rows


def disc(cx, cy, r):
	return [(x, y) for y in range(N) for x in range(N) if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r]


def rect(x0, y0, x1, y1):
	return [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]


def diag_band(x0, y0, length, half_w, dir_=(1, -1)):
	"""沿 45° 方向的带子: 起点 (x0,y0), 往 dir_ 走 length 格, 横向半宽 half_w(格)。"""
	pts = set()
	dx, dy = dir_
	px, py = -dy, dx
	for t in range(length):
		cx, cy = x0 + dx * t, y0 + dy * t
		for s in range(-half_w, half_w + 1):
			pts.add((cx + px * s, cy + py * s))
			if s < half_w:
				pts.add((cx + px * s + dx, cy + py * s))   # 45° 带子补缝
	return list(pts)


ICONS = []


def icon(fn):
	ICONS.append(fn)
	return fn


@icon
def sword():
	ic = Icon("sword")
	# 剑身: 赤钢, 左下 → 右上; 横截面 4 格: 上沿刃(亮) / 剑脊两格(本色 + 高光线) / 下沿刃(暗)
	for t in range(0, 15):
		bx, by = 12 + t, 19 - t
		ic.put(bx - 1, by - 1, "crimson", 2)      # 上沿刃
		ic.put(bx, by - 1, "crimson", 3 if t % 4 == 1 else 2)
		ic.put(bx, by, "crimson", 1)
		ic.put(bx + 1, by, "crimson", 1)
		ic.put(bx + 1, by + 1, "crimson", 0)      # 下沿刃
	ic.erase([(11, 18), (12, 18), (12, 19), (13, 20)])
	# 剑尖
	ic.erase([(25, 3), (26, 3), (26, 4), (27, 5)])
	ic.put(27, 3, "crimson", 3); ic.put(26, 4, "crimson", 2); ic.put(27, 4, "crimson", 1)
	# 护手: 金, 宽 2, 两端翘, 中间红宝石
	for s_ in range(-5, 6):
		ic.fill("gold", [(11 + s_, 20 + s_), (12 + s_, 20 + s_)])
		ic.tone[(11 + s_, 20 + s_)] = 2
		ic.tone[(12 + s_, 20 + s_)] = 0 if s_ > 0 else 1
	ic.put(5, 15, "gold", 3); ic.put(17, 26, "gold", 0); ic.put(18, 26, "gold", 0)
	ic.fill("crimson", [(11, 20), (12, 20), (12, 21), (11, 19)])
	ic.put(11, 19, "crimson", 3); ic.put(11, 20, "crimson", 2); ic.put(12, 21, "crimson", 0)
	# 握柄: 皮革缠绕, 宽 3
	for t in range(1, 6):
		ic.put(10 - t, 21 + t, "leather", 2 if t % 2 else 1)
		ic.put(11 - t, 21 + t, "leather", 1 if t % 2 else 3)
		ic.put(10 - t, 22 + t, "leather", 0)
	# 柄头: 金球
	ic.fill("gold", disc(4.0, 28.5, 2.1))
	ic.put(3, 27, "gold", 3); ic.put(4, 27, "gold", 2)
	return ic


@icon
def shield():
	ic = Icon("shield")
	# 鸢形盾: 上平下尖, 钢边 2 格 + 金面
	body = []
	for y in range(5, 28):
		if y <= 16:
			hw = 10
		else:
			hw = int(round(10 - (y - 16) * 0.95))
		for x in range(16 - hw, 16 + hw):
			body.append((x, y))
	ic.fill("steel", body)
	inner = []
	for y in range(7, 26):
		if y <= 16:
			hw = 8
		else:
			hw = int(round(8 - (y - 16) * 0.95))
		for x in range(16 - hw, 16 + hw):
			if hw > 0:
				inner.append((x, y))
	ic.fill("gold", inner)
	# 金面左上亮、右下暗的对角渐变
	for (x, y) in inner:
		d = (x - 8) + (y - 7)
		ic.tone[(x, y)] = 2 if d < 9 else (1 if d < 22 else 0)
	# 中间龟壳六边形徽记(暗金底 + 亮金线)
	for y in range(10, 22):
		for x in range(10, 22):
			dx, dy = abs(x + 0.5 - 16), abs(y + 0.5 - 15.5)
			h = max(dx * 0.866 + dy * 0.5, dy)
			if h <= 5.6:
				if h > 4.6:
					ic.put(x, y, "brass", 0)                     # 龟壳外圈
				elif h < 1.9:
					ic.put(x, y, "gold", 3 if (x + y) % 2 == 0 else 2)   # 中心甲片
				elif dx < 0.6 or abs(dy - dx * 0.577) < 0.55:
					ic.put(x, y, "brass", 0)                     # 放射甲纹
				else:
					ic.put(x, y, "gold", 2 if (x + 0.5 < 16 and y + 0.5 < 15.5) else 1)
	# 钢边铆钉 + 高光
	for (x, y) in [(8, 6), (23, 6), (8, 15), (23, 15)]:
		ic.put(x, y, "steel", 3)
	for x in range(9, 15):
		ic.put(x, 5, "steel", 3 if x < 12 else 2)
	return ic


@icon
def gun():
	ic = Icon("gun")
	# 燧发手枪, 朝右: 铜身 + 钢管 + 木握把
	ic.fill("steel", rect(14, 8, 28, 11))           # 枪管
	ic.fill("brass", rect(22, 8, 23, 11))           # 铜箍
	ic.fill("steel", [(29, 9), (29, 10), (29, 11)])
	ic.fill("brass", rect(9, 9, 16, 14))            # 机匣
	ic.fill("brass", rect(12, 15, 16, 15))
	# 握把: 木, 往左下斜
	grip = []
	for y in range(13, 26):
		x0 = 9 - (y - 13) // 2
		grip += [(x, y) for x in range(x0, x0 + 5)]
	ic.fill("wood", grip)
	ic.fill("brass", [(x, y) for (x, y) in grip if y >= 24])   # 握把底铜帽
	# 扳机护圈
	ic.fill("brass", [(13, 16), (13, 17), (14, 18), (15, 18), (16, 17), (16, 16)])
	ic.put(14, 16, "steel", 0)                       # 扳机
	ic.put(14, 17, "steel", 1)
	# 击锤
	ic.fill("steel", [(9, 7), (10, 7), (10, 8), (11, 8)])
	ic.put(9, 7, "steel", 3)
	# 枪管高光 + 管口
	for x in range(15, 28):
		if x not in (22, 23):
			ic.put(x, 8, "steel", 3 if x in (17, 18, 25) else 2)
	ic.put(22, 8, "brass", 3)
	ic.put(29, 10, "ink", 0)
	# 机匣花纹 + 高光
	ic.put(10, 10, "brass", 3); ic.put(11, 10, "brass", 3)
	ic.put(12, 12, "brass", 0); ic.put(13, 12, "brass", 0); ic.put(14, 12, "brass", 0)
	ic.put(7, 17, "wood", 3); ic.put(6, 19, "wood", 3)
	return ic


@icon
def bow():
	ic = Icon("bow")
	# 拉满的反曲弓: 弓臂在右往右鼓, 弦往左拉到箭尾, 箭朝右
	limb = []
	for y in range(3, 29):
		t = (y - 15.5) / 12.5
		x = 18 + int(round(7 * (1 - t * t)))
		limb += [(x, y), (x + 1, y)]
		if abs(t) < 0.75:
			limb += [(x + 2, y)]   # 弓臂中段加粗到 3 格
		if abs(t) > 0.85:
			limb += [(x - 1, y)]   # 反曲尖往回翘
	ic.fill("violet", limb)
	for y in (8, 9, 10, 21, 22, 23):
		xs = [x for (x, yy) in limb if yy == y]
		ic.tone[(min(xs), y)] = 3
	# 握把缠金 + 梢头金饰
	ic.fill("gold", rect(25, 14, 26, 17))
	ic.put(25, 14, "gold", 3)
	ic.fill("gold", [(17, 3), (18, 3), (17, 28), (18, 28)])
	# 弦: 两条斜线汇到箭尾 (9,15)
	for (x0, y0) in ((17, 4), (17, 27)):
		n = abs(y0 - 15)
		for i in range(n + 1):
			x = int(round(x0 + (9 - x0) * i / n))
			y = int(round(y0 + (15 - y0) * i / n))
			if (x, y) not in ic.reg:
				ic.put(x, y, "string", 2 if i % 3 else 1)
	# 箭: 木杆 2 行 + 钢头 + 红羽
	for x in range(10, 27):
		ic.put(x, 15, "wood", 2); ic.put(x, 16, "wood", 0)
	ic.fill("steel", [(27, 14), (27, 15), (27, 16), (27, 17), (28, 15), (28, 16), (29, 15), (29, 16), (26, 13), (26, 18)])
	ic.put(28, 15, "steel", 3); ic.put(27, 14, "steel", 2); ic.put(27, 17, "steel", 0)
	ic.fill("crimson", [(10, 13), (11, 13), (11, 14), (12, 14), (10, 18), (11, 18), (11, 17), (12, 17)])
	ic.put(10, 13, "crimson", 2); ic.put(10, 18, "crimson", 0)
	ic.put(9, 15, "gold", 2); ic.put(9, 16, "gold", 0)
	return ic


@icon
def staff():
	ic = Icon("staff")
	# 法杖: 木杆左下 → 右上, 顶端金托 + 翠晶
	for t in range(0, 14):
		ic.fill("wood", [(6 + t, 27 - t), (7 + t, 27 - t), (7 + t, 28 - t)])
	for t in (2, 6, 10):
		ic.put(6 + t, 27 - t, "wood", 3)
	# 金箍
	ic.fill("gold", [(13, 19), (14, 19), (13, 20), (14, 20), (12, 20)])
	# 金托: 两只爪
	ic.fill("gold", [(18, 14), (19, 14), (17, 13), (18, 13), (22, 13), (23, 12), (17, 11), (17, 10), (21, 14), (22, 14), (23, 13)])
	# 翠晶: 菱形
	gem = []
	for y in range(2, 14):
		for x in range(15, 28):
			if abs(x + 0.5 - 21) * 1.0 + abs(y + 0.5 - 8) <= 6.6:
				gem.append((x, y))
	ic.fill("emerald", gem)
	for (x, y) in gem:
		if x + 0.5 < 21 and y + 0.5 < 8:
			ic.tone[(x, y)] = 2
		elif x + 0.5 > 21 and y + 0.5 > 8:
			ic.tone[(x, y)] = 0
	ic.put(19, 6, "emerald", 3); ic.put(20, 5, "emerald", 3); ic.put(19, 5, "emerald", 3)
	# 光点
	for (x, y) in [(27, 3), (14, 4), (28, 11)]:
		ic.put(x, y, "emerald", 3)
	ic.put(26, 3, "emerald", 2); ic.put(28, 3, "emerald", 2); ic.put(27, 2, "emerald", 2); ic.put(27, 4, "emerald", 2)
	return ic


@icon
def spirit():
	ic = Icon("spirit")
	# 章鱼: 圆头 + 四条粗触手(上宽 4 → 尖), 两侧两条往外卷, 中间两条往里卷
	head = disc(16, 11, 8.0)
	ic.fill("octo", head)
	for (x, y) in head:
		d = math.hypot(x + 0.5 - 13, y + 0.5 - 7)
		ic.tone[(x, y)] = 3 if d < 1.8 else (2 if d < 5.0 else (1 if d < 8.5 else 0))
	tips = []
	for k, (bx, curl) in enumerate([(9.5, -1), (14.0, -1), (18.0, 1), (22.5, 1)]):
		lean = (bx - 16.0) / 6.5
		for y in range(16, 27):
			f = (y - 16) / 10.0
			w = 4 if y < 21 else (3 if y < 24 else 2)
			cx = bx + lean * (y - 16) * 0.22 + curl * 1.4 * f * f
			x0 = int(round(cx - w / 2.0))
			for i in range(w):
				ic.fill("octo", [(x0 + i, y)])
				ic.tone[(x0 + i, y)] = 2 if i == 0 else (0 if i == w - 1 else 1)
		ex = int(round(bx + lean * 10 * 0.22 + curl * 1.4))
		tips.append((ex, curl))
	for (ex, curl) in tips:
		ic.put(ex + curl, 27, "octo", 1)
		ic.put(ex + 2 * curl, 27, "octo", 0)
		ic.put(ex + 2 * curl, 26, "octo", 2)
	# 吸盘(每条触手下段一颗)
	for (ex, curl) in tips:
		ic.put(ex, 24, "octo", 3)
	# 眼: 白底黑瞳 + 高光
	for ex in (12, 18):
		ic.fill("bone", rect(ex, 11, ex + 2, 13))
		ic.put(ex + 1, 12, "ink", 0); ic.put(ex + 2, 12, "ink", 0); ic.put(ex + 1, 13, "ink", 0); ic.put(ex + 2, 13, "ink", 1)
		ic.put(ex, 11, "bone", 3)
	ic.put(11, 14, "crimson", 2); ic.put(21, 14, "crimson", 2)
	return ic


@icon
def gadget():
	ic = Icon("gadget")
	# 齿轮: 钢蓝, 8 齿, 内圈 + 中心螺栓
	pts = []
	for y in range(N):
		for x in range(N):
			dx, dy = x + 0.5 - 16, y + 0.5 - 16
			r = math.hypot(dx, dy)
			a = math.atan2(dy, dx)
			# 齿 = 沿 8 根轴(每 45°)的等宽长方条, 不按角度判(角度判在斜向采样出来齿宽不一)
			tooth = False
			for k in range(8):
				ax, ay = math.cos(k * math.pi / 4 + math.pi / 8), math.sin(k * math.pi / 4 + math.pi / 8)   # 转 22.5°: 8 个齿对像素网格的角度全一样(网格旋转 90° / 镜像对称), 齿形才一致
				along, perp = dx * ax + dy * ay, abs(-dx * ay + dy * ax)
				if along > 0 and perp <= 2.6 and along <= 13.6:
					tooth = True
			if (r <= 9.4 or tooth) and r >= 3.2:
				pts.append((x, y))
	ic.fill("blue", pts)
	for (x, y) in pts:
		dx, dy = x + 0.5 - 16, y + 0.5 - 16
		r = math.hypot(dx, dy)
		lit = (-dx - dy) / max(r, 0.01)
		if 5.0 <= r <= 6.2:
			ic.tone[(x, y)] = 0 if lit > 0 else 2      # 内圈凹槽: 反向明暗
		else:
			ic.tone[(x, y)] = 2 if lit > 0.55 else (0 if lit < -0.55 else 1)
	# 中心螺栓: 铜
	bolt = disc(16, 16, 3.3)
	ic.fill("brass", bolt)
	ic.put(15, 15, "brass", 3); ic.put(16, 16, "brass", 0); ic.put(17, 16, "brass", 0); ic.put(16, 17, "brass", 0)
	# 齿顶高光
	for (x, y) in [(9, 6), (8, 7), (16, 4), (5, 15), (15, 3)]:
		if (x, y) in ic.reg:
			ic.tone[(x, y)] = 3
	return ic


@icon
def food():
	ic = Icon("food")
	# 烤鸡腿: 肉 = 两头不一样粗的胶囊(右上粗、往左下收), 骨头从细端伸出
	P0, R0, P1, R1 = (19.5, 11.0), 7.6, (12.5, 18.0), 3.2
	meat = []
	vx, vy = P1[0] - P0[0], P1[1] - P0[1]
	L2 = vx * vx + vy * vy
	for y in range(N):
		for x in range(N):
			px, py = x + 0.5 - P0[0], y + 0.5 - P0[1]
			t = max(0.0, min(1.0, (px * vx + py * vy) / L2))
			cx, cy = P0[0] + vx * t, P0[1] + vy * t
			if math.hypot(x + 0.5 - cx, y + 0.5 - cy) <= R0 + (R1 - R0) * t:
				meat.append((x, y))
	ic.fill("meat", meat)
	for (x, y) in meat:
		d = (x + 0.5 - 15) + (y + 0.5 - 6)
		ic.tone[(x, y)] = 2 if d < 7 else (1 if d < 17 else 0)
	for (x, y) in [(16, 6), (17, 6), (15, 7), (14, 8), (22, 7)]:
		ic.put(x, y, "meat", 3)
	for (x, y) in [(20, 13), (21, 12), (23, 15), (17, 16), (18, 15)]:
		ic.put(x, y, "meat", 0)
	# 骨: 宽 2 + 两个骨节
	for t in range(0, 6):
		ic.fill("bone", [(10 - t, 20 + t), (11 - t, 20 + t), (10 - t, 21 + t)])
		ic.tone[(10 - t, 20 + t)] = 2
	ic.fill("bone", disc(4.0, 25.5, 1.7) + disc(6.5, 28.0, 1.7))
	ic.put(3, 25, "bone", 3); ic.put(6, 27, "bone", 2)
	return ic


@icon
def relic():
	ic = Icon("relic")
	# 古瓮: 玉身 + 金口金把手 + 纹带
	body = []
	for y in range(9, 28):
		t = (y - 18.5) / 9.5
		hw = 7.5 * math.sqrt(max(0.0, 1 - t * t * 0.9)) + 1.0
		if y >= 25:
			hw = min(hw, 5.0)
		for x in range(N):
			if abs(x + 0.5 - 16) <= hw:
				body.append((x, y))
	ic.fill("jade", body)
	for (x, y) in body:
		d = math.hypot((x + 0.5 - 12.5) / 1.0, (y + 0.5 - 14.0) / 1.3)
		ic.tone[(x, y)] = 3 if d < 1.3 else (2 if d < 4.2 else (1 if d < 8.6 else 0))
	# 瓶颈 + 口沿
	ic.fill("jade", rect(13, 6, 18, 8))
	ic.fill("gold", rect(11, 4, 20, 5))
	ic.put(11, 4, "gold", 2); ic.put(12, 4, "gold", 3)
	# 纹带(金)
	for x in range(N):
		if (x, 18) in ic.reg and ic.reg[(x, 18)] == "jade":
			ic.put(x, 18, "gold", 1)
			ic.put(x, 19, "gold", 0)
	for x in range(10, 23, 3):
		if (x, 18) in ic.reg:
			ic.put(x, 18, "gold", 3)
	# 底座
	ic.fill("gold", rect(11, 28, 20, 28))
	# 把手: 从瓶肩接出的金环
	for (x, y) in [(9, 10), (8, 10), (7, 11), (7, 12), (7, 13), (8, 14), (9, 14)]:
		ic.put(x, y, "gold", 2 if y < 12 else 1)
	for (x, y) in [(22, 10), (23, 10), (24, 11), (24, 12), (24, 13), (23, 14), (22, 14)]:
		ic.put(x, y, "gold", 1 if y < 12 else 0)
	return ic


@icon
def potion():
	ic = Icon("potion")
	# 圆底烧瓶: 玻璃壁 + 青色药液 + 软木塞 + 气泡
	bulb = disc(16, 19.5, 9.3)
	ic.fill("glass", bulb)
	liquid = [(x, y) for (x, y) in disc(16, 19.5, 8.0) if y >= 16]
	ic.fill("cyan", liquid)
	for (x, y) in liquid:
		d = (x + 0.5 - 16) + (y + 0.5 - 19.5)
		ic.tone[(x, y)] = 2 if d < -3 else (1 if d < 5 else 0)
	for x in range(N):
		if (x, 16) in ic.reg and ic.reg[(x, 16)] == "cyan":
			ic.put(x, 16, "cyan", 3)      # 液面亮线
	# 瓶颈
	ic.fill("glass", rect(13, 6, 18, 11))
	ic.fill("glass", rect(12, 5, 19, 5))
	# 软木塞
	ic.fill("cork", rect(13, 2, 18, 4))
	ic.put(13, 2, "cork", 3)
	# 玻璃反光
	for (x, y) in [(10, 14), (9, 15), (9, 16), (9, 17), (14, 7), (14, 8), (14, 9)]:
		ic.put(x, y, "glass", 3)
	# 气泡
	for (x, y) in [(19, 20), (17, 23), (21, 24), (18, 18)]:
		ic.put(x, y, "cyan", 3)
	return ic


def main():
	os.makedirs(OUT, exist_ok=True)
	pal = {"~": OUTLINE, ".": None}   # 描边用「~」: 不在材质字符表里(原来用 o, 跟皮革的亮色阶撞了)
	for m, ch in CHARS.items():
		for i, c in enumerate(ch):
			pal[c] = MAT[m][i]
	with open(os.path.join(OUT, "palette.txt"), "w", encoding="utf-8", newline="\n") as f:
		for c, col in pal.items():
			if col is not None:
				f.write("%s %d %d %d\n" % (c, col[0], col[1], col[2]))
	for fn in ICONS:
		ic = fn()
		rows = ic.grid()
		with open(os.path.join(OUT, ic.name + ".txt"), "w", encoding="utf-8", newline="\n") as f:
			f.write("\n".join(rows) + "\n")
	try:
		from PIL import Image
		S = 8
		sheet = Image.new("RGBA", (len(ICONS) * (N * S + 16) + 16, N * S + 32), (40, 30, 24, 255))
		for i, fn in enumerate(ICONS):
			rows = open(os.path.join(OUT, fn().name + ".txt"), encoding="utf-8").read().split()
			im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
			for y, r in enumerate(rows):
				for x, c in enumerate(r):
					if pal.get(c):
						im.putpixel((x, y), pal[c] + (255,))
			sheet.alpha_composite(im.resize((N * S, N * S), Image.NEAREST), (16 + i * (N * S + 16), 16))
		sheet.save(os.path.join(ROOT, ".out", "icons", "draft.png"))
	except ImportError:
		pass
	print("ok", len(ICONS))


if __name__ == "__main__":
	main()
