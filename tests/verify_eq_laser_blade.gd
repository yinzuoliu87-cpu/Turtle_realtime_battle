extends Node
## verify_eq_laser_blade.gd —— 010「激光长刃」美术 + 演出 + 接线的门禁。
##
## ★★为什么要新建这一份: 重做之前 010 只有 `verify_equip_batch_20260801._t7_laser` 的
##   **2 条**断言, 全在机制侧(近战 +250), **美术侧 0 条**。于是四张素材一张都不是像素画
##   (595 / 2623 / 2762 / 21296 色)、扇形零预兆、后两帧平均 alpha 只有 56/255,
##   而门禁全绿 —— 这正是 memory `fb-weld-visual-lessons-into-gate` 说的那件事:
##   **memory 靠我想起来, 门禁自己会红。**
##
## ★判据都落在**产品自己的账**上(素材字节 / 常量 / 真入口的承伤), 不数我插的标记
##   (memory `fb-gate-must-measure-requirement-not-my-hook`)。
##
## 反向验证(2026-09-10 实跑过, 每条都单独变异过一次, 见方案书「验收清单」):
##   · 把 eq010-slash.png 换回旧的 laser-slash-anim.png  ⇒ ①②④⑤⑥ 一起红
##   · 把 LASER_R_TEX 改回 53                            ⇒ ③ 红(半径画的比打的小一半)
##   · 把 `_on_line` 的半宽拆成另一个字面量 80.0          ⇒ ⑧ 红
##   · 把 `_eq_laser_sweep` 里的 `laser_fan_strike` 注释掉 ⇒ ⑩ 红(真入口零伤害)
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EQ := preload("res://scripts/systems/equip/equip_system.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(msg: String, cond: bool, extra: String = "") -> void:
	_n += 1
	if cond:
		print("  [OK] %s" % msg)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [msg, extra])


## 一张贴图的规格: (色数, 半透像素数, 不透明像素数)
func _spec(path: String) -> Array:
	var tex: Texture2D = load(path)
	if tex == null:
		return [-1, -1, -1]
	var img: Image = tex.get_image()
	var cols := {}
	var semi := 0
	var opaque := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			var a: int = int(round(c.a * 255.0))
			if a <= 0:
				continue
			if a < 255:
				semi += 1
			else:
				opaque += 1
			cols["%d_%d_%d" % [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]] = true
	return [cols.size(), semi, opaque]


