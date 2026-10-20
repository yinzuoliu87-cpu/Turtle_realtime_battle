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
func _sheet_stats(name: String, fw: int) -> Array:
	if _sheet_cache.has(name):
		return _sheet_cache[name]
	var im := _img("res://assets/sprites/vfx/" + name + ".png")
	var out: Array = []
	if im == null:
		return out
	im.convert(Image.FORMAT_RGBA8)
	var n: int = im.get_width() / fw
	var fh: int = im.get_height()
	var cx := fw * 0.5; var cy := fh * 0.5
	for i in range(n):
		var ds: Array = []
		var bright := 0; var x0 := 99999; var x1 := -1; var y0 := 99999; var y1 := -1; var cnt := 0
		for y in range(fh):
			for x in range(fw):
				var c := im.get_pixel(i * fw + x, y)
				if c.a8 == 0:
					continue
				x0 = mini(x0, x); x1 = maxi(x1, x); y0 = mini(y0, y); y1 = maxi(y1, y); cnt += 1
				if (c.r8 + c.g8 + c.b8) / 3 > 200:
					bright += 1
				var dd := Vector2(x - cx, y - cy).length()
				if dd > cx * 0.6:
					ds.append(dd)
		ds.sort()
		out.append({"ring": float(ds[ds.size() / 2]) if ds.size() >= 150 else 0.0, "bright": bright, "w": (x1 - x0 + 1) if x1 >= 0 else 0, "n": cnt, "h": (y1 - y0 + 1) if y1 >= 0 else 0})
	_sheet_cache[name] = out
	return out


