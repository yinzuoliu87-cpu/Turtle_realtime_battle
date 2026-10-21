extends Node
## verify_two_head_anim —— 变脸龟两套动作 + 技能特效(方案书 20261007-双头龟重绘两形态 done-when)。
##
## 判据全部落在【素材像素 + 真对局循环】上, 不落在截图上(memory fb-weld-visual-lessons-into-gate):
##  A 素材: 每条动作帧表在、方帧 128、帧数够到关键帧、宽 ≤ 4096(安卓采样上限)
##  B 归一: 每条从站姿起的动作第 0 帧 == 立绘逐像素(贴在 24,48); 变脸后半段末帧 == 新形态立绘
##          ⇒ 像素尺寸与脚底与立绘完全一致(运行期再核 pixel_size / offset)
##  C 朝向: 量脸不量重心 —— 术士: 头部皮肤重心在兜帽重心左边; 战士: 眼白/牙重心在红脸重心左边
##          (项目约定原图朝左); 每条攻击/技能的关键帧往左伸得比往右远(出手方向 = 朝向)
##  D 接线(真入口 REVIEW 单技能台 + 每帧恰 1 步 sim):
##     普攻: 出手那一步立绘正好在关键帧; 远程弹体用新素材; 命中那一步出命中特效
##     切形态: 切的那一刻斗篷挡满脸(变脸前半段关键帧)
##     锤击: 落地砸下那一步立绘在第 6 帧, 同一步出裂地特效、目标掉血
##     精神干扰 / 吸收 / 灵能冲击 / 融合: 结算那一步立绘在关键帧, 同一步出对应特效
##  E 死亡: 按形态播死亡帧表
##  F 二轮画面(2026-10-20): ①变脸龟自己那几次给盾的通用护盾罩排在立绘之前画(不洗白变脸/砸地/挥锤)
##     ②锤击: 裂地画在【锤头落点】(按素材量出来的锤头位置, 不读常量)且画在单位上面; 挥锤弧同一步出、也在上面;
##       落地后紧跟的普攻前摇不许把锤贴地那几帧吞掉 ③融合施法: 红斗篷在出现之后每一帧都在(推杖帧不许闪没)
##  F⑥ 锤击砸地重做(2026-10-20, 锤击改范围技): 贴地冲击环画多大 = 判定半径(量素材环半径 × 运行期 pixel_size);
##     落地起 0.1 秒内落点爆点白核够亮且画在单位上面; 冲击环由内向外扩到满径; 碎石/尘团真的往外散开;
##     圈边尘团正好落在判定半径上、冲击环到之前不露 —— 全按【素材像素 + 运行期节点】量, 不读 TwoHeadVfx 常量
## 每条断言都配一条分母断言(这一类事件真的发生过 ≥ N 次)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const FRAME := 128
var _fails := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fails += 1


func _img(path: String) -> Image:
	var t: Texture2D = load(path)
	return t.get_image() if t != null else null


func _base(form: String) -> Image:
	var src := _img("res://assets/sprites/pets/two_head.png" if form == "ranged" else "res://assets/sprites/pets/two_head_melee.png")
	var im := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	src.convert(Image.FORMAT_RGBA8)
	im.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i(TwoHeadArt.ART_X, TwoHeadArt.ART_Y))
	return im


func _frame(sheet: Image, i: int) -> Image:
	var f := sheet.get_region(Rect2i(i * FRAME, 0, FRAME, FRAME))
	f.convert(Image.FORMAT_RGBA8)
	return f


func _same(a: Image, b: Image) -> int:   # 不同像素数(只比不透明区, alpha 也算)
	var d := 0
	for y in range(FRAME):
		for x in range(FRAME):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if ca.a8 == 0 and cb.a8 == 0:
				continue
			if ca.to_rgba32() != cb.to_rgba32():
				d += 1
	return d


func _bbox(im: Image) -> Rect2i:
	return im.get_used_rect()


## 朝向(量脸): 3/4 侧脸里【吻部在眼睛前面】 ⇒ 头部皮肤(术士灰紫 / 战士红)的横向重心 − 眼白的横向重心,
##   < 0 = 吻部在眼睛左边 = 脸朝左。只看头部那几行(52~78), 不碰法杖 / 锤头 / 浮石。
##   ★标定过正反两面: 术士 −2.8 / 镜像 +1.6; 战士 −2.5 / 镜像 +10.6(2026-10-20)。
##   ★为什么不用"眼白对红脸": 我第一版这么量, 战士给出 +5.2(判成朝右) —— 吻部整块是红的, 眼睛在后半边。
func _face_dx(im: Image, form: String) -> float:
	var fx := 0.0; var fn := 0
	var ex := 0.0; var en := 0
	for y in range(52, 79):
		for x in range(40, 82):
			var c := im.get_pixel(x, y)
			if c.a8 == 0:
				continue
			var r := c.r8; var g := c.g8; var b := c.b8
			if mini(r, mini(g, b)) > 190:
				ex += x; en += 1
			elif form == "ranged" and absi(r - g) < 20 and b > r + 10 and r > 70:
				fx += x; fn += 1
			elif form == "melee" and r > 150 and g < 70 and b < 70:
				fx += x; fn += 1
	if fn < 20 or en < 3:
		return 999.0
	return fx / fn - ex / en


## 出手帧集合(量素材, 不读 TwoHeadArt.CLIPS —— 否则改常量判据跟着改 = 恒真):
##   包围盒左沿离最左那一帧 ≤ 2 像素的帧。远程掌心推出 / 锤落左下 / 双臂推法球 / 杖头推出 都是"最往左"的那一下。
var _reach_cache := {}
func _reach_set(key: String) -> Array:
	if _reach_cache.has(key):
		return _reach_cache[key]
	var sh := _img(TwoHeadArt.DIR + key + ".png")
	var n: int = sh.get_width() / FRAME
	var lefts: Array = []
	var mn := 9999
	for i in range(n):
		var bx: int = _bbox(_frame(sh, i)).position.x
		lefts.append(bx)
		mn = mini(mn, bx)
	var out: Array = []
	for i in range(n):
		if int(lefts[i]) <= mn + 2:
			out.append(i)
	_reach_cache[key] = out
	return out


## F②: 锤头在立绘里的位置(量素材, 不读 TwoHeadVfx 常量 —— 否则改常量判据跟着改 = 恒真)。
##   锤头 = 帧左半边的石灰色像素(r≈g≈b, 100~230)。返回 [贴地帧集合, 第一张贴地帧里锤头重心离帧中线多少像素]。
func _hammer_ground() -> Array:
	var sh := _img(TwoHeadArt.DIR + "melee_strike.png")
	var n: int = sh.get_width() / FRAME
	var frames: Array = []
	var dx := 0.0
	for i in range(n):
		var f := _frame(sh, i)
		var low := -1; var sx := 0.0; var sn := 0
		for y in range(FRAME):
			for x in range(0, 60):
				var c := f.get_pixel(x, y)
				if c.a8 == 0:
					continue
				if absi(c.r8 - c.g8) < 15 and absi(c.g8 - c.b8) < 20 and c.r8 > 100 and c.r8 < 230:
					low = maxi(low, y); sx += x; sn += 1
		if low >= 118 and sn >= 40:
			if frames.is_empty():
				dx = FRAME * 0.5 - sx / sn
			frames.append(i)
	return [frames, dx]


