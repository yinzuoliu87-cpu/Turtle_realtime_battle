extends Node
## verify_screen_flash_lane_clear.gd — 全屏白闪不许残留(2026-10-13 内测反馈)
##
## 玩家 b250de29(iPhone15,4 · v0.19.570):「如果远小将放的导弹爆炸同属战场结束，那么整个画面变白」。
## 根因: `_screen_flash_light()` 的淡出走 `_reg_tween()`(进 _sim_tweens);
##   换路 `_dl_clear_units()` 把 _sim_tweens 全部 kill ⇒ 淡出与 queue_free 都不执行,
##   遮罩停在 ≤28% 白一直盖着后面几路; 整局打完 sim 不再喂 tween 时同理。
## 判据:
##   ① 白闪刚出来就换路 ⇒ 几帧后屏幕上没有残留的白闪层
##   ② 白闪的淡出不登记进 _sim_tweens(不靠 sim 推进), 且按真实时间淡出并删掉自己
##   每条配分母: 触发后白闪层确实在场。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_screen_flash_lane_clear.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _s = null
var _gs = null


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _flashes() -> Array:
	return get_tree().get_nodes_in_group(RB.SCREEN_FLASH_GROUP).filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	print("=== 全屏白闪不残留 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_gs.current_lane = "top"
	_s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame

	## ① 白闪刚出来就换路
	_s._screen_flash_light()
	_ok("① 分母: 触发后白闪层在场", _flashes().size() == 1, "n=%d" % _flashes().size())
	_s._dl_sys._dl_clear_units()
	for _i in range(20):
		await get_tree().process_frame
	_ok("① ★白闪刚出来就换路 ⇒ 屏幕上没有残留的白闪层", _flashes().is_empty(), "n=%d" % _flashes().size())

	## ② 不依赖 sim 推进(整局打完 / 停在结算时 sim 不再喂 _sim_tweens)
	_s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame
	var reg0: int = (_s._sim_tweens as Array).size()
	_s._screen_flash_light()
	_ok("② 分母: 触发后白闪层在场", _flashes().size() == 1, "n=%d" % _flashes().size())
	_ok("② ★白闪的淡出不登记进 _sim_tweens(不靠 sim 推进; 换路 kill 不到它)", (_s._sim_tweens as Array).size() == reg0,
		"登记表 %d → %d" % [reg0, (_s._sim_tweens as Array).size()])
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500 and not _flashes().is_empty():
		await get_tree().process_frame
	_ok("② 白闪按真实时间 1.5 秒内淡出并删掉自己", _flashes().is_empty(),
		"n=%d · 等了 %d ms" % [_flashes().size(), Time.get_ticks_msec() - t0])

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 全屏白闪不残留 (%d/%d)" % [_n, _n])
	get_tree().quit(1 if _fail > 0 else 0)
