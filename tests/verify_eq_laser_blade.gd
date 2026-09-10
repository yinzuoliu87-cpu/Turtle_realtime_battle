extends Node
## verify_eq_laser_blade.gd —— 010「激光长刃」美术 + 演出 + 接线的门禁。
##
## ★★为什么要这一份: 重做之前 010 只有 `verify_equip_batch_20260801._t7_laser` 的
##   **2 条**断言, 全在机制侧(近战 +250), **美术侧 0 条**。于是四张素材一张都不是像素画
##   (595 / 2623 / 2762 / 21296 色)、后两帧平均 alpha 只有 56/255, 而门禁全绿 ——
##   这正是 memory `fb-weld-visual-lessons-into-gate` 说的那件事:
##   **memory 靠我想起来, 门禁自己会红。**
##
## ★★★判据是**照着装备文案逐条钉的**(用户 2026-09-10:「你没有遵从装备效果, 你明白吗」)。
##   文案原话:
##     「每隔一次攻击间隔朝最近的敌人斩出一道 120° 扇形红激光, 半径等于自身攻击射程(3 星 ×2);
##       若携带者为近战单位, 半径再 +250 码。对扇形内每名敌人造成物理伤害;
##       **若仅命中 1 名敌人则追加一道竖劈冲击波, 沿直线推进对沿途每名敌人各造成一次全额伤害**;
##       携带者回复本次总伤害 35/80/100% 的生命。」
##   我上一版栽的两跤都是「没照着文案做」, 所以各配一条判据把它钉死:
##     · 加了文案里**没有**的东西(0.30 秒预警扇形)
##         ⇒ ⑩b「触发到掉血的游戏时长 ≤ 0.05 秒」—— 有预警当场红
##     · 换掉了文案里**有**的东西(把"沿直线推进的波"做成了一排静态条依次点亮)
##         ⇒ ⑪「走廊上三个敌人必须按距离**先后**掉血, 且时间差 == 距离差 / 推进速度」
##           —— 一次性结算 / 一排板子同时亮 当场红
##
## ★判据都落在**产品自己的账**上(素材字节 / 常量 / 真入口的承伤与承伤时刻), 不数我插的标记
##   (memory `fb-gate-must-measure-requirement-not-my-hook`)。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EQ := preload("res://scripts/systems/equip/equip_system.gd")

var _s = null
var _n := 0
var _fail := 0

## ★★整图**缓存**: 斩击表是 3584×1120 = 4.0 M 像素, 而 ②③④⑤⑥⑦ 一共要取 30+ 格 ——
##   每次都 `get_image()` 就是 30 次显存→内存整表拷贝, 实测会把这条门禁变成整轮里最慢的一个。
##   一张表只拷一次, 之后只 `get_region`。
var _img_cache := {}


func _ok(msg: String, cond: bool, extra: String = "") -> void:
	_n += 1
	if cond:
		print("  [OK] %s" % msg)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [msg, extra])


## 一张贴图的规格: (色数, 半透像素数)
func _spec(path: String) -> Array:
	var tex: Texture2D = load(path)
	if tex == null:
		return [-1, -1]
	var img: Image = tex.get_image()
	var cols := {}
	var semi := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			var a: int = int(round(c.a * 255.0))
			if a <= 0:
				continue
			if a < 255:
				semi += 1
			cols["%d_%d_%d" % [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]] = true
	return [cols.size(), semi]