## 取一格(方向 dirf, 帧 f)的不透明掩码, 返回 Image。
## ★★整图**缓存**: 斩击表是 3584×1120 = 4.0 M 像素, 而 ④⑤⑥⑦ 一共要取 31 格 ——
##   每次都 `get_image()` 就是 31 次显存→内存整表拷贝, 实测把这条门禁变成整轮里最慢的一个。
##   一张表只拷一次, 之后只 `get_region`。
var _img_cache := {}

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
	#  ① 素材规格: 四张都必须是**锁定调色板的像素画**
	# ══════════════════════════════════════════════════════════════
	print("-- 1 素材规格(色数 / 半透像素) --")
	var files := {
		"预警扇形": EQ.LASER_TEL_TEX,
		"斩击": EQ.LASER_SLASH_TEX,
		"行波条": EQ.LASER_BAR_TEX,
		"图标": "res://assets/sprites/equip/eq010-icon.png",
	}
	var checked := 0
	for name in files.keys():
		var sp: Array = _spec(String(files[name]))
		checked += 1
		_ok("① %s 存在且是像素画: %d 色(须 1~8) / %d 半透(须 0)" % [name, sp[0], sp[1]],
			sp[0] >= 1 and sp[0] <= 8 and sp[1] == 0,
			"旧素材是 595/2623/2762/21296 色 —— 色数超标或有半透 = 又贴了张渲染图")
	_ok("★分母: 查了 %d 张素材(应 4)" % checked, checked == 4)

	# ══════════════════════════════════════════════════════════════
	#  ② 预警铺满: 整片 120° 扇形, 里面不许有"更小的范围"
	# ══════════════════════════════════════════════════════════════
	print("-- 2 预警铺满整片扇形(用户 2026-09-09:「预警是告诉玩家要实际产生伤害的地区」) --")
	var cell: int = int(round(EQ.LASER_R_TEX * 2.0)) + 8   # 224
	var tel: Image = _cell(EQ.LASER_TEL_TEX, 0, 0, cell)
	var half: float = deg_to_rad(EQ.LASER_HALF_DEG)
	var cx: float = float(cell) * 0.5
	var sector := 0
	var filled := 0
	var out_of_range := 0
	## 6(径) × 8(角) 的子格, 每一格都必须被盖到 —— "整片"不能靠中间一坨撑起来
	var sub: Array = []
	for i in range(48):
		sub.append(0)
	for y in range(cell):
		for x in range(cell):
			var fx: float = (float(x) + 0.5 - cx) / EQ.LASER_R_TEX
			var fy: float = (float(y) + 0.5 - cx) / EQ.LASER_R_TEX
			var r: float = sqrt(fx * fx + fy * fy)
			var a: float = atan2(fy, fx)
			var on: bool = tel.get_pixel(x, y).a > 0.03
			if r > 1.0 or absf(a) > half:
				## ★缩图(BOX 面积平均)会在边界外渗一点点, 允许 1 像素;
				##   再多就是"画出来的范围 > 打得到的范围", 那是真缺陷。
				if on and r > 1.0 + 1.5 / EQ.LASER_R_TEX:
					out_of_range += 1
				continue
			sector += 1
			if on:
				filled += 1
				var ir: int = clampi(int(r * 6.0), 0, 5)
				var ia: int = clampi(int((a + half) / (2.0 * half) * 8.0), 0, 7)
				sub[ir * 8 + ia] = 1
	var empty := 0
	for v in sub:
		if int(v) == 0: empty += 1
	var cov: float = 100.0 * float(filled) / maxf(1.0, float(sector))
	_ok("★分母: 扇形内共 %d 像素(须 > 8000)" % sector, sector > 8000)
	_ok("② 预警覆盖率 %.1f%%(须 ≥ 55%% —— 只画几条边界线 = 面积感为零)" % cov, cov >= 55.0)
	_ok("② 预警 6×8=48 子格空 %d 个(须 0 —— 每一小块都要说'这里也打')" % empty, empty == 0)
	_ok("② 预警越界 %d 像素(须 0 —— 画得比打得大 = 站在外面的敌人白挨一次预警)" % out_of_range,
		out_of_range == 0)

	# ══════════════════════════════════════════════════════════════
	#  ③ 画的范围 == 打的范围: 贴图缩放常量 ↔ 判定常量
	# ══════════════════════════════════════════════════════════════
	print("-- 3 画多远就打多远(素材半径 ↔ pixel_size ↔ 判定半径) --")
	## 贴图里扇形半径 = LASER_R_TEX 像素; 运行时 pixel_size = rng*WS/LASER_R_TEX
	## ⇒ 画出来的半径(米) = LASER_R_TEX * pixel_size = rng*WS = 判定半径。恒等式, 但它焊住
	##   「改了 R_TEX 却没重烤素材」这类漂移: 下面直接量素材里扇形的最大半径。
	var rmax := 0.0
	var amin := 999.0
	var amax := -999.0
	for y in range(cell):
		for x in range(cell):
			if tel.get_pixel(x, y).a <= 0.03: continue
			var fx: float = float(x) + 0.5 - cx
			var fy: float = float(y) + 0.5 - cx
			rmax = maxf(rmax, sqrt(fx * fx + fy * fy))
			if sqrt(fx * fx + fy * fy) > EQ.LASER_R_TEX * 0.30:
				var a2: float = rad_to_deg(atan2(fy, fx))
				amin = minf(amin, a2); amax = maxf(amax, a2)
	_ok("③ 素材里扇形半径 %.1f px(须 = LASER_R_TEX %.0f ± 2)" % [rmax, EQ.LASER_R_TEX],
		absf(rmax - EQ.LASER_R_TEX) <= 2.0,
		"素材与常量对不上 = 画出来的半径不是判定半径")
	_ok("③ 素材里扇形全角 %.1f°(须 = LASER_ARC_DEG %.0f ± 3)" % [amax - amin, EQ.LASER_ARC_DEG],
		absf((amax - amin) - EQ.LASER_ARC_DEG) <= 3.0,
		"改了 LASER_ARC_DEG 没重烤素材 ⇒ 画一个角度、打另一个角度")

	# ══════════════════════════════════════════════════════════════
	#  ④⑤ 斩击: 领先边单调推进 + 每帧径向盖满 + 五帧并集铺满
	# ══════════════════════════════════════════════════════════════
	print("-- 4/5 斩击「从一边扫到另一边」且盖满(用户 2026-09-09 三句话) --")
	var leads: Array = []
	var thin := 0
	var un: Array = []
	for i in range(48):
		un.append(0)
	var un_px := 0
	var minmax_r: Array = []
	for f in range(EQ.LASER_SLASH_FRAMES):
		var im: Image = _cell(EQ.LASER_SLASH_TEX, 0, f, cell)
		var lead := -999.0
		var rlo := 9.0
		var rhi := -9.0
		var got := 0
		for y in range(cell):
			for x in range(cell):
				if im.get_pixel(x, y).a <= 0.03: continue
				var fx: float = (float(x) + 0.5 - cx) / EQ.LASER_R_TEX
				var fy: float = (float(y) + 0.5 - cx) / EQ.LASER_R_TEX
				var r: float = sqrt(fx * fx + fy * fy)
				var a: float = atan2(fy, fx)
				if r > 1.02 or absf(a) > half: continue
				got += 1
				un_px += 1
				lead = maxf(lead, rad_to_deg(a))
				rlo = minf(rlo, r); rhi = maxf(rhi, r)
				var ir2: int = clampi(int(r * 6.0), 0, 5)
				var ia2: int = clampi(int((a + half) / (2.0 * half) * 8.0), 0, 7)
				un[ir2 * 8 + ia2] = 1
		leads.append(lead)
		minmax_r.append([rlo, rhi])
		if got > 0 and (rlo > 0.14 or rhi < 0.94):
			thin += 1
	var mono := true
	for i in range(1, leads.size()):
		if float(leads[i]) < float(leads[i - 1]) - 0.5:
			mono = false
	var span: float = float(leads[leads.size() - 1]) - float(leads[0])
	var un_empty := 0
	for v in un:
		if int(v) == 0: un_empty += 1
	_ok("★分母: 五帧共 %d 个不透明像素(须 > 15000)" % un_px, un_px > 15000)
	_ok("④ 领先边逐帧单调推进(%.1f → %.1f → %.1f → %.1f → %.1f)"
		% [leads[0], leads[1], leads[2], leads[3], leads[4]], mono,
		"每帧都跨满全角 = 原地张开不是扫; 用户原话「没有从一边到另一边的感觉」")
	_ok("④ 领先边总共推了 %.1f°(须 ≥ 全角 %.0f° 的一半)" % [span, EQ.LASER_ARC_DEG],
		span >= EQ.LASER_ARC_DEG * 0.5, "扫的幅度太小 = 看不出是一刀扫过去")
	_ok("⑤ 每帧都径向盖满 0..R, 偏窄的帧 %d 个(须 0)" % thin, thin == 0,
		"斩痕比伤害区窄 = 玩家看见细细一道却整片掉血。逐帧 r 范围 %s" % str(minmax_r))
	_ok("⑤ 五帧并集 48 子格空 %d 个(须 0 —— 扫完整片都被切过)" % un_empty, un_empty == 0)

	# ══════════════════════════════════════════════════════════════
	#  ⑥ 消散靠碎不靠淡: 每一帧的最亮像素都得是满亮
	# ══════════════════════════════════════════════════════════════
	print("-- 6 消散靠碎开不靠变暗(旧素材第 4 帧平均亮度只有 14/255) --")
	## ★★这条判据改过一版。第一版写的是「每帧**最亮像素** ≥ 200/255」——
	##   反向验证当场证明它是**放过真 bug 的那一格**: 我把除刀刃以外的所有像素压成最暗档
	##   P[5](亮度 65) 重烤了斩击表(md5 真的变了), 门禁**照样全绿** ——
	##   因为领先边那条刀刃仍然是 P[0](247), 「最亮像素」这个量一条线就能满足。
	## ⇒ 改成量**不透明像素的平均亮度**, 而且基准取【像素最多的那一帧】而不是第 0 帧
	##   (009 那一轮的教训: 扫过式的第 0 帧只是一小片刀刃, 平均亮度天然最高,
	##    拿它当基线会把正常的扫判成变暗)。
	## 实测: 现役 219.5/163.9/151.9/151.3/146.2(最满帧 151.9 ⇒ 最低 96%);
	##       旧素材 125.8/89.1/64.8/56.2/**14.0**(最满帧 56.2 ⇒ 最低 25%)。
	var lum: Array = []
	var npx: Array = []
	for f in range(EQ.LASER_SLASH_FRAMES):
		var im2: Image = _cell(EQ.LASER_SLASH_TEX, 0, f, cell)
		var sum := 0.0
		var cnt := 0
		for y in range(cell):
			for x in range(cell):
				var c: Color = im2.get_pixel(x, y)
				if c.a <= 0.03: continue
				sum += (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * c.a * 255.0
				cnt += 1
		lum.append(sum / maxf(1.0, float(cnt)))
		npx.append(cnt)
	var fullest := 0
	for f in range(npx.size()):
		if int(npx[f]) > int(npx[fullest]): fullest = f
	var base: float = float(lum[fullest])
	var lo := 9999.0
	for v in lum:
		lo = minf(lo, float(v))
	var ratio: float = lo / maxf(1.0, base)
	_ok("★分母: 最满的是第 %d 帧(%d 像素), 平均亮度 %.1f" % [fullest, int(npx[fullest]), base],
		int(npx[fullest]) > 3000 and base > 80.0)
	_ok("⑥ 逐帧平均亮度 %s; 最低 / 最满帧 = %.0f%%(须 ≥ 70%%)"
		% [str(lum).replace("
", ""), ratio * 100.0], ratio >= 0.70,
		"靠把颜色压暗来消散 = 黑地上读成几块暗棕爪痕(fb-vfx-defect-families 的「淡出病」)")

	# ══════════════════════════════════════════════════════════════
	#  ⑦ 画的方向 == 打的方向: 16 档逐档量素材重心角 vs _ground_dir_frame
	# ══════════════════════════════════════════════════════════════
	print("-- 7 16 档方向: 素材第 k 格的朝向 == _ground_dir_frame 反算的第 k 档 --")
	var worst := 0.0
	var worst_k := -1
	var measured := 0
	for d in range(EQ.LASER_DIRS):
		var im3: Image = _cell(EQ.LASER_TEL_TEX, d, 0, cell)
		var sx := 0.0
		var sy := 0.0
		var cnt := 0
		for y in range(cell):
			for x in range(cell):
				if im3.get_pixel(x, y).a <= 0.03: continue
				sx += float(x) + 0.5 - cx
				sy += float(y) + 0.5 - cx
				cnt += 1
		if cnt < 3000:
			continue
		measured += 1
		var want: Vector2 = _s._equip_sys._laser_dir_of(d)
		var got_a: float = atan2(sy, sx)
		var dd: float = absf(rad_to_deg(wrapf(got_a - atan2(want.y, want.x), -PI, PI)))
		if dd > worst:
			worst = dd; worst_k = d
	_ok("★分母: 量到 %d 档方向(应 %d)" % [measured, EQ.LASER_DIRS], measured == EQ.LASER_DIRS)
	_ok("⑦ 素材朝向与 _laser_dir_of 最大偏差 %.2f°(第 %d 档; 须 ≤ 1.5°)" % [worst, worst_k],
		worst <= 1.5, "画的方向 ≠ 打的方向 ⇒ 敌人明明画在扇里却不掉血")

	# ══════════════════════════════════════════════════════════════
	#  ⑧ 竖劈: 条画多宽就打多宽(同一个常量)
	# ══════════════════════════════════════════════════════════════
	print("-- 8 行波条宽度 == 判定宽度(旧版画 125 码 / 打 160 码) --")
	var barc: int = 44
	var bim: Image = _cell(EQ.LASER_BAR_TEX, 0, 1, barc)   # 第 1 帧 = 波前(实心)
	var bcx: float = float(barc) * 0.5
	var hw_px := 0.0
	for y in range(barc):
		for x in range(barc):
			if bim.get_pixel(x, y).a <= 0.03: continue
			hw_px = maxf(hw_px, absf(float(y) + 0.5 - bcx))   # 第 0 档方向朝 +x ⇒ 条宽在 y 上
	## 素材半宽 (px) × 运行时 pixel_size = 判定半宽(米)
	var drawn_m: float = hw_px * (EQ.LASER_CHOP_HALF_W * _s.WS / EQ.LASER_BAR_HW_TEX)
	var hit_m: float = EQ.LASER_CHOP_HALF_W * _s.WS
	_ok("⑧ 条画出来半宽 %.2f 米 vs 判定半宽 %.2f 米(误差须 ≤ 6%%)" % [drawn_m, hit_m],
		absf(drawn_m - hit_m) <= hit_m * 0.06,
		"素材里半宽 %.1f px 与 LASER_BAR_HW_TEX %.0f 对不上" % [hw_px, EQ.LASER_BAR_HW_TEX])

	# ══════════════════════════════════════════════════════════════
	#  ⑨ 竖劈结算是**纯几何 + 同步**, 不依赖任何演出 tween
	# ══════════════════════════════════════════════════════════════
	print("-- 9 竖劈判定: 逐格量落点(CLAUDE.md §3.5 不许依赖 tween) --")
	var o0: Vector2 = Vector2(0.0, 0.0)
	var dr: Vector2 = Vector2.RIGHT
	var probes: Array = [
		{"pos": Vector2(120.0, 0.0), "alive": true},      # 走廊内, 第 3 格
		{"pos": Vector2(120.0, EQ.LASER_CHOP_HALF_W - 4.0), "alive": true},   # 贴着边界内侧
		{"pos": Vector2(120.0, EQ.LASER_CHOP_HALF_W + 8.0), "alive": true},   # 边界外
		{"pos": Vector2(-40.0, 0.0), "alive": true},      # 身后
	]
	var slab_all: Array = _s._equip_sys.laser_chop_slab(o0, dr, 0.0, 400.0, probes)
	_ok("⑨ 走廊 0~400 码内命中 %d 个(应 2: 轴上 + 贴边内侧; 边界外与身后都不算)" % slab_all.size(),
		slab_all.size() == 2, "边界判据没卡住 ±LASER_CHOP_HALF_W")
	var slab_near: Array = _s._equip_sys.laser_chop_slab(o0, dr, 0.0, 96.0, probes)
	_ok("⑨ 只推到 96 码时命中 %d 个(应 0 —— 波前没到就不许结算)" % slab_near.size(),
		slab_near.size() == 0, "推进与结算不是同一条时钟")

	# ══════════════════════════════════════════════════════════════
	#  ⑪ 行波条正好铺满 [0, reach]: 不越界、不留缝
	# ══════════════════════════════════════════════════════════════
	print("-- 11 行波条铺满走廊且不越出 reach --")
	## ★这条是这一轮**我自己看代码时抓到的**: 原来条心是 `(i+0.5)×LASER_BAR_STEP`,
	##   reach=200 时第 5 条心落在 216、外缘 240 —— 画出来比打得到的长 40 码(20%)。
	##   抽成 `laser_bar_positions` 之后演出与门禁共用同一份落位。
	var half_t: float = EQ.LASER_BAR_STEP * 0.5   # 条半厚 = 步长的一半(素材 BAR_THICK 就是这么烤的)
	var worst_over := 0.0
	var worst_gap := 0.0
	var reaches: Array = [200.0, 380.0, 900.0]
	for R in reaches:
		var ps: Array = _s._equip_sys.laser_bar_positions(float(R))
		if ps.is_empty(): continue
		var stp: float = float(R) / float(ps.size())
		var near: float = float(ps[0]) - stp * 0.5
		var far: float = float(ps[ps.size() - 1]) + stp * 0.5
		worst_over = maxf(worst_over, maxf(absf(near), absf(far - float(R))))
		for i in range(1, ps.size()):
			worst_gap = maxf(worst_gap, float(ps[i]) - float(ps[i - 1]) - EQ.LASER_BAR_STEP)
	_ok("★分母: 量了 %d 种 reach %s" % [reaches.size(), str(reaches)], reaches.size() == 3)
	_ok("⑪ 整排两端与 [0, reach] 的最大偏差 %.2f 码(须 ≤ 1)" % worst_over, worst_over <= 1.0,
		"画出来的走廊比判定长/短 = 又一次「画的和打的不是一回事」")
	_ok("⑪ 条与条最大缝隙 %.2f 码(须 ≤ 0 —— 只许重叠不许留缝)" % worst_gap, worst_gap <= 0.0)

	# ══════════════════════════════════════════════════════════════
	#  ⑩ 真入口: 走 _tick_laser → _eq_laser_sweep, 敌人真的掉血
	#     (断言函数存在守不住"还有没有人调" —— memory fb-verify-must-run-the-real-path)
	# ══════════════════════════════════════════════════════════════
	print("-- 10 真入口 _tick_laser → _eq_laser_sweep: 敌人真的吃到伤害 --")
	print("     [探针] 清场前 _s._units = %d 个" % _s._units.size())
	_s._units.clear()
	var c2: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	## ★★携带者必须是一个**只会放 010** 的平台 —— 三样都要关:
	##   `no_basic`(普攻) / `no_move`(走位) / **`active_skills = []`(龟能技)**。
	##   漏掉最后一样是**这一轮反向验证抓到的真事**: 我把 `laser_fan_strike` 从
	##   `_eq_laser_sweep` 里拿掉(接线断了), 这条断言**照样绿** ——
	##   因为 `basicBarrage` 一直在往 `_st_taken` 里加账, 我量的是"敌人掉血了"
	##   而不是"010 打的"。判据要量被测那件事的账(memory fb-make-the-noise-deterministic)。
	var carrier: Dictionary = _s._spawn._make_unit("basic", "left", c2 + Vector2(-200.0, 0.0))
	carrier["no_basic"] = true
	carrier["no_move"] = true
	carrier["move_spd"] = 0.0
	carrier["active_skills"] = []
	carrier["equips"] = [{"id": "p2eq_010", "star": 3}]
	carrier["eq_state"] = {}
	carrier["atk_interval"] = 0.4   # 让 _tick_laser 早点满
	_s._units.append(carrier)
	var foe: Dictionary = _s._spawn._make_unit("basic", "right", c2 + Vector2(60.0, 0.0))
	foe["maxHp"] = 1.0e8
	foe["hp"] = 1.0e8
	foe["_st_taken"] = 0
	foe["no_move"] = true
	foe["move_spd"] = 0.0
	_s._units.append(foe)
	var before: int = int(foe.get("_st_taken", 0))
	_ok("★分母: 场上 %d 个单位(应 2), 敌人在 %.0f 码处(< 3★半径 %.0f)"
		% [_s._units.size(), (foe["pos"] as Vector2).distance_to(carrier["pos"]),
			_s._equip_sys.laser_fan_range(carrier, 2)],
		_s._units.size() == 2 and (foe["pos"] as Vector2).distance_to(carrier["pos"])
			< _s._equip_sys.laser_fan_range(carrier, 2))
	## ★★对照组: 同一个平台**不带 010**, 推同样长的窗口 —— 它必须一点伤害都打不出来。
	##   没有这一条就证明不了"上面那条量的是 010", 只能证明"有东西打了它"。
	carrier["equips"] = []
	var ctrl_end: int = Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < ctrl_end:
		_s._equip_tick_sys._tick_laser(carrier, 0.05)
		await get_tree().process_frame
	var ctrl: int = int(foe.get("_st_taken", 0)) - before
	_ok("⑩ 对照组(不带 010)承伤 %d(须 = 0 —— 否则这个台子上还有别的伤害源)" % ctrl, ctrl == 0,
		"普攻/龟能技没关干净, 下面那条就量不到被测那件事")
	carrier["equips"] = [{"id": "p2eq_010", "star": 3}]
	carrier["eq_state"] = {}
	before = int(foe.get("_st_taken", 0))
	## ★用**墙钟**当上限(CLAUDE.md §3.5: 帧数/游戏钟都不能当尺子)
	var t_end: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < t_end:
		_s._equip_tick_sys._tick_laser(carrier, 0.05)
		await get_tree().process_frame
		if int(foe.get("_st_taken", 0)) > before:
			break
	var dealt: int = int(foe.get("_st_taken", 0)) - before
	## 3★ 扇形斩 = atk×8 + 200 ⇒ 光底伤就 200; 门槛卡在 150 = 只有 010 打得出来
	print("     [探针] 真入口承伤 +%d(3★ 底伤 200, 门槛 150)" % dealt)
	_ok("⑩ 真入口打出 %d 点伤害(须 ≥ 150 = 只有 010 的量级)" % dealt, dealt >= 150,
		"0 = 接线断了(_tick_laser 没到 _eq_laser_sweep, 或 _eq_laser_sweep 没调 laser_fan_strike)")

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 010 激光长刃" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
