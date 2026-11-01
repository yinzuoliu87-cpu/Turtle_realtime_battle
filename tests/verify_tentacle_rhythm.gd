extends Node
## verify_tentacle_rhythm.gd — 触手【做法纪律】: 粗细不逐帧变 + 命中白闪与伤害同一帧
## (2026-08-04 立「拍击节奏」· 2026-10-31 随灵物触手重做改写, 方案书 docs/plans/20261031d-灵物触手重做.md §4.3)
##
## 2026-08 那版守的是逐帧对齐俄洛伊的扁带网格(弧长包络 / 带宽先细后鼓 / 卷曲余振), 那套网格整个删了。
## 10-31 第一版改写时这里还守过按参考定的尺子(高约龟 1~1.7 倍 / 宽约 1 只龟 / 拍下 1~4 帧到底 / 拍痕 0.3~0.4 秒 /
##   预警期露出 46%→100%) —— 用户否了第一版成品(「效果差，这是3d吗」「甚至不如旧版，你完全不知道怎么动的」),
##   第一路改成「动作以旧版中心线计算为起点原样恢复、只修抽搐那一处; 尺寸照旧版」⇒ 那几把按参考定的尺子撤掉;
##   动作好不好的阈值等第一路交回「抽搐修复」的数值再定(方案书 §5 U11, 量法已在 verify_tentacle_continuity 打印)。
##
## 留下的是**做法层面**的(与动作长什么样无关, 新旧动作都该守):
##   ⑤ ★粗细不逐帧变(用户 10-31「一直闪光」的嫌疑之一是旧版 `r *= 1 + 0.055 sin(…)`): 建材质时设的半径 / 长度这类
##      uniform 整套动作(出土 → 待机 → 预警 → 前摇 → 拍击 → 收回)一次都没变, 而且不在逐帧直播的「每步会变」名单里
##   ③ ★命中白闪(着色器有 `flash` 且列在「每步会变」名单里时)第一帧 = 伤害结算那一帧 —— 人没到地先炸 / 打完才闪都算错
## ★全部读着色器拿到的 uniform(tests/_tentacle_geo.gd), 走真路径(strike → 逐帧 tick), 不手改状态。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_tentacle_rhythm.tscn

const G := preload("res://tests/_tentacle_geo.gd")
const TV := preload("res://scripts/systems/equip/tentacle_vfx.gd")

var _n := 0
var _fail := 0
var _s
var _v


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 材质上「不在每步会变名单里」的全部 uniform 的当前值
func _fixed(mi: MeshInstance3D, hot: PackedStringArray) -> Dictionary:
	var out := {}
	var m := G.mat_of(mi)
	if m == null:
		return out
	for p in m.get_property_list():
		var nm: String = str((p as Dictionary)["name"])
		if not nm.begins_with("shader_parameter/"):
			continue
		var bare := nm.substr(17)
		if hot.has(bare):
			continue
		out[bare] = m.get(nm)
	return out


