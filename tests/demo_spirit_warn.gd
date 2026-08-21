extends Node
## demo_spirit_warn.gd — 【验收场景 A6】触手预警区: 敌我异色 + 保持到命中才消失
##
## 用户 2026-08-20 原话:
##   「一个是预警区，必须要生成精美的蓝色（如果对方则红色）像素风图案动画
##     知道拍击命中时才消失」
##
## 本场景【开箱即用】, 启动就能看:
##   · **左右各一只带灵物的龟** ⇒ 屏幕上**同时**出现两条预警带
##       我方(左) = 蓝  ·  敌方(右) = 红   ← 同屏才比得出来, 分开看会自欺
##   · 每条带子各配自己的假人(站桩·不还手·不死), 所以两边都会真的拍下去
##   · 屏幕左上角实时显示: 两条带子的**真实顶点色**与可见性、以及"命中那一刻带子还在不在"
##
## ★★两个"判据会骗我"的堵口:
##   ① 颜色**从已建好的网格里读顶点色**(`warn_color_of`), 不是回读 `WARN_COL_ALLY` 常量 ——
##      回读常量只能证明"我写了个蓝常量", 证明不了屏幕上那条是蓝的。
##   ② "保持到命中"要在**命中那一帧**采样, 不能事后问 —— 特效早没了再问永远是"不在"。
##      ⇒ 每帧记录"本次拍击里带子最后一次可见是在 SLAM 的第几秒", 与 `T_TOUCH` 对比。
##
## 怎么跑:
##   <godot> --path . res://tests/demo_spirit_warn.tscn
##   WARN_SECS=30  跑多少秒(默认 30, 够看 4~5 轮拍击)

const SPIRIT_IDS := ["p2eq_032", "p2eq_025"]
const ST_NAME := ["出土", "待机", "蓄势", "拍下", "起身", "搬家", "预警"]

var _scn = null
var _t0 := 0.0
var _lab: Label = null
## 每侧: 本次拍击中"带子最后一次可见"发生在 ST_SLAM 的第几秒(-1 = 这次还没进 SLAM)
var _last_vis_ts := {"left": -1.0, "right": -1.0}
var _best_vis_ts := {"left": -1.0, "right": -1.0}
var _slams := {"left": 0, "right": 0}
var _prev_state := {"left": -1, "right": -1}


func _env_f(k: String, d: float) -> float:
	return float(OS.get_environment(k)) if OS.has_environment(k) else d


func _ready() -> void:
	await get_tree().process_frame
	## ★★验收场景一律强制 `test_mode` —— **窗口模式下它默认是 false, 会写真存档**
	##   (headless 才自动开; 见 `GameState.gd:912`)。2026-08-21 我跑了一次带窗口的 demo,
	##   往 `match_history` 写进一条对局记录, `verify_ui_consistency` 当场红。
	##   铁律: 测试/演示不许污染玩家存档。
	## ★★验收场景【不判胜负】—— `NOVERDICT` 走的是 `_check_end` 里那道守卫。
	##   由来(2026-08-21 用户实拍截图): `demo_spirit_stacks` 阶段①要"场上一个敌人都没有"
	##   才演得出"射程内没敌人就只攒不放", 结果正好撞上「敌方全灭 = 胜利」⇒
	##   演到一半弹出「胜利」结算屏把画面全盖住了。
	## ⚠ 不借 `VFXPREVIEW`: 那个开关会连带开一整套技能预览并改相机 fov(battle_vfx.gd:603)。
	## ⚠ 也不新增成员变量: 上帝文件有行数预算(`tools/arch_budget.py`), 改已有那行守卫净增 0 行。
	OS.set_environment("NOVERDICT", "1")
	var _gs = get_node_or_null("/root/GameState")
	if _gs != null:
		_gs.test_mode = true
	get_tree().root.size = Vector2i(1280, 720)
	_scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_scn)
	await get_tree().process_frame
	await get_tree().process_frame

	for u in _scn._units.duplicate():
		var sp = u.get("sprite", null)
		if sp != null and is_instance_valid(sp):
			sp.queue_free()
	_scn._units.clear()

	## ★两边【各配一只带灵物的携带者】—— 只配一边就只有一条带子, 比不出异色。
	for side in ["left", "right"]:
		var s: String = str(side)
		var root: Vector2 = _scn._tentacle_vfx.default_root(s, 0)
		# 携带者站在自己触手根部附近, 站桩不攻击不死
		var carrier: Dictionary = _scn._spawn._make_unit(
			"basic", s, Vector2(root.x + (-130.0 if s == "left" else 130.0), root.y - 150.0))
		carrier["no_move"] = true
		carrier["no_basic"] = true
		carrier["move_spd"] = 0.0
		carrier["active_skills"] = []
		carrier["deathfloor_until"] = 999999.0
		var eqs: Array = []
		for i in range(SPIRIT_IDS.size()):
			eqs.append({"id": SPIRIT_IDS[i], "star": 1})
		carrier["equips"] = eqs
		_scn._units.append(carrier)

		## 给这条触手配一个【对面阵营】的假人站在它射程内 ⇒ 它才会真的拍。
		var foe_side: String = "right" if s == "left" else "left"
		var d: Dictionary = _scn._spawn._make_unit("basic", foe_side,
			Vector2(root.x + (230.0 if s == "left" else -230.0), root.y))
		d["no_move"] = true
		d["no_basic"] = true
		d["move_spd"] = 0.0
		d["active_skills"] = []
		d["base_def"] = 0.0
		d["base_mr"] = 0.0
		_scn._recalc_stats(d)
		d["maxHp"] = 900000.0
		d["hp"] = 900000.0
		d["deathfloor_until"] = 999999.0
		_scn._units.append(d)

	## ★★必须先 `clear()` 再 `apply_all()` —— `apply_all` 里有一道 `is_empty()` 守卫,
	##   缓存非空就**不重算**。战斗启动时已按默认队算过一次 ⇒ 我换掉的阵容会被忽略。
	##   实测症状: 敌方档位 = 0、右边那条触手压根不出现(A6 场景第一版就栽在这)。
	##   左边"碰巧"能用只是因为默认左队没羁绊、缓存正好是空的 —— 那是运气不是正确。
	##   正规顺序见 `dual_lane_flow.gd:540`(换路时就是 clear + apply_all)。
	_scn._synergy.clear()
	_scn._synergy.apply_all()
	var tl: int = _scn._spirit_syn._side_tier("left")
	var tr: int = _scn._spirit_syn._side_tier("right")
	print("  ★分母自证: 灵物档位 我方=%d 敌方=%d (任一为 0 就少一条带子, 比不出异色)" % [tl, tr])
	_mk_hud()
	print("=== 【验收场景 A6】预警区: 敌我异色 + 保持到命中才消失 ===")
	print("  两条带子【同屏】: 我方(左)应为蓝、敌方(右)应为红")
	print("  ★颜色是从**已建好的网格顶点色**里读的, 不是回读常量")
	print("  ★「保持到命中」= 带子最后一次可见的时刻 ≥ 落地时刻 T_TOUCH(%.2fs)"
		% float(_scn._tentacle_vfx.T_TOUCH))
	print("")
	_t0 = float(Time.get_ticks_msec()) / 1000.0