## F⑥: 一张帧表每帧的量: 冲击环半径(离帧中心 > 半边 60% 的不透明像素 ≥150 个才算有环, 取到中心距离的中位数;
##   ★≥150 是反向验证收紧的: 第一版 ≥40 把冷却期地裂伸出去的几十个像素也算成"环", 素材倒放时没红) / 亮像素数(亮度 > 200) / 不透明 bbox 宽。
var _sheet_cache := {}
func _sheet_stats(name: String, fw: int, fh_in: int = 0, cols: int = 0) -> Array:
	if _sheet_cache.has(name):
		return _sheet_cache[name]
	var im := _img("res://assets/sprites/vfx/" + name + ".png")
	var out: Array = []
	if im == null:
		return out
	im.convert(Image.FORMAT_RGBA8)
	var fh: int = fh_in if fh_in > 0 else im.get_height()
	var ncol: int = cols if cols > 0 else im.get_width() / fw
	var n: int = ncol * (im.get_height() / fh)
	var cx := fw * 0.5; var cy := fh * 0.5
	for i in range(n):
		var ds: Array = []
		var bright := 0; var x0 := 99999; var x1 := -1; var y0 := 99999; var y1 := -1; var cnt := 0
		var ox: int = (i % ncol) * fw; var oy: int = (i / ncol) * fh
		var colc := PackedInt32Array(); colc.resize(fw)
		for y in range(fh):
			for x in range(fw):
				var c := im.get_pixel(ox + x, oy + y)
				if c.a8 == 0:
					continue
				x0 = mini(x0, x); x1 = maxi(x1, x); y0 = mini(y0, y); y1 = maxi(y1, y); cnt += 1
				colc[x] += 1
				if (c.r8 + c.g8 + c.b8) / 3 > 200:
					bright += 1
				var dd := Vector2(x - cx, y - cy).length()
				if dd > cx * 0.6:
					ds.append(dd)
		ds.sort()
		## 主体宽: 每列 ≥6 个不透明像素的列的跨度(去掉稀疏火星 / 碎片)
		var b0 := -1; var b1 := -1
		for x in range(fw):
			if colc[x] >= 6:
				if b0 < 0: b0 = x
				b1 = x
		out.append({"ring": float(ds[ds.size() / 2]) if ds.size() >= 150 else 0.0, "bright": bright, "w": (x1 - x0 + 1) if x1 >= 0 else 0, "n": cnt, "h": (y1 - y0 + 1) if y1 >= 0 else 0, "bw": (b1 - b0 + 1) if b1 >= 0 else 0})
	_sheet_cache[name] = out
	return out


## F⑥ 图案判据(量素材本身, 不读 TwoHeadVfx 常量): 一帧里某一类颜色的连通块个数(4 邻接, 块 ≥ min_px 像素才算)。
func _blobs(im: Image, x0: int, w: int, h: int, pred: Callable, min_px: int) -> int:
	var seen := PackedByteArray(); seen.resize(w * h)
	var n := 0
	for y in range(h):
		for x in range(w):
			if seen[y * w + x] != 0 or not pred.call(im.get_pixel(x0 + x, y)):
				continue
			var stack: Array = [Vector2i(x, y)]
			seen[y * w + x] = 1
			var cnt := 0
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				cnt += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = p + d
					if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or seen[q.y * w + q.x] != 0:
						continue
					if pred.call(im.get_pixel(x0 + q.x, q.y)):
						seen[q.y * w + q.x] = 1
						stack.append(q)
			if cnt >= min_px:
				n += 1
	return n


func _sheet(name: String) -> Image:
	var im := _img("res://assets/sprites/vfx/" + name + ".png")
	if im != null:
		im.convert(Image.FORMAT_RGBA8)
	return im


## 一帧里不透明像素到帧中心的平均距离(地面印记「从外往里碎」用)。
func _mean_r(im: Image, x0: int, w: int, h: int) -> float:
	var s := 0.0; var n := 0
	for y in range(h):
		for x in range(w):
			if im.get_pixel(x0 + x, y).a8 > 0:
				s += Vector2(x - w * 0.5, y - h * 0.5).length(); n += 1
	return s / float(n) if n > 0 else 0.0


## 程序生成的范围细圈: 量贴图本身 alpha 最亮那一圈的半径(像素, 沿中线往右扫)。
func _ring_tex_r(tex: Texture2D) -> float:
	if tex == null:
		return 0.0
	var im := tex.get_image()
	im.convert(Image.FORMAT_RGBA8)
	var cy: int = im.get_height() / 2
	var best := -1; var bx := 0
	for x in range(im.get_width() / 2, im.get_width()):
		var a: int = im.get_pixel(x, cy).a8
		if a > best:
			best = a; bx = x
	return float(bx) + 0.5 - float(im.get_width()) * 0.5


