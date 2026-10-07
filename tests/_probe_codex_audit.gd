extends Node
## _probe_codex_audit.gd — 图鉴全量截图 + 文本转储(2026-10-06 内测前体检, 只量不判·非门禁)
## 跑法(要窗口, 无头拿不到视口):
##   AUD_OUT=C:/tmp/codex_audit/1280 QUIET=1 <godot> --path . res://tests/_probe_codex_audit.tscn --resolution 1280x720 --position 2000,80
## 产物: <AUD_OUT>/<tab>_<i>[_suffix].png + <AUD_OUT>/dump.txt(每页所有可见文字 + 疑似溢出)

const SCN := preload("res://scenes/Codex.tscn")
var _inst
var _out := ""
var _dump: PackedStringArray = []


func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])


func _texts(n: Node, acc: PackedStringArray) -> void:
	for c in n.get_children():
		if c is RichTextLabel:
			acc.append("[RT] " + (c as RichTextLabel).get_parsed_text().replace("\n", " ⏎ "))
		elif c is Label:
			acc.append("[L] " + (c as Label).text.replace("\n", " ⏎ "))
		elif c is Button:
			acc.append("[B] " + (c as Button).text)
		_texts(c, acc)


## 详情内控件超出详情框右缘 / 富文本被裁(不含技能卡: 那些有自己的"点开看全部"机制)
func _overflow(tag: String) -> void:
	var fr: Rect2 = _inst.detail_frame.get_global_rect()
	for c in _inst.detail.get_children():
		if not (c is Control) or not (c as Control).visible:
			continue
		var ctl := c as Control
		var r := ctl.get_global_rect()
		if c is Label:
			var lbl := c as Label
			var f: Font = lbl.get_theme_font("font")
			var fs: int = lbl.get_theme_font_size("font_size")
			var w: float = f.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f else r.size.x
			if r.position.x + w > fr.position.x + fr.size.x - 4.0 or r.position.x < fr.position.x:
				_dump.append("  !! OVERFLOW-X %s 「%s」 x0=%.0f ink_right=%.0f frame_right=%.0f" % [tag, lbl.text, r.position.x, r.position.x + w, fr.position.x + fr.size.x])
		elif c is RichTextLabel:
			var rt := c as RichTextLabel
			if r.position.x + r.size.x > fr.position.x + fr.size.x + 1.0:
				_dump.append("  !! RT-WIDER-THAN-FRAME %s 「%s」 right=%.0f frame_right=%.0f" % [tag, rt.get_parsed_text().substr(0, 30), r.position.x + r.size.x, fr.position.x + fr.size.x])
			if not rt.fit_content and rt.get_content_height() > rt.size.y + 1.0 and rt.size.y < 30.0:
				_dump.append("  !! ONE-LINE-CLIPPED %s 「%s」 content_h=%.0f box_h=%.0f" % [tag, rt.get_parsed_text().substr(0, 60), rt.get_content_height(), rt.size.y])


func _capture(tag: String) -> void:
	await _settle(4)
	var acc: PackedStringArray = []
	_texts(_inst.detail, acc)
	_dump.append("=== %s ===" % tag)
	_dump.append_array(acc)
	_overflow(tag)
	await _shot(tag)
	var vs: VScrollBar = _inst._detail_scroll.get_v_scroll_bar()
	if vs.max_value - vs.page > 4.0:
		_inst._detail_scroll.scroll_vertical = int(vs.max_value)
		await _settle(2)
		await _shot(tag + "_bottom")
		_dump.append("  (scrollable: max=%.0f page=%.0f)" % [vs.max_value, vs.page])
		_inst._detail_scroll.scroll_vertical = 0


func _ready() -> void:
	_out = OS.get_environment("AUD_OUT")
	DirAccess.make_dir_recursive_absolute(_out)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	_inst = SCN.instantiate()
	add_child(_inst)
	await get_tree().create_timer(1.0).timeout
	var only := OS.get_environment("AUD_TABS")
	for tab in ["pets", "equips", "synergies", "status"]:
		if only != "" and not only.split(",").has(tab):
			continue
		_inst._switch_tab(tab)
		await get_tree().create_timer(0.8).timeout
		# 列表整体: 顶部 + 滚到底
		await _shot("%s_list_top" % tab)
		_inst.list_scroll.scroll_vertical = 100000
		await _settle(3)
		await _shot("%s_list_bottom" % tab)
		_inst.list_scroll.scroll_vertical = 0
		var lacc: PackedStringArray = []
		_texts(_inst.list_vbox, lacc)
		_dump.append("=== LIST %s (%d items) ===" % [tab, _inst._items.size()])
		_dump.append_array(lacc)
		for i in range(_inst._items.size()):
			_inst._select(i)
			var it: Dictionary = _inst._items[i]
			var nm: String = str(it.get("id", it.get("_minion", it.get("_type", i))))
			await _capture("%s_%02d_%s" % [tab, i, nm])
			if tab == "pets" and not it.has("_minion"):
				# 被动展开
				_inst._codex_passive_view = true
				_inst._codex_detail._show_pet(it)
				await _capture("%s_%02d_%s_passive" % [tab, i, nm])
				_inst._codex_passive_view = false
				# 每个技能详情(普通池 + 形态池)
				var pools := [["s", it.get("skillPool", [])], ["m", it.get("meleeSkills", [])], ["v", it.get("volcanoSkills", [])]]
				for pl in pools:
					var arr = pl[1]
					if not (arr is Array):
						continue
					for k in range((arr as Array).size()):
						_inst._codex_form_view = (pl[0] != "s")
						_inst._codex_skill_detail = arr[k]
						_inst._codex_detail._show_pet(it)
						await _capture("%s_%02d_%s_%s%d" % [tab, i, nm, pl[0], k])
					_inst._codex_skill_detail = {}
				_inst._codex_form_view = false
				# 形态卡片视图
				if (it.get("meleeSkills", []) is Array and not (it.get("meleeSkills", []) as Array).is_empty()) \
						or (it.get("volcanoSkills", []) is Array and not (it.get("volcanoSkills", []) as Array).is_empty()):
					_inst._codex_form_view = true
					_inst._codex_detail._show_pet(it)
					await _capture("%s_%02d_%s_formcards" % [tab, i, nm])
					_inst._codex_form_view = false
	var f := FileAccess.open("%s/dump.txt" % _out, FileAccess.WRITE)
	f.store_string("\n".join(_dump))
	f.close()
	print("PROBE DONE shots in ", _out)
	get_tree().quit(0)