func _ready() -> void:
	await get_tree().process_frame
	print("=== 灵物触手: 做法纪律(粗细不逐帧变 / 白闪与伤害同帧) ===")
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	_s = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(_s)
	_s.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_s._debug._edit_clear()
	_v = _s._tentacle_vfx
	_v.clear()
	_v.ensure("left", 1)
	var mi := G.node_of(_v, "left", 0)
	_ok("分母: 触手节点与着色器材质都在、带「每步会变」名单", mi != null and G.mat_of(mi) != null and mi.has_meta(&"stream_shader_params"))
	if mi == null or G.mat_of(mi) == null:
		_done()
		return
	var hot := PackedStringArray(mi.get_meta(&"stream_shader_params", PackedStringArray()))
	var fixed0 := _fixed(mi, hot)
	var set_n := 0
	for k in fixed0:
		if fixed0[k] != null:
			set_n += 1

	## ── 出土 → 待机 → 一整套正常拍击 → 回到待机, 逐帧核 ──
	var touch_step := [-1]
	var rows: Array = []          # [状态, 白闪]
	## 名单里的「粗细」类(半径 / 宽度; 恢复版是每个控制点一个半径 `ctrl_r`): 允许跟着姿态慢慢变(8 月那版粗细随抻直度,
	##   待机呼吸 3.6 秒一个来回), 但**不许逐帧起伏** —— 方案书 §2.2 嫌疑③ 的形状是叠在姿态上的高频起伏。
	##   判据: 待机稳态(进待机 0.5 秒以后)每个元素的变化方向每秒最多换 2 次(呼吸是 0.56 次; 逐帧起伏是几十次)。
	var radius_like: Array = []
	for nm0 in hot:
		var lw := str(nm0).to_lower()
		if lw.contains("rad") or lw.ends_with("_r") or lw.contains("width") or lw.contains("thick"):
			radius_like.append(nm0)
	var idle_t := 0.0
	var idle_series := {}         # 参数名 → [每帧的值](待机稳态)
	var bad: Array = []
	var seen := {}
	## 待机先站 4 秒(稳态 3.5 秒, 够一个呼吸周期 3.6 秒左右) —— 太短的话换向次数按秒折算是噪声(第一版只站 0.47 秒, 2 次换向折成 4.3 次/秒)
	var total := int((TV.T_EMERGE + 4.2 + TV.T_WARN + TV.T_REAR + TV.T_SLAM + TV.T_RECOVER + 0.5) / G.SIM_DT)
	var struck := false
	for _i in range(total):
		if not struck and int(_v.state_of("left", 0)) == 1 and rows.size() > int((TV.T_EMERGE + 4.0) / G.SIM_DT):
			_v.strike("left", 0, _v.root_pos("left", 0) + Vector2(400.0, 30.0), 1.0, func() -> void: touch_step[0] = rows.size())
			struck = true
		G.step(_v)
		seen[int(_v.state_of("left", 0))] = true
		var fl = G.uni(mi, "flash")
		rows.append([int(_v.state_of("left", 0)), float(fl) if fl != null else 0.0])
		if int(_v.state_of("left", 0)) == 1:
			idle_t += G.SIM_DT
			if idle_t > 0.5:
				for rn in radius_like:
					(idle_series.get_or_add(rn, []) as Array).append(G.uni(mi, rn))
		else:
			idle_t = 0.0
		var cur := _fixed(mi, hot)
		for k2 in fixed0:
			if cur.get(k2) != fixed0[k2] and bad.size() < 4:
				bad.append("%s 第 %d 帧 %s → %s" % [str(k2), rows.size(), str(fixed0[k2]), str(cur.get(k2))])

	# ══ ⑤ 粗细不逐帧变 ═══════════════════════════════════════
	var tex_like: Array = []
	for nm in hot:
		var low := str(nm).to_lower()
		if low.contains("uv") or low.contains("scroll") or low.contains("offset"):
			tex_like.append(nm)
	print("     「每步会变」名单 %s · 其余 uniform %d 个(建材质时设过值的 %d 个) · 走过的状态 %s" % [str(hot), fixed0.size(), set_n, str(seen.keys())])
	_ok("⑤ 分母: 走过出土 / 待机 / 预警 / 前摇 / 拍击 / 收回、名单外有 ≥ 3 个 uniform(其中 ≥ 1 个建材质时设过值)",
		seen.has(0) and seen.has(1) and seen.has(6) and seen.has(2) and seen.has(3) and seen.has(4) and fixed0.size() >= 3 and set_n >= 1, str(seen.keys()))
	_ok("⑤ ★★名单外的 uniform(半径 / 长度 / 颜色 / 吸盘 …)整套动作里一次都没变(%d 帧)" % rows.size(), bad.is_empty() and rows.size() > 200, str(bad))
	_ok("⑤ ★「每步会变」名单里没有贴图坐标 / 滚动这一类(不滚纹理)", tex_like.is_empty() and hot.size() > 0, str(tex_like))
	## 每个元素的变化方向换向次数 / 秒(取最大的那个元素), 以及每帧最大相对变化
	var worst_rev := 0.0
	var worst_rel := 0.0
	var frames := 0
	for rn2 in idle_series:
		var ser: Array = idle_series[rn2]
		frames = maxi(frames, ser.size())
		if ser.size() < 3:
			continue
		var n_el: int = (ser[0] as PackedFloat32Array).size() if ser[0] is PackedFloat32Array else 1
		for el in range(n_el):
			var rev := 0
			var lastd := 0.0
			for f in range(1, ser.size()):
				var a: float = float((ser[f - 1] as PackedFloat32Array)[el]) if ser[f - 1] is PackedFloat32Array else float(ser[f - 1])
				var b: float = float((ser[f] as PackedFloat32Array)[el]) if ser[f] is PackedFloat32Array else float(ser[f])
				var d := b - a
				worst_rel = maxf(worst_rel, absf(d) / maxf(absf(a), 0.01))
				if absf(d) > 1.0e-7:
					if lastd != 0.0 and signf(d) != signf(lastd):
						rev += 1
					lastd = d
			worst_rev = maxf(worst_rev, float(rev) / maxf(float(ser.size()) * G.SIM_DT, 0.01))
	print("     名单里的粗细类 %s · 待机稳态 %d 帧 · 单个元素变化方向每秒最多换 %.2f 次 · 每帧最大相对变化 %.4f" % [str(radius_like), frames, worst_rev, worst_rel])
	_ok("⑤ ★★不逐帧改粗细: 待机稳态里半径类 uniform 的变化方向每秒最多换 2 次(%.2f; 名单里没有半径类则只守名单外不变)" % worst_rev,
		radius_like.is_empty() or (frames > 150 and worst_rev <= 2.0))

	# ══ ③ 白闪与伤害同帧 ══════════════════════════════════════
	var fl_first := -1
	var fl_n := 0
	for k8 in range(rows.size()):
		if float(rows[k8][1]) > 0.0:
			fl_n += 1
			if fl_first < 0:
				fl_first = k8
	print("     伤害回调在第 %d 帧; 着色器白闪 %s, 亮 %d 帧, 第一帧是第 %d 帧" % [int(touch_step[0]),
		"在名单里" if hot.has("flash") else "没有(不判)", fl_n, fl_first])
	_ok("③ 分母: 这一击真的结算了伤害(第 %d 帧)" % int(touch_step[0]), int(touch_step[0]) > 0)
	if hot.has("flash"):
		_ok("③ ★★命中白闪第一帧 = 伤害结算那一帧(白闪第 %d 帧 / 伤害第 %d 帧)" % [fl_first, int(touch_step[0])],
			fl_n > 0 and fl_first == int(touch_step[0]))
	_done()


func _done() -> void:
	if _v != null:
		_v.clear()
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = false
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 触手做法纪律" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
