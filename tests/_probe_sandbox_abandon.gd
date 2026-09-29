extends Node
## _probe_sandbox_abandon.gd — 复核 ①: 中途退出教学 = 深海币/season_leaders 永久丢
## 真流程: 主菜单「?」→ _begin_tutorial → begin_sandbox() → 教学里有人 save() → 中途走人
## 只打数, 不判定。

func _ready() -> void:
	await get_tree().process_frame
	var td = get_node_or_null("/root/TutorialDirector")
	print("[probe] TutorialDirector=", td != null)
	## ★★要看"盘上到底存成了什么"就必须临时开闸(headless 默认 test_mode=true, save() 空转)。
	##   ⚠ 开闸就会**真写 user://savegame.json** ⇒ 必须显式加 `TUT_PROBE_ALLOW_SAVE=1` 才放行,
	##   而且只该配隔离过的 APPDATA 跑。没给这个开关就只跑内存部分 —— 本仓栽过"调试台写真存档"。
	var allow_save: bool = OS.get_environment("TUT_PROBE_ALLOW_SAVE") == "1"
	if allow_save:
		GameState.test_mode = false
	else:
		print("[probe] ⚠ 没给 TUT_PROBE_ALLOW_SAVE=1 ⇒ 不开存档闸, 盘上那几行会全是 -1(只看内存)")
	# ── 真存档: 292 币 + 三统领
	GameState.meta_deepsea_coins = 292
	GameState.season_leaders = ["candy", "ghost", "pirate"]
	GameState.persistent_bench = [{"id": "__real__", "star": 1}]
	GameState.tutorial_active = false
	GameState.save()
	print("[probe] 进教学前(盘上): coins=%d leaders=%s" % [_disk_coins(), str(_disk_leaders())])

	# ── 主菜单「?」→ _begin_tutorial(false) 干的事
	GameState.tutorial = true
	GameState.tutorial_active = true
	GameState.tutorial_stage = "match1_pick"
	GameState.clear_team()
	td.begin_sandbox()
	print("[probe] begin_sandbox 后(内存): coins=%d leaders=%s" % [int(GameState.meta_deepsea_coins), str(GameState.season_leaders)])
	# ── TeamSelectScene:1346 确认阵容(教学也照写)
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	# ── 教学里买/装一件装备 → equip_ops/ShopScene 都会 GameState.save()
	GameState.save()
	print("[probe] 教学中 save() 后(盘上): coins=%d leaders=%s" % [_disk_coins(), str(_disk_leaders())])

	# ── 中途走人: 背包 ESC → MainMenu (InventoryScene.gd:168)
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	for _i in range(60):
		await get_tree().process_frame
	print("[probe] 回到主菜单后(内存): coins=%d leaders=%s snapshot_empty=%s" % [
		int(GameState.meta_deepsea_coins), str(GameState.season_leaders), str(td._econ_snapshot.is_empty())])
	print("[probe] 回到主菜单后(盘上): coins=%d leaders=%s" % [_disk_coins(), str(_disk_leaders())])
	print("[probe] current_scene=", str(get_tree().current_scene))
	print("PROBE DONE")
	get_tree().quit(0)

func _disk_coins() -> int:
	var d := _disk()
	return int(d.get("meta_deepsea_coins", -1))

func _disk_leaders() -> Array:
	var d := _disk()
	return d.get("season_leaders", []) if d.get("season_leaders", null) is Array else []

func _disk() -> Dictionary:
	var f := FileAccess.open("user://savegame.json", FileAccess.READ)
	if f == null:
		return {}
	var j = JSON.parse_string(f.get_as_text())
	f.close()
	return j if j is Dictionary else {}
