extends Node
## 触控热区普查 —— 列出短边 < 44pt(81px) 的可点元素。
##
## ★尺子: 视口高 720 ↔ iPhone 横屏 390pt ⇒ 1pt = 1.846px ⇒ 44pt = 81px。
##   整套界面是在 1280x720 桌面设计空间里用鼠标摆的, 所以"看着够大"的东西在手机上未必够。
## ★两个必须处理的口径:
##   ① 点击层 TouchPad **本身不算**一个可点元素 —— 它是别人的热区。
##      不排除的话数字会反着涨(实测 43 → 51), 看着像越修越糟。
##   ② 有效热区 = 控件自己的矩形 与 它挂的 TouchPad 取大。

const SCENES := ["MainMenu", "Inventory", "Codex", "TeamSelect", "Shop", "Settings", "Record"]
const TOUCH_MIN := 81.0


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	print("=== 触控热区普查(下限 %.0fpx = 44pt) ===" % TOUCH_MIN)
	var tot := 0
	var tot_both := 0
	for scn in SCENES:
		var path := "res://scenes/%s.tscn" % scn
		if not ResourceLoader.exists(path):
			continue
		if scn == "Inventory" and ResourceLoader.exists("res://tests/_setup_inv_demo.gd"):
			var sc = load("res://tests/_setup_inv_demo.gd")
			if sc != null and sc.has_method("run"):
				sc.run()
		var inst = (load(path) as PackedScene).instantiate()
		add_child(inst)
		for _i in range(120):
			await get_tree().process_frame
		var small: Dictionary = {}
		var n_small := 0
		var n_both := 0
		var st: Array = [inst]
		while not st.is_empty():
			var n: Node = st.pop_back()
			if n is Control and (n as Control).is_visible_in_tree() and str(n.name) != "TouchPad":
				var c := n as Control
				var hit: bool = c is BaseButton or c.gui_input.get_connections().size() > 0
				var ew: float = c.size.x
				var eh: float = c.size.y
				var padn = c.get_node_or_null("TouchPad")
				if padn != null and padn is Control:
					ew = maxf(ew, (padn as Control).size.x)
					eh = maxf(eh, (padn as Control).size.y)
				if hit and ew > 1.0 and eh > 1.0 \
						and minf(ew, eh) < TOUCH_MIN and maxf(ew, eh) < 200.0:
					var k := "%.0fx%.0f %s" % [ew, eh, c.get_class()]
					small[k] = int(small.get(k, 0)) + 1
					n_small += 1
					if ew < TOUCH_MIN and eh < TOUCH_MIN:
						n_both += 1
			for ch in n.get_children():
				st.append(ch)
		tot += n_small
		tot_both += n_both
		if n_small > 0:
			print("  %-12s %2d 个 (其中两边都不够的 %d)" % [scn, n_small, n_both])
			for k in small:
				print("        %s x%d" % [k, int(small[k])])
		inst.queue_free()
		await get_tree().process_frame
	print("  合计 %d 个 · 其中【两个方向都不够】的 %d 个(真正难点)" % [tot, tot_both])
	print("PROBE DONE")
	get_tree().quit(0)
