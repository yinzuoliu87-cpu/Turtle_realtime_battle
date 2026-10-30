extends Node
## _shot_teamselect.gd — 选龟页实拍(给人看, 不是门禁): 全选版 / 锁定版。
## 由来: 2026-10-30 选龟页整页重做(方案书 docs/plans/20261030-选龟页重做.md)。
## LOCKED=1 = 锁定版(打了一周的号: 统领已定、身上有装备 ⇒ 羁绊纸上有字); 否则全选版(三只上阵、点选第二格、看第一只)。
## 每态拍两张: all(稀有度「全部」) / S(只看 S)。锁定版没有龟池, 两张一样。
## 跑法: TSOUT=<目录> [LOCKED=1] WINDOW=1 bash godot-quiet.sh --position 2000,80 --resolution 1560x720 res://tests/_shot_teamselect.tscn

var ts


func _ready() -> void:
	var out: String = OS.get_environment("TSOUT")
	if out == "":
		out = "C:/tmp/teamselect"
	DirAccess.make_dir_recursive_absolute(out)
	GameState.test_mode = true
	if int(GameState.season_total_battles) <= 0:
		GameState.season_total_battles = 3
	var locked := OS.get_environment("LOCKED") == "1"
	if locked:
		load("res://tests/_setup_appstore.gd").run()
	else:
		GameState.season_leaders = []
	await get_tree().process_frame
	ts = (load("res://scenes/TeamSelect.tscn") as PackedScene).instantiate()
	add_child(ts)
	for _i in range(60):
		await get_tree().process_frame
	if not locked:
		var ids: Array = []
		for p in DataRegistry.launch_pets:
			if str(p.get("rarity", "")) in ["SS", "S", "A"] and ids.size() < 3:
				ids.append(str(p["id"]))
		ts.team = ids
		ts._active_slot_idx = -1
		ts._selected_slot_idx = 1
		ts.detail_pet_id = ids[0]
		ts._refresh_all()
	for _i in range(20):
		await get_tree().process_frame
	await _shot(out, "all", locked)
	if not locked:
		ts.filter_rarity = "S"
		ts._pet_grid._refresh_grid()
		for _i in range(20):
			await get_tree().process_frame
		await _shot(out, "S", locked)
	print("SHOT DONE -> ", out)
	get_tree().quit(0)


func _shot(out: String, tag: String, locked: bool) -> void:
	for _i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var vs := get_viewport().get_visible_rect().size
	get_viewport().get_texture().get_image().save_png("%s/%s_%s_%dx%d.png" % [out, "locked" if locked else "open", tag, int(vs.x), int(vs.y)])
