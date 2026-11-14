extends Node
## demo_tentacle_side.gd — 【调试场】触手侧视: 一根触手 + 一个敌人摆在同一条水平线上, 拍击方向横穿画面,
##   镜头拉近到整根触手, 从侧面看抬起 / 后弯 / 拍下 / 收回的完整角度。
## 用户 2026-11-01:「搞个调试场去测试行吗？就水平的放置一根触手，放置一根敌人，然后给我老老实实的拍摄整整个触手的角度」
##
## 跑法(窗口, 右屏, 静音):
##   bash godot-quiet.sh --position 2000,80 res://tests/demo_tentacle_side.tscn
##   录视频: 加 --write-movie <路径>.avi
## 环境变量: SIDE_SECS=16(跑多少秒) · SIDE_ZOOM=2.0(拉近倍数) · SIDE_DX=260(敌人离根部多少码)
##   SIDE_ANG=0(出手方向: 场地上从「正右」往「远离镜头」转多少度; 和 LoL 某一击并排时设成那一击的方向, 例 31.1 s 那击 = 52)

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
var _last_st := -99


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
	## SIDE_PAL=<配色名>: 换触手外形 / 配色(TentacleMeshVfx.PALETTES; 11-13 自己设计外形对比用)
	if OS.has_environment("SIDE_PAL"):
		TentacleMeshVfx.palette_override = OS.get_environment("SIDE_PAL")
	_scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_scn)
	await get_tree().process_frame
	await get_tree().process_frame
	_secs = _env_f("SIDE_SECS", 16.0)
	## SIDE_IDLE=1: 触手只播待机(不出手、不搬家) —— 用户 11-13「把待机动画播放给我」
	if OS.get_environment("SIDE_IDLE") == "1":
		_scn._tentacle_vfx.hold_idle = true
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
	var ang: float = deg_to_rad(_env_f("SIDE_ANG", 0.0))
	var off2 := Vector2(cos(ang), -sin(ang)) * dx
	var d: Dictionary = _scn._spawn._make_unit("basic", "right", root + off2)
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
	print("[side] 灵物档位 = %d (1 档 = 1 根触手) · 根部 %s · 敌人 %s" % [_scn._spirit_syn._side_tier("left"), str(root), str(root + off2)])

	_cam_off = _scn._cam_base - _scn.CAM_TARGET
	_fov0 = _scn._cam.fov
	_focus = root + off2 * 0.25
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
	## SIDE_IDLE: 每帧打出「待机姿势表播到第几秒」—— 用来和 LoL 录屏并排对时间(用户 11-13 要一比一)
	if _scn._tentacle_vfx.hold_idle:
		var tt = _scn._tentacle_vfx._tents.get(_scn._tentacle_vfx._key("left", 0), null)
		if tt is Dictionary:
			print("[ROTO] f=%d st=%d tl=%.4f" % [Engine.get_frames_drawn(), int(tt["state"]),
				fposmod(_scn._t + float(tt["phase"]) / TAU * TentacleIdleKeys.period(), TentacleIdleKeys.period())])
			## 中心线(相对根部, 世界米; x = 拍击方向, y = 高, z = 侧向) —— 「线对线」对比用
			var mp = tt.get("mv_pts", null)
			if mp is PackedVector3Array and mp.size() > 1:
				var sl := PackedStringArray()
				for q in mp:
					sl.append("%.3f,%.3f,%.3f" % [q.x, q.y, q.z])
				print("[LINE] f=%d " % Engine.get_frames_drawn() + ";".join(sl))
				## 背侧(鳍那一侧 / 截面朝向)在根部的方向 —— 量「身子在拧」用
				var dn = tt.get("rig_dn", null)
				if dn is Vector3:
					print("[DN] %.3f,%.3f,%.3f" % [dn.x, dn.y, dn.z])
	## 每次状态切换打一行(并排对时间用): [ST] 帧 战斗时钟 状态
	var tt2 = _scn._tentacle_vfx._tents.get(_scn._tentacle_vfx._key("left", 0), null)
	## SIDE_SCR=1: 每帧打出中心线投影到屏幕上的像素坐标(真实中心线, 不是抠图) —— 「在原图上画条线」对照用(用户 11-13)
	if OS.get_environment("SIDE_SCR") == "1" and tt2 is Dictionary:
		var cen = tt2.get("center", null)
		if cen is PackedVector3Array and cen.size() > 1:
			var sl2 := PackedStringArray()
			for q in cen:
				var sp: Vector2 = _scn._cam.unproject_position(q)
				sl2.append("%.1f,%.1f" % [sp.x, sp.y])
			print("[SCR] t=%.4f st=%d " % [_scn._t, int(tt2["state"])] + ";".join(sl2))
			var dn2 = tt2.get("rig_dn", null)
			if dn2 is Vector3 and not _scn._tentacle_vfx.hold_idle:
				var mp2 = tt2.get("mv_pts", null)
				if mp2 is PackedVector3Array and mp2.size() > 1:
					print("[LINE] f=0 %.3f,%.3f,%.3f;%.3f,%.3f,%.3f" % [mp2[0].x, mp2[0].y, mp2[0].z, mp2[1].x, mp2[1].y, mp2[1].z])
				print("[DN] %.3f,%.3f,%.3f" % [dn2.x, dn2.y, dn2.z])
				var mr2 = tt2.get("mv_r", null)
				var mp3 = tt2.get("mv_pts", null)
				if mr2 is PackedFloat32Array and mp3 is PackedVector3Array:
					var sr := PackedStringArray()
					for q2 in range(mp3.size()):
						sr.append("%.3f,%.3f,%.3f,%.3f" % [mp3[q2].x, mp3[q2].y, mp3[q2].z, mr2[mini(q2, mr2.size() - 1)]])
					print("[RAD] " + ";".join(sr))
	if tt2 is Dictionary and int(tt2["state"]) != _last_st:
		_last_st = int(tt2["state"])
		print("[ST] f=%d t=%.3f st=%d" % [Engine.get_frames_drawn(), _scn._t, _last_st])
	if _scn._t > _secs:
		get_tree().quit(0)
