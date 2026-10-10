extends Node
## _probe_codex_shot —— 图鉴某一件装备 / 某只龟那一页截图(看「玩家看到的是什么」)。探针, 不进门禁, 要非无头跑。
##   CODEX_TAB=equips|pets|synergies  CODEX_ID=p2eq_052(羁绊页写类型名, 如 剑)  CODEX_OUT=C:/tmp/x.png

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
	## CODEX_ID=minion:front|back|elite —— 深海小将(虚拟条目, 没有 id, 按 _minion 认)
	for i in range(items.size()):
		var _it: Dictionary = items[i]
		if str(_it.get("id", _it.get("_type", ""))) == want or (want.begins_with("minion:") and str(_it.get("_minion", "")) == want.substr(7)):
			cs.call("_select", i)
			break
	## CODEX_IDX=N: 直接按左栏序号选(中文类型名走环境变量在 Windows 上会被代码页弄乱)
	if OS.get_environment("CODEX_IDX") != "":
		cs.call("_select", int(OS.get_environment("CODEX_IDX")))
	## CODEX_FORM=1: 双形态龟切到另一形态(与点「切换至…形态」钮同一个状态位)
	if OS.get_environment("CODEX_FORM") == "1" and tab == "pets":
		await get_tree().process_frame
		cs.set("_codex_form_view", true)
		cs.get("_codex_detail").call("_show_pet", _find_pet(want))
	## CODEX_PASSIVE=1: 展开被动(与点被动条同一个状态位)
	if OS.get_environment("CODEX_PASSIVE") == "1" and tab == "pets":
		await get_tree().process_frame
		cs.set("_codex_passive_view", true)
		cs.get("_codex_detail").call("_show_pet", _find_pet(want))
	## CODEX_STAR=1|2|3: 装备页切到那一档再截(走 CodexDetail._set_eq_star, 与点签牌同一个入口)
	var want_star := OS.get_environment("CODEX_STAR")
	if want_star != "" and tab == "equips":
		await get_tree().process_frame
		var cur: Dictionary = DataRegistry.phase2_equipment_by_id.get(want, {})
		cs.get("_codex_detail").call("_set_eq_star", cur, int(want_star))
	## CODEX_WAIT=帧: 等入场滑动落位(实拍要 400 帧上下才干净)
	for _i in range(maxi(20, int(OS.get_environment("CODEX_WAIT")))):
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


func _find_pet(pid: String) -> Dictionary:
	for p in DataRegistry.launch_pets:
		if str((p as Dictionary).get("id", "")) == pid:
			return p
	return {}
