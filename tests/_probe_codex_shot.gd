extends Node
## _probe_codex_shot —— 图鉴某一件装备 / 某只龟那一页截图(看「玩家看到的是什么」)。探针, 不进门禁, 要非无头跑。
##   CODEX_TAB=equips|pets  CODEX_ID=p2eq_052  CODEX_OUT=C:/tmp/x.png

func _ready() -> void:
	var cs = (load("res://scenes/Codex.tscn") as PackedScene).instantiate()
	add_child(cs)
	for _i in range(4):
		await get_tree().process_frame
	var tab := OS.get_environment("CODEX_TAB")
	if tab == "":
		tab = "equips"
	cs.call("_switch_tab", tab)
	await get_tree().process_frame
	var want := OS.get_environment("CODEX_ID")
	var items: Array = cs.get("_items")
	for i in range(items.size()):
		if str((items[i] as Dictionary).get("id", "")) == want:
			cs.call("_select", i)
			break
	## CODEX_STAR=1|2|3: 装备页切到那一档再截(走 CodexDetail._set_eq_star, 与点签牌同一个入口)
	var want_star := OS.get_environment("CODEX_STAR")
	if want_star != "" and tab == "equips":
		await get_tree().process_frame
		var cur: Dictionary = DataRegistry.phase2_equipment_by_id.get(want, {})
		cs.get("_codex_detail").call("_set_eq_star", cur, int(want_star))
	for _i in range(20):
		await get_tree().process_frame
	## CODEX_SCROLL=像素: 把装着详情的那个 ScrollContainer 往下滚(看页底的羁绊块)
	var want_scroll := OS.get_environment("CODEX_SCROLL")
	if want_scroll != "":
		var det: Node = cs.get("detail")
		var p: Node = det.get_parent() if det != null else null
		while p != null and not (p is ScrollContainer):
			p = p.get_parent()
		if p is ScrollContainer:
			(p as ScrollContainer).scroll_vertical = int(want_scroll)
		for _i in range(6):
			await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("CODEX_OUT"))
	print("[CODEX] saved ", OS.get_environment("CODEX_OUT"))
	get_tree().quit()
