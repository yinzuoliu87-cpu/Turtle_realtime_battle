extends Node
## verify_codex_scroll_reset.gd — 图鉴换条目时详情区回到顶部(2026-10-13 内测截图)
##
## 用户截图: 镇海杵 / 银色箭袋 / 枪羁绊 三页的标题都被详情框上沿挡住一截。本机同比例实拍标题完整 ⇒
##   不是版式, 是【滚动位置】: 在上一条往下滚过, 点下一条时详情区不归零(_select 只重画不复位)。
## 判据: 三个页签各选第 1 条 ⇒ 详情区滚到底 ⇒ 选第 2 条 ⇒ 几帧后 scroll_vertical == 0。
##   分母: 滚到底之前内容确实超出一屏(否则没东西可滚, 判据恒真)。

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 图鉴换条目时详情区回到顶部 ===")
	var cs = (load("res://scenes/Codex.tscn") as PackedScene).instantiate()
	add_child(cs)
	for _i in range(6):
		await get_tree().process_frame
	for tab in ["equips", "synergies", "pets"]:
		cs.call("_switch_tab", tab)
		for _i in range(4):
			await get_tree().process_frame
		var items: Array = cs.get("_items")
		var sc: ScrollContainer = cs.get("_detail_scroll")
		## 找一条内容超出一屏的当「上一条」
		var src := -1
		for i in range(mini(items.size(), 30)):
			cs.call("_select", i)
			for _j in range(4):
				await get_tree().process_frame
			if sc.get_v_scroll_bar().max_value > sc.size.y + 40.0:
				src = i
				break
		_ok("%s 分母: 找到内容超出一屏的条目" % tab, src >= 0)
		if src < 0:
			continue
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
		await get_tree().process_frame
		_ok("%s 分母: 已滚离顶部(%d)" % [tab, sc.scroll_vertical], sc.scroll_vertical > 0)
		var dst: int = (src + 1) % items.size()
		cs.call("_select", dst)
		for _j in range(6):
			await get_tree().process_frame
		_ok("%s ★换条目后详情区回到顶部" % tab, sc.scroll_vertical == 0, "scroll_vertical=%d" % sc.scroll_vertical)
	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 图鉴换条目时详情区回到顶部 (%d/%d)" % [_n, _n])
	get_tree().quit(1 if _fail > 0 else 0)
