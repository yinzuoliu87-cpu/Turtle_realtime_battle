extends Node
## verify_debug_no_season —— 调试场(DEBUG_EDIT)打完不计入赛季: 场次/胜场/命/深海币都不变。
## 由来: 用户 2026-10-07「在调试场里打的为什么会计入局数啊」。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fails := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fails += 1


func _snap(gs) -> Array:
	return [int(gs.season_total_battles), int(gs.season_wins), int(gs.hearts), int(gs.coins)]


func _run(debug: bool) -> Array:
	var gs = get_node("/root/GameState")
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.tutorial_active = false
	RB.DEBUG_EDIT = debug
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var before := _snap(gs)
	s._settle_season(true)
	var after := _snap(gs)
	var had: bool = bool(s._had_season)
	s.queue_free()
	await get_tree().process_frame
	RB.DEBUG_EDIT = false
	return [before, after, had]


func _ready() -> void:
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	var r = await _run(true)
	_ok("★调试场打完: 场次/胜场/命/深海币全不变", r[0] == r[1], "%s → %s" % [r[0], r[1]])
	_ok("调试场不进赛季记账(_had_season=false)", r[2] == false)
	## 对照组(分母): 同样的调用在非调试场下确实会记账 —— 否则上面那条是空检查
	var c = await _run(false)
	_ok("分母: 非调试场同一调用确实会改变赛季数据", c[0] != c[1], "%s → %s" % [c[0], c[1]])
	print("ALL PASS — 调试场不计入赛季" if _fails == 0 else "FAIL x%d" % _fails)
	get_tree().quit()
