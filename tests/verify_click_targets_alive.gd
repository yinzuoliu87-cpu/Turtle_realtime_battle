extends Node
## verify_click_targets_alive.gd — 【接了点击、却收不到点击】的死处理器扫描 (2026-08-17)
##
## ══════════════════════════════════════════════════════════════════════════
##  由来
## ══════════════════════════════════════════════════════════════════════════
##   2026-08-17 实拍战斗信息面板发现: 技能三槽 / 装备三槽 /「更多属性」/「战利品」
##   **一个都点不动** —— 它们建的时候都设了 `MOUSE_FILTER_STOP` 并接了 `gui_input`,
##   但后面有一句 `_info_passthrough()` 为了"手机能竖滑"把面板里
##   **除 Button 外的控件一律刷成 IGNORE**, 而重做后的可点元素【一个 Button 都没有】。
##   探针数字: 面板里 266 个容器, 真正收得到点击的只有【最外层面板 1 个】。
##   代码里 `_show_detail` 写得好好的, 点上去永远到不了它。
##
## ★这是一类【通用形状】, 不是那一个 bug:
##     接了 gui_input  +  mouse_filter == IGNORE  ⇒ 这个处理器【永远不会被调用】。
##   它不报错、不崩溃、不红任何数值门禁 —— 只是点了没反应。
##   (memory fb-verify-must-run-the-real-path: 断言"函数存在"守不住"还有没有人调"。)
##
## ★判据量【真实节点】: 逐个场景实例化, 遍历整棵树, 找
##   `gui_input.get_connections().size() > 0` 且 `mouse_filter == MOUSE_FILTER_IGNORE`
##   的 Control。不搜源码字符串 —— 源码里两句离得很远, 搜不出来。
##
## 跑法: <godot> --headless --path . res://tests/verify_click_targets_alive.tscn --quit-after 6000

const SCENES: Array = [
	"res://scenes/MainMenu.tscn",
	"res://scenes/Shop.tscn",
	"res://scenes/Inventory.tscn",
	"res://scenes/Codex.tscn",
	"res://scenes/TeamSelect.tscn",
	"res://scenes/Settings.tscn",
	"res://scenes/Record.tscn",
]

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 一棵树里: [接了 gui_input 的控件数, 收不到点击的清单, 有字却挤没了的清单]
##
## ★第三项是另一类同族 bug(2026-08-17 实拍抓到): 资源条的结论那句
##   「攒满变火山形态」在节点树里好端端存在, 量出来 **1x17** —— 屏幕上一个像素都没有。
##   根因是 `clip_text` 把 Label 的最小宽压成 1, 同一行里的弹簧就把它吃光了。
##   ★判据必须量【真实矩形】: "文本非空"那种断言永远绿, 因为文本一直非空。
func _scan(root: Node) -> Array:
	var wired := 0
	var dead: Array = []
	var squashed: Array = []
	var labels := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			var c := n as Control
			if c.gui_input.get_connections().size() > 0:
				wired += 1
				if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
					dead.append("%s(%s)" % [c.name, c.get_class()])
			## ★探针(先只统计, 不判): 【容器的子节点设了非默认 anchors】= 那些设置静默失效。
			##   今晚描述框就栽在这: 写着 offset_top=-300, 挂在 PanelContainer 下 ⇒ 一个像素没生效。
			if n is Label and c.is_visible_in_tree():
				var tx := str((n as Label).text).strip_edges()
				if tx.length() >= 2:
					labels += 1
				## 一个汉字最小也要十几像素; 有字而宽/高不足 6px = 屏幕上根本看不见。
				if tx.length() >= 2 and (c.size.x < 6.0 or c.size.y < 6.0):
					squashed.append("「%s」%.0fx%.0f" % [tx.substr(0, 12), c.size.x, c.size.y])
		for ch in n.get_children():
			stack.append(ch)
	return [wired, dead, squashed, labels]


