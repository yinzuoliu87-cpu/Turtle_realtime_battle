extends Node
## 选龟页动效录屏台(不是门禁, 2026-10-30)。用户「他们游戏是动态的，并不是你看到这么静态的」⇒ 动效交视频验收。
## 全程走产品入口(真选龟页 / 真点击事件); 光标 = 产品自己的光标节点, 按脚本里的「假鼠标」摆(真鼠标不动)。
## 时间线(--write-movie 下 游戏秒 = 视频秒):
##   全选版: 入场 → 悬停一张卡 → 点一只上阵(飞入) → 再点一只 SS(扫光) → 切「S」页签(浮上来) → 点第三只(出战键亮起) → 点一个技能(弹) → 停
##   锁定版(LOCKED=1): 入场 → 三张大卡待机 → 点第二张(金边换过去 + 右栏立绘弹进来) → 停
## 跑法:
##   TURTLE_SUPABASE=" " [LOCKED=1] <godot> --path . --audio-driver Dummy --resolution 1560x720 --position 2000,80 \
##     --write-movie <输出>/ts.avi --fixed-fps 60 --quit-after 3000 res://tests/_rec_teamselect.tscn

var ts
var ct
var _mouse := Vector2(780, 640)
var _fist := false


func _ready() -> void:
	GameState.test_mode = true
	if int(GameState.season_total_battles) <= 0:
		GameState.season_total_battles = 3
	var locked := OS.get_environment("LOCKED") == "1"
	if locked:
		load("res://tests/_setup_appstore.gd").run()
	else:
		GameState.season_leaders = []
	ct = get_node_or_null("/root/CursorTheme")
	if ct != null:
		ct.set_process(false)
	ts = (load("res://scenes/TeamSelect.tscn") as PackedScene).instantiate()
	add_child(ts)
	if locked:
		await _locked_reel()
	else:
		await _open_reel()
	print("REC DONE")
	get_tree().quit(0)


func _process(_dt: float) -> void:
	if ct != null and ct._cur != null:
		ct._g.texture = ct._fist_tex if _fist else ct._point_tex
		var hot: Vector2 = ct.hot_for(_fist)
		ct._cur.pivot_offset = hot
		ct._cur.scale = Vector2.ONE
		ct._glow.visible = false
		ct._cur.position = _mouse - hot


func _wait(sec: float) -> void:
	var n := int(round(sec * 60.0))
	for _i in range(n):
		await get_tree().process_frame


## 假鼠标平滑移到 to(推真的鼠标移动事件, 悬停 / 离开照常触发)
func _move_to(to: Vector2, sec: float = 0.45) -> void:
	var from := _mouse
	var n := maxi(1, int(round(sec * 60.0)))
	for k in range(1, n + 1):
		var t := float(k) / float(n)
		t = t * t * (3.0 - 2.0 * t)
		var p := from.lerp(to, t)
		var mm := InputEventMouseMotion.new()
		mm.position = p; mm.global_position = p
		mm.relative = p - _mouse
		get_viewport().push_input(mm, true)
		_mouse = p
		await get_tree().process_frame


func _click() -> void:
	var dn := InputEventMouseButton.new()
	dn.button_index = MOUSE_BUTTON_LEFT; dn.pressed = true; dn.position = _mouse; dn.global_position = _mouse
	dn.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(dn, true)
	await _wait(0.08)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.position = _mouse; up.global_position = _mouse
	get_viewport().push_input(up, true)
	await get_tree().process_frame


func _card(pid: String) -> Control:
	for c in (ts._grid_flow as Node).get_children():
		if c is Control and str((c as Control).get_meta("pet_id", "")) == pid and not (c as Node).is_queued_for_deletion():
			return c
	return null


func _center(c: Control) -> Vector2:
	var r := c.get_global_rect()
	return r.position + r.size * Vector2(0.5, 0.42)


func _open_reel() -> void:
	await _wait(1.4)                                     # 入场
	## 第一只: 悬停一会儿(抬起 + 动起来)再点
	var picks: Array = []
	for p in DataRegistry.launch_pets:
		if str(p.get("rarity", "")) == "A" and picks.size() < 1:
			picks.append(str(p["id"]))
	var c1 := _card(str(picks[0]))
	await _move_to(_center(c1), 0.6)
	await _wait(1.2)
	await _click()
	await _wait(1.0)
	## 第二只: SS(有扫光)
	var ss := ""
	for p in DataRegistry.launch_pets:
		if str(p.get("rarity", "")) == "SS" and ss == "":
			ss = str(p["id"])
	var c2 := _card(ss)
	await _move_to(_center(c2), 0.5)
	await _wait(1.4)
	await _click()
	await _wait(1.0)
	## 切到「S」页签
	for rb in ts._rarity_btns:
		if rb["key"] == "S":
			await _move_to((rb["btn"] as Control).get_global_rect().get_center(), 0.5)
			await _click()
	await _wait(1.0)
	## 第三只(S)⇒ 出战键亮起
	var c3: Control = null
	for c in (ts._grid_flow as Node).get_children():
		if c is Control and not (str((c as Control).get_meta("pet_id", "")) in ts.team):
			c3 = c
			break
	await _move_to(_center(c3), 0.5)
	await _wait(0.6)
	await _click()
	await _wait(1.6)
	## 点一个技能(右栏下格第三个图标)
	var icons: Array = (ts._detail_bottom as Node).find_children("*", "Button", true, false)
	if icons.size() >= 3:
		await _move_to((icons[2] as Control).get_global_rect().get_center(), 0.5)
		await _click()
		await _wait(0.5)
		## 关掉点技能弹出的说明
		if ts.has_method("_close_detail_popup"):
			ts._close_detail_popup()
	await _wait(0.6)
	## 指着出战键停一会儿(就绪光在呼吸)
	await _move_to((ts._start_btn as Control).get_global_rect().get_center() + Vector2(0, 8), 0.6)
	await _wait(2.2)


func _locked_reel() -> void:
	await _wait(2.6)                                     # 入场 + 三张大卡待机
	var s1: Control = ts._slot_nodes[1]
	await _move_to(s1.get_global_rect().get_center(), 0.6)
	await _wait(0.8)
	await _click()
	await _wait(2.4)
	var s2: Control = ts._slot_nodes[2]
	await _move_to(s2.get_global_rect().get_center(), 0.6)
	await _wait(0.5)
	await _click()
	await _wait(2.6)
