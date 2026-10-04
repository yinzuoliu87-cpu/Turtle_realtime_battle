extends Node

## verify_trainer_move.gd — 训龟大师 U2: 不可移动、不由人操控、自动放技能、敌我同规则
##
## ★★这份门禁原来验的是「PC 键盘 / 移动端摇杆 移速 130」(用户 2026-07-22)。
##   母方案书 `docs/plans/20260916-大轮赛制v2周赛制.md` U2(用户 2026-09-16 拍板, 原话):
##   「训龟大师估计得调整为一个不能移动的形象和每个周期固定投放一个技能这样子，不再由人来操控」
##   「射程提升到 2000 码，只带一个，最近的，保留，同规则，法术盘可以留冷却显示，还有魔法石来显示层数，
##     大师现在改为不可被打，相当于一个装饰品了，不在拥有血量，但还是可以攻击，移除掉训龟大师的信息栏」
##   2026-10-03 回放方案书(`20261003-跨设备回放.md` Q2, 用户授权按推荐)把它落地 ——
##   人操控的大师是局内实时输入、且在 sim 步之外按帧施加, 实战因此不可复现。
##   ⇒ 本门禁整份改成验 U2。原「移速 130 / 摇杆 / 键盘」那些断言的对象已经删了(不是回归)。
##
## ★判据都量**真对象**(真战斗场 + 真 sim 步), 不验源码里有没有某个字符串 ——
##   只有 ④「人为施法/移动入口不存在」是源码判据, 因为"不存在"量不出来。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
var _n := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)          # 自己逐步喂 sim, 一步不多一步不少
	s._debug._edit_clear()
	s._edit_dummy_killable = false
	s._edit_dummy_hp = 40000.0
	s._edit_trainer_active = "hook"
	var tl: Dictionary = s._debug._edit_place_unit(s.TRAINER_ID, "left", Vector2(100.0, 360.0))
	var tr: Dictionary = s._debug._edit_place_unit(s.TRAINER_ID, "right", Vector2(1500.0, 360.0))
	s._debug._edit_place_unit("basic", "left", Vector2(500.0, 300.0))
	s._debug._edit_place_unit("basic", "left", Vector2(520.0, 460.0))
	var near_r: Dictionary = s._debug._edit_place_unit("basic", "right", Vector2(1000.0, 360.0))
	s._debug._edit_place_unit("basic", "right", Vector2(1200.0, 200.0))
	s._debug._edit_start_battle()
	## 调试场重建了单位字典 ⇒ 重新从场上取
	tl = _trainer(s, "left")
	tr = _trainer(s, "right")
	_ok("分母: 双方各有一个训龟大师在场", not tl.is_empty() and not tr.is_empty())
	if tl.is_empty() or tr.is_empty():
		_finish(s)
		return

	# ── ① 不可移动 ──
	_ok("★① 移速字段 = 0(U2 不可移动)", float(tl.get("move_spd", -1.0)) == 0.0 and float(tr.get("move_spd", -1.0)) == 0.0,
		"左 %.1f / 右 %.1f" % [float(tl.get("move_spd", -1.0)), float(tr.get("move_spd", -1.0))])
	var p_l: Vector2 = tl["pos"]
	var p_r: Vector2 = tr["pos"]
	## 真按着方向键跑 —— 原来的键盘路径如果还在, 我方大师会走
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	var casts_l := 0
	var casts_r := 0
	var dir_ok := 0
	var dir_n := 0
	var others_moved := false
	var other0: Dictionary = _first_non_trainer(s, "left")
	var o0: Vector2 = other0.get("pos", Vector2.ZERO)
	for _i in range(60 * 25):   # 25 游戏秒: 钩锁冷却 20 秒(空放 10), 双方都至少放两次
		var cd_l: float = float(tl.get("_active_cd", 0.0))
		var cd_r: float = float(tr.get("_active_cd", 0.0))
		var nf: int = s._trainer_sys._flights.size()
		var want_l: Vector2 = _nearest_dir(s, tl)
		var want_r: Vector2 = _nearest_dir(s, tr)
		s._sim_step(s.SIM_DT, false, false)
		await get_tree().process_frame
		if cd_l <= 0.0 and float(tl.get("_active_cd", 0.0)) > 0.0:
			casts_l += 1
			dir_n += 1
			if _last_flight_dir_close(s, tl, want_l, nf): dir_ok += 1
		if cd_r <= 0.0 and float(tr.get("_active_cd", 0.0)) > 0.0:
			casts_r += 1
			dir_n += 1
			if _last_flight_dir_close(s, tr, want_r, nf): dir_ok += 1
		if not other0.is_empty() and (other0["pos"] as Vector2).distance_to(o0) > 1.0:
			others_moved = true
	key.pressed = false
	Input.parse_input_event(key)
	_ok("分母: 这 25 秒里战斗真的在推进(我方别的龟走动了)", others_moved)
	_ok("★① 按住方向键 25 秒, 我方大师一码都没动", (tl["pos"] as Vector2) == p_l, "%s → %s" % [p_l, tl["pos"]])
	_ok("★① 敌方大师也一码都没动(原 AI 随机游走已删)", (tr["pos"] as Vector2) == p_r, "%s → %s" % [p_r, tr["pos"]])

	# ── ② 自动放技能 · 敌我同规则 · 打最近的 ──
	_ok("★② 我方大师自己放了主动技(不靠人按): %d 次 ≥ 2" % casts_l, casts_l >= 2)
	_ok("★② 敌方大师同一套规则: %d 次 ≥ 2" % casts_r, casts_r >= 2)
	_ok("★② 每一发都朝【最近的敌人】(%d/%d)" % [dir_ok, dir_n], dir_n > 0 and dir_ok == dir_n)

	# ── ③ 不可被打 · 没有血量 · 不建信息栏 ──
	for t in [tl, tr]:
		var side: String = str(t.get("side", ""))
		_ok("★③ %s 大师没有头顶信息栏(血条/龟能/等级)" % side, not is_instance_valid(t.get("bar_root", null)))
		_ok("★③ %s 大师任何伤害(含真伤)都是 0" % side,
			s._mitigate_incoming(t, 1.0e9, true, false) == 0.0 and s._mitigate_incoming(t, 999.0, false, false) == 0.0)
		s._kill(t, near_r)
		_ok("★③ %s 大师直接处决也杀不死" % side, bool(t.get("alive", false)))

	# ── ③ 两侧头像栏里也没有大师那一格(U2「移除大师信息栏」) ──
	s._hud._build_team_panels()
	var frames_n := 0
	var tr_frames := 0
	for col in [s._team_panel_left, s._team_panel_right]:
		if col == null or not is_instance_valid(col):
			continue
		for ch in col.get_children():
			if str(ch.name).begins_with("Frame_"):
				frames_n += 1
				if str(ch.name) == "Frame_" + s.TRAINER_ID:
					tr_frames += 1
	_ok("★③ 头像栏里没有训龟大师(分母: 头像框 %d 个)" % frames_n, frames_n > 0 and tr_frames == 0, "大师框 %d 个" % tr_frames)

	# ── ③b 仍能攻击: 扔石头那条线还在 ──
	var rocks := 0
	for u in s._units:
		if not u.get("is_trainer", false) and float(u.get("_st_taken", 0.0)) > 0.0:
			rocks += 1
	_ok("★③b 仍能攻击(场上有单位挨过打: %d 个)" % rocks, rocks > 0)

	# ── ④ 人为操控入口不存在(源码判据: "不存在"量不出来) ──
	var ts_src: String = FileAccess.get_file_as_string("res://scripts/systems/trainer/trainer_system.gd")
	var rb_src: String = FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("★④ 训龟大师系统里没有读键盘/摇杆的代码", not ts_src.contains("Input.is_key_pressed") and not ts_src.contains("_joystick"))
	_ok("★④ 战斗场没有 Q 键施法", not rb_src.contains("KEY_Q"))
	_ok("★④ 摇杆与瞄准子系统文件已删", not FileAccess.file_exists("res://scripts/scenes/virtual_joystick.gd")
		and not FileAccess.file_exists("res://scripts/scenes/battle/battle_aim.gd"))

	# ── ⑤ 法术盘留作只读显示 ──
	var disc = s._spell_disc
	_ok("★⑤ 法术盘还在(冷却 + 魔法石层数显示)", disc != null and is_instance_valid(disc))
	if disc != null and is_instance_valid(disc):
		_ok("★⑤ 法术盘只读: 不接任何点击(mouse_filter = IGNORE)", disc.mouse_filter == Control.MOUSE_FILTER_IGNORE)
		_ok("★⑤ 法术盘没有施法回调", not disc.has_method("_gui_input") and not ("_on_tap" in disc))
	_finish(s)