func _ready() -> void:
	await get_tree().process_frame
	print("=== 死点击处理器扫描(接了 gui_input 却是 IGNORE) ===")
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame

	var total_wired := 0
	var all_dead: Array = []
	var all_squashed: Array = []
	var total_labels := 0
	var opened := 0
	for path in SCENES:
		if not ResourceLoader.exists(str(path)):
			continue
		var ps: PackedScene = load(str(path))
		if ps == null:
			continue
		var inst = ps.instantiate()
		add_child(inst)
		## 入场动画/延迟建树: 多等几帧, 否则量到的是还没建好的空壳。
		for _i in range(8):
			await get_tree().process_frame
		var r := _scan(inst)
		var wired: int = int(r[0])
		var dead: Array = r[1]
		total_labels += int(r[3])
		for sq in (r[2] as Array):
			all_squashed.append("%s → %s" % [str(path).get_file(), str(sq)])
		total_wired += wired
		opened += 1
		if not dead.is_empty():
			for d in dead:
				all_dead.append("%s → %s" % [str(path).get_file(), str(d)])
		print("    [分母] %-22s 接了点击的控件 %d 个, 其中收不到点击 %d 个"
			% [str(path).get_file(), wired, dead.size()])
		inst.queue_free()
		await get_tree().process_frame

	## ── 战斗信息面板 ──────────────────────────────────────────────────────
	##   ★这一段【必须有】: bug 本来就出在这里, 只扫独立场景的话,
	##     这个门禁抓不到它自己的起因 —— 那种门禁是弱的。
	##   面板不是独立场景, 要建战斗场再开一次面板才量得到。
	var RB := load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	var bs = RB.new()
	add_child(bs)
	await get_tree().process_frame
	await get_tree().process_frame
	bs._units.clear()
	bs._edit_mode = false
	bs._over = false
	bs.set_process(false)
	var c: Vector2 = bs.ARENA.position + bs.ARENA.size * 0.5
	var bu: Dictionary = bs._spawn._make_unit("lava", "left", c)
	bu["equips"] = [{"id": "p2eq_004", "star": 2}, {"id": "p2eq_021", "star": 1}]
	## ★必须喂【专属资源】—— 不喂的话带结论文字的那一行根本不会建出来,
	##   "有字却挤没了"这条断言就走不到, 变成空检查。
	##   (第一版就是这样: 反向验证把 clip_text 放回 true, 门禁照样全绿。)
	bu["rage"] = 30.0
	bu["shield"] = 240.0
	bu["burn_stacks"] = 5.0
	bs._units.append(bu)
	bs._hud._show_unit_info_panel(bu)
	for _k in range(6):
		await get_tree().process_frame
	## ★还要【把描述浮层打开】—— 它是点开才建的。不开的话浮层里的节点一个都扫不到,
	##   而"容器子节点的锚静默失效"那条判据的起因正在浮层里 ⇒ 又是一次判据走不到。
	##   (今晚第二次栽在同一形状: 断言本身没错, 是被测对象没被造出来。)
	var _ents: Array = bs._info_sys._skill_bar_entries(bu)
	if not _ents.is_empty():
		var _e0: Dictionary = _ents[_ents.size() - 1]
		bs._info_sys._show_detail(bs._info_panel, "scan", str(_e0.get("name", "")),
			str(_e0.get("desc", "")), _e0, bu)
	for _k2 in range(6):
		await get_tree().process_frame
	if bs._info_panel != null and is_instance_valid(bs._info_panel):
		var rb2 := _scan(bs._info_panel)
		total_wired += int(rb2[0])
		opened += 1
		for d2 in (rb2[1] as Array):
			all_dead.append("战斗信息面板 → %s" % str(d2))
		total_labels += int(rb2[3])
		for s2 in (rb2[2] as Array):
			all_squashed.append("战斗信息面板 → %s" % str(s2))
		print("    [分母] %-22s 接了点击的控件 %d 个, 其中收不到点击 %d 个"
			% ["战斗信息面板", int(rb2[0]), (rb2[1] as Array).size()])
	else:
		all_dead.append("战斗信息面板: 没建出来(下面是空检查)")
	bs.queue_free()
	await get_tree().process_frame

	## ★分母先立住: 一个场景都没开 / 一个 gui_input 都没找到 = 这是空检查, 不是通过。
	_ok("★分母: 真的实例化了场景(含战斗信息面板)", opened >= 6, "开了 %d 个" % opened)
	_ok("★分母: 真的找到了接点击的控件(N=0 是空检查)", total_wired >= 5,
		"共 %d 个控件接了 gui_input" % total_wired)

	_ok("★★没有【接了点击却收不到点击】的死处理器", all_dead.is_empty(),
		"死的: %s" % str(all_dead.slice(0, 8)))

	_ok("★分母: 真的扫到了带字的标签(0 个 = 下面是空检查)", total_labels >= 40,
		"扫到 %d 个" % total_labels)
	_ok("★★没有【有字却被挤成看不见】的标签", all_squashed.is_empty(),
		"挤没的: %s" % str(all_squashed.slice(0, 8)))

	## ★★这里【本来想加第三条】: "给容器的子节点设贴边/居中锚 = 静默失效"
	##   (今晚描述框就栽在这: 写着 offset_top=-300, 挂在 PanelContainer 下, 一个像素没生效)。
	##   **做不成, 已放弃, 原因记在这里免得下次再试**:
	##   Godot 的 `Container::fit_child_in_rect` 在排版时会把子节点的锚点
	##   【重置成 TOP_LEFT】—— 我设的贴边锚在运行时已经被抹掉, 证据在测量之前就没了。
	##   实测: 把描述框退回原 bug 的形状(外层换成 PanelContainer), 这条断言【照样全绿】。
	##   ⇒ 一个永远不会红的断言比没有更糟(它制造虚假信心), 所以不留。
	##   这一类只能靠 verify_info_panel_fits 那条"描述框不许铺满面板"从【后果】上守 ——
	##   量不到原因就量后果, 别留一条量不到的。

	print("")
	print("  (共 %d 条断言 · 扫了 %d 个场景 · %d 个接点击的控件)" % [_n, opened, total_wired])
	if _fail == 0:
		print("ALL PASS — 点击处理器都活着")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