func _slam_checks(r1: Array, hg: Array) -> void:
	print("── F⑥ 锤击(第六版·照研究文档 E1~E9): 图案 / 尺寸比例 / 范围细圈 = 判定半径 / 时序 / 亮度曲线 ──")
	var R: float = TwoHeadSystem.STRIKE_MELEE_RADIUS
	## ── 素材图案(量像素) ──
	var star := _sheet("twohead-quake-star"); var crys := _sheet("twohead-quake-crystal"); var grd := _sheet("twohead-quake-ground")
	var arc := _sheet("twohead-quake-arc")
	var is_green := func(c: Color) -> bool: return c.a8 > 0 and c.g8 > 150 and c.g8 > c.r8 + 50 and c.g8 >= c.b8
	var is_dark := func(c: Color) -> bool: return c.a8 > 0 and maxi(c.r8, maxi(c.g8, c.b8)) < 110 and c.r8 >= c.g8
	var is_face := func(c: Color) -> bool: return c.a8 > 0 and c.r8 >= 30 and c.r8 < 150 and c.r8 > c.g8 + 15 and c.b8 > c.g8      # 格面 = 暗暖粉(格边是亮橙细线, 把格面隔开)
	var is_curl := func(c: Color) -> bool: return c.a8 > 0 and c.r8 > 140 and c.g8 < 110 and c.b8 < 120
	## 亮斑 = 绿色或绿白色(亮斑中心是近白的 e0fff4, 只数纯绿会把一颗斑的绿边数成两段)
	var is_spot := func(c: Color) -> bool: return c.a8 > 0 and c.g8 > 150 and c.g8 >= c.r8 + 20
	var st_green: int = _blobs(star, 0, 136, 136, is_spot, 4) if star != null else 0
	var st_dark: int = _blobs(star, 0, 136, 136, is_dark, 400) if star != null else 0
	_ok("★E4 暗星徽记: 第 0 帧是一整块深紫褐星体(≥400 像素的暗色连通块 = 1)且嵌着 3~5 颗符文绿亮斑", st_dark == 1 and st_green >= 3 and st_green <= 6, "暗色块 %d · 绿斑 %d" % [st_dark, st_green])
	var cr_cells: int = _blobs(crys, 224 * 2, 224, 224, is_face, 30) if crys != null else 0
	var cr_green: int = _blobs(crys, 224 * 3, 224, 224, is_green, 8) if crys != null else 0
	var cr_late: int = _blobs(crys, 224 * 9, 224, 224, is_face, 30) if crys != null else 0
	_ok("★E5 晶格能量泡: 第 2 帧 ≥ 20 块暗暖粉晶面被亮格边隔开(碎玻璃格) · 第 3 帧有符文绿裂纹 · 第 9 帧(波纹环段)晶面已散尽", cr_cells >= 20 and cr_green >= 1 and cr_late == 0, "晶面 %d · 绿裂纹段 %d · 末段晶面 %d" % [cr_cells, cr_green, cr_late])
	## ★泡是半透明发光的(主会话 10-21 自审:「像一颗橙色陶砖球, 目标龟几乎完全被盖住」): 晶格帧(1~4)里泡内亮像素(最大通道 ≥ 180)
	##   只许是格边细线 / 裂纹 / 光刃 —— 占泡内面积 ≤ 30%; 而且格边真的在(≥ 5%), 否则是空检查。
	var bright_frac := 1.0; var bright_min := 1.0
	if crys != null:
		bright_frac = 0.0
		for fi in range(1, 5):
			var nb := 0; var nd := 0
			for y in range(224):
				for x in range(224):
					if Vector2(x - 112, y - 112).length() > 84.0:
						continue
					nd += 1
					var c := crys.get_pixel(fi * 224 + x, y)
					if c.a8 > 0 and maxi(c.r8, maxi(c.g8, c.b8)) >= 180:
						nb += 1
			bright_frac = maxf(bright_frac, float(nb) / float(nd))
			bright_min = minf(bright_min, float(nb) / float(nd))
	_ok("★E5 泡半透明: 晶格帧泡内亮像素(格边 / 裂纹)占 5%~30%, 格面是暗的(加色下只透一层淡暖粉)", bright_frac <= 0.3 and bright_min >= 0.05, "最多 %.0f%% · 最少 %.0f%%" % [bright_frac * 100.0, bright_min * 100.0])
	var g0: int = _blobs(grd, 0, 200, 200, func(c: Color) -> bool: return c.a8 > 0, 30) if grd != null else 0
	var gr0: float = _mean_r(grd, 0, 200, 200) if grd != null else 0.0
	var gr2: float = _mean_r(grd, 400, 200, 200) if grd != null else 99.0
	_ok("★E8 地面碎晶印记: 第 0 帧 ≥ 20 块碎格 · 格子从外往里碎(第 2 帧剩余像素平均半径 < 第 0 帧的 0.7)", g0 >= 20 and gr2 < gr0 * 0.7, "碎格 %d · 平均半径 %.1f → %.1f" % [g0, gr0, gr2])
	var ac: int = _blobs(arc, 176, 176, 172, is_curl, 6) if arc != null else 0
	_ok("★E3 锤迹: 月牙带里有 ≥ 4 个红色涡卷纹(第 1 帧)", ac >= 4, "涡卷 %d" % ac)
	## ── 运行期 ──
	var body_h: float = 73.0 * float(r1[r1.size() - 1]["idle_px"])          # 变脸龟立绘可见高(像素 73 = two_head_melee.png 不透明包围盒高)
	var n_land := 0
	var ok_cover := 0; var d_cover := ""
	var ok_at := 0; var ok_over := 0; var ok_size := 0; var ok_ring := 0; var ok_time := 0; var ok_curve := 0; var ok_leap := 0; var ok_arc := 0
	var d_at := ""; var d_size := ""; var d_ring := ""; var d_time := ""; var d_curve := ""; var d_leap := ""; var d_arc := ""
	for i in range(1, r1.size()):
		var a: Dictionary = r1[i - 1]; var b: Dictionary = r1[i]
		if not (a["slam"] and not b["slam"] and b["form"] == "melee"):
			continue
		n_land += 1
		var fwd: float = 1.0 if bool(b["face_right"]) else -1.0
		var hx: float = float(b["x"]) + fwd * float(hg[1]) * float(b["idle_px"]) / RB.WS     # 锤头落点(按立绘素材量)
		var hy: float = float(b["y"])
		var t0: float = float(b["t"])
		var nodes := {}
		for nd in b["slam_nodes"]:
			nodes[str(nd["name"])] = nd
		## ① 落地那一步整套节点都建好, 全在锤头落点(= 结算圆心)
		var want := ["quake_star", "quake_flash", "quake_flash_body", "quake_bubble_glow", "quake_bubble_tint", "quake_crystal", "quake_beam", "quake_flare", "quake_ball", "quake_range", "quake_ground", "quake_embers"]
		var miss: Array = []; var off: Array = []
		for k in want:
			if not nodes.has(k):
				miss.append(k)
			elif Vector2(float(nodes[k]["x"]) - hx, float(nodes[k]["z"]) - hy).length() > 8.0:
				off.append(k)
		d_at = "缺 %s · 偏离落点 %s" % [str(miss), str(off)]
		if miss.is_empty() and off.is_empty():
			ok_at += 1
		else:
			continue
		## ② 竖立的发光 / 图案层画在所有单位上面(关深度测试 + 优先级高于立绘)
		var under: Array = []
		for k in ["quake_star", "quake_flash", "quake_crystal", "quake_beam", "quake_flare"]:
			if not bool(nodes[k]["ndt"]) or int(nodes[k]["prio"]) <= int(b["unit_prio_max"]):
				under.append(k)
		if under.is_empty():
			ok_over += 1
		## ③ 尺寸比例: 能量泡(晶格素材主体宽 × 运行期 pixel_size)≈ 变脸龟身高 2.3~3.2 倍, 且明显小于判定圈(不撑满 200 码)
		var cs: Array = _sheet_stats("twohead-quake-crystal", 224)
		var cw := 0
		for e in cs:
			cw = maxi(cw, int(e["bw"]))
		var bub_m: float = float(cw) * float(nodes["quake_crystal"]["px"])
		d_size = "泡 %d 像素 × %.4f = %.2f 米 · 变脸龟身高 %.2f 米 · %.2f 倍 · 判定圈直径 %.2f 米" % [cw, float(nodes["quake_crystal"]["px"]), bub_m, body_h, bub_m / body_h, 2.0 * R * RB.WS]
		if bub_m / body_h >= 2.3 and bub_m / body_h <= 3.2 and bub_m < 2.0 * R * RB.WS * 0.75:
			ok_size += 1
		## ④ 范围细圈 = 判定半径: 量贴图亮圈半径 × 运行期 pixel_size, 贴地平躺
		var rn: Dictionary = nodes["quake_range"]
		var r_world: float = float(rn["ring_px"]) * float(rn["px"]) / RB.WS
		d_ring = "贴图亮圈半径 %.1f 像素 × %.4f = %.1f 码 · 判定 %.0f 码 · 平躺 %s" % [float(rn["ring_px"]), float(rn["px"]), r_world, R, str(rn["flat"])]
		if absf(r_world - R) <= R * 0.03 and bool(rn["flat"]):
			ok_ring += 1
		## ⑤ 时序(按游戏钟, 顿帧期间钟不走): 各层第一次露面 / 最后一次露面; 光柱最粗那一刻; 亮度峰
		var first := {}; var last := {}; var amax := {}; var tmax := {}; var beam_w_t := -1.0; var beam_w := 0.0; var bub_a := []; var mix_cover := 0.0
		for j in range(i, mini(r1.size(), i + 90)):
			var c: Dictionary = r1[j]
			var dt: float = float(c["t"]) - t0
			for nd in c["slam_nodes"]:
				var k := str(nd["name"])
				if not bool(nd["vis"]):
					continue
				if not first.has(k):
					first[k] = dt
				last[k] = dt
				if float(nd["a"]) > float(amax.get(k, -1.0)):
					amax[k] = float(nd["a"]); tmax[k] = dt
				if k == "quake_beam" and float(nd["sx"]) > beam_w:
					beam_w = float(nd["sx"]); beam_w_t = dt
				if not bool(nd["add"]) and dt >= 0.15 and dt <= 0.5 and k in ["quake_bubble_tint", "quake_flash_body", "quake_crystal"]:
					mix_cover = maxf(mix_cover, float(nd["a"]))
				if k == "quake_bubble_glow":
					bub_a.append([dt, float(nd["a"])])
		var fs := func(k: String) -> float: return float(first.get(k, -1.0))
		d_time = "星 %.3f~%.3f · 爆光 %.3f · 泡晶格 %.3f~%.3f · 光柱最粗 %.3f · 星芒 %.3f · 光球 %.3f · 地印 %.3f · 余火 %.3f · 细圈 %.3f~%.3f" % [
			fs.call("quake_star"), float(last.get("quake_star", -1.0)), fs.call("quake_flash"), fs.call("quake_crystal"), float(last.get("quake_crystal", -1.0)),
			beam_w_t, fs.call("quake_flare"), fs.call("quake_ball"), fs.call("quake_ground"), fs.call("quake_embers"), fs.call("quake_range"), float(last.get("quake_range", -1.0))]
		var tok: bool = fs.call("quake_star") <= 0.001 and float(last.get("quake_star", 9.0)) <= 0.11 \
			and fs.call("quake_flash") >= 0.0 and fs.call("quake_flash") <= 0.05 \
			and fs.call("quake_crystal") >= 0.08 and fs.call("quake_crystal") <= 0.13 and float(last.get("quake_crystal", 9.0)) <= 0.52 \
			and beam_w_t >= 0.2 and beam_w_t <= 0.34 \
			and fs.call("quake_flare") >= 0.27 and fs.call("quake_ball") >= 0.27 \
			and fs.call("quake_ground") >= 0.4 and fs.call("quake_embers") >= 0.55 \
			and absf(fs.call("quake_range") - fs.call("quake_crystal")) <= 0.03 and float(last.get("quake_range", 9.0)) <= 0.52
		if tok:
			ok_time += 1
		## ⑥ 亮度曲线: 白热(爆光加色层)峰在 #75 附近; 泡光峰在 #78 附近, 峰后 0.12 秒已降到峰值 0.65 以下(粉光每 0.06 秒减半)
		var pk_t: float = float(tmax.get("quake_bubble_glow", -1.0)); var pk_a: float = float(amax.get("quake_bubble_glow", 0.0))
		var a_late := 1.0
		for e in bub_a:
			if absf(float(e[0]) - (pk_t + 0.12)) <= 0.01:
				a_late = float(e[1])
		d_curve = "白热峰 +%.3f 秒 · 泡光峰 +%.3f 秒(%.2f) → +0.12 秒后 %.2f" % [float(tmax.get("quake_flash", -1.0)), pk_t, pk_a, a_late]
		d_cover = "泡段(+0.15~0.5 秒)盖在目标上的普通混合层最大不透明度 %.2f · 泡体染色存在 %s" % [mix_cover, str(amax.has("quake_bubble_tint"))]
		if mix_cover <= 0.3 and amax.has("quake_bubble_tint"):
			ok_cover += 1
		if absf(float(tmax.get("quake_flash", -1.0)) - 0.117) <= 0.02 and absf(pk_t - 0.167) <= 0.02 and pk_a > 0.3 and a_late < pk_a * 0.65:
			ok_curve += 1
		## ⑦ 起跳: 尘 + 风痕(≥ 6 团, 都在上升段) + 锤头光; 落地那一步全部收掉
		var wind_n := 0; var wind_late := 0; var dust := false; var hammer := false; var arc_dt := 99.0
		for j in range(maxi(1, i - 40), i):
			var c0: Dictionary = r1[j - 1]; var c1: Dictionary = r1[j]
			var s0 := {}
			for nd in c0["slam_nodes"]:
				s0[nd["id"]] = true
			for nd in c1["slam_nodes"]:
				var k := str(nd["name"])
				if k == "quake_hammer_glow" and bool(nd["vis"]) and float(nd["a"]) > 0.3:
					hammer = true
				if s0.has(nd["id"]):
					continue
				if k == "quake_wind":
					wind_n += 1
					if t0 - float(c1["t"]) < 0.2:
						wind_late += 1
				elif k == "quake_dust":
					dust = true
				elif k == "quake_arc":
					arc_dt = t0 - float(c1["t"])
		var left := 0
		for nd in b["slam_nodes"]:
			if str(nd["name"]) in ["quake_wind", "quake_dust", "quake_hammer_glow", "quake_hammer_core"]:
				left += 1
		d_leap = "风痕 %d 团(落地前 0.2 秒内 %d) · 起跳尘 %s · 锤头光 %s · 落地后残留 %d" % [wind_n, wind_late, str(dust), str(hammer), left]
		if wind_n >= 6 and wind_late == 0 and dust and hammer and left == 0:
			ok_leap += 1
		d_arc = "锤迹在落地前 %.3f 秒建" % arc_dt
		if arc_dt >= 0.04 and arc_dt <= 0.12:
			ok_arc += 1
	_ok("分母: 锤击落地 ≥ 1 次", n_land >= 1, "%d" % n_land)
	_ok("★落地那一步整套节点都建好、全在锤头落点(结算圆心)", ok_at == n_land and n_land > 0, d_at)
	_ok("★暗星 / 爆光 / 晶格 / 光柱 / 星芒画在所有单位上面", ok_over == n_land and n_land > 0, "%d/%d" % [ok_over, n_land])
	_ok("★能量泡 ≈ 变脸龟身高 2.3~3.2 倍(不撑满判定圈)", ok_size == n_land and n_land > 0, d_size)
	_ok("★范围细圈半径(量贴图 × 运行期 pixel_size) == 判定半径 ±3%, 贴地", ok_ring == n_land and n_land > 0, d_ring)
	_ok("★时序照研究文档帧表(星 #68~#74 / 爆光 #70 / 泡 #74~#98 / 光柱 #82~#88 / 星芒光球 #86 起 / 地印 #96 起 / 余火 #104 起 / 细圈随泡)", ok_time == n_land and n_land > 0, d_time)
	_ok("★泡段目标透得出来: 盖在目标上的普通混合层不透明度 ≤ 0.3(目标 ≥ 70% 可辨)", ok_cover == n_land and n_land > 0, d_cover)
	_ok("★亮度曲线: 白热峰 #75 · 泡光峰 #78、之后快速衰减", ok_curve == n_land and n_land > 0, d_curve)
	_ok("★起跳: 起跳尘 + 上升段风痕 ≥ 6 团 + 锤头光, 落地收掉", ok_leap == n_land and n_land > 0, d_leap)
	_ok("★下砸锤迹在落地前 0.04~0.12 秒出现(参考 #64; 扫下三帧要看得清)", ok_arc == n_land and n_land > 0, d_arc)


