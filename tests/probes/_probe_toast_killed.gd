extends Node
## _probe_toast_killed.gd — 复核 ②: 背包 toast 生下来那一帧就被 _rebuild() 销毁
## 只打数, 不判定。

const InvScene := preload("res://scripts/scenes/InventoryScene.gd")

func _walk(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)

func _labels_with(sc: Node, needle: String) -> Array:
	var all: Array = []
	_walk(sc, all)
	var hit: Array = []
	for l in all:
		if str((l as Label).text).find(needle) >= 0:
			hit.append(l)
	return hit

func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(1280, 720)
	for _q in range(4):
		await get_tree().process_frame
	GameState.test_mode = true

	# 一只装满 3 件的统领 + 背包里还有一件 → 再装 = 撞单只上限分支
	var ids: Array = DataRegistry.phase2_equipment_by_id.keys()
	var e0 := str(ids[0])
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	GameState.persistent_equipped = {"basic": [
		{"id": e0, "star": 1}, {"id": e0, "star": 1}, {"id": e0, "star": 1}]}
	GameState.persistent_bench = [{"id": str(ids[1]), "star": 1}]

	var sc = InvScene.new()
	get_tree().root.add_child(sc)
	for _i in range(12):
		await get_tree().process_frame

	var before: int = _labels_with(sc, "已装满").size()
	print("[probe] 触发前 屏上『已装满』Label 数 = ", before)
	print("[probe] 分母: 该龟身上件数 = ", (GameState.persistent_equipped.get("basic", []) as Array).size(),
		" / 背包件数 = ", GameState.persistent_bench.size(), " / 上限 = ", sc.P2.UNIT_EQUIP_CAP)

	sc._sel_bench = 0
	sc._inv_ops._equip_to("basic", 0)

	# 同一帧(同步)就查一次 —— toast 的 add_child 是同步的
	print("[probe] 同帧 立刻查: ", _labels_with(sc, "已装满").size(), " 个")
	for k in range(1, 7):
		await get_tree().process_frame
		print("[probe] +%d 帧: 『已装满』Label = %d 个" % [k, _labels_with(sc, "已装满").size()])

	## 分母二: 那次操作真的走到了 toast 分支吗 —— 走到了就【不会装上】(件数不变)
	print("[probe] 操作后 该龟件数 = ", (GameState.persistent_equipped.get("basic", []) as Array).size(),
		" / 背包件数 = ", GameState.persistent_bench.size())
	print("PROBE DONE")
	get_tree().quit(0)
