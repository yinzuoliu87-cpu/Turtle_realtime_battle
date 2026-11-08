extends Node
## 录制探针(11-08): 龟壳「暗影俯冲」「复制」重做后的实机画面, 给逐帧研究用(docs/studies/20261108-龟壳特效实机逐帧.md)。不是门禁。
## 用法(屏幕外静音窗口, 每帧 = 1/60 秒游戏时间, _deterministic 每帧恰一步 sim):
##   <godot> --path . --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 5000,5000
##           --write-movie .out/shell_vfx/rec.avi --fixed-fps 60 --quit-after 560 res://tests/probes/_rec_shell_vfx.tscn
## 第 40 帧放暗影俯冲(龟壳在左, 路径中段一名敌人、落点一名、路径外一名); 第 420 帧放复制(两名敌人各带一个技能 ⇒ 两条锁链)。
## 每帧打印 [POS] 帧号 龟壳屏幕x 屏幕y(裁图跟着龟壳), 放技能那一帧打印 [CAST]。

var s
var _units: Array = []
var _sh = null


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	OS.set_environment("TURTLE_SEED", "424242")       # 地图 / 障碍固定(与 verify_shell_vfx 同一个种子)
	s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for _i in range(6):
		await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	s._deterministic = true
	print("[REC] 开场单位数 %d" % s._units.size())
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	## ── 暗影俯冲 ──
	_sh = _mk("shell", "left", c + Vector2(-320, 0))
	var e1 := _mk("basic", "right", c + Vector2(-80, 10))
	var e2 := _mk("basic", "right", c + Vector2(240, -20))
	var e3 := _mk("basic", "right", c + Vector2(-60, 260))
	_put([_sh, e1, e2, e3])
	while Engine.get_frames_drawn() < 40:
		await get_tree().process_frame
	print("[CAST] frame=%d dive" % Engine.get_frames_drawn())
	s._do_skill(_sh, e2, "shellShadow")
	while Engine.get_frames_drawn() < 400:
		await get_tree().process_frame
	## ── 复制 ──
	for u in _units:
		if is_instance_valid(u.get("sprite", null)):
			u["sprite"].visible = false
	_sh = _mk("shell", "left", c + Vector2(-220, 0))
	var fa := _mk("basic", "right", c + Vector2(160, -90))
	var fb := _mk("basic", "right", c + Vector2(160, 90))
	fa["active_skills"] = ["iceFreeze"]
	fb["active_skills"] = ["lineInkBomb"]
	_put([_sh, fa, fb])
	while Engine.get_frames_drawn() < 420:
		await get_tree().process_frame
	print("[CAST] frame=%d copy" % Engine.get_frames_drawn())
	s._do_skill(_sh, fa, "shellCopy")


func _mk(id: String, side: String, p: Vector2) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit(id, side, p, {})
	u["no_basic"] = true
	u["no_move"] = true
	u["energy"] = 0.0
	if side == "right":
		u["maxHp"] = 50000.0
		u["hp"] = 50000.0
	return u


func _put(us: Array) -> void:
	s._units.clear()
	s._units.append_array(us)
	s._over = false
	_units = us


func _process(_dt: float) -> void:
	for u in _units:
		u["energy"] = 0.0
	if _sh != null and s != null and s._cam != null:
		var sp: Vector2 = s._cam.unproject_position(s._world_pos(_sh["pos"], 0.8))
		print("[POS] %d %d %d" % [Engine.get_frames_drawn(), int(sp.x), int(sp.y)])
