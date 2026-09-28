extends Node
## _shot_tsround.gd — 选龟屏实拍(给人看, 不是门禁)
## 跑法: <godot> --path . res://tests/_shot_tsround.tscn --position 5000,5000 --resolution 1280x720
##   OUT 环境变量指定输出目录(默认 C:/tmp/tsshots/after)

func _ready() -> void:
	var out: String = OS.get_environment("TSOUT")
	if out == "":
		out = "C:/tmp/tsshots/after"
	DirAccess.make_dir_recursive_absolute(out)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		if int(gs.season_total_battles) <= 0:
			gs.season_total_battles = 3
	await get_tree().process_frame
	var ps: PackedScene = load("res://scenes/TeamSelect.tscn")
	var inst = ps.instantiate()
	add_child(inst)
	for _i in range(60):
		await get_tree().process_frame
	# ① 空阵容 + 第 0 格 active(待填)
	inst.team = [null, null, null]
	inst._active_slot_idx = 0
	inst._refresh_all()
	for _i in range(40):
		await get_tree().process_frame
	await _save(out + "/1_empty.png")
	# ② 两只就位 + 详情打开
	var ids: Array = []
	for p in DataRegistry.launch_pets:
		ids.append(str(p["id"]))
		if ids.size() >= 3:
			break
	inst.team = [ids[0], null, ids[1]]
	inst._active_slot_idx = 1
	inst._selected_slot_idx = -1
	inst.detail_pet_id = ids[0]
	inst._refresh_all()
	for _i in range(40):
		await get_tree().process_frame
	await _save(out + "/2_filled.png")
	# ③ 满阵容 + 选中一格
	inst.team = [ids[0], ids[1], ids[2]]
	inst._active_slot_idx = -1
	inst._selected_slot_idx = 1
	inst._refresh_all()
	for _i in range(40):
		await get_tree().process_frame
	await _save(out + "/3_full.png")
	# ④ 未解锁(dev_locked)形态 —— 现在没有任何一只龟的技能没标 impl,
	#   所以这一态**数据上走不到**。临时把 idx=2 的 impl 拿掉, 把那一格逼出来拍一张。
	var pet0: Dictionary = DataRegistry.pet_by_id.get(ids[0], {})
	var pool: Array = pet0.get("skillPool", [])
	if pool.size() > 2 and pool[2] is Dictionary:
		(pool[2] as Dictionary)["impl"] = false
		inst.detail_pet_id = ids[0]
		inst._detail._refresh_detail()
		for _i in range(30):
			await get_tree().process_frame
		await _save(out + "/4_devlocked.png")
		(pool[2] as Dictionary)["impl"] = true
	print("SHOT DONE -> %s" % out)
	get_tree().quit(0)


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("  saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])
