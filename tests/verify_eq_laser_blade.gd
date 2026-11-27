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
## ★2026-11-27 画面整体重做(旧 16 向序列帧删掉, 改着色器网格 + 灰度贴图粒子, scripts/scenes/battle/laser_blade_vfx.gd):
##   ①~⑧ 从「量序列帧像素」换成「量真画出来的网格」—— 扇形网格半径 / 张角 / 16 档朝向 == 判定, 光带宽 == 判定宽。
## ★判据都落在**产品自己的账**上(素材字节 / 常量 / 真入口的承伤与承伤时刻), 不数我插的标记
##   (memory `fb-gate-must-measure-requirement-not-my-hook`)。
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


## 节点上网格的全部顶点, 按节点自己的 transform 摆到世界里(位置 + 朝向)
func _verts_world(n: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var arr: Array = n.mesh.surface_get_arrays(0)
	for v in arr[Mesh.ARRAY_VERTEX]:
		out.append(n.transform * v)
	return out


## 这次调用新挂上的那一条画面记录(k = fan / scorch_fan / beam)
func _new_live(fx, before: int, k: String) -> Dictionary:
	for i in range(before, fx._live.size()):
		if String(fx._live[i].get("k", "")) == k:
			return fx._live[i]
	return {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true   # 台子绝不写玩家存档(memory fb-debug-stage-writes-real-save)
	_s = RB.new()
	add_child(_s)
	## ★★开**确定性模式**(2026-09-24): 每帧恰跑**一步** SIM_DT。
	##   ⑪ 拿「三个敌人各自掉血的时刻」反推推进速度, 而采样在**引擎帧**循环里:
	##   本地一帧≈1 步 ⇒ 量得准; 15fps 一帧 **4 步** ⇒ 两个命中可能落在同一帧、
	##   拿到同一个时刻, 首尾时间差塔缩 ⇒ 超出 3 步的容差。
	##   (与饱血连斩 ⑪ 同一个形状: **采样分辨率比被测的节拍还粗**。)
	_s._deterministic = true
	await get_tree().process_frame
	await get_tree().process_frame

	print("")
	print("═══ 010 激光长刃 · 素材/演出/接线 ═══")

	# ══════════════════════════════════════════════════════════════
	#  ① 素材: 图标 64×64; 特效贴图都是**灰度形状图**(颜色由引擎上色), 旧序列帧删干净
	# ══════════════════════════════════════════════════════════════
	print("-- 1 素材 --")
	var icon: Image = (load("res://assets/sprites/equip/eq010-icon.png") as Texture2D).get_image()
	var icon_cols := {}
	var icon_px := 0
	for y in range(icon.get_height()):
		for x in range(icon.get_width()):
			var ic: Color = icon.get_pixel(x, y)
			if ic.a <= 0.0:
				continue
			icon_px += 1
			icon_cols[ic.to_html(false)] = true
	_ok("① 图标 %dx%d(须 64x64) / %d 个不透明像素(须 > 500) / %d 色(须 8~32)" % [icon.get_width(), icon.get_height(), icon_px, icon_cols.size()],
		icon.get_width() == 64 and icon.get_height() == 64 and icon_px > 500 and icon_cols.size() >= 8 and icon_cols.size() <= 32,
		"不是 64 像素 / 几乎是空的 / 色数像渲染图")
	var grey_ok := 0
	var tex_names := ["spindle", "spindle_v", "flare", "ring", "burst"]
	for tn in tex_names:
		var tp: String = "res://assets/sprites/vfx/eq010/%s.png" % tn
		if not ResourceLoader.exists(tp):
			_ok("① 特效贴图 %s 存在" % tp, false)
			continue
		var ti: Image = (load(tp) as Texture2D).get_image()
		var colored := 0
		var lit := 0
		for y in range(ti.get_height()):
			for x in range(ti.get_width()):
				var tc: Color = ti.get_pixel(x, y)
				if tc.a <= 0.01:
					continue
				lit += 1
				if absf(tc.r - tc.g) > 0.02 or absf(tc.g - tc.b) > 0.02:
					colored += 1
		_ok("① %s: %d 个有色像素(须 0 = 灰度, 引擎上色) / %d 个亮像素(须 > 100)" % [tn, colored, lit], colored == 0 and lit > 100)
		if colored == 0 and lit > 100:
			grey_ok += 1
	_ok("★分母: 灰度贴图过了 %d 张(应 %d)" % [grey_ok, tex_names.size()], grey_ok == tex_names.size())
	var left: Array = []
	for lp in ["eq010-slash", "eq010-wave", "eq010-chop", "eq010-tel", "eq010-bar"]:
		if ResourceLoader.exists("res://assets/sprites/vfx/%s.png" % lp):
			left.append(lp)
	_ok("①b 旧序列帧 / 预警素材已删干净(残留 %d 张)" % left.size(), left.is_empty(),
		"残留: %s —— 010 没有预警(用户 2026-09-10), 旧序列帧不许再被谁拿去贴" % str(left))

	# ══════════════════════════════════════════════════════════════
	#  ②③ 画的范围 == 打的范围: 扇形网格半径 / 张角 ↔ 判定常量
	#  ⑦ 画的方向 == 打的方向: 16 档逐档量网格重心角
	# ══════════════════════════════════════════════════════════════
	print("-- 2/3/7 扇形网格 == 判定(半径 / 张角 / 16 档朝向) --")
	var fx = _s._equip_sys.laser_fx()
	var org0: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var rng0: float = 450.0
	var arc0: float = deg_to_rad(EQ.LASER_ARC_DEG)
	var worst := 0.0
	var worst_k := -1
	var measured := 0
	var r_err := 0.0
	var arc_err := 0.0
	var scorch_same := true
	for d in range(EQ.LASER_DIRS):
		var dir0: Vector2 = _s._equip_sys._laser_dir_of(d)
		var before: int = fx._live.size()
		fx.sweep(org0, dir0, rng0, arc0, [])
		var lf: Dictionary = _new_live(fx, before, "fan")
		var ls: Dictionary = _new_live(fx, before, "scorch_fan")
		if lf.is_empty() or ls.is_empty():
			continue
		measured += 1
		var fan_n: MeshInstance3D = lf["node"]
		var c0: Vector3 = fan_n.position
		var vs: PackedVector3Array = _verts_world(fan_n)
		var rmax := 0.0
		var amin := 999.0
		var amax := -999.0
		var cen := Vector2.ZERO
		var dang: float = atan2(dir0.y, dir0.x)
		for v in vs:
			var rel := Vector2(v.x - c0.x, v.z - c0.z)
			var rr: float = rel.length()
			rmax = maxf(rmax, rr)
			cen += rel
			if rr > 0.01:
				var av: float = rad_to_deg(wrapf(atan2(rel.y, rel.x) - dang, -PI, PI))
				amin = minf(amin, av)
				amax = maxf(amax, av)
		var dev: float = absf(rad_to_deg(wrapf(atan2(cen.y, cen.x) - dang, -PI, PI)))
		if dev > worst:
			worst = dev
			worst_k = d
		r_err = maxf(r_err, absf(rmax - rng0 * _s.WS))
		arc_err = maxf(arc_err, absf((amax - amin) - EQ.LASER_ARC_DEG))
		## 地面熔痕与刃是同一块扇形(同半径 / 同朝向), 只是贴地
		var sc_n: MeshInstance3D = ls["node"]
		var sv: PackedVector3Array = _verts_world(sc_n)
		var srmax := 0.0
		for v in sv:
			srmax = maxf(srmax, Vector2(v.x - sc_n.position.x, v.z - sc_n.position.z).length())
		if absf(srmax - rmax) > 0.01 or absf(sc_n.rotation.y - fan_n.rotation.y) > 0.001 or sc_n.position.y > fan_n.position.y:
			scorch_same = false
	_ok("★分母: 量到 %d 档方向(应 %d)" % [measured, EQ.LASER_DIRS], measured == EQ.LASER_DIRS)
	_ok("③ 扇形网格半径与判定半径 %.0f 码 × WS 最大差 %.3f 米(须 ≤ 0.02)" % [rng0, r_err], measured > 0 and r_err <= 0.02,
		"画出来的半径不是判定半径")
	_ok("③ 扇形网格全角与 LASER_ARC_DEG %.0f° 最大差 %.2f°(须 ≤ 0.5)" % [EQ.LASER_ARC_DEG, arc_err], measured > 0 and arc_err <= 0.5,
		"改了 LASER_ARC_DEG 画面没跟 ⇒ 画一个角度、打另一个角度")
	_ok("⑦ 扇形网格朝向与 _laser_dir_of 最大偏差 %.2f°(第 %d 档; 须 ≤ 0.5°)" % [worst, worst_k], measured > 0 and worst <= 0.5,
		"画的方向 ≠ 打的方向 ⇒ 敌人明明画在扇里却不掉血")
	_ok("②b 地面熔痕 = 同半径同朝向的贴地扇形(16 档都对)", measured > 0 and scorch_same)

	# ══════════════════════════════════════════════════════════════
	#  ④⑤⑥ 节拍: 刃扫完 120° 在结算等待的 0.25 秒以内; 命中特效按刃扫到那人的时刻出
	# ══════════════════════════════════════════════════════════════
	print("-- 4/5/6 节拍 --")
	var wait_sec: float = EQ.LASER_SLASH_FRAMES * EQ.LASER_SLASH_STEP
	var sweep_sec: float = fx._t_of_prog(1.0)
	_ok("④ 刃扫完全角用 %.3f 秒(须 0.05~%.2f = 结算那边扇形斩之后等的时长)" % [sweep_sec, wait_sec],
		sweep_sec >= 0.05 and sweep_sec <= wait_sec, "太快看不出扫 / 太慢则追斩起手时扇形还没扫完")
	_ok("⑤ 扇形画面寿命 FAN_LIFE %.3f == 结算等待 %.3f" % [fx.FAN_LIFE, wait_sec], absf(fx.FAN_LIFE - wait_sec) < 0.001)
	var mono := true
	var prev_t := -1.0
	for k in range(11):
		var tk: float = fx._t_of_prog(float(k) / 10.0)
		if tk < prev_t - 1e-6:
			mono = false
		prev_t = tk
	_ok("⑥ 刃的推进单调(扫到 -60° 的人先亮, +60° 的人后亮)", mono and fx._t_of_prog(0.0) <= 0.001)

	# ══════════════════════════════════════════════════════════════
	#  ⑧ 直线追斩光带: 画多宽就打多宽, 画多远至少推多远, 朝向 == 打的方向
	# ══════════════════════════════════════════════════════════════
	print("-- 8 光带 == 判定 --")
	var bdir: Vector2 = _s._equip_sys._laser_dir_of(3)
	var before_b: int = fx._live.size()
	var bh: Dictionary = fx.chop_begin(org0, bdir, 300.0, EQ.LASER_CHOP_SPEED, EQ.LASER_CHOP_HALF_W)
	var lb: Dictionary = _new_live(fx, before_b, "beam")
	_ok("★分母: 光带挂上了", not lb.is_empty())
	if not lb.is_empty():
		var bn: MeshInstance3D = lb["node"]
		var bc: Vector3 = bn.position
		var bang: float = atan2(bdir.y, bdir.x)
		var along_max := 0.0
		var side_max := 0.0
		for v in _verts_world(bn):
			var rel := Vector2(v.x - bc.x, v.z - bc.z)
			along_max = maxf(along_max, rel.dot(bdir))
			side_max = maxf(side_max, absf(rel.dot(Vector2(-bdir.y, bdir.x))))
		var hit_hw: float = EQ.LASER_CHOP_HALF_W * _s.WS
		_ok("⑧ 光带半宽 %.3f 米 vs 判定半宽 %.3f 米(差须 ≤ 0.02)" % [side_max, hit_hw], absf(side_max - hit_hw) <= 0.02,
			"画多宽 ≠ 打多宽(旧版画 125 码 / 打 160 码)")
		_ok("⑧ 光带长 %.2f 米 ≥ 推进距离 %.2f 米" % [along_max, 300.0 * _s.WS], along_max >= 300.0 * _s.WS - 0.01)
		_ok("⑧ 光带波前速度 %.0f == LASER_CHOP_SPEED %.0f(画面和结算同一个速度)" % [float(lb["speed"]), EQ.LASER_CHOP_SPEED],
			absf(float(lb["speed"]) - EQ.LASER_CHOP_SPEED) < 0.01)
	fx.chop_end(bh)

	# ══════════════════════════════════════════════════════════════
	#  ⑧b 落刃: 波是被劈出来的(用户 11-27「竖劈的时候没有东西劈下来…是有东西劈出这波来的」)
	#      只命中 1 人 ⇒ 扇形斩那边就举刃; 刃尖落地那一刻 == 推波那一刻; 刃尖贴地不钻地; 劈的竖面 == 结算方向; 从上往下劈
	# ══════════════════════════════════════════════════════════════
	print("-- 8b 落刃 --")
	var t_sw: float = _s._t
	var before_s: int = fx._live.size()
	fx.sweep(org0, Vector2.RIGHT, rng0, arc0, [{"pos": org0 + Vector2(200.0, 30.0), "height": 0.0}])
	var lsw: Dictionary = _new_live(fx, before_s, "swing")
	_ok("★分母: 只命中 1 人 ⇒ 扇形斩时就举起了落刃", not lsw.is_empty())
	var before_n: int = fx._live.size()
	fx.sweep(org0, Vector2.RIGHT, rng0, arc0, [{"pos": org0 + Vector2(200.0, 30.0)}, {"pos": org0 + Vector2(200.0, -30.0)}])
	_ok("⑧b 命中 2 人(不追加直线斩) ⇒ 不举刃", _new_live(fx, before_n, "swing").is_empty())
	if not lsw.is_empty():
		_ok("⑧b 举刃时刻 = 扇形斩后 %.3f 秒(须 = FAN_LIFE - SWING_SEC = %.3f)" % [float(lsw["t0"]) - t_sw, fx.FAN_LIFE - fx.SWING_SEC],
			absf(float(lsw["t0"]) - t_sw - (fx.FAN_LIFE - fx.SWING_SEC)) < 0.001)
		var cdir: Vector2 = _s._equip_sys._laser_dir_of(1)   # 与举刃时的预瞄方向(朝靶子)不同 ⇒ 量的是摆正之后
		var bh2: Dictionary = fx.chop_begin(org0, cdir, 300.0, EQ.LASER_CHOP_SPEED, EQ.LASER_CHOP_HALF_W)
		_ok("⑧b 推波时用上了这把刃", bool(lsw["used"]))
		_ok("⑧b 刃尖落地时刻 %.4f == 推波时刻 %.4f" % [float(lsw["t0"]) + fx.SWING_SEC, _s._t],
			absf(float(lsw["t0"]) + fx.SWING_SEC - _s._t) < 0.0005, "落地和推波对不上 = 波不是被劈出来的")
		var sn: MeshInstance3D = lsw["node"]
		var arr: Array = sn.mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var vw: PackedVector3Array = _verts_world(sn)
		var miny := 999.0
		var maxy := -999.0
		var low := Vector3.ZERO
		var y_start := 0.0
		var y_end := 0.0
		var n_s := 0
		var n_e := 0
		for i in range(vw.size()):
			var v: Vector3 = vw[i]
			if v.y < miny:
				miny = v.y
				low = v
			maxy = maxf(maxy, v.y)
			if uvs[i].x < 0.001:
				y_start += v.y
				n_s += 1
			elif uvs[i].x > 0.999:
				y_end += v.y
				n_e += 1
		var lrel := Vector2(low.x - sn.position.x, low.z - sn.position.z)
		var ldev: float = absf(rad_to_deg(wrapf(atan2(lrel.y, lrel.x) - atan2(cdir.y, cdir.x), -PI, PI)))
		_ok("⑧b 刃尖最低点离地 %.3f 米(须 -0.01~0.05: 砸到地面, 不钻地)" % miny, miny >= -0.01 and miny <= 0.05)
		_ok("⑧b 刃举起最高 %.2f 米(须 ≥ 1.5 = 从头顶劈下来)" % maxy, maxy >= 1.5)
		_ok("⑧b 落刃竖面朝向与结算方向偏差 %.2f°(须 ≤ 0.5)" % ldev, ldev <= 0.5)
		_ok("⑧b 从上往下劈: 起刃那边平均高 %.2f 米 > 落地那边 %.2f 米" % [y_start / maxf(1.0, n_s), y_end / maxf(1.0, n_e)],
			n_s > 0 and n_e > 0 and y_start / n_s > y_end / n_e + 1.0)
		fx.chop_end(bh2)

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

	## ⑨b **竖劈推多远 == 扇形罩多远**(用户 2026-09-10 拍板:「让竖劈跟上扇形」)。
	##   改之前是两个各算一份的公式: 扇形 `射程×2 + 250`、竖劈 `射程×2` ——
	##   小龟 3★ 扇形 450 而波只推 200, 打 200 码开外的孤立敌人波够不着。
	##   ⇒ 判据落在【两个数相等】, 谁再各算一份当场红。
	##   ★这里用**本地合成单位**: ⑨ 跑在 ⑩ 建携带者之前, 而且这条本来就只跟射程/近战有关。
	var probe_u := {"atk_range": 100.0, "melee": true, "alive": true}
	for star_i in [0, 1, 2]:
		var fr: float = _s._equip_sys.laser_fan_range(probe_u, star_i)
		var cr: float = _s._equip_sys.laser_chop_reach(probe_u, star_i)
		_ok("⑨b %d★ 竖劈 reach %.0f == 扇形半径 %.0f" % [star_i + 1, cr, fr], absf(cr - fr) < 0.01,
			"两个数各算一份 = 画到 450 却只推 200, 远处那一刀白斩")

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
			_s._equip_sys.laser_chop_reach(carrier, 2)],
		_s._units.size() == 2 and foe_d < _s._equip_sys.laser_fan_range(carrier, 2)
			and foe_d < _s._equip_sys.laser_chop_reach(carrier, 2))
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
	_s._equip_sys._eq_laser_chop(cr2, 2, cr2["pos"], Vector2.RIGHT, reach2)
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
