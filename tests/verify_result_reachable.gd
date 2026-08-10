extends Node
## verify_result_reachable.gd — 结算屏【按钮必须点得到】门禁 (2026-08-10)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 用户实测「战斗结束后如果名单很多, 根本点不到回到主菜单的按钮」
## ══════════════════════════════════════════════════════════════════
## 结算卡是 `CenterContainer > PanelContainer > VBoxContainer`, 按钮行加在
## 【数据表下面】。而数据表那个 ScrollContainer **没有任何高度上限** ——
## 名单一长, 整张卡就比视口还高; CenterContainer 居中它 ⇒ **上下两头都溢出屏幕**,
## 按钮行正好在下面那一头 ⇒ 点不到, 玩家被卡死在结算屏(只能杀进程)。
##
## ★这条为什么必须量【真实屏幕矩形】而不是"算一下高度":
##   memory [[fb-write-without-reader-and-fake-gates]] —— 门禁模拟公式 ≠ 量真实对象。
##   这里一律走 `get_global_rect()`, 并要求它**完整落在视口内**。
##
## ★分母: 必须真的造出一份【长名单】, 否则卡片不够高、这条断言永远绿(空检查)。
##   所以先塞满单位再开结算, 并断言"卡片确实比某个下限高"。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_result_reachable.tscn --quit-after 1800

const SCENE := "res://scenes/RealtimeBattle3D.tscn"

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])