## F③: 融合施法红斗篷(战士斗篷两色: 暗红 108,24,22 / 亮红 172,55,49)在脖子以下的像素数, 逐帧。
func _cloak_counts() -> Array:
	var sh := _img(TwoHeadArt.DIR + "fusion_cast.png")
	var out: Array = []
	for i in range(sh.get_width() / FRAME):
		var f := _frame(sh, i)
		var c := 0
		for y in range(80, FRAME):
			for x in range(FRAME):
				var p := f.get_pixel(x, y)
				if p.a8 == 255 and ((p.r8 == 108 and p.g8 == 24 and p.b8 == 22) or (p.r8 == 172 and p.g8 == 55 and p.b8 == 49)):
					c += 1
		out.append(c)
	return out


func _static_checks() -> void:
	print("── A 素材 / B 归一 / C 朝向 ──")
	var keys: Array = TwoHeadArt.CLIPS.keys() + ["ranged_death", "melee_death"]
	var n_ok := 0
	for k in keys:
		var t: Texture2D = load(TwoHeadArt.DIR + str(k) + ".png")
		if t == null:
			_ok("帧表在: " + str(k), false)
			continue
		var w := t.get_width(); var h := t.get_height()
		var key: int = int(TwoHeadArt.CLIPS[k][0]) if TwoHeadArt.CLIPS.has(k) else 0
		var good := h == FRAME and w % FRAME == 0 and w <= 4096 and w / FRAME > key
		if good:
			n_ok += 1
		else:
			_ok("帧表规格: " + str(k), false, "%dx%d key=%d" % [w, h, key])
	_ok("分母: 帧表全部在且规格对(方帧128·帧数够到关键帧·宽≤4096)", n_ok == keys.size() and n_ok >= 17, "%d/%d" % [n_ok, keys.size()])
	# B 归一: 起手第 0 帧 == 立绘
	var starts := {"ranged": ["ranged_idle", "ranged_walk", "ranged_attack", "ranged_strike", "ranged_disrupt", "ranged_death", "to_melee_a", "fusion_cast"],
		"melee": ["melee_idle", "melee_walk", "melee_attack", "melee_strike", "melee_absorb", "melee_death", "to_ranged_a"]}
	var n_norm := 0
	for form in starts:
		var base := _base(form)
		for k in starts[form]:
			var d := _same(_frame(_img(TwoHeadArt.DIR + k + ".png"), 0), base)
			if d == 0:
				n_norm += 1
			else:
				_ok("★归一: %s 第0帧 == %s 立绘" % [k, form], false, "差 %d 像素" % d)
	_ok("★归一: 15 条起手动作第 0 帧逐像素 == 立绘(同像素尺寸·同脚底)", n_norm == 15, "%d/15" % n_norm)
	for pair in [["to_melee_b", "melee"], ["to_ranged_b", "ranged"]]:
		var sh := _img(TwoHeadArt.DIR + pair[0] + ".png")
		var last := _frame(sh, sh.get_width() / FRAME - 1)
		var d2 := _same(last, _base(pair[1]))
		_ok("★归一: %s 末帧 == %s 立绘(变脸落定不跳)" % pair, d2 == 0, "差 %d 像素" % d2)
	# C 朝向
	for form in ["ranged", "melee"]:
		var dx := _face_dx(_base(form), form)
		_ok("★朝向(量脸): %s 立绘脸朝左(吻部在眼睛左边)" % form, dx < -1.0 and dx < 900.0, "dx=%.1f" % dx)
	## 出手方向: 关键帧 ±1 帧里, 包围盒往左伸出的量 > 往右伸出的量。
	##   ★吸收(近身攥取)例外: 手只比锤柄多伸 3 像素, 右边斗篷飘起来也 3 像素, 包围盒分不出 ⇒
	##     改量【比第 0 帧新长出来的像素】的重心在不在身体中线左边(实测 −8.2; 镜像 +8.2)。
	##   ★融合不能用重心(实测 +26: 推杖时紫斗篷向右甩, 新像素大半在右), 用包围盒(杖头往左伸 30+)。
	var reach_n := 0
	for k in ["ranged_attack", "melee_attack", "ranged_strike", "melee_strike", "ranged_disrupt", "melee_absorb", "fusion_cast"]:
		var sh2 := _img(TwoHeadArt.DIR + k + ".png")
		var f0 := _frame(sh2, 0)
		var b0 := _bbox(f0)
		var kk: int = int(TwoHeadArt.CLIPS[k][0])
		var best_l := 0; var best_r := 0
		var nx := 0.0; var nn := 0
		for i in range(maxi(0, kk - 1), mini(sh2.get_width() / FRAME, kk + 2)):
			var fk := _frame(sh2, i)
			var bk := _bbox(fk)
			best_l = maxi(best_l, b0.position.x - bk.position.x)
			best_r = maxi(best_r, bk.end.x - b0.end.x)
			for y in range(FRAME):
				for x in range(FRAME):
					if fk.get_pixel(x, y).a8 > 0 and f0.get_pixel(x, y).a8 == 0:
						nx += x; nn += 1
		var cdx: float = (nx / maxf(1.0, float(nn))) - (b0.position.x + b0.size.x * 0.5)
		var good: bool = (cdx < -4.0) if k == "melee_absorb" else (best_l > best_r)
		if good:
			reach_n += 1
		else:
			_ok("★朝向(出手方向): %s" % k, false, "包围盒 左 %d / 右 %d · 新像素重心 %.1f" % [best_l, best_r, cdx])
	_ok("★朝向: 7 条攻击/技能的关键帧都往左出手(= 原图朝左口径)", reach_n == 7, "%d/7" % reach_n)
	## F③ 融合红斗篷: 从第一次出现(≥150 像素)到最后一次出现之间, 每一帧都不许掉到两端平均的一半以下(推杖帧闪没)
	var cc: Array = _cloak_counts()
	var cf := -1; var cl := -1
	for i in range(cc.size()):
		if int(cc[i]) >= 150:
			if cf < 0:
				cf = i
			cl = i
	var ref_n: float = (float(cc[cf]) + float(cc[cl])) * 0.5 if cf >= 0 else 0.0
	var holes: Array = []
	for i in range(maxi(0, cf), cl + 1):
		if float(cc[i]) < ref_n * 0.5:
			holes.append("%d:%d" % [i, int(cc[i])])
	_ok("分母: 融合施法红斗篷出现跨 ≥ 10 帧", cf >= 0 and cl - cf >= 10, "第 %d~%d 帧 · 逐帧 %s" % [cf, cl, str(cc)])
	_ok("★融合施法红斗篷连续(推杖帧不闪没)", holes.is_empty(), "掉帧 %s / 参照 %.0f" % [str(holes), ref_n])