func _slam_checks(r1: Array, hg: Array) -> void:
	print("── F⑥ 锤击砸地: 冲击环 = 判定半径 / 爆点不被挡 / 向外扩散 / 圈边尘团 ──")
	var gs: Array = _sheet_stats("twohead-slam-ring", 208)
	var bs: Array = _sheet_stats("twohead-slam-burst", 168)
	var xs: Array = _sheet_stats("twohead-slam-boom", 123)
	var ok_boom := 0; var boom_detail := ""
	var ring_px := 0.0
	for e in gs:
		ring_px = maxf(ring_px, float(e["ring"]))
	var R: float = TwoHeadSystem.STRIKE_MELEE_RADIUS
	var n_land := 0; var ok_radius := 0; var ok_center := 0; var ok_flash := 0; var ok_expand := 0; var ok_spread := 0
	var ok_dust := 0; var dust_n := 0
	var detail := ""; var flash_detail := ""; var exp_detail := ""; var spread_detail := ""; var dust_detail := ""
	for i in range(1, r1.size()):
		var a: Dictionary = r1[i - 1]; var b: Dictionary = r1[i]
		if not (a["slam"] and not b["slam"] and b["form"] == "melee"):
			continue
		n_land += 1
		var fwd: float = 1.0 if bool(b["face_right"]) else -1.0
		var hx: float = float(b["x"]) + fwd * float(hg[1]) * float(b["idle_px"]) / RB.WS     # 锤头落点(按立绘素材量)
		var hy: float = float(b["y"])
		var seen0 := {}
		for nd in a["slam_nodes"]:
			seen0[nd["id"]] = true
		var g = null; var bu = null; var bo = null; var dusts: Array = []
		for nd in b["slam_nodes"]:
			if seen0.has(nd["id"]):
				continue
			if nd["name"] == "twohead-slam-ring":
				g = nd
			elif nd["name"] == "twohead-slam-burst":
				bu = nd
			elif nd["name"] == "twohead-slam-edgedust":
				dusts.append(nd)
			elif nd["name"] == "twohead-slam-boom":
				bo = nd
		if g == null or bu == null:
			detail = "落地那一步没建贴地层/爆点 g=%s b=%s" % [str(g != null), str(bu != null)]
			continue
		## ① 冲击环满径(素材量) × 运行期 pixel_size == 判定半径
		var r_world: float = ring_px * float(g["px"]) / RB.WS
		detail = "素材环半径 %.1f 像素 × pixel_size %.4f = %.1f 码 · 判定 %.0f 码" % [ring_px, float(g["px"]), r_world, R]
		if absf(r_world - R) <= R * 0.05 and bool(g["flat"]):
			ok_radius += 1
		## ② 贴地层 / 爆点都在锤头落点(= 结算圆心)
		if Vector2(float(g["x"]) - hx, float(g["z"]) - hy).length() <= 8.0 and Vector2(float(bu["x"]) - hx, float(bu["z"]) - hy).length() <= 8.0:
			ok_center += 1
		else:
			detail += " · 圆心偏: 地(%.0f,%.0f) 爆(%.0f,%.0f) 应(%.0f,%.0f)" % [float(g["x"]), float(g["z"]), float(bu["x"]), float(bu["z"]), hx, hy]
		## 往后逐步跟这三类节点显示的帧(按游戏钟算时刻: 顿帧期间钟不走)
		var t0: float = float(b["t"])
		var max_bright := 0; var ring_seq: Array = []; var w_after: Array = []
		var dust_vis_early := 0; var dust_vis_late := 0
		var boom_n := 0; var boom_h := 0
		var dust_ids := {}
		for dd in dusts:
			dust_ids[dd["id"]] = true
		for j in range(i, mini(r1.size(), i + 120)):
			var c: Dictionary = r1[j]
			var dt: float = float(c["t"]) - t0
			for nd in c["slam_nodes"]:
				var f: int = int(nd["frame"])
				if nd["id"] == bu["id"]:
					if dt <= 0.1 + 1e-6 and f < bs.size():
						max_bright = maxi(max_bright, int(bs[f]["bright"]))
					if f >= 4 and f < bs.size():
						w_after.append(int(bs[f]["w"]))
				elif bo != null and nd["id"] == bo["id"]:
					if dt <= 0.5 + 1e-6 and f < xs.size():
						boom_n = maxi(boom_n, int(xs[f]["n"])); boom_h = maxi(boom_h, int(xs[f]["h"]))
				elif nd["id"] == g["id"]:
					if dt <= 0.3 + 1e-6 and f < gs.size():
						ring_seq.append(float(gs[f]["ring"]))
				elif dust_ids.has(nd["id"]):
					if dt < 0.05 and bool(nd["vis"]):
						dust_vis_early += 1
					if dt >= 0.15 and dt <= 0.3 and bool(nd["vis"]):
						dust_vis_late += 1
		## ③ 落地起 0.1 秒内爆点白核够亮(≥ 600 亮像素)且画在所有单位上面
		flash_detail = "0.1 秒内最亮帧亮像素 %d · 关深度测试 %s · 优先级 %d > 立绘 %d" % [max_bright, str(bu["ndt"]), int(bu["prio"]), int(b["unit_prio_max"])]
		if max_bright >= 600 and bool(bu["ndt"]) and int(bu["prio"]) > int(b["unit_prio_max"]):
			ok_flash += 1
		## ④ 冲击环由内向外: 到满径 90% 之前显示过的环半径不缩, 0.3 秒内到过满径 90%
		var mono := true; var top := 0.0; var prev := -1.0; var first := -1.0
		for rv in ring_seq:
			if float(rv) > 0.0:
				if first < 0.0:
					first = float(rv)
				if prev > 0.0 and float(rv) + 0.5 < prev and top < ring_px * 0.9:
					mono = false
				prev = float(rv)
				top = maxf(top, float(rv))
		exp_detail = "0.3 秒内显示过的环半径 %s · 首次出现 %.1f / 满径 %.1f" % [str(ring_seq.slice(0, 12)), first, ring_px]
		if mono and top >= ring_px * 0.9 and ring_seq.size() >= 3 and first > 0.0 and first <= ring_px * 0.75:
			ok_expand += 1
		## ⑤ 碎石 / 尘团往外散: 闪光过后, 显示过的最宽一帧 ≥ 闪光刚过那帧的 1.8 倍
		spread_detail = "闪光后显示过的 bbox 宽 %s" % str(w_after.slice(0, 12))
		if w_after.size() >= 4 and float(w_after.max()) >= 1.8 * float(w_after[0]):
			ok_spread += 1
		## ⑦ 落点爆炸(用户「起码要有爆炸的特效吧」): 与冲击环同一步建、在锤头落点、画在所有单位上面,
		##   0.5 秒内显示过的帧里火球体积够大(不透明 ≥ 5000 像素、高 ≥ 80 像素 ≈ 2 米 = 龟身 1.5 倍以上)
		if bo == null:
			boom_detail = "落地那一步没建爆炸"
		else:
			boom_detail = "0.5 秒内最大面积 %d 像素 · 最高 %d 像素 · 离落点 %.1f 码 · 关深度 %s · 优先级 %d" % [boom_n, boom_h,
				Vector2(float(bo["x"]) - hx, float(bo["z"]) - hy).length(), str(bo["ndt"]), int(bo["prio"])]
			if boom_n >= 5000 and boom_h >= 80 and Vector2(float(bo["x"]) - hx, float(bo["z"]) - hy).length() <= 8.0 and bool(bo["ndt"]) and int(bo["prio"]) > int(b["unit_prio_max"]):
				ok_boom += 1
		## ⑥ 圈边尘团: 离锤头落点 = 判定半径 × (0.85~1.0), 冲击环到之前不露、到了之后露
		var on_ring := 0
		for dd in dusts:
			var rr: float = Vector2(float(dd["x"]) - hx, float(dd["z"]) - hy).length()
			if rr >= R * 0.85 and rr <= R * 1.0:
				on_ring += 1
		dust_n += dusts.size()
		dust_detail = "圈边尘团 %d 个 · 在判定半径 85~100%% 处 %d 个 · 提前露 %d 次 · 环到后露 %d 次" % [dusts.size(), on_ring, dust_vis_early, dust_vis_late]
		if dusts.size() >= 4 and on_ring == dusts.size() and dust_vis_early == 0 and dust_vis_late >= dusts.size():
			ok_dust += 1
	_ok("分母: 锤击落地 ≥ 1 次 · 素材量得到冲击环半径 ≥ 80 像素 · 爆点表 ≥ 8 帧", n_land >= 1 and ring_px >= 80.0 and bs.size() >= 8, "落地 %d · 环 %.1f 像素 · 爆点 %d 帧" % [n_land, ring_px, bs.size()])
	_ok("★特效即判定: 冲击环满径(素材量 × 运行期 pixel_size) == 锤击判定半径 ±5%, 且贴地平躺", ok_radius == n_land and n_land > 0, detail)
	_ok("★贴地层与爆点都在锤头落点(= 结算圆心)", ok_center == n_land and n_land > 0, "%d/%d" % [ok_center, n_land])
	_ok("★落地起 0.1 秒内落点白核够亮(≥600 亮像素)且画在所有单位上面", ok_flash == n_land and n_land > 0, flash_detail)
	_ok("★冲击环由内向外扩到满径(首次出现 ≤ 满径 75%, 0.3 秒内到 90%, 中途不缩)", ok_expand == n_land and n_land > 0, exp_detail)
	_ok("★碎石 / 尘团往外散开(闪光后最宽帧 ≥ 1.8 × 起始)", ok_spread == n_land and n_land > 0, spread_detail)
	_ok("★落点爆炸: 与冲击环同一步起爆、在锤头落点、画在单位上面, 0.5 秒内火球 ≥ 5000 像素且高 ≥ 80 像素", ok_boom == n_land and n_land > 0 and xs.size() >= 10, boom_detail)
	_ok("★圈边尘团落在判定半径上, 冲击环到之前不露", ok_dust == n_land and n_land > 0 and dust_n >= 4, dust_detail)


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
				if fp.ends_with("twohead-slam-burst.png") or fp.ends_with("twohead-hammer-swing.png"):
					seen_fx[c.get_instance_id()] = true
					fx_props.append({"name": fp.get_file().get_basename(), "ndt": (c as Sprite3D).no_depth_test, "prio": (c as Sprite3D).render_priority,
						"x": (c as Sprite3D).position.x / s.WS + float(s._arena_center.x)})
		## F⑥: 锤击砸地三张表的节点(每步都记: 帧号 / 显隐 / 场地坐标 / 像素尺寸 / 绘制属性)
		var slam_nodes: Array = []
		for c in s._world.get_children():
			if c is Sprite3D and (c as Sprite3D).texture != null:
				var sp3 := c as Sprite3D
				var fp3 := str(sp3.texture.resource_path)
				if fp3.contains("/vfx/twohead-slam-"):
					slam_nodes.append({"id": c.get_instance_id(), "name": fp3.get_file().get_basename(), "frame": sp3.frame, "vis": sp3.visible,
						"px": sp3.pixel_size, "x": sp3.position.x / s.WS + float(s._arena_center.x), "z": sp3.position.z / s.WS + float(s._arena_center.y),
						"ndt": sp3.no_depth_test, "prio": sp3.render_priority, "flat": sp3.billboard == BaseMaterial3D.BILLBOARD_DISABLED})
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
			if b["tex"] == "melee_strike" and absi(int(b["frame"]) - 6) <= 1 and "twohead-slam-burst" in b["fresh"] and int(b["taken"]) > int(a["taken"]):
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
	## F② 锤击落地那一步: 裂地 + 挥锤弧都出, 都关深度测试且优先级高于场上所有单位立绘; 裂地在锤头落点
	var hg: Array = _hammer_ground()
	var g_frames: Array = hg[0]
	var land_fx := 0; var land_fx_ok := 0; var anchor_ok := 0; var hold_steps := 0; var hold_n := 0
	var anchor_detail := ""
	for i in range(1, r1.size()):
		var a: Dictionary = r1[i - 1]; var b: Dictionary = r1[i]
		if a["slam"] and not b["slam"] and b["form"] == "melee":
			land_fx += 1
			var has_slam := false; var has_swing := false; var over := true
			for fx in b["fx"]:
				if fx["name"] == "twohead-slam-burst":
					has_slam = true
					var fwd: float = 1.0 if bool(b["face_right"]) else -1.0
					var want: float = float(b["x"]) + fwd * float(hg[1]) * float(b["idle_px"]) / RB.WS
					anchor_detail = "裂地 x=%.1f · 落点 x=%.1f · 素材锤头应在 x=%.1f(锤头离中线 %.1f 像素)" % [float(fx["x"]), float(b["x"]), want, float(hg[1])]
					if absf(float(fx["x"]) - want) <= 8.0:
						anchor_ok += 1
				elif fx["name"] == "twohead-hammer-swing":
					has_swing = true
				if not bool(fx["ndt"]) or int(fx["prio"]) <= int(b["unit_prio_max"]):
					over = false
			if has_slam and has_swing and over:
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
	_ok("★锤击落地那一步: 裂地 + 挥锤弧同一步出, 都画在所有单位立绘上面(关深度测试 + 优先级更高)", land_fx_ok == land_fx, "%d/%d" % [land_fx_ok, land_fx])
	_ok("★裂地画在锤头落点(按素材量出的锤头位置), 不在施法者脚下", anchor_ok == land_fx, anchor_detail)
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
