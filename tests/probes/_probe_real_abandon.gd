extends Node
## _probe_real_abandon.gd — 真路径复核: 真 change_scene_to_file + 真 ESC 键 → 币还回来了吗
##
## ★怎么在场景切换里活下来: 先把 SceneTree.current_scene 挪给一个替身 —— change_scene_to_file
##   free 的是 current_scene, 于是它 free 掉替身, 本节点(root 的子节点)照常活着接着看。
##   不这么做的话本节点会被 free, 后面的打印一行都不会出现(而进程照样 rc=0)。

var _real: int = 292
var _leaders: Array = ["candy", "ghost", "pirate"]

func _ready() -> void:
	await get_tree().process_frame
	var td = get_node_or_null("/root/TutorialDirector")
	## ★★要看"玩家存档里到底剩多少币"就必须开闸(headless 默认 test_mode=true, save() 空转)。
	##   ⚠ 开闸会**真写 user://savegame.json** ⇒ 必须显式 `TUT_PROBE_ALLOW_SAVE=1`,
	##   且只该配隔离过的 APPDATA 跑(本仓栽过"调试台写真存档")。
	var allow_save: bool = OS.get_environment("TUT_PROBE_ALLOW_SAVE") == "1"
	GameState.test_mode = not allow_save
	GameState.meta_deepsea_coins = _real
	GameState.season_leaders = _leaders.duplicate()
	GameState.persistent_bench = [{"id": "__real_gear__", "star": 3}]
	GameState.onboarded = true            # 别让主菜单又强制拉一遍教学
	if allow_save:
		GameState.save()
	print("[probe] 进教学前: coins=%d leaders=%s | 盘上 coins=%d" % [
		int(GameState.meta_deepsea_coins), str(GameState.season_leaders), _disk_coins()])

	# ── 主菜单「?」→ _begin_tutorial(false) 干的那几件事
	GameState.tutorial = true
	GameState.tutorial_active = true
	GameState.tutorial_stage = "inventory"     # 直接站在"背包课"那一站
	td.begin_sandbox()
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	print("[probe] 教学中: coins=%d leaders=%s" % [int(GameState.meta_deepsea_coins), str(GameState.season_leaders)])

	# ── 替身接住 current_scene, 本节点得以活过两次真场景切换
	var stunt := Node.new()
	stunt.name = "Stunt"
	get_tree().root.add_child(stunt)
	get_tree().current_scene = stunt

	get_tree().change_scene_to_file("res://scenes/Inventory.tscn")
	for _i in range(40):
		await get_tree().process_frame
	print("[probe] 现在这一屏: %s" % str(get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "<null>"))
	if allow_save:
		GameState.save()          # 教学里装一件装备就会走这一步(equip_ops.gd 每个分支末尾)
	print("[probe] 教学中(在背包屏): coins=%d | 盘上 coins=%d | 残留在不在=%s" % [
		int(GameState.meta_deepsea_coins), _disk_coins(),
		str(FileAccess.file_exists(str(td.get("_residue_path"))))])

	# ── 真按 ESC: 走产品自己的 InventoryScene._unhandled_input → change_scene_to_file(MainMenu)
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	Input.parse_input_event(ev)
	for _i in range(60):
		await get_tree().process_frame
	var cs = get_tree().current_scene
	print("[probe] ESC 之后这一屏: %s" % str(cs.scene_file_path if cs != null else "<null>"))
	print("[probe] 看门狗记到的上一屏 = %s ; 快照空吗 = %s ; MAIN_MENU 常量 = %s" % [
		str(td.get("_last_scene_path")), str(td._econ_snapshot.is_empty()), str(td.MAIN_MENU)])
	print("[probe] 手动调 on_abandon() 看它自己灵不灵: %s" % str(td.on_abandon()))
	print("[probe] 手动调之后: coins=%d" % int(GameState.meta_deepsea_coins))
	print("[probe] ★退出后: coins=%d leaders=%s bench=%s" % [
		int(GameState.meta_deepsea_coins), str(GameState.season_leaders), str(GameState.persistent_bench)])
	print("[probe] ★★退出后【盘上】: coins=%d leaders=%s | 残留还在吗=%s" % [
		_disk_coins(), str(_disk_leaders()), str(FileAccess.file_exists(str(td.get("_residue_path"))))])
	print("[probe] 判定: 币还回来了吗 = %s ; leaders 还回来了吗 = %s" % [
		str(int(GameState.meta_deepsea_coins) == _real),
		str(Array(GameState.season_leaders) == _leaders)])
	print("PROBE DONE")
	get_tree().quit(0)


func _disk_coins() -> int:
	return int(_disk().get("meta_deepsea_coins", -1))


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