# ═══════════════════════════════════════════════════════════════════
#  D 真对局
# ═══════════════════════════════════════════════════════════════════
func _vfx_names(s) -> Dictionary:
	var out := {}
	for c in s._world.get_children():
		if c is Sprite3D and (c as Sprite3D).texture != null:
			var p := str((c as Sprite3D).texture.resource_path)
			if p.contains("/vfx/twohead-"):
				out[c.get_instance_id()] = p.get_file().get_basename()
	return out


## 跑一场 REVIEW 单技能台, 逐步记录: 形态 / 状态 / 当前动作 / 帧号 / 新出现的特效 / 假人累计受伤。
func _run(skill: int, steps: int) -> Array:
	OS.set_environment("REVIEW", "1")
	OS.set_environment("REVIEW_TURTLE", "two_head")
	OS.set_environment("REVIEW_SKILL", str(skill))
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._deterministic = true
	var rec: Array = []
	var seen := {}
	var seen_fx := {}
	var th = null
	for _n in range(steps):
		await get_tree().process_frame
		if th == null:
			for u in s._units:
				if str(u.get("id", "")) == "two_head":
					th = u
		if th == null:
			continue
		var taken := 0
		for u in s._units:
			if str(u.get("side", "")) == "right":
				taken += int(u.get("_st_taken", 0))
		var now := _vfx_names(s)
		var fresh: Array = []
		for id in now:
			if not seen.has(id):
				fresh.append(now[id])
				seen[id] = true
		var spr = th["sprite"]
		## F①: 这一步新给这只龟建的通用护盾罩(按节点认新旧, 不按时刻)的材质优先级 / 立绘自己材质的优先级
		var shells: Array = []
		for e in s._follow_vfx:
			if is_same(e.get("unit", null), th):
				var sp_e = e.get("spr", null)
				if not is_instance_valid(sp_e) or seen_fx.has(sp_e.get_instance_id()):
					continue
				seen_fx[sp_e.get_instance_id()] = true
				if sp_e is Sprite3D and (sp_e as Sprite3D).texture != null and (sp_e as Sprite3D).texture.resource_path == BattleVfx.SHELL_TEX:
					shells.append(int(((sp_e as Sprite3D).material_override as Material).render_priority) if (sp_e as Sprite3D).material_override != null else 0)
		var body_prio: int = int((spr.material_override as Material).render_priority) if spr.material_override != null else int(spr.render_priority)
		## F②: 这一步新出现的锤击 / 挥锤特效节点的绘制属性与位置(码)
		var fx_props: Array = []
		for c in s._world.get_children():
			if c is Sprite3D and (c as Sprite3D).texture != null and not seen_fx.has(c.get_instance_id()):
				var fp := str((c as Sprite3D).texture.resource_path)
				if fp.ends_with("twohead-quake-star.png"):
					seen_fx[c.get_instance_id()] = true
					fx_props.append({"name": fp.get_file().get_basename(), "ndt": (c as Sprite3D).no_depth_test, "prio": (c as Sprite3D).render_priority,
						"x": (c as Sprite3D).position.x / s.WS + float(s._arena_center.x)})
		## F⑥: 锤击第六版的全部节点(按节点名 quake_* 认: 程序贴图没有 resource_path) —— 每步都记: 帧号 / 显隐 / 场地坐标 / 像素尺寸 / 绘制属性 / 亮度 / 宽度
		var slam_nodes: Array = []
		for c in s._world.get_children():
			## 节点名 = quake_<名>_<序号>(同名会被引擎改名成 @x@123): 剥掉 @ 与尾部序号再认
			var nm := str(c.name).lstrip("@")
			nm = nm.split("@")[0]
			while nm.length() > 0 and ((nm[nm.length() - 1] >= "0" and nm[nm.length() - 1] <= "9") or nm[nm.length() - 1] == "_"):
				nm = nm.substr(0, nm.length() - 1)
			if c is Sprite3D and nm.begins_with("quake_"):
				var sp3 := c as Sprite3D
				var mo = sp3.material_override
				var ndt: bool = (mo as BaseMaterial3D).no_depth_test if mo is BaseMaterial3D else sp3.no_depth_test
				var prio: int = (mo as Material).render_priority if mo is Material else sp3.render_priority
				var nmb := nm
				slam_nodes.append({"id": c.get_instance_id(), "name": nmb, "frame": sp3.frame, "vis": sp3.visible,
					"px": sp3.pixel_size, "x": sp3.position.x / s.WS + float(s._arena_center.x), "z": sp3.position.z / s.WS + float(s._arena_center.y),
					"ndt": ndt, "prio": prio, "flat": sp3.billboard == BaseMaterial3D.BILLBOARD_DISABLED, "h": sp3.position.y,
					"a": sp3.modulate.a, "sx": sp3.scale.x, "add": mo is BaseMaterial3D and (mo as BaseMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "ring_px": _ring_tex_r(sp3.texture) if nmb == "quake_range" else 0.0})
		var unit_prio_max := -999
		for uu in s._units:
			var us = uu.get("sprite", null)
			if is_instance_valid(us) and us is Sprite3D:
				unit_prio_max = maxi(unit_prio_max, int(((us as Sprite3D).material_override as Material).render_priority) if (us as Sprite3D).material_override != null else (us as Sprite3D).render_priority)
		rec.append({"shells": shells, "body_prio": body_prio, "fx": fx_props, "unit_prio_max": unit_prio_max, "slam_nodes": slam_nodes,
			"x": float((th["pos"] as Vector2).x), "y": float((th["pos"] as Vector2).y), "face_right": bool(th.get("face_right", true)),
			"t": float(s._t), "form": str(th.get("two_form", "")), "state": str(th.get("state", "")),
			"pending": str(th.get("pending", "")), "clip": str(th.get("_tha_clip", "")),
			"tex": str((spr.texture as Texture2D).resource_path.get_file().get_basename()) if spr.texture != null else "",
			"frame": int(spr.frame), "px": float(spr.pixel_size), "offy": float(spr.offset.y), "idle_px": float(th.get("idle_px", 0.0)),
			"taken": taken, "fresh": fresh, "frozen": float(th.get("stun_until", 0.0)) > float(s._t), "slam": bool(th.get("_slam", false)), "melee": bool(th.get("melee", false))})
	s.queue_free()
	await get_tree().process_frame
	return rec


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	RB.DEBUG_EDIT = false
	_static_checks()

	print("── D 普攻(REVIEW 技0) ──")
	var r0: Array = await _run(0, 900)
	var rel := 0; var rel_ok := 0; var bolt := 0; var hit_n := 0; var hit_ok := 0; var norm_bad := 0
	var wu_steps := 0; var wu_back := 0; var frozen_steps := 0; var frozen_moved := 0
	for i in range(1, r0.size()):
		var a: Dictionary = r0[i - 1]; var b: Dictionary = r0[i]
		if b["tex"].begins_with("ranged_") or b["tex"].begins_with("melee_") or b["tex"].begins_with("to_"):
			if absf(float(b["px"]) - float(b["idle_px"])) > 1e-6 or absf(float(b["offy"]) - FRAME * 0.5) > 1e-3:
				norm_bad += 1
		if a["state"] == "windup" and b["state"] == "windup" and a["tex"] == b["tex"]:
			wu_steps += 1
			if int(b["frame"]) < int(a["frame"]):
				wu_back += 1                       # 同一段前摇里帧号倒退 = 动作被重开了
			if b["frozen"] and a["frozen"]:
				frozen_steps += 1
				if int(b["frame"]) != int(a["frame"]):
					frozen_moved += 1                  # 被钩住眩晕期间动作还在往前走 = 解冻后出手帧对不上
		if a["state"] == "windup" and a["pending"] == "B" and b["state"] != "windup":
			rel += 1
			if b["tex"] == b["form"] + "_attack" and int(b["frame"]) in _reach_set(b["form"] + "_attack"):
				rel_ok += 1
			else:
				print("    出手步: t=%.3f tex=%s frame=%d" % [b["t"], b["tex"], b["frame"]])
			if "twohead-psi-bolt" in b["fresh"]:
				bolt += 1
		## ★只数灵能弹那一档(≥5): 场上训龟大师每 1.5 秒有一发固定 1 点的伤害(实测 +1 / 1.52 秒), 它不是变脸龟打的
		if int(b["taken"]) - int(a["taken"]) >= 5 and b["form"] == "ranged":
			hit_n += 1
			if "twohead-psi-hit" in b["fresh"]:
				hit_ok += 1
			else:
				print("    掉血步无命中特效: t=%.3f +%d tex=%s frame=%d fresh=%s" % [b["t"], int(b["taken"]) - int(a["taken"]), b["tex"], b["frame"], str(b["fresh"])])
	_ok("分母: 普攻出手 ≥ 4 次", rel >= 4, "%d" % rel)
	_ok("★出手那一步立绘正好在攻击关键帧(掌心出手 / 锤落)", rel_ok == rel, "%d/%d" % [rel_ok, rel])
	_ok("★远程出手同一步飞出新灵能弹(twohead-psi-bolt)", bolt == rel and bolt > 0, "%d/%d" % [bolt, rel])
	_ok("分母: 灵能弹命中掉血 ≥ 3 次", hit_n >= 3, "%d" % hit_n)
	_ok("★命中掉血那一步出命中特效(twohead-psi-hit)", hit_ok == hit_n, "%d/%d" % [hit_ok, hit_n])
	_ok("分母: 前摇中被冻住(眩晕/钩住)的步 ≥ 30(审阅台的训龟大师会钩)", frozen_steps >= 30, "%d / 前摇步 %d" % [frozen_steps, wu_steps])
	_ok("★前摇被冻住时动作不重开(帧号不倒退)", wu_back == 0, "倒退 %d 次" % wu_back)
	_ok("★前摇被冻住时画面停在原帧(帧号不动)", frozen_moved == 0, "冻住中走了 %d 步" % frozen_moved)
	_ok("★运行期归一: 播动作时 pixel_size == 立绘 idle_px 且脚底偏移 == 帧高/2", norm_bad == 0, "违例 %d 步" % norm_bad)

	print("── D 技一(灵能冲击 / 锤击) + 切形态 ──")
	var r1: Array = await _run(1, 1500)
	var sw := 0; var sw_ok := 0; var land := 0; var land_ok := 0; var orb := 0; var orb_ok := 0; var blast := 0
	for i in range(1, r1.size()):
		var a: Dictionary = r1[i - 1]; var b: Dictionary = r1[i]
		if a["form"] != b["form"] and a["form"] != "":
			sw += 1
			var ka: String = "to_" + str(b["form"]) + "_a"
			if a["tex"] == ka and int(a["frame"]) >= int(TwoHeadArt.CLIPS[ka][0]) - 1:
				sw_ok += 1
			else:
				print("    切形态前一步: t=%.3f tex=%s frame=%d" % [a["t"], a["tex"], a["frame"]])
		if a["slam"] and not b["slam"] and b["form"] == "melee":
			land += 1
			if b["tex"] == "melee_strike" and absi(int(b["frame"]) - 6) <= 1 and "twohead-quake-star" in b["fresh"] and int(b["taken"]) > int(a["taken"]):
				land_ok += 1
			else:
				print("    落地步: t=%.3f tex=%s frame=%d fresh=%s dmg=%s" % [b["t"], b["tex"], b["frame"], str(b["fresh"]), str(int(b["taken"]) > int(a["taken"]))])
		if "twohead-psi-orb-grow" in b["fresh"]:
			orb += 1
			if b["tex"] == "ranged_strike" and int(b["frame"]) in _reach_set("ranged_strike"):
				orb_ok += 1
			else:
				print("    法球出手步: t=%.3f tex=%s frame=%d" % [b["t"], b["tex"], b["frame"]])
		if "twohead-psi-blast" in b["fresh"] and int(b["taken"]) > int(a["taken"]):
			blast += 1
	_ok("分母: 切形态 ≥ 2 次(远→近→远)", sw >= 2, "%d" % sw)
	_ok("★切形态那一刻斗篷挡满脸(变脸前半段走到关键帧)", sw_ok == sw, "%d/%d" % [sw_ok, sw])
	_ok("分母: 锤击落地 ≥ 1 次", land >= 1, "%d" % land)
	_ok("★锤击落地那一步: 立绘第6帧砸地 + 裂地特效 + 目标掉血 同一步", land_ok == land, "%d/%d" % [land_ok, land])
	_ok("分母: 灵能冲击出手 ≥ 1 次", orb >= 1, "%d" % orb)
	_ok("★法球出手那一步立绘在双臂推出帧", orb_ok == orb, "%d/%d" % [orb_ok, orb])
	_ok("★法球爆炸特效与 200 码内掉血同一步", blast >= 1, "%d" % blast)

	print("── F 二轮画面: 护盾罩层级 / 锤头落点 / 砸地停帧 ──")
	## F① 变脸龟自己那几次给盾(切近战 / 锤击落地 / 强化普攻)建的罩, 必须排在立绘之前画(优先级 < 立绘材质)
	var sh_n := 0; var sh_bad := 0; var sh_sw := 0; var sh_land := 0
	for i in range(1, r1.size()):
		var a: Dictionary = r1[i - 1]; var b: Dictionary = r1[i]
		for pr in b["shells"]:
			sh_n += 1
			if int(pr) >= int(b["body_prio"]):
				sh_bad += 1
		if not (b["shells"] as Array).is_empty():
			if a["form"] == "ranged" and b["form"] == "melee":
				sh_sw += 1
			if a["slam"] and not b["slam"]:
				sh_land += 1
	_ok("分母: 切近战那一步 / 锤击落地那一步 各给过盾(建过通用护盾罩)", sh_sw >= 1 and sh_land >= 1, "切近战 %d · 落地 %d · 共 %d 个罩" % [sh_sw, sh_land, sh_n])
	_ok("★变脸龟给自己的护盾罩排在立绘之前画(不洗白变脸 / 砸地 / 挥锤)", sh_bad == 0, "违例 %d/%d" % [sh_bad, sh_n])
	## F② 锤击落地那一步: 命中星核出、关深度测试且优先级高于场上所有单位立绘、在锤头落点
	##   (2026-10-20 第五版: 落地时复用的普攻挥锤弧删了 —— 用户「不能共用啊，这一个是技能一个是攻击」; 下砸月牙弧由 F⑥ 管)
	var hg: Array = _hammer_ground()
	var g_frames: Array = hg[0]
	var land_fx := 0; var land_fx_ok := 0; var anchor_ok := 0; var hold_steps := 0; var hold_n := 0
	var anchor_detail := ""
	for i in range(1, r1.size()):
		var a: Dictionary = r1[i - 1]; var b: Dictionary = r1[i]
		if a["slam"] and not b["slam"] and b["form"] == "melee":
			land_fx += 1
			var has_slam := false; var over := true
			for fx in b["fx"]:
				if fx["name"] == "twohead-quake-star":
					has_slam = true
					var fwd: float = 1.0 if bool(b["face_right"]) else -1.0
					var want: float = float(b["x"]) + fwd * float(hg[1]) * float(b["idle_px"]) / RB.WS
					anchor_detail = "星核 x=%.1f · 落点 x=%.1f · 素材锤头应在 x=%.1f(锤头离中线 %.1f 像素)" % [float(fx["x"]), float(b["x"]), want, float(hg[1])]
					if absf(float(fx["x"]) - want) <= 8.0:
						anchor_ok += 1
				if not bool(fx["ndt"]) or int(fx["prio"]) <= int(b["unit_prio_max"]):
					over = false
			if has_slam and over:
				land_fx_ok += 1
			## 落地后到切走之前, 锤贴地那几帧(量素材)一共播了多少步
			for j in range(i, mini(r1.size(), i + 90)):
				var c: Dictionary = r1[j]
				if c["tex"] != "melee_strike":
					break
				if int(c["frame"]) in g_frames:
					hold_steps += 1
			hold_n += 1
	_ok("分母: 素材里量得到锤贴地帧 ≥ 3 张、锤击落地 ≥ 1 次", g_frames.size() >= 3 and land_fx >= 1, "贴地帧 %s · 落地 %d" % [str(g_frames), land_fx])
	_ok("★锤击落地那一步: 命中星核同一步出, 画在所有单位立绘上面(关深度测试 + 优先级更高)", land_fx_ok == land_fx, "%d/%d" % [land_fx_ok, land_fx])
	_ok("★星核画在锤头落点(按素材量出的锤头位置), 不在施法者脚下", anchor_ok == land_fx, anchor_detail)
	_ok("★落地后锤贴地帧播满 ≥ 0.15 秒(不被紧跟的普攻前摇吞掉)", hold_n >= 1 and hold_steps >= 9 * hold_n, "%d 步 / %d 次落地" % [hold_steps, hold_n])
	_slam_checks(r1, hg)

	print("── D 技二(精神干扰 / 吸收) ──")
	var r2: Array = await _run(2, 1500)
	var dis := 0; var dis_ok := 0; var ab := 0; var ab_ok := 0
	for i in range(1, r2.size()):
		var a: Dictionary = r2[i - 1]; var b: Dictionary = r2[i]
		if "twohead-mind-burst" in b["fresh"]:
			dis += 1
			if "twohead-mind-crest" in b["fresh"] and int(b["taken"]) > int(a["taken"]) and b["tex"] == "ranged_disrupt" and absi(int(b["frame"]) - 5) <= 1:
				dis_ok += 1
			else:
				print("    精神干扰步: t=%.3f tex=%s frame=%d fresh=%s" % [b["t"], b["tex"], b["frame"], str(b["fresh"])])
		if "twohead-siphon-pull" in b["fresh"]:
			ab += 1
			if "twohead-siphon-wisp" in b["fresh"] and int(b["taken"]) > int(a["taken"]) and b["tex"] == "melee_absorb" and absi(int(b["frame"]) - 4) <= 1:
				ab_ok += 1
			else:
				print("    吸收步: t=%.3f tex=%s frame=%d fresh=%s" % [b["t"], b["tex"], b["frame"], str(b["fresh"])])
	_ok("分母: 精神干扰 ≥ 1 次 / 吸收 ≥ 1 次", dis >= 1 and ab >= 1, "%d / %d" % [dis, ab])
	_ok("★精神干扰: 精神波+头部冲击与真伤同一步, 立绘在瞪眼帧", dis_ok == dis, "%d/%d" % [dis_ok, dis])
	_ok("★吸收: 攥出生命+血流与伤害同一步, 立绘在攥拳回扯帧", ab_ok == ab, "%d/%d" % [ab_ok, ab])

	print("── D 技三(融合·魔法波) ──")
	var r3: Array = await _run(3, 1200)
	var fw := 0; var fw_first := 0; var fw_ok := 0
	for i in range(1, r3.size()):
		var a: Dictionary = r3[i - 1]; var b: Dictionary = r3[i]
		var n_w := 0
		for f in b["fresh"]:
			if f == "twohead-fusion-wave":
				n_w += 1
		fw += n_w
		if n_w > 0 and a["clip"] == "fusion_cast" and int(a["frame"]) < int(TwoHeadArt.CLIPS["fusion_cast"][0]):
			fw_first += 1
			if b["tex"] == "fusion_cast" and int(b["frame"]) in _reach_set("fusion_cast"):
				fw_ok += 1
			else:
				print("    首波步: t=%.3f tex=%s frame=%d" % [b["t"], b["tex"], b["frame"]])
	_ok("分母: 魔法波 ≥ 4 道", fw >= 4, "%d" % fw)
	_ok("分母: 融合施放 ≥ 1 次", fw_first >= 1, "%d" % fw_first)
	_ok("★第一道魔法波出手那一步立绘在双脸推出帧", fw_ok == fw_first, "%d/%d" % [fw_ok, fw_first])
	## F③ 换表时序: 融合施法那一段里立绘贴图不许中途换成别的表(斗篷闪没若是换表造成的, 这里会抓到)
	var fu_steps := 0; var fu_bad := 0
	for b in r3:
		if b["clip"] == "fusion_cast":
			fu_steps += 1
			if b["tex"] != "fusion_cast":
				fu_bad += 1
	_ok("★融合施法整段都在 fusion_cast 表上(没有中途换表)", fu_steps >= 30 and fu_bad == 0, "%d 步里换表 %d 步" % [fu_steps, fu_bad])
	## F④ 融合停帧(2026-10-20 三轮): 融合施法后紧跟的远程普攻前摇曾把融合第 14~21 帧(推出后收手回立绘)截掉 ——
	##   画面上双脸推出后直接跳成术士抬手。按锤击那套停帧(TwoHeadArt.HOLD)把融合播完再接普攻:
	##   每次融合, 从关键帧到最后一帧【每一帧都上过屏】, 而且其后第一次普攻出手那一步仍在掌心出手帧(结算不动)。
	var fz_n := 0; var fz_ok := 0; var fz_detail := ""; var fz_rel := 0; var fz_rel_ok := 0
	var fz_last: int = int((load(TwoHeadArt.DIR + "fusion_cast.png") as Texture2D).get_width()) / FRAME - 1
	var fz_k: int = int(TwoHeadArt.CLIPS["fusion_cast"][0])
	for i in range(1, r3.size()):
		var a: Dictionary = r3[i - 1]; var b: Dictionary = r3[i]
		if not (b["tex"] == "fusion_cast" and int(b["frame"]) >= fz_k and not (a["tex"] == "fusion_cast" and int(a["frame"]) >= fz_k)):
			continue
		fz_n += 1
		var shown := {}
		var j := i
		while j < r3.size() and r3[j]["tex"] == "fusion_cast":
			shown[int(r3[j]["frame"])] = true
			j += 1
		var miss: Array = []
		for f in range(fz_k, fz_last + 1):
			if not shown.has(f):
				miss.append(f)
		if miss.is_empty():
			fz_ok += 1
		else:
			fz_detail = "t=%.2f 漏帧 %s · 之后接 %s" % [float(b["t"]), str(miss), (r3[j]["tex"] if j < r3.size() else "-")]
		## 其后第一次普攻出手: 前摇结束那一步(state 离开 windup 且 pending 是 B)立绘应在攻击关键帧
		for m in range(maxi(j, 1), mini(r3.size(), j + 240)):
			var c0: Dictionary = r3[m - 1]; var c1: Dictionary = r3[m]
			if c0["state"] == "windup" and c0["pending"] == "B" and c1["state"] != "windup":
				fz_rel += 1
				if c1["tex"] == "ranged_attack" and absi(int(c1["frame"]) - int(TwoHeadArt.CLIPS["ranged_attack"][0])) <= 1:
					fz_rel_ok += 1
				else:
					print("    融合后首次普攻出手步: t=%.3f tex=%s frame=%d" % [float(c1["t"]), c1["tex"], int(c1["frame"])])
				break
	_ok("分母: 融合推出(到关键帧)≥ 2 次", fz_n >= 2, "%d" % fz_n)
	_ok("★融合停帧: 关键帧 %d 到第 %d 帧每一帧都上过屏(不被紧跟的普攻前摇截掉)" % [fz_k, fz_last], fz_ok == fz_n, "%d/%d %s" % [fz_ok, fz_n, fz_detail])
	_ok("★融合之后第一次普攻出手那一步立绘仍在掌心出手帧(停帧不挪结算)", fz_rel >= 1 and fz_rel_ok == fz_rel, "%d/%d" % [fz_rel_ok, fz_rel])

	print("── F⑤ 切近战后的强化普攻: 不画无含义的地面环 ──")
	## 原来近战强化那一下在自己脚下画 62 码的 _skill_ring —— 不是射程也不是判定(特效九类毛病④)。
	## 量真对象: 直接走强化普攻入口, 数这一下新建的地面环(skill-ring 贴图)节点; 分母 = 同一下确实给了盾、建了护盾罩。
	if true:
		var s = RB.new()
		add_child(s)
		await get_tree().process_frame
		await get_tree().process_frame
		var u: Dictionary = s._spawn._make_unit("two_head", "left", Vector2(300, 400))
		var tg: Dictionary = s._spawn._make_unit("basic", "right", Vector2(360, 400))
		s._units.append(u)
		s._units.append(tg)
		var before := {}
		for c in s._world.get_children():
			before[c.get_instance_id()] = true
		var sh0: float = float(u.get("shield", 0.0))
		s._two_head_sys._two_head_enhanced_basic(u, tg, "melee")
		var rings := 0; var shells := 0
		for c in s._world.get_children():
			if before.has(c.get_instance_id()) or not (c is Sprite3D) or (c as Sprite3D).texture == null:
				continue
			var tp := str((c as Sprite3D).texture.resource_path)
			if tp.ends_with("skill-ring-10f.png"):
				rings += 1
			elif tp == BattleVfx.SHELL_TEX:
				shells += 1
		_ok("分母: 近战强化那一下确实给了盾(护盾 %.0f → %.0f)且建了护盾罩 %d 个" % [sh0, float(u.get("shield", 0.0)), shells],
			float(u.get("shield", 0.0)) > sh0 and shells >= 1)
		_ok("★近战强化普攻不在脚下画地面环(无含义圆环)", rings == 0, "新建地面环 %d 个" % rings)
		s.queue_free()
		await get_tree().process_frame

	print("── E 死亡(按形态) ──")
	for form in ["ranged", "melee"]:
		var s = RB.new()
		add_child(s)
		await get_tree().process_frame
		await get_tree().process_frame
		var u: Dictionary = s._spawn._make_unit("two_head", "left", Vector2(300, 400))
		s._units.append(u)
		s._spawn._apply_spawn_passive_one(u)          # 真出生入口(变脸龟在这里挂死亡帧表)
		if form == "melee":
			s._two_head_sys._two_head_after_cast(u, null)
		s._vfx._play_action(u, "death")
		var tx := str((u["sprite"].texture as Texture2D).resource_path.get_file())
		_ok("★%s 形态死亡播 %s_death 帧表、像素尺寸 == 立绘" % [form, form], tx == form + "_death.png" and absf(float(u["sprite"].pixel_size) - float(u["idle_px"])) < 1e-6, tx)
		s.queue_free()
		await get_tree().process_frame

	print("ALL PASS — 变脸龟两套动作 + 技能特效" if _fails == 0 else "FAIL x%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
