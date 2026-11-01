extends Node
## demo_tentacle_side.gd — 【调试场】触手侧视: 一根触手 + 一个敌人摆在同一条水平线上, 拍击方向横穿画面,
##   镜头拉近到整根触手, 从侧面看抬起 / 后弯 / 拍下 / 收回的完整角度。
## 用户 2026-11-01:「搞个调试场去测试行吗？就水平的放置一根触手，放置一根敌人，然后给我老老实实的拍摄整整个触手的角度」
##
## 跑法(窗口, 右屏, 静音):
##   bash godot-quiet.sh --position 2000,80 res://tests/demo_tentacle_side.tscn
##   录视频: 加 --write-movie <路径>.avi
## 环境变量: SIDE_SECS=16(跑多少秒) · SIDE_ZOOM=2.0(拉近倍数) · SIDE_DX=260(敌人在根部右边多少码)

const SPIRIT_IDS := ["p2eq_032", "p2eq_025"]

var _scn = null
var _t0 := 0.0
var _secs := 16.0
var _zoom := 2.0
var _cam_off := Vector3.ZERO
var _fov0 := 0.0
var _focus := Vector2.ZERO
var _foe = null
var _foe_pos := Vector2.ZERO


func _env_f(k: String, d: float) -> float:
	return float(OS.get_environment(k)) if OS.has_environment(k) else d


func _ready() -> void:
	## _process 默认开着, 而下面要等几帧才配好镜头 ⇒ 先关, 配好再开(否则 fov 写成 0 直接崩)
	set_process(false)
	await get_tree().process_frame
	## 不判胜负 + 不写真存档(见 demo_spirit_slap.gd 同段注释)
	OS.set_environment("NOVERDICT", "1")
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	get_tree().root.size = Vector2i(1280, 720)
	_scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_scn)
	await get_tree().process_frame
	await get_tree().process_frame
	_secs = _env_f("SIDE_SECS", 16.0)
	_zoom = _env_f("SIDE_ZOOM", 2.0)
	var dx: float = _env_f("SIDE_DX", 260.0)

	for u in _scn._units.duplicate():
		var sp = u.get("sprite", null)
		if sp != null and is_instance_valid(sp):
			sp.queue_free()
	_scn._units.clear()

	var root: Vector2 = _scn._tentacle_vfx.default_root("left", 0)
	## 携带者放在根部左后方、画面外侧(只为凑 1 档 = 1 根触手), 不攻击不移动不死
	var carrier: Dictionary = _scn._spawn._make_unit("basic", "left", Vector2(root.x - 60.0, root.y + 260.0))
	carrier["no_move"] = true
	carrier["no_basic"] = true
	carrier["move_spd"] = 0.0
	carrier["active_skills"] = []
	carrier["deathfloor_until"] = 999999.0
	var eqs: Array = []
	for id in SPIRIT_IDS:
		eqs.append({"id": id, "star": 1})
	carrier["equips"] = eqs
	_scn._units.append(carrier)

	## 敌人: 根部正右方, 同一条水平线 ⇒ 拍击方向 = 画面水平向右, 后弯 = 画面向左
	var d: Dictionary = _scn._spawn._make_unit("basic", "right", Vector2(root.x + dx, root.y))
	d["no_move"] = true
	d["no_basic"] = true
	d["move_spd"] = 0.0
	d["active_skills"] = []
	_scn._recalc_stats(d)
	d["maxHp"] = 9.0e7
	d["hp"] = 9.0e7
	d["move_spd"] = 0.0
	d["_home_pos"] = d["pos"]
	_scn._units.append(d)
	_foe = d
	_foe_pos = d["pos"]

	_scn._synergy.clear()
	_scn._synergy.apply_all()
	print("[side] 灵物档位 = %d (1 档 = 1 根触手) · 根部 %s · 敌人 %s" % [_scn._spirit_syn._side_tier("left"), str(root), str(Vector2(root.x + dx, root.y))])

	_cam_off = _scn._cam_base - _scn.CAM_TARGET
	_fov0 = _scn._cam.fov
	_focus = Vector2(root.x + dx * 0.25, root.y)
	_t0 = float(Time.get_ticks_msec()) / 1000.0
	set_process(true)


func _process(_d: float) -> void:
	if _scn == null or not is_instance_valid(_scn):
		return
	## 镜头每帧写 `_cam_zoom_base`(battle_render 每帧会用它覆盖相机位置, 见 battle_vfx_lab.gd:_apply_camera)
	var w: Vector3 = _scn._world_pos(_focus, 4.0)
	_scn._cam_zoom_base = w + _cam_off
	_scn._cam.position = _scn._cam_zoom_base
	_scn._cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_fov0 * 0.5)) / _zoom))
	## 敌人钉在原地(灵物装备自己的效果会把它挪走, 第一版录出来敌人跑到根部左边、触手往左拍)
	if _foe != null:
		_foe["pos"] = _foe_pos
	if _scn._t > _secs:
		get_tree().quit(0)