func _ready() -> void:
	await get_tree().process_frame
	## ★★强制真实视口: 无头下 `--resolution` **不生效**(实测四个分辨率全拿到 1280x1280),
	##   而项目是 canvas_items + expand / 基准 1280x720 ⇒ 真机上逻辑高度恒为 720。
	##   不强制的话这条门禁测的是一个现实中不存在的方形视口 —— **永远拓不到 bug**。
	var _vpw: int = int(OS.get_environment("RR_W")) if OS.get_environment("RR_W") != "" else 1280
	var _vph: int = int(OS.get_environment("RR_H")) if OS.get_environment("RR_H") != "" else 720
	get_tree().root.content_scale_size = Vector2i(_vpw, _vph)
	get_tree().root.size = Vector2i(_vpw, _vph)
	for _q in range(4):
		await get_tree().process_frame
	var sc = load(SCENE).instantiate()
	get_tree().root.add_child(sc)
	for _i in range(30):
		await get_tree().process_frame

	# ── 造一份【长名单】: 两边各塞满, 让数据表撑到最高 ──────────────
	var made := 0
	for side in ["left", "right"]:
		for k in range(14):
			var u = sc._spawn._make_unit("green", side, sc.ARENA.position + sc.ARENA.size * 0.5
				+ Vector2(-260.0 + 34.0 * float(k), -140.0 + 120.0 * (0.0 if side == "left" else 1.0)))
			if u is Dictionary:
				# 给点伤害数据, 否则统计表可能整行不画
				u["dmg_done"] = 1000.0 + 137.0 * float(k)
				u["dmg_taken"] = 500.0 + 91.0 * float(k)
				u["heal_done"] = 40.0 * float(k)
				## ★★必须真的推进 `_units` —— 第一版只调了 `_make_unit`, 它不入队,
				##   结果统计面板只按场上原有 9 个单位画 ⇒ 面板才 306 高,
				##   根本够不到 y=511 那行按钮 ⇒ **断言假绿**。
				##   名单长度就是这条门禁的被测条件, 塑不够高等于没测。
				if not sc._arr_has_unit(sc._units, u):
					sc._units.append(u)
				made += 1
	_ok("★分母: 造出 %d 个单位(名单要足够长, 否则这条是空检查)" % made, made >= 24, "made=%d" % made)
	for _i in range(6):
		await get_tree().process_frame

	# ══ ★★先把【伤害统计面板】打开 ══
	#   用户实测「名单很多时点不到回主菜单」—— 那个面板有个 **0.4 秒自刷计时器**,
	#   `render()` 第一行就是 `_to_front()` ⇒ 它会把自己反复提到 _ui_layer 最前。
	#   而 `_show_banner()` 只收了投降面板, 没管它 ⇒ 结算卡建好后 0.4 秒内被盖住。
	#   ★所以这条门禁必须①真的把面板开着 ②喂过 0.4 秒 —— 少一样都拓不到。
	sc._on_dmg_stats_toggle()   ## ★走真入口(它会先 setup 再 toggle), 不直接调内部函数
	for _i in range(4):
		await get_tree().process_frame
	_ok("★分母: 伤害统计面板真的开着(没开 = 下面那条是空检查)",
		sc._dmg_stats.panel != null and sc._dmg_stats.panel.is_visible_in_tree())

	# ── 开结算 ────────────────────────────────────────────────────
	sc._hud._show_banner(true)
	## ★喂过 0.4 秒的自刷周期 —— 面板就是在那一刻把自己提到最前的。
	##   只等几帧的话结算卡还在上面, 断言会假绿。
	var _w := 0.0
	while _w < 0.9:
		await get_tree().process_frame
		_w += get_process_delta_time()
	for _i in range(10):
		await get_tree().process_frame

	var vp: Vector2 = sc.get_viewport().get_visible_rect().size
	var vrect := Rect2(Vector2.ZERO, vp)
	_ok("★分母: 拿到视口尺寸", vp.x > 100.0 and vp.y > 100.0, str(vp))

	# ── 找到结算屏上所有按钮, 量它们的真实屏幕矩形 ──────────────────
	var btns: Array = []
	_collect_buttons(sc._ui_layer, btns)
	_ok("★分母: 结算屏上找到 %d 个按钮(0 个 = 没开出来, 下面全是空检查)" % btns.size(),
		btns.size() >= 1, "btns=%d" % btns.size())

	var shell: Control = _find_shell(sc._ui_layer)
	var outside: Array = []
	for b in btns:
		var r: Rect2 = (b as Control).get_global_rect()
		# 完整落在视口内才算"点得到" —— 露出一半也可能点不中
		if r.position.y < 0.0 or r.end.y > vp.y or r.position.x < 0.0 or r.end.x > vp.x:
			outside.append("%s @ %s" % [str((b as Button).text), str(r)])
	_ok("★★结算屏每个按钮都完整落在屏幕内(名单再长也点得到)",
		outside.is_empty(), "溢出的: %s" % str(outside))

	# 卡片本体也不该比视口高 —— 高了就说明没有任何高度约束
	if shell != null:
		var sr: Rect2 = shell.get_global_rect()
		_ok("★分母: 结算卡真的很高(%.0f px) —— 不够高说明名单没塞进去" % sr.size.y,
			sr.size.y > 260.0, "卡高 %.0f" % sr.size.y)
		_ok("★★结算卡整体不超出视口高度(超出 ⇒ 上下两头够不到)",
			sr.position.y >= -1.0 and sr.end.y <= vp.y + 1.0,
			"卡 %s / 视口高 %.0f" % [str(sr), vp.y])

	# ══ ★★真实命中测试: "在屏幕内" 不等于 "点得到" ══
	#   可能被别的 Control 盖住(mouse_filter 不是 IGNORE 就会吃掉点击)。
	#   ★★不自己写"找最上层" —— 第一版我手写了一个遍历, 它的顺序根本不是
	#   Godot 的命中顺序, 直接造出 5 条假阳性。改成**推一个鼠标移动事件进去,
	#   读引擎自己的 `gui_get_hovered_control()`** —— 那才是真正会收到点击的控件。
	#   (memory [[fb-hand-rolled-copies-drift]]: 就地手写标准层已有的东西 = 拄一次永远落后一次。)
	var vpt: Viewport = sc.get_viewport()
	## ★只查【结算卡内】的按钮: 战斗 HUD 自己的按钮被结算暗幕盖住是**应该的**,
	##   把它们一起算进来会造出一堆假阳性(第一版就是这么红的)。
	var card_btns: Array = []
	if shell != null:
		_collect_buttons(shell, card_btns)
	_ok("★分母: 结算卡内找到 %d 个按钮" % card_btns.size(), card_btns.size() >= 1)
	var unclickable: Array = []
	for b in card_btns:
		var bc: Control = b
		var ctr: Vector2 = bc.get_global_rect().get_center()
		var mm := InputEventMouseMotion.new()
		mm.position = ctr
		mm.global_position = ctr
		vpt.push_input(mm)
		await get_tree().process_frame
		var hov: Control = vpt.gui_get_hovered_control()
		if hov != bc:
			unclickable.append("%s 上面是 %s(%s)" % [str((bc as Button).text),
				(hov.name if hov != null else "<null>"), (hov.get_class() if hov != null else "-")])
	# ── 诊断: 面板到底在哪、树序多少 ──
	var _pn: Control = sc._dmg_stats.panel
	if _pn != null:
		print("    [探针] 面板 rect=%s  树序=%d  可见=%s"
			% [str(_pn.get_global_rect()), _pn.get_index(), str(_pn.is_visible_in_tree())])
	if shell != null:
		print("    [探针] 结算卡 rect=%s  center 树序=%d"
			% [str(shell.get_global_rect()), shell.get_parent().get_index()])
	print("    [探针] battle._units = %d  _ui_layer 子节点 %d"
		% [sc._units.size(), sc._ui_layer.get_child_count()])
	for b in card_btns:
		print("    [探针] 按钮 '%s' rect=%s" % [str((b as Button).text), str((b as Control).get_global_rect())])

	_ok("★★每个按钮中心点真的能命中它自己(引擎命中测试, 不是我手算的)",
		unclickable.is_empty(), str(unclickable))

	sc.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 结算屏按钮可达" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button and (n as Control).is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)


## 结算卡 = CenterContainer 下面那个 PanelContainer。
func _find_shell(n: Node) -> Control:
	if n is CenterContainer:
		for c in n.get_children():
			if c is PanelContainer:
				return c as Control
	for c in n.get_children():
		var r: Control = _find_shell(c)
		if r != null:
			return r
	return null
