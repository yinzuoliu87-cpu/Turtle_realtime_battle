extends Node
## 录制探针(11-08 晚): 龟壳「潜影」被动形态的实机画面(用户「隐形的话，透明的还是怎么样的？这都没设计啊」)。不是门禁。
## 用法(屏幕外静音窗口, 每帧 = 1/60 秒游戏时间):
##   <godot> --path . --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 5000,5000
##           --write-movie .out/shell_vfx/stealth.avi --fixed-fps 60 --quit-after 330 res://tests/probes/_rec_shell_stealth.tscn
## 我方龟壳(左)与敌方龟壳(右)同时进潜影(敌我同一个样子) → 两只各自走一段(暗影池 / 暗火跟着) →
## 第 120 帧我方龟壳吃一下伤害(不破隐, 闪一下) → 第 200 帧我方破隐 → 第 260 帧敌方破隐。

var s
var _sh = null
var _sh2 = null
var _foe = null


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	OS.set_environment("TURTLE_SEED", "424242")
	s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for _i in range(6):
		await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	s._deterministic = true
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	_sh = _mk("shell", "left", c + Vector2(-330, -40))
	_sh2 = _mk("shell", "right", c + Vector2(330, 60))
	_foe = _mk("basic", "right", c + Vector2(120, -160))
	var ally := _mk("basic", "left", c + Vector2(-120, 170))
	s._units.clear()
	s._units.append_array([_sh, _sh2, _foe, ally])
	s._over = false
	await _until(30)
	print("[CAST] frame=%d stealth both" % Engine.get_frames_drawn())
	s._shell_sys._shell_enter_stealth(_sh)
	s._shell_sys._shell_enter_stealth(_sh2)
	await _until(120)
	print("[CAST] frame=%d hit left shell" % Engine.get_frames_drawn())
	s._damage._apply_damage_from(_foe, _sh, 60, Color.RED)
	await _until(200)
	print("[CAST] frame=%d break left" % Engine.get_frames_drawn())
	s._shell_sys._shell_break_stealth(_sh)
	await _until(260)
	print("[CAST] frame=%d break right" % Engine.get_frames_drawn())
	s._shell_sys._shell_break_stealth(_sh2)


func _until(f: int) -> void:
	while Engine.get_frames_drawn() < f:
		await get_tree().process_frame


func _mk(id: String, side: String, p: Vector2) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit(id, side, p, {})
	u["no_basic"] = true
	u["no_move"] = true
	u["energy"] = 0.0
	u["maxHp"] = 50000.0
	u["hp"] = 50000.0
	return u


func _process(_dt: float) -> void:
	if _sh == null:
		return
	for u in s._units:
		u["energy"] = 0.0
	var f: int = Engine.get_frames_drawn()
	## 第 40~170 帧两只各走一段(我方往右上、敌方往左下), 看暗影池 / 暗火跟不跟
	if f >= 40 and f < 170:
		_sh["pos"] = (_sh["pos"] as Vector2) + Vector2(2.2, 0.6)
		_sh2["pos"] = (_sh2["pos"] as Vector2) + Vector2(-2.2, -0.5)
