extends Node
## 录制探针(11-08): 近战小将人体浪板 + 精英小将铁锁的「链子留到被拽过去、途中逐段收」实机画面, 给逐帧研究用
##   (docs/studies/20261108-小将拉人链子逐帧.md)。不是门禁。
## 用法(屏幕外静音窗口, 每帧 = 1/60 秒游戏时间):
##   <godot> --path . --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 5000,5000
##           --write-movie .out/ref_shell/rope.avi --fixed-fps 60 --quit-after 520 res://tests/probes/_rec_pull_rope.tscn
## 第 30 帧近战小将放人体浪板(目标在右 500 码); 第 260 帧精英小将甩铁锁(目标在右 300 码)。

var s


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for _i in range(6):
		await get_tree().process_frame
	s._deterministic = true
	var ar: Rect2 = s.ARENA
	var p0: Vector2 = ar.position + Vector2(ar.size.x * 0.22, ar.size.y * 0.30)
	var mn: Dictionary = s._spawn._make_unit("__minion__", "left", p0, {"minion": true, "level": 1})
	var foe: Dictionary = s._spawn._make_unit("stone", "right", p0 + Vector2(500, 0), {})
	foe["maxHp"] = 50000.0; foe["hp"] = 50000.0
	foe["untargetable_until"] = 1.0e9
	mn["untargetable_until"] = 1.0e9
	s._units.append(mn); s._units.append(foe)
	for _i in range(24):
		await get_tree().process_frame
	print("[REC] 第 %d 帧 近战小将放人体浪板" % Engine.get_frames_drawn())
	s._hiding_sys._sk_minion_bodysurf(mn, foe)
	for _i in range(230):
		await get_tree().process_frame
	var p1: Vector2 = ar.position + Vector2(ar.size.x * 0.30, ar.size.y * 0.72)
	var e: Dictionary = s._spawn._make_unit("__minion__", "left", p1, {"minion": true, "elite": true, "level": 1})
	var f: Dictionary = s._spawn._make_unit("stone", "right", p1 + Vector2(300, 0), {})
	f["maxHp"] = 50000.0; f["hp"] = 50000.0
	s._units.append(e); s._units.append(f)
	e["_whip_cd"] = 0.0; e["stun_until"] = 0.0; e["_slam"] = false
	e["taunt_until"] = float(s._t) + 100.0; e["taunt_by"] = f
	e["untargetable_until"] = float(s._t) + 100.0
	f["untargetable_until"] = float(s._t) + 100.0
	await get_tree().process_frame
	print("[REC] 第 %d 帧 精英小将甩铁锁" % Engine.get_frames_drawn())
	s._tick_elite_whip(e)
