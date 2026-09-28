extends Node
## _probe_infoskill.gd — 探针: 面板上的技能/被动伤害数值到底跟不跟着属性变?
## 只打印, 不断言。走真入口: _show_unit_info_panel → 喂真点击给槽 → 读屏上文字。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var pid := str(OS.get_environment("PROBE_PET"))
	if pid == "": pid = "basic"
	var u: Dictionary = _s._spawn._make_unit(pid, "left", c)
	_s._units.clear()
	_s._units.append(u)
	_s._edit_mode = false
	_s._over = false
	_s.set_process(false)

	print("=== unit: id=%s atk=%.1f base_atk=%.1f active=%s ===" % [
		u.get("id", ""), float(u.get("atk", 0.0)), float(u.get("base_atk", 0.0)),
		str(u.get("active_skills", []))])

	_s._hud._show_unit_info_panel(u)
	for _i in range(4):
		await get_tree().process_frame

	print("\n===== 节点树剖面 (info_panel) =====")
	_dump(_s._info_panel, 0)

	print("\n===== _info_skill_lbls 登记了什么 =====")
	for e in _s._info_skill_lbls:
		var d: Dictionary = e
		print("  lbl=%s  tpl(前60)=%s  sk.type=%s" % [
			str(d.get("lbl", null)), str(d.get("tpl", "")).substr(0, 60),
			str((d.get("sk", {}) as Dictionary).get("type", ""))])

	print("\n===== 逐个槽点开, 读屏上描述 =====")
	var slots := _find_skill_slots(_s._info_panel)
	print("找到 %d 个技能槽" % slots.size())
	for i in range(slots.size()):
		_click(slots[i])
		for _j in range(3):
			await get_tree().process_frame
		var before := _overlay_text()
		# 属性翻倍 —— 走产品自己的 buff 入口(_damage._buff → _recalc_stats)
		var atk0: float = float(u.get("atk", 0.0))
		_s._damage._buff(u, "atk", 1.0, true, 9999.0)
		var atk1: float = float(u.get("atk", 0.0))
		_s._info_sys._refresh_info_panel()
		for _j2 in range(3):
			await get_tree().process_frame
		var after := _overlay_text()
		print("--- 槽 %d ---" % i)
		print("  atk %.1f → %.1f" % [atk0, atk1])
		print("  [修前] ", before.replace("\n", " / "))
		print("  [修后] ", after.replace("\n", " / "))
		print("  两次一样? ", "是 ⇒ BUG 复现" if before == after else "否 ⇒ 会变")
		# 还原 buff, 下一个槽从干净状态起
		(u["buffs"] as Array).clear()
		_s._recalc_stats(u)
		_s._info_sys._refresh_info_panel()
		# 收起浮层
		_click(slots[i])
		await get_tree().process_frame

	print("\n用掉 %d 帧" % Engine.get_process_frames())
	print("PROBE DONE")
	get_tree().quit(0)


func _overlay_text() -> String:
	var ov = _s._info_panel.get_node_or_null("DetailOverlay")
	if ov == null or not ov.visible:
		return "<浮层未开>"
	var bd = ov.get_node_or_null("Box/Body")
	if bd == null:
		return "<无 Body>"
	for ch in bd.get_children():
		if ch is RichTextLabel:
			return str((ch as RichTextLabel).get_parsed_text())
	return "<无 RichTextLabel>"


## 技能槽 = 88×88 的 PanelContainer 且自己接了 gui_input
func _find_skill_slots(n: Node) -> Array:
	var out: Array = []
	_collect_slots(n, out)
	return out


func _collect_slots(n: Node, out: Array) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n is PanelContainer and not (n as Control).gui_input.get_connections().is_empty():
		var cm: Vector2 = (n as Control).custom_minimum_size
		if int(cm.x) == 88 and int(cm.y) == 88:
			out.append(n)
	for ch in n.get_children():
		_collect_slots(ch, out)


func _click(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	c.gui_input.emit(ev)


func _dump(n: Node, d: int) -> void:
	if n == null or not is_instance_valid(n) or d > 7:
		return
	var pad := ""
	for _i in range(d):
		pad += "  "
	var extra := ""
	if n is Label:
		extra = " text='%s'" % str((n as Label).text).replace("\n", "\\n").substr(0, 48)
	elif n is RichTextLabel:
		extra = " rich='%s'" % str((n as RichTextLabel).get_parsed_text()).replace("\n", "\\n").substr(0, 48)
	if n is Control:
		var cc := n as Control
		extra += "  [mf=%d gui=%d cms=%s]" % [cc.mouse_filter, cc.gui_input.get_connections().size(), str(cc.custom_minimum_size)]
	print(pad, n.get_class(), " '", n.name, "'", extra)
	for ch in n.get_children():
		_dump(ch, d + 1)