func _mk_hud() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 90
	add_child(cl)
	var pan := PanelContainer.new()
	pan.position = Vector2(14, 12)
	cl.add_child(pan)
	_lab = Label.new()
	_lab.add_theme_font_size_override("font_size", 18)
	pan.add_child(_lab)


## 这个颜色读起来是"蓝"还是"红"—— 用真实分量比, 不是拿名字对名字。
func _hue_name(c: Color) -> String:
	if c.a <= 0.001:
		return "无带子"
	if c.b > c.r + 0.2:
		return "蓝"
	if c.r > c.b + 0.2:
		return "红"
	return "★分不出(r=%.2f b=%.2f)" % [c.r, c.b]


func _process(_dt: float) -> void:
	if _scn == null or _lab == null:
		return
	var el: float = float(Time.get_ticks_msec()) / 1000.0 - _t0
	var tv = _scn._tentacle_vfx
	var lines := PackedStringArray()
	lines.append("【A6 预警区】%.1fs   落地时刻 T_TOUCH=%.2fs" % [el, float(tv.T_TOUCH)])
	for side in ["left", "right"]:
		var s: String = str(side)
		var st: int = int(tv.state_of(s, 0))
		var vis: bool = bool(tv.warn_visible_of(s, 0))
		var col: Color = tv.warn_color_of(s, 0)
		## ★★"保持到命中"必须在【拍击进行中】逐帧记, 事后问永远是"不在"。
		##   ST_SLAM=3 期间每见到一次带子, 就把"最后可见时刻"往后推。
		if st == 3:
			if int(_prev_state[s]) != 3:
				_last_vis_ts[s] = -1.0            # 新的一次拍击, 重新计
				_slams[s] = int(_slams[s]) + 1
			if vis:
				_last_vis_ts[s] = float(tv.slam_ts_of(s, 0))
		elif int(_prev_state[s]) == 3:
			# 这次拍击刚结束 —— 结算本次的"最后可见时刻"
			_best_vis_ts[s] = float(_last_vis_ts[s])
		_prev_state[s] = st
		lines.append("%s  触手=%-4s  带子=%s  颜色=%s(r%.2f g%.2f b%.2f)" % [
			"我方(左)" if s == "left" else "敌方(右)",
			ST_NAME[clampi(st, 0, 6)], "在" if vis else "没了",
			_hue_name(col), col.r, col.g, col.b])
		lines.append("        已拍 %d 次 · 上次拍击中带子撑到 SLAM+%.2fs %s" % [
			int(_slams[s]), float(_best_vis_ts[s]),
			"✓够到命中" if float(_best_vis_ts[s]) >= float(tv.T_TOUCH) - 0.03
				else ("(还没拍完)" if float(_best_vis_ts[s]) < 0.0 else "★早撤了")])
	_lab.text = "\n".join(lines)

	if el >= _env_f("WARN_SECS", 30.0):
		print("  ── 收尾自证 ──")
		var okc := true
		for side in ["left", "right"]:
			var s2: String = str(side)
			var c2: Color = tv.warn_color_of(s2, 0)
			var want: String = "蓝" if s2 == "left" else "红"
			var got: String = _hue_name(c2)
			print("  %s 拍了 %d 次 · 带子撑到 SLAM+%.2fs (落地 %.2fs) · 颜色=%s(要 %s)" % [
				"我方(左)" if s2 == "left" else "敌方(右)", int(_slams[s2]),
				float(_best_vis_ts[s2]), float(tv.T_TOUCH), got, want])
			## ★颜色必须**喂进结论** —— 第一版只把它打印出来, 反向验证(敌我对调)时
			##   屏幕上明明写着「颜色=红(要 蓝)」, 结论却还是「两侧都通过」。
			##   打印 != 判据 (memory [[fb-judge-must-fit-the-shape]])。
			if got != want:
				okc = false
			if int(_slams[s2]) <= 0:
				print("    ★分母不足: 这一侧一次都没拍, 上面的数字不算数")
				okc = false
			if float(_best_vis_ts[s2]) < float(tv.T_TOUCH) - 0.03:
				okc = false
		print("  结论: %s" % ("两侧都通过" if okc else "★有不达标项, 见上"))
		print("DEMO DONE")
		get_tree().quit(0)
