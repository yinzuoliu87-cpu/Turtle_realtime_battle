extends Node
## _probe_cam_extent.gd — 镜头可达范围逐机位实拍(探针, 不进门禁)。
##
## 由来(用户 2026-10-05):「地图的话我们镜头是可以移动缩放的啊，有一堆问题啊」
##   之前四张图只在默认机位验过。这里起【真对局】(SHIP=1, 主题由 ARENA_THEME 强制),
##   跑一会儿冻结, 然后把镜头摆到 默认 / 最近 / 最远 / 各平移极限(上下左右四角)×(最远 / 默认 / 最近) 逐张拍。
##
## 跑法: ARENA_THEME=dusk SHIP=1 CAM_SHOT_DIR=<目录> QUIET=1 <godot> --audio-driver Dummy --path . \
##       --resolution 1560x720 --position 5000,5000 res://tests/_probe_cam_extent.tscn
##   输出 <目录>/<机位名>.png, 每张打一行 CAM_SHOT。

func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	if name != "CamProbeRunner":
		var n := Node.new()
		n.name = "CamProbeRunner"
		n.set_script(get_script())
		get_tree().root.add_child.call_deferred(n)
		get_tree().change_scene_to_file("res://scenes/RealtimeBattle3D.tscn")
		return
	for _i in range(int(OS.get_environment("CAM_WARM")) if OS.has_environment("CAM_WARM") else 240):
		await get_tree().process_frame
	var b = get_tree().current_scene
	var out_dir: String = OS.get_environment("CAM_SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("CAM_PROBE theme=%s  zoom[%.2f..%.2f]  pan_limit=%s" % [ArenaTheme.active, b.CAM_ZOOM_MIN, b.CAM_ZOOM_MAX, str(b.get("PAN_LIMIT"))])
	## ★不冻结战斗: 冻结后血条/名牌停在默认机位的投影处(不跟镜头走), 拍出来像 UI 漂走 —— 那是探针造的假象。
	## 调试: CAM_TINT=<节点名> 把那个节点的材质换成纯品红(看它到底盖在哪)
	if OS.has_environment("CAM_TINT"):
		var tn: Node = b._world.find_child(OS.get_environment("CAM_TINT"), true, false)
		if OS.get_environment("CAM_TINT") == "@water":
			for n in b._world.find_children("*", "MultiMeshInstance3D", true, false):
				if n.material_override is ShaderMaterial and str(n.material_override.shader.resource_path).contains("water"):
					tn = n
		if tn is GeometryInstance3D:
			var mm := StandardMaterial3D.new()
			mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mm.albedo_color = Color(1, 0, 1)
			tn.material_override = mm
	if OS.has_environment("CAM_DUMP"):
		for n in b._world.find_children("*", "GeometryInstance3D", true, false):
			var mo = n.material_override
			if mo is ShaderMaterial and mo.shader != null and str(mo.shader.resource_path).contains("water"):
				print("CAM_DUMP %s %s pos=%s edge_floor=%s crest_deep=%s outer=%s shallow=%s vis=%s" % [n.name, n.get_class(), n.global_position, mo.get_shader_parameter("edge_floor"), mo.get_shader_parameter("crest_deep"), mo.get_shader_parameter("outer_mode"), mo.get_shader_parameter("shallow_col"), n.is_visible_in_tree()])
	var shots: Array = cam_positions(b)
	if OS.has_environment("CAM_ONLY"):
		var only: PackedStringArray = OS.get_environment("CAM_ONLY").split(",")
		shots = shots.filter(func(s): return s[0] in only)
	for s in shots:
		b._shake_amp = 0.0
		b._cam_zoom = s[1]
		b._cam_pan = Vector3.ZERO
		b._apply_cam_zoom()
		## 平移走产品自己的入口(含它的夹紧) —— 拖很远, 让夹紧决定落在哪
		if s[2] != Vector2.ZERO:
			for _k in range(40):
				b._cam_pan_by(-s[2].x * 60.0, -s[2].y * 60.0)
		for _k in range(3):
			await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, s[0]])
		print("CAM_SHOT %s zoom=%.2f pan=%s cam=%s" % [s[0], b._cam_zoom, b._cam_pan, b._cam.position])
	print("CAM_PROBE_DONE n=%d" % shots.size())
	get_tree().quit(0)


## [名字, 缩放, 平移方向(屏幕: x 右 / y 下)]。方向 (1,0) = 视野往右看 = 拖到右极限。
static func cam_positions(b) -> Array:
	var r: Array = [["a_default", 1.0, Vector2.ZERO], ["a_zoom_in", b.CAM_ZOOM_MAX, Vector2.ZERO], ["a_zoom_out", b.CAM_ZOOM_MIN, Vector2.ZERO]]
	var dirs := {"T": Vector2(0, -1), "B": Vector2(0, 1), "L": Vector2(-1, 0), "R": Vector2(1, 0),
		"TL": Vector2(-1, -1), "TR": Vector2(1, -1), "BL": Vector2(-1, 1), "BR": Vector2(1, 1)}
	for zn in [["out", b.CAM_ZOOM_MIN], ["def", 1.0], ["in", b.CAM_ZOOM_MAX]]:
		for k in ["T", "B", "L", "R", "TL", "TR", "BL", "BR"]:
			r.append(["%s_%s" % [zn[0], k], zn[1], dirs[k]])
	return r
