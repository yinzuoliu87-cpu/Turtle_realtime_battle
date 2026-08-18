extends Node
## _probe_interactive.gd — 各屏【可点击/可交互元素】的全面清点(2026-08-18, 只量不判)
##
## 由来: 用户问「所有可以点击和交互的地方都考虑了吗」。
## 现有 `verify_click_targets_alive` 有两个缺口, 这个探针先把它们量出来:
##   ① 它实例化的是**空背包** —— 33 个格子、6 张卡片根本没建出来, 只量到 6 个可点控件
##   ② 它的判据是 `gui_input + MOUSE_FILTER_IGNORE`, **完全覆盖不到 `Button`**
##      (按钮走 `pressed` 信号, 不走 gui_input) —— 一个 IGNORE 的 Button 同样是死的
##
## 量三件事:
##   A. 每屏的可交互元素总数(gui_input 的 + Button 的 + 有 pressed 连接的)
##   B. 其中【收不到点击】的(IGNORE)
##   C. 其中【还用 Godot 默认皮】的 Button —— 圆角纯色, 是"没游戏味"最直接的来源
##   D. 触控热区不足 44pt(=81 视口像素) 的
##
## 跑法: <godot> --headless --path . res://tests/_probe_interactive.tscn --quit-after 20000

const SCENES: Array = [
	["res://scenes/MainMenu.tscn", ""],
	["res://scenes/Inventory.tscn", "res://tests/_setup_inv_demo.gd"],
	["res://scenes/Codex.tscn", ""],
	["res://scenes/TeamSelect.tscn", ""],
	["res://scenes/Settings.tscn", ""],
	["res://scenes/Record.tscn", ""],
]

const TOUCH_MIN := 81.0     # 44pt × 1.846


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	print("=== 各屏可交互元素清点(热区下限 %.0fpx = 44pt) ===" % TOUCH_MIN)
	var tot_i := 0
	var tot_dead := 0
	var tot_stock := 0
	var tot_small := 0
	for row in SCENES:
		var path: String = str(row[0])
		var setup: String = str(row[1])
		if not ResourceLoader.exists(path):
			continue
		if setup != "" and ResourceLoader.exists(setup):
			var sc = load(setup)
			if sc != null and sc.has_method("run"):
				sc.run()
		var ps: PackedScene = load(path)
		var inst = ps.instantiate()
		add_child(inst)
		for _i in range(14):
			await get_tree().process_frame
		var n_i := 0
		var n_dead := 0
		var n_stock := 0
		var stock_names: Array = []
		var small: Array = []
		var st: Array = [inst]
		while not st.is_empty():
			var n: Node = st.pop_back()
			if n is Control and (n as Control).is_visible_in_tree():
				var c := n as Control
				var is_btn: bool = c is BaseButton
				var wired: bool = c.gui_input.get_connections().size() > 0
				if is_btn or wired:
					n_i += 1
					if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
						n_dead += 1
					## ⚠ 判据第一版把 `flat = true` 的按钮也算成"默认皮" —— 那是**透明点击层**,
					##   Godot 对 flat 按钮**什么都不画**(主菜单那 8 个就是: 视觉由下面那张金框图给,
					##   Button 只负责接点击)。它们不是"没游戏味", 是**故意没有视觉**。
					##   ⇒ 排除 flat, 否则报出来的 12 个里大半是假的。
					## ⚠ 判据第二次太宽: `TextureButton` 用**贴图**不用 stylebox,
					##   `has_theme_stylebox_override` 对它永远是 false ⇒ 被误报成"默认皮"。
					##   主菜单那两个 82×82 就是它(本来就有自己的美术)。
					##   ⇒ 只判真正吃 stylebox 的 `Button`, 且排除 flat(透明点击层)。
					##   (同一晚第五次判据宽窄不对 —— 每次都是"没问对问题"而不是代码错。)
					if c is Button and not (c as Button).flat 							and not c.has_theme_stylebox_override("normal"):
						n_stock += 1
						stock_names.append("「%s」%.0fx%.0f" % [
							str((c as Button).text).substr(0, 10), c.size.x, c.size.y])
					## ⚠ 判据第一版是 `min(w,h) < 81` ⇒ 把 416×62 的整行也算成"难点",
					##   而那种横向 225pt 宽的条**很好命中**, 报出来只是噪音(82 个里大半是它)。
					##   收紧成【两个方向都不够大】: 短边 < 44pt **且** 长边 < 200px(不是整行/整列)。
					##   —— 判据要刚好卡住"真的难点"那个形状。
					var w: float = c.size.x
					var h: float = c.size.y
					if w > 1.0 and h > 1.0 and minf(w, h) < TOUCH_MIN and maxf(w, h) < 200.0:
						small.append("%.0fx%.0f" % [w, h])
			for ch in n.get_children():
				st.append(ch)
		tot_i += n_i
		tot_dead += n_dead
		tot_stock += n_stock
		tot_small += small.size()
		print("  %-18s 可交互 %3d · 收不到点击 %d · 默认皮按钮 %2d %s · 热区不足 %2d %s"
		% [path.get_file(), n_i, n_dead, n_stock,
		   str(stock_names.slice(0, 3)) if not stock_names.is_empty() else "",
		   small.size(), str(small.slice(0, 3)) if not small.is_empty() else ""])
		inst.queue_free()
		await get_tree().process_frame
	print("  ────────────────────────────────────────")
	print("  合计: 可交互 %d · 死的 %d · 默认皮按钮 %d · 热区不足 %d"
		% [tot_i, tot_dead, tot_stock, tot_small])
	print("PROBE DONE")
	get_tree().quit(0)