func _finish(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 训龟大师 U2(不可移动/自动施法/敌我同规则/不可被打/只读法术盘) %d 条" % _n if _fail == 0 else "FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)


func _trainer(s, side: String) -> Dictionary:
	for u in s._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == side:
			return u
	return {}


func _first_non_trainer(s, side: String) -> Dictionary:
	for u in s._units:
		if not u.get("is_trainer", false) and str(u.get("side", "")) == side:
			return u
	return {}


## 用产品自己的选靶函数(不手抄一份): 大师「打最近的」就是它。
func _nearest_dir(s, t: Dictionary) -> Vector2:
	var tgt = s._targeting._nearest_enemy_for_trainer(t)
	return ((tgt["pos"] as Vector2) - (t["pos"] as Vector2)).normalized() if tgt != null else Vector2.ZERO


## 这一步刚甩出去的那一发(同一步里别的钩子可能刚好收回 ⇒ 不能按数组长度判, 按"刚出手 t≈0"找)。
func _last_flight_dir_close(s, t: Dictionary, want: Vector2, _n_before: int) -> bool:
	for f in s._trainer_sys._flights:
		if is_same(f.get("src", null), t) and float(f.get("t", 99.0)) <= s.SIM_DT + 1.0e-6:
			if want == Vector2.ZERO:
				return false
			var ok: bool = (f["dir"] as Vector2).dot(want) > 0.999
			if not ok:
				print("    [方向] %s 大师 出手 %s / 最近敌 %s" % [str(t.get("side", "")), f["dir"], want])
			return ok
	print("    [方向] %s 大师 这一步没找到刚出手的钩子" % str(t.get("side", "")))
	return false
