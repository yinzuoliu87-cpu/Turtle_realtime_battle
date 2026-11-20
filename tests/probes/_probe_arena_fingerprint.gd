extends Node
## _probe_arena_fingerprint —— 四张新图建场后的世界树逐节点导出(2026-11-20 删旧图前后对比用; 方案书 docs/plans/20261120b-删除旧地图.md)。
##   ARENA_FP_OUT=res://.out/arena_fp/before godot --headless --path . res://tests/probes/_probe_arena_fingerprint.tscn
## 每张图两条路: dev = 调试场(开发工具那条建场路), formal = 正式双路对局(开到开打第一帧, MapProps 已建)。
## 每行: 节点路径(去掉引擎自动编号) | 类型 | 贴图路径 | 位置 / 缩放取两位 | 显隐。行排序后写 <OUT>_<图>_<路>.txt。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AT := preload("res://scripts/gamedata/arena_theme.gd")
const Backend := preload("res://scripts/net/backend.gd")
const THEMES := ["dusk", "reef", "shoal", "storm"]
const SEED := 424242


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var out: String = OS.get_environment("ARENA_FP_OUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	for th in THEMES:
		var a: Array = await _run_dev(th)
		_write(out, th, "dev", a)
		var b: Array = await _run_formal(th)
		_write(out, th, "formal", b)
	print("[FP] done")
	get_tree().quit()


func _write(out: String, th: String, mode: String, lines: Array) -> void:
	lines.sort()
	var p: String = ProjectSettings.globalize_path("%s_%s_%s.txt" % [out, th, mode])
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("\n".join(PackedStringArray(lines)))
	f.close()
	print("[FP] %s %s %d 行 → %s" % [th, mode, lines.size(), p])


func _dump(n: Node, prefix: String, acc: Array) -> void:
	for c in n.get_children():
		var nm: String = RegEx.create_from_string("@[A-Za-z0-9_]+@\\d+").sub(str(c.name), "@", true)
		nm = RegEx.create_from_string("\\d+$").sub(nm, "#", true)
		var path: String = prefix + "/" + nm
		var tex := ""
		if c is Sprite3D and (c as Sprite3D).texture != null:
			tex = (c as Sprite3D).texture.resource_path
		elif c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			tex = (c as MeshInstance3D).mesh.get_class()
		var pos := ""
		var vis := ""
		if c is Node3D:
			var p3: Vector3 = (c as Node3D).position
			var s3: Vector3 = (c as Node3D).scale
			pos = "%.2f,%.2f,%.2f s%.2f" % [p3.x, p3.y, p3.z, s3.x]
			vis = "v" if (c as Node3D).visible else "h"
		acc.append("%s|%s|%s|%s|%s" % [path, c.get_class(), tex, pos, vis])
		_dump(c, path, acc)


func _run_dev(th: String) -> Array:
	AT.active = th
	RB.DEBUG_EDIT = true
	OS.set_environment("TURTLE_SEED", str(SEED))
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var acc: Array = ["#theme=" + str(AT.active)]
	_dump(s._world, "W", acc)
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	RB.DEBUG_EDIT = false
	return acc


func _run_formal(th: String) -> Array:
	var gs = GameState
	gs.reset_dual_lane()
	gs.test_mode = true
	gs.tutorial_active = false
	gs.week_phase = "ranked"
	gs.season_leaders = ["basic", "stone", "dice"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []}, {"kind": "leader", "slot": 2, "id": "dice", "equips": []}],
	}
	gs.persistent_equipped = {}
	gs.season_level = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	gs.dual_ghost = Backend.make_bot(3, rng)
	gs.dual_active = true
	AT.forced = th
	RB.DEBUG_EDIT = false
	OS.set_environment("TURTLE_SEED", str(SEED))
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	var last := ""
	var st_frames := 0
	for _i in range(900):
		var st: String = str(s._dl_state)
		if st != last:
			last = st
			st_frames = 0
		st_frames += 1
		if (st == "overview" or st == "lane_settle") and st_frames == 9:
			s._dl_sys._dl_present_click()
		s._process(1.0 / 60.0)
		if str(s._dl_state) == "fight":
			break
		await get_tree().process_frame
	var acc: Array = ["#theme=" + str(AT.active), "#state=" + str(s._dl_state)]
	_dump(s._world, "W", acc)
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	AT.forced = ""
	return acc
