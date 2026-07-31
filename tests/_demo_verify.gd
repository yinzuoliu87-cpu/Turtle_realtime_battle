extends Node
## 验收演示窗口 (2026-07-31)。用户:「你来开图或窗口给我验收吧」
##
## 按时间线自动演一遍今天改的五件, 每步在屏幕上写清楚【该看哪里】。
## 演完把主动技换成口哨并重建圆盘 —— 之后可以自己点右下角圆盘验"点击就放、不出方向轮盘"。
##
## 跑法(窗口放屏幕右侧垂直居中·屏幕 1707×1067):
##   SHIP=1 <godot> --path . res://tests/_demo_verify.tscn --resolution 1200x675 --position 491,196

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _lbl: Label = null
var _sub: Label = null
var _s = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.season_level = 5
	gs.trainer_skill = "tame"
	gs.dual_active = true
	gs.current_lane = "top"
	_s = RB.new()
	add_child(_s)
	for _i in range(50):
		await get_tree().process_frame
	_build_overlay()
	_s._dl_sys._dl_clear_units()
	_s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame
	_s._dl_sys._dl_start_fight()

	await _say("① 新地图 · 沉岛斗场（网格已加密一倍）",
		"看：岛的轮廓不再是大方块台阶 / 岛缘那圈灰色岸线 / 亮青潟湖从四个斜角扫进来", 9.0)

	await _say("② 驯服 —— 先打标记（此刻还没换队）",
		"驯服是【标记】不是当场换队；等被标记的那只死掉才归顺", 0.2)
	var tr = null
	var victim = null
	for u in _s._units:
		if u.get("_isEgg", false):
			continue
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			tr = u
		elif str(u.get("side", "")) == "right" and u.get("alive", false) and victim == null:
			victim = u
	if tr != null and victim != null:
		victim["pos"] = tr["pos"] + Vector2(240.0, 0.0)
		tr["_active_cd"] = 0.0
		_s._trainer_sys._cast_tame(tr, Vector2(240.0, 0.0))
		var w := 0
		while w < 400 and not victim.get("tame_pending", false):
			await get_tree().process_frame
			w += 1
		await _hold(2.0)
		await _say("② 驯服 · 归顺瞬间",
			"看：这只龟的血条变我方绿 / 头像框从右栏挪到左栏 / 框边由红变蓝", 0.2)
		_s._kill(victim)
		await _hold(7.0)

	await _say("③ PK 条 · 回血带",
		"看：顶部血条上那一段【薄荷绿】= 刚回的血（改前治疗在这条上完全没反馈）", 0.2)
	for u in _s._units:
		if u.get("alive", false) and not u.get("_isEgg", false):
			u["hp"] = float(u["maxHp"]) * 0.35
	_s._hud._pk_acc = 999.0
	await _hold(2.5)
	for u in _s._units:
		if u.get("alive", false) and not u.get("_isEgg", false):
			u["hp"] = float(u["maxHp"]) * 0.92
	_s._hud._pk_acc = 999.0
	await _hold(6.0)

	await _say("④ 敌方团灭 → 龟蛋暴露 → 归顺龟一起砸蛋",
		"改前：归顺的龟一直给原队顶着一个存活数 → 团灭永不触发 → 本路卡死", 0.2)
	for u in _s._units:
		if str(u.get("side", "")) == "right" and u.get("alive", false) \
			and not u.get("_isEgg", false) and not u.get("is_trainer", false) \
			and str(u.get("tamed_side", "")) == "":
			u["hp"] = 1.0
			_s._kill(u)
	await _hold(14.0)

	# ⑤ 换成口哨, 重建圆盘 → 交给用户自己点
	gs.trainer_skill = "whistle"
	for u in _s._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			u["_tr_active"] = "whistle"
			u["_active_cd"] = 0.0
	if _s._spell_disc != null and is_instance_valid(_s._spell_disc):
		_s._spell_disc.queue_free()
		_s._spell_disc = null
	await get_tree().process_frame
	_s._hud._build_spell_disc()
	await _say("⑤ 口哨 · 请你自己点右下角圆盘",
		"按住拖一圈再松手 —— 应当【不出方向轮盘、战场上没有方向带】, 和轻点完全一样", 0.2)
	while true:                                  # 停在这一步, 窗口不关
		await _hold(3.0)
		for u in _s._units:
			if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
				u["_active_cd"] = 0.0            # 一直保持就绪, 方便反复试


func _build_overlay() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 200
	add_child(cl)
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(0.0, 66.0)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.08, 0.88)
	sb.set_border_width_all(2)
	sb.border_color = Color("#ffd93d")
	sb.set_content_margin_all(10)
	box.add_theme_stylebox_override("panel", sb)
	cl.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	box.add_child(vb)
	_lbl = Label.new()
	_lbl.add_theme_font_size_override("font_size", 22)
	_lbl.add_theme_color_override("font_color", Color("#ffd93d"))
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_lbl)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 15)
	_sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_sub)


func _say(title: String, sub: String, hold: float) -> void:
	if _lbl != null:
		_lbl.text = title
		_sub.text = sub
	print("[演示] ", title, "  —— ", sub)
	await _hold(hold)


## ★用【墙钟】等 —— 不能用帧数(不同机器帧率差几十倍)也不能用游戏时钟(_kill 后会冻结)。
##   这是本项目 CLAUDE.md §3.5 的铁律, 我今天已经栽过一次。
func _hold(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().process_frame