## 取一格(方向 dirf, 帧 f)。表的排布是 (cell×dirs, cell×frames): **方向在 X, 帧在 Y**。
func _cell(path: String, dirf: int, f: int, cell: int) -> Image:
	if not _img_cache.has(path):
		_img_cache[path] = (load(path) as Texture2D).get_image()
	return (_img_cache[path] as Image).get_region(Rect2i(dirf * cell, f * cell, cell, cell))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true   # 台子绝不写玩家存档(memory fb-debug-stage-writes-real-save)
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	print("")
	print("═══ 010 激光长刃 · 素材/演出/接线 ═══")

	# ══════════════════════════════════════════════════════════════
	#  ① 素材规格: 三张特效 + 图标, 都必须是**锁定调色板的像素画**
	# ══════════════════════════════════════════════════════════════
	print("-- 1 素材规格(色数 / 半透像素) --")
	var files := {
		"扇形斩": EQ.LASER_SLASH_TEX,
		"竖劈波前": EQ.LASER_WAVE_TEX,
		"竖劈落刃": EQ.LASER_CHOP_TEX,
		"图标": "res://assets/sprites/equip/eq010-icon.png",
	}
	var checked := 0
	for name in files.keys():
		var sp: Array = _spec(String(files[name]))
		checked += 1
		_ok("① %s 是像素画: %d 色(须 1~8) / %d 半透(须 0)" % [name, sp[0], sp[1]],
			sp[0] >= 1 and sp[0] <= 8 and sp[1] == 0,
			"旧素材是 595/2623/2762/21296 色 —— 色数超标或有半透 = 又贴了张渲染图")
	_ok("★分母: 查了 %d 张素材(应 4)" % checked, checked == 4)

	# ══════════════════════════════════════════════════════════════
	#  ①b 预警素材必须**不存在**(用户 2026-09-10:「不应该有预警啊」)
	# ══════════════════════════════════════════════════════════════
	var tel_left: Array = []
	for p in ["res://assets/sprites/vfx/eq010-tel.png", "res://assets/sprites/vfx/eq010-bar.png"]:
		if ResourceLoader.exists(p):
			tel_left.append(p)
	_ok("①b 预警/静态条素材已删干净(残留 %d 张)" % tel_left.size(), tel_left.is_empty(),
		"残留: %s —— 010 没有预警, 竖劈也不是一排静态条" % str(tel_left))

	# ══════════════════════════════════════════════════════════════
	#  ②③ 画的范围 == 打的范围: 斩击素材的半径 / 全角 ↔ 判定常量
	# ══════════════════════════════════════════════════════════════
	print("-- 2/3 斩击画多远打多远、画多大角打多大角 --")
	var cell: int = int(round(EQ.LASER_R_TEX * 2.0)) + 8   # 224
	var cx: float = float(cell) * 0.5
	var half: float = deg_to_rad(EQ.LASER_HALF_DEG)
	## 单帧是**故意不对称**的(刀刃在领先边、拖痕往回拖), 所以量**五帧并集**
	## —— 009 那一轮的教训: 拿单帧量方向会自证出 +10.4° 的假偏差。
	var un: Array = []
	for i in range(48):
		un.append(0)
	var rmax := 0.0
	var amin := 999.0
	var amax := -999.0
	var un_px := 0
	var out_of_range := 0
	var over_max := 0.0
	for f in range(EQ.LASER_SLASH_FRAMES):
		var im: Image = _cell(EQ.LASER_SLASH_TEX, 0, f, cell)
		for y in range(cell):
			for x in range(cell):
				if im.get_pixel(x, y).a <= 0.03:
					continue
				var fx: float = float(x) + 0.5 - cx
				var fy: float = float(y) + 0.5 - cx
				var rp: float = sqrt(fx * fx + fy * fy)
				var a2: float = atan2(fy, fx)
				## ★★判据量的是【越出扇形边界多少**像素**】, 不是【超了多少度】。
				##   第一版写的是 `absf(a2) > half + 0.03`(超 1.7° 就算越界), 它在**扇顶**是错的形状:
				##   离顶点 1.6 px 的那颗像素角度差 11.6°, 但垂直越界只有 0.32 px —— 顶点附近
				##   两条扇边本来就挤在一起, 拿角度当尺子会把"贴着携带者脚下那一格"判成缺陷
				##   (memory `fb-judge-must-fit-the-shape`)。换成垂直距离后:
				##   现役素材最大越界 0.40 px; 而"画 130° 打 120°"这类真缺陷在 r=100 处是 8.7 px, 照红。
				##   容差 1.5 px = 缩图(BOX 面积平均)在边界外的渗出量。
				var over: float = rp - EQ.LASER_R_TEX
				if absf(a2) > half:
					over = maxf(over, rp * sin(absf(a2) - half))
				over_max = maxf(over_max, over)
				if over > 1.5:
					out_of_range += 1
					continue
				if rp > EQ.LASER_R_TEX or absf(a2) > half:
					continue   # 在容差内但确实在扇外: 不算缺陷, 也不拿它去量半径/全角
				un_px += 1
				rmax = maxf(rmax, rp)
				if rp > EQ.LASER_R_TEX * 0.30:
					amin = minf(amin, rad_to_deg(a2))
					amax = maxf(amax, rad_to_deg(a2))
				var ir: int = clampi(int(rp / EQ.LASER_R_TEX * 6.0), 0, 5)
				var ia: int = clampi(int((a2 + half) / (2.0 * half) * 8.0), 0, 7)
				un[ir * 8 + ia] = 1
	var un_empty := 0
	for v in un:
		if int(v) == 0:
			un_empty += 1
	_ok("★分母: 五帧并集 %d 个不透明像素(须 > 15000)" % un_px, un_px > 15000)
	_ok("② 斩击越出扇形边界 %d 像素(最大越界 %.2f px; 须 0 —— 画得比打得大 = 站在外面的敌人白挨一刀)"
		% [out_of_range, over_max], out_of_range == 0)
	_ok("③ 素材里扇形半径 %.1f px(须 = LASER_R_TEX %.0f ± 2)" % [rmax, EQ.LASER_R_TEX],
		absf(rmax - EQ.LASER_R_TEX) <= 2.0, "素材与常量对不上 = 画出来的半径不是判定半径")
	_ok("③ 素材里扇形全角 %.1f°(须 = LASER_ARC_DEG %.0f ± 3)" % [amax - amin, EQ.LASER_ARC_DEG],
		absf((amax - amin) - EQ.LASER_ARC_DEG) <= 3.0,
		"改了 LASER_ARC_DEG 没重烤素材 ⇒ 画一个角度、打另一个角度")
	_ok("③ 五帧并集 6×8=48 子格空 %d 个(须 0 —— 扫完整片都被切过)" % un_empty, un_empty == 0)

	# ══════════════════════════════════════════════════════════════
	#  ④⑤ 斩击: 领先边单调推进 + 每帧径向盖满
	# ══════════════════════════════════════════════════════════════
	print("-- 4/5 斩击「从一边扫到另一边」且盖满(用户 2026-09-09 三句话) --")
	var leads: Array = []
	var thin := 0
	var minmax_r: Array = []
	for f in range(EQ.LASER_SLASH_FRAMES):
		var im2: Image = _cell(EQ.LASER_SLASH_TEX, 0, f, cell)
		var lead := -999.0
		var rlo := 9.0
		var rhi := -9.0
		var got := 0
		for y in range(cell):
			for x in range(cell):
				if im2.get_pixel(x, y).a <= 0.03:
					continue
				var fx: float = (float(x) + 0.5 - cx) / EQ.LASER_R_TEX
				var fy: float = (float(y) + 0.5 - cx) / EQ.LASER_R_TEX
				var rr: float = sqrt(fx * fx + fy * fy)
				var aa: float = atan2(fy, fx)
				if rr > 1.02 or absf(aa) > half:
					continue
				got += 1
				lead = maxf(lead, rad_to_deg(aa))
				rlo = minf(rlo, rr)
				rhi = maxf(rhi, rr)
		leads.append(lead)
		minmax_r.append([rlo, rhi])
		if got > 0 and (rlo > 0.14 or rhi < 0.94):
			thin += 1
	var mono := true
	for i in range(1, leads.size()):
		if float(leads[i]) < float(leads[i - 1]) - 0.5:
			mono = false
	var span: float = float(leads[leads.size() - 1]) - float(leads[0])
	_ok("④ 领先边逐帧单调推进(%.1f → %.1f → %.1f → %.1f → %.1f)"
		% [leads[0], leads[1], leads[2], leads[3], leads[4]], mono,
		"每帧都跨满全角 = 原地张开不是扫; 用户原话「没有从一边到另一边的感觉」")
	_ok("④ 领先边总共推了 %.1f°(须 ≥ 全角 %.0f° 的一半)" % [span, EQ.LASER_ARC_DEG],
		span >= EQ.LASER_ARC_DEG * 0.5, "扫的幅度太小 = 看不出是一刀扫过去")
	_ok("⑤ 每帧都径向盖满 0..R, 偏窄的帧 %d 个(须 0)" % thin, thin == 0,
		"斩痕比伤害区窄 = 玩家看见细细一道却整片掉血。逐帧 r 范围 %s" % str(minmax_r))

	# ══════════════════════════════════════════════════════════════
	#  ⑥ 消散靠碎不靠淡: 量【平均亮度 / 最满帧】, 不量最亮像素
	# ══════════════════════════════════════════════════════════════
	print("-- 6 消散靠碎开不靠变暗(旧素材第 4 帧平均亮度只有 14/255) --")
	## ★★这条判据改过一版。第一版写的是「每帧**最亮像素** ≥ 200/255」——
	##   反向验证当场证明它是**放过真 bug 的那一格**: 我把除刀刃以外的所有像素压成最暗档
	##   重烤了斩击表(md5 真的变了), 门禁**照样全绿** —— 因为领先边那条刀刃仍是 P[0](247),
	##   「最亮像素」这个量**一条线就能满足**(memory `fb-judge-must-fit-the-shape`)。
	## ⇒ 改成量**不透明像素的平均亮度**, 基准取【像素最多的那一帧】而不是第 0 帧
	##   (扫过式的第 0 帧只是一小片刀刃, 平均亮度天然最高, 拿它当基线会把正常的扫判成变暗)。
	var lum: Array = []
	var npx: Array = []
	for f in range(EQ.LASER_SLASH_FRAMES):
		var im3: Image = _cell(EQ.LASER_SLASH_TEX, 0, f, cell)
		var sum := 0.0
		var cnt := 0
		for y in range(cell):
			for x in range(cell):
				var c: Color = im3.get_pixel(x, y)
				if c.a <= 0.03:
					continue
				sum += (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * c.a * 255.0
				cnt += 1
		lum.append(sum / maxf(1.0, float(cnt)))
		npx.append(cnt)
	var fullest := 0
	for f in range(npx.size()):
		if int(npx[f]) > int(npx[fullest]):
			fullest = f
	var base: float = float(lum[fullest])
	var lo := 9999.0
	for v in lum:
		lo = minf(lo, float(v))
	var ratio: float = lo / maxf(1.0, base)
	_ok("★分母: 最满的是第 %d 帧(%d 像素), 平均亮度 %.1f" % [fullest, int(npx[fullest]), base],
		int(npx[fullest]) > 3000 and base > 80.0)
	_ok("⑥ 逐帧平均亮度最低 / 最满帧 = %.0f%%(须 ≥ 70%%)" % (ratio * 100.0), ratio >= 0.70,
		"靠把颜色压暗来消散 = 黑地上读成几块暗棕爪痕(fb-vfx-defect-families 的「淡出病」)")

	# ══════════════════════════════════════════════════════════════
	#  ⑦ 画的方向 == 打的方向: 16 档逐档量五帧并集的重心角
	# ══════════════════════════════════════════════════════════════
	print("-- 7 16 档方向: 素材第 k 格的朝向 == _laser_dir_of(k) --")
	var worst := 0.0
	var worst_k := -1
	var measured := 0
	for d in range(EQ.LASER_DIRS):
		var sx := 0.0
		var sy := 0.0
		var cnt2 := 0
		for f in range(EQ.LASER_SLASH_FRAMES):
			var im4: Image = _cell(EQ.LASER_SLASH_TEX, d, f, cell)
			for y in range(cell):
				for x in range(cell):
					if im4.get_pixel(x, y).a <= 0.03:
						continue
					sx += float(x) + 0.5 - cx
					sy += float(y) + 0.5 - cx
					cnt2 += 1
		if cnt2 < 3000:
			continue
		measured += 1
		var want: Vector2 = _s._equip_sys._laser_dir_of(d)
		var dd: float = absf(rad_to_deg(wrapf(atan2(sy, sx) - atan2(want.y, want.x), -PI, PI)))
		if dd > worst:
			worst = dd
			worst_k = d
	_ok("★分母: 量到 %d 档方向(应 %d)" % [measured, EQ.LASER_DIRS], measured == EQ.LASER_DIRS)
	_ok("⑦ 素材朝向与 _laser_dir_of 最大偏差 %.2f°(第 %d 档; 须 ≤ 2.5°)" % [worst, worst_k],
		worst <= 2.5, "画的方向 ≠ 打的方向 ⇒ 敌人明明画在扇里却不掉血")

	# ══════════════════════════════════════════════════════════════
	#  ⑧ 竖劈波前: 画多宽就打多宽(同一个常量)
	# ══════════════════════════════════════════════════════════════
	print("-- 8 波前宽度 == 判定宽度(旧版画 125 码 / 打 160 码) --")
	var wc: int = 48
	var wcx: float = float(wc) * 0.5
	var wim: Image = _cell(EQ.LASER_WAVE_TEX, 0, 1, wc)   # 第 0 档朝 +x ⇒ 波宽落在 y 上; 第 1 帧 = 满波前
	var hw_px := 0.0
	var wpx := 0
	for y in range(wc):
		for x in range(wc):
			if wim.get_pixel(x, y).a <= 0.03:
				continue
			wpx += 1
			hw_px = maxf(hw_px, absf(float(y) + 0.5 - wcx))
	## 素材半宽 (px) × 运行时 pixel_size = 画出来的半宽(米)
	var drawn_m: float = hw_px * (EQ.LASER_CHOP_HALF_W * _s.WS / EQ.LASER_WAVE_HW_TEX)
	var hit_m: float = EQ.LASER_CHOP_HALF_W * _s.WS
	_ok("★分母: 波前第 1 帧 %d 个不透明像素(须 > 150)" % wpx, wpx > 150)
	_ok("⑧ 波前画出来半宽 %.2f 米 vs 判定半宽 %.2f 米(误差须 ≤ 6%%)" % [drawn_m, hit_m],
		absf(drawn_m - hit_m) <= hit_m * 0.06,
		"素材里半宽 %.1f px 与 LASER_WAVE_HW_TEX %.0f 对不上" % [hw_px, EQ.LASER_WAVE_HW_TEX])

	# ══════════════════════════════════════════════════════════════
	#  ⑨ 竖劈判定: 纯几何逐格量落点(不依赖任何 tween)
	# ══════════════════════════════════════════════════════════════
	print("-- 9 竖劈判定: 逐格量落点(CLAUDE.md §3.5 不许依赖 tween) --")
	var o0: Vector2 = Vector2(0.0, 0.0)
	var dr: Vector2 = Vector2.RIGHT
	var probes: Array = [
		{"pos": Vector2(120.0, 0.0), "alive": true},                          # 走廊内
		{"pos": Vector2(120.0, EQ.LASER_CHOP_HALF_W - 4.0), "alive": true},   # 贴着边界内侧
		{"pos": Vector2(120.0, EQ.LASER_CHOP_HALF_W + 8.0), "alive": true},   # 边界外
		{"pos": Vector2(-40.0, 0.0), "alive": true},                          # 身后
	]
	var slab_all: Array = _s._equip_sys.laser_chop_slab(o0, dr, 0.0, 400.0, probes)
	_ok("⑨ 走廊 0~400 码内命中 %d 个(应 2: 轴上 + 贴边内侧; 边界外与身后都不算)" % slab_all.size(),
		slab_all.size() == 2, "边界判据没卡住 ±LASER_CHOP_HALF_W")
	var slab_near: Array = _s._equip_sys.laser_chop_slab(o0, dr, 0.0, 96.0, probes)
	_ok("⑨ 只推到 96 码时命中 %d 个(应 0 —— 波前没到就不许结算)" % slab_near.size(),
		slab_near.size() == 0, "推进与结算不是同一条时钟")

	# ══════════════════════════════════════════════════════════════
	#  ⑩ 真入口 + ⑩b「触发就斩, 不许有预警」+ ⑩c「追加竖劈也走真入口」
	# ══════════════════════════════════════════════════════════════
	print("-- 10 真入口 _tick_laser → _eq_laser_sweep, 且触发就斩 --")
	print("     [探针] 清场前 _s._units = %d 个" % _s._units.size())
	_s._units.clear()
	var c2: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	## ★★携带者必须是一个**只会放 010** 的平台 —— 三样都要关:
	##   `no_basic`(普攻) / `no_move`(走位) / **`active_skills = []`(龟能技)**。
	##   漏掉最后一样是反向验证抓到的真事: 我把 `laser_fan_strike` 从 `_eq_laser_sweep`
	##   里拿掉(接线断了), 这条断言**照样绿** —— 因为 `basicBarrage` 一直在往 `_st_taken`
	##   里加账, 我量的是"敌人掉血了"而不是"010 打的"
	##   (memory `fb-make-the-noise-deterministic`: 量被测那件事的账)。
	## ★atk_interval 拉到 3.0 秒: 一次触发之后 3 游戏秒内不会有第二次扇形斩 ——
	##   ⑩c 要在那段安静窗口里单独看【追加竖劈】的账, 不能被下一刀污染。
	var carrier: Dictionary = _s._spawn._make_unit("basic", "left", c2 + Vector2(-200.0, 0.0))
	carrier["no_basic"] = true
	carrier["no_move"] = true
	carrier["move_spd"] = 0.0
	carrier["active_skills"] = []
	## ★★暴击必须关掉。`_resolve_dmg` 里 `_battle_rng.randf() < u["crit"]` 会把这一发 ×1.5 ——
	##   于是同一件装备的两刀可能是 462 / 694, ⑩c 那个「总承伤 ≥ 首刀 ×1.8」的比值判据就成了掷骰子:
	##   两刀都不暴 ⇒ 2.00 过、两刀都暴 ⇒ 2.00 过、**只有首刀暴** ⇒ 1.67 红。
	##   门禁跑了三次单跑全绿、并行门禁里当场红, 正是这个(memory `fb-make-assertions-rng-insensitive`
	##   / `fb-ci-vs-local-divergence`: 拿干净合成单位隔离随机, 别把判据放宽)。
	##   关掉之后每一刀都恰好是 `laser_hit_dmg`, 判据可以从「≥1.8 倍」收紧成「正好两份」。
	carrier["crit"] = 0.0
	carrier["maxHp"] = 1.0e8
	carrier["hp"] = 1.0e8
	carrier["equips"] = [{"id": "p2eq_010", "star": 3}]
	carrier["eq_state"] = {}
	carrier["atk_interval"] = 3.0
	_s._units.append(carrier)
	## ★敌人必须同时落在【扇形半径】和【竖劈 reach】里, 否则 ⑩c 量不到追加竖劈:
	##   3★近战的扇形半径 = 射程×2 + 250 = 450, 而竖劈 reach = 射程×2 = 200(与重做前逐字相同)。
	##   放 260 码处 ⇒ 扇形打得到、波推到 200 码就停了, 那是**这件装备本来的样子**, 不是缺陷。
	var foe: Dictionary = _s._spawn._make_unit("basic", "right", c2 + Vector2(-70.0, 0.0))
	foe["maxHp"] = 1.0e8
	foe["hp"] = 1.0e8
	foe["_st_taken"] = 0
	foe["no_move"] = true
	foe["move_spd"] = 0.0
	_s._units.append(foe)
	var before: int = int(foe.get("_st_taken", 0))
	var foe_d: float = (foe["pos"] as Vector2).distance_to(carrier["pos"])
	_ok("★分母: 场上 %d 个单位(应 2), 敌人在 %.0f 码处(须 < 扇形半径 %.0f **且** < 竖劈 reach %.0f)"
		% [_s._units.size(), foe_d, _s._equip_sys.laser_fan_range(carrier, 2),
			_s._equip_sys.laser_chop_reach(carrier)],
		_s._units.size() == 2 and foe_d < _s._equip_sys.laser_fan_range(carrier, 2)
			and foe_d < _s._equip_sys.laser_chop_reach(carrier))
	## ★★对照组: 同一个平台**不带 010**, 推同样长的窗口 —— 它必须一点伤害都打不出来。
	##   没有这一条就证明不了"上面那条量的是 010", 只能证明"有东西打了它"。
	## ★★**不手喂 `_tick_laser`**: 它本来就挂在 `_tick_unit` 里(RealtimeBattle3DScene.gd:2791),
	##   每个 sim 步都会跑 —— 手喂一遍等于让计时器双份地涨, 于是"到底是我这一拍打的还是
	##   sim 那一拍打的"变成竞态: 上一版就因此在同一份代码上一次量到触发时刻、一次量不到。
	##   让真入口自己跑, 我只负责观测(memory `fb-verify-must-run-the-real-path`)。
	carrier["equips"] = []
	var ctrl_end: int = Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < ctrl_end:
		await get_tree().process_frame
	var ctrl: int = int(foe.get("_st_taken", 0)) - before
	_ok("⑩ 对照组(不带 010)承伤 %d(须 = 0 —— 否则这个台子上还有别的伤害源)" % ctrl, ctrl == 0,
		"普攻/龟能技没关干净, 下面那条就量不到被测那件事")
	carrier["equips"] = [{"id": "p2eq_010", "star": 3}]
	carrier["eq_state"] = {}
	before = int(foe.get("_st_taken", 0))
	## ★★⑩b 量的是【从触发到首次掉血】的**游戏时长**。
	##   `_tick_laser` 的计时器 `laser_t` 只会单调地涨, **只有开斩那一拍会把它清零** ——
	##   所以"这一帧看到的值比上一帧小"就是触发时刻, 不用我在产品里插任何标记。
	##   伤害若与斩击同帧落地, 这个差就是 0.000。我上一版加了 0.30 游戏秒的预警扇形,
	##   这条会当场红 —— 这就是「不应该有预警」在门禁里的样子。
	## ★用**墙钟**当上限(CLAUDE.md §3.5: 帧数/游戏钟都不能当尺子)。
	var t_fire := -1.0
	var t_hit := -1.0
	var lt_prev := -1.0
	var t_end: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < t_end:
		var lt: float = float((carrier["equips"][0] as Dictionary).get("laser_t", 0.0))
		if lt < lt_prev:
			t_fire = float(_s._t)   # 计时器掉下来了 = 这一帧开的斩
		lt_prev = lt
		if int(foe.get("_st_taken", 0)) > before:
			t_hit = float(_s._t)
			break
		await get_tree().process_frame
	var d1: int = int(foe.get("_st_taken", 0)) - before
	var lag: float = (t_hit - t_fire) if (t_fire >= 0.0 and t_hit >= 0.0) else -1.0
	print("     [探针] 触发 t=%.3f  首刀落地 t=%.3f  延迟 %.3f 游戏秒  首刀伤害 %d" % [t_fire, t_hit, lag, d1])
	_ok("⑩ 真入口打出 %d 点伤害(须 ≥ 150 = 只有 010 的量级)" % d1, d1 >= 150,
		"0 = 接线断了(_tick_laser 没到 _eq_laser_sweep, 或 _eq_laser_sweep 没调 laser_fan_strike)")
	_ok("⑩b 触发→掉血 %.3f 游戏秒(须 ≤ 0.05 —— 文案里 010 **没有预警**, 触发就斩)" % lag,
		lag >= 0.0 and lag <= 0.05,
		"加了预警/蓄力当场红。上一版我按 009 的套路给它加了 0.30 秒预警扇形, 被用户否掉")
	## ⑩c 追加竖劈也必须走真入口: 场上只有 1 个敌人 ⇒ 文案说「若仅命中 1 名敌人则追加一道竖劈冲击波」,
	##    而竖劈「各造成一次全额伤害」⇒ 同一个敌人总共该吃到 **两次全额**。
	##    ★这一段**不再手喂 `_tick_laser`**: atk_interval=3.0 ⇒ 3 游戏秒内没有第二刀, 窗口是干净的。
	var t_2nd := -1.0
	var t2_end: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < t2_end and float(_s._t) - t_hit < 1.0:
		await get_tree().process_frame
		if int(foe.get("_st_taken", 0)) - before >= d1 * 2 - 2:   # 暴击已关 ⇒ 第二刀必然与首刀等额
			t_2nd = float(_s._t)
			break
	var tot: int = int(foe.get("_st_taken", 0)) - before
	print("     [探针] 首刀后总承伤 %d(首刀 %d), 竖劈落地 t=%.3f(首刀 +%.3f 游戏秒)"
		% [tot, d1, t_2nd, (t_2nd - t_hit) if t_2nd >= 0.0 else -1.0])
	_ok("⑩c 只命中 1 人 ⇒ 追加竖劈: 总承伤 %d == 首刀 %d 的**正好两份**(「各造成一次全额伤害」)"
		% [tot, d1], absf(float(tot) - float(d1) * 2.0) <= 2.0,
		"竖劈没接上真入口(=1 份), 或者它打的不是全额(比值 %.3f)" % (float(tot) / maxf(1.0, float(d1))))
	_ok("⑩c 竖劈落在首刀之后 %.3f 游戏秒(须在 0.20~0.80 —— 斩击 5 帧 %.2f 秒演完才追)"
		% [t_2nd - t_hit, EQ.LASER_SLASH_FRAMES * EQ.LASER_SLASH_STEP],
		t_2nd >= 0.0 and (t_2nd - t_hit) >= 0.20 and (t_2nd - t_hit) <= 0.80,
		"与斩击同帧就没有『追加』这回事; 太晚 = 波飞了半天才到")

	# ══════════════════════════════════════════════════════════════
	#  ⑪ 竖劈冲击波：**沿直线推进**, 沿途敌人按距离先后掉血
	# ══════════════════════════════════════════════════════════════
	print("-- 11 竖劈是「一道波在移动」不是「一排板子同时结算」 --")
	## ⑪a 波前步长必须**正好落在 sim 步边界上**。`_wait_sim` 只能停在 sim 步上,
	##    步长不是 SIM_DT 的整数倍就会被向上取整 —— 写 0.035 实际等 0.05,
	##    于是波前真实速度 19.25/0.05 = 385 码/秒, 而常量写着 550。
	##    这类"常量说一套、画面走另一套"用时间差量太钝(误差只有 0.077 秒), 直接量整除关系。
	var q: float = EQ.LASER_CHOP_STEP / _s.SIM_DT
	var q_err: float = absf(q - round(q))
	_ok("⑪a 波前步长 %.5f 秒 = %.3f × SIM_DT(须是整数倍, 余 %.4f ≤ 0.01)"
		% [EQ.LASER_CHOP_STEP, q, q_err], q_err <= 0.01,
		"被 _wait_sim 向上取整 ⇒ 实际速度 %.0f 码/秒 ≠ 常量 %.0f"
			% [EQ.LASER_CHOP_SPEED * EQ.LASER_CHOP_STEP / (ceil(q) * _s.SIM_DT), EQ.LASER_CHOP_SPEED])
	## ★★这条是这一版的核心判据。文案原话:「沿直线推进对沿途每名敌人各造成一次全额伤害」。
	##   量法: 走廊上按 40 / 120 / 190 码摆三个敌人, 跑**真的** `_eq_laser_chop`,
	##   记录每个敌人掉血的**游戏时刻**。
	##     · 波在移动   ⇒ 必须**按距离先后**掉血, 且时间差 ≈ 距离差 / LASER_CHOP_SPEED
	##     · 一排板子同时点亮 / 一次性全场结算 ⇒ 三个时刻挤在一起, 这条当场红
	##   我上一版就是后者: 几何全对(每条正是 160 码判定带), 但那不是「波在移动」。
	_s._units.clear()
	var cr2: Dictionary = _s._spawn._make_unit("basic", "left", c2 + Vector2(-300.0, 0.0))
	cr2["no_basic"] = true
	cr2["no_move"] = true
	cr2["move_spd"] = 0.0
	cr2["active_skills"] = []
	cr2["equips"] = []
	cr2["crit"] = 0.0
	cr2["maxHp"] = 1.0e8
	cr2["hp"] = 1.0e8
	_s._units.append(cr2)
	var dists: Array = [40.0, 120.0, 190.0]
	var foes: Array = []
	for d in dists:
		var f2: Dictionary = _s._spawn._make_unit("basic", "right",
			(cr2["pos"] as Vector2) + Vector2(float(d), 0.0))
		f2["maxHp"] = 1.0e8
		f2["hp"] = 1.0e8
		f2["_st_taken"] = 0
		f2["no_move"] = true
		f2["move_spd"] = 0.0
		_s._units.append(f2)
		foes.append(f2)
	var reach2: float = 200.0
	_ok("★分母: 走廊上摆了 %d 个敌人 %s 码(reach = %.0f, 都在走廊内)"
		% [foes.size(), str(dists), reach2], foes.size() == 3 and float(dists[2]) < reach2)
	var t_at: Array = [-1.0, -1.0, -1.0]
	_s._equip_sys._eq_laser_chop(cr2, 2, cr2["pos"], Vector2.RIGHT, 0, reach2)
	var t3_end: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < t3_end:
		await get_tree().process_frame
		var done := 0
		for i in range(foes.size()):
			if t_at[i] < 0.0 and int((foes[i] as Dictionary).get("_st_taken", 0)) > 0:
				t_at[i] = float(_s._t)
			if t_at[i] >= 0.0:
				done += 1
		if done == foes.size():
			break
	print("     [探针] 三个敌人掉血时刻: %.3f / %.3f / %.3f(游戏秒)" % [t_at[0], t_at[1], t_at[2]])
	var all_hit: bool = t_at[0] >= 0.0 and t_at[1] >= 0.0 and t_at[2] >= 0.0
	_ok("⑪ 沿途三个敌人**都**掉血了(「对沿途每名敌人各造成一次全额伤害」)", all_hit,
		"时刻 %s —— -1 = 那个敌人根本没被波扫到" % str(t_at))
	if all_hit:
		_ok("⑪ 按距离**先后**掉血(%.3f < %.3f < %.3f)" % [t_at[0], t_at[1], t_at[2]],
			float(t_at[0]) < float(t_at[1]) and float(t_at[1]) < float(t_at[2]),
			"三个时刻挤在一起 = 不是波在移动, 是一次性结算")
		var want_gap: float = (float(dists[2]) - float(dists[0])) / EQ.LASER_CHOP_SPEED
		var got_gap: float = float(t_at[2]) - float(t_at[0])
		## 容差取 3 个波前步: 落点被量化到"覆盖它的那一步"上, 天然有 ±1 步的抖动。
		## 一次性结算的话 got_gap = 0, 误差 = want_gap = 0.27 秒 ⇒ 远超容差, 当场红。
		var tol: float = 3.0 * EQ.LASER_CHOP_STEP
		_ok("⑪ 首尾时间差 %.3f 秒 vs 距离差 %.0f 码 / 推进速度 %.0f = %.3f 秒(误差须 ≤ %.3f)"
			% [got_gap, float(dists[2]) - float(dists[0]), EQ.LASER_CHOP_SPEED, want_gap, tol],
			absf(got_gap - want_gap) <= tol,
			"实测推进速度 %.0f 码/秒 ≠ 常量 %.0f —— 画的推进和打的推进不是一回事"
				% [(float(dists[2]) - float(dists[0])) / maxf(0.001, got_gap), EQ.LASER_CHOP_SPEED])

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 010 激光长刃" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
