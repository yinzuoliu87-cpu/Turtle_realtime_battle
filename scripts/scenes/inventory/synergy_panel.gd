class_name InvSynergy
extends RefCounted
## 背包·类型羁绊面板+详情弹框
## 类内名不变;外部名加 battle.

var host

func _init(b) -> void:
	host = b

func _team_equips_for_synergy() -> Array:
	var all_equips: Array = []
	for pid in host._lineup_ids():
		for it in GameState.persistent_equipped.get(str(pid), []):
			all_equips.append(it)
	var lineup = GameState.get_dual_lineup()
	for lk in ["top", "bottom"]:
		for u in lineup.get(lk, []):
			if u is Dictionary and str(u.get("kind", "")) == "minion" and u.get("equips", null) is Array:
				for it in u.get("equips", []):
					all_equips.append(it)
	return all_equips

# 右侧类型羁绊(大改): 只显名称+档位, 点击弹框看完整效果; 计入小将装备.
# 右侧类型羁绊(大改): 只显名称+档位, 点击弹框看完整效果; 计入小将装备.
func _build_synergy_panel(leaders: Array) -> void:
	var w = 300.0                    # 羁绊窄列(用户2026-07-18"不要这么多空间")·靠右
	var x0 = host._vw - w - 28.0
	var hdr = Label.new(); hdr.text = "类型羁绊"
	hdr.add_theme_font_size_override("font_size", 17); hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(x0, 100); hdr.size = Vector2(w, 24); host.add_child(hdr)
	var cy = 132.0
	if host._sel_bench >= 0:   # 装备模式上下文提示: 引导玩家凑同类型激活/升档羁绊(用户2026-07-19)
		var ctx = Label.new(); ctx.text = "▸ 给同一只装多件同类型 → 激活 / 升档"
		ctx.add_theme_font_size_override("font_size", 13); ctx.add_theme_color_override("font_color", Color("#7fe39a"))
		ctx.position = Vector2(x0, 126); ctx.size = Vector2(w, 18); ctx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; host.add_child(ctx)
		cy = 152.0
	var active: Array = host.Phase2Types.calc_active([{"_p2_equips": _team_equips_for_synergy()}])
	if active.is_empty():
		var e = Label.new(); e.text = "（给龟 / 小将装多件同类型装备 → 激活羁绊）"
		e.add_theme_font_size_override("font_size", 13); e.add_theme_color_override("font_color", Color("#5a6675"))
		e.position = Vector2(x0, cy); e.size = Vector2(w, 40); e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; host.add_child(e)
		return
	var y = cy
	for a in active:
		var t = str(a.get("type", ""))
		var tier = int(a.get("tier", 1))
		var chip = Panel.new()
		var csb = StyleBoxFlat.new()
		csb.bg_color = Color("#16263a"); csb.border_color = Color("#3e6a8e")
		csb.set_border_width_all(2); csb.set_corner_radius_all(8)
		chip.add_theme_stylebox_override("panel", csb)
		chip.position = Vector2(x0, y); chip.size = Vector2(w, 40); host.add_child(chip)
		var nm = Label.new()
		nm.text = "%s %s  ×%d   档%d" % [host.Phase2Types.emoji_of(t), host.Phase2Types.display_name(t), int(a.get("count", 0)), tier]
		nm.add_theme_font_size_override("font_size", 16); nm.add_theme_color_override("font_color", Color("#ffd93d"))
		nm.position = Vector2(12, 8); nm.size = Vector2(w - 40, 24); nm.mouse_filter = Control.MOUSE_FILTER_IGNORE; chip.add_child(nm)
		var arw = Label.new(); arw.text = "›"; arw.add_theme_font_size_override("font_size", 20); arw.add_theme_color_override("font_color", Color("#7fb0d8"))
		arw.position = Vector2(w - 26, 4); arw.size = Vector2(18, 30); arw.mouse_filter = Control.MOUSE_FILTER_IGNORE; chip.add_child(arw)
		chip.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _show_synergy_popup(t, tier))
		y += 48.0

## 羁绊详情弹框: 1/2/3 档效果全列, 当前档高亮. 点暗幕/关闭 关.
func _show_synergy_popup(type_key: String, cur_tier: int) -> void:
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: dim.queue_free())
	host.add_child(dim)
	var bw = 620.0; var bh = 320.0
	var box = Panel.new()
	var sb = StyleBoxFlat.new(); sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(host._vw / 2.0 - bw / 2.0, 190.0); box.size = Vector2(bw, bh)
	box.mouse_filter = Control.MOUSE_FILTER_STOP   # 框内不穿透关闭
	dim.add_child(box)
	var ttl = Label.new(); ttl.text = "%s %s   (当前 档%d)" % [host.Phase2Types.emoji_of(type_key), host.Phase2Types.display_name(type_key), cur_tier]
	ttl.add_theme_font_size_override("font_size", 24); ttl.add_theme_color_override("font_color", Color("#ffd93d"))
	ttl.position = Vector2(24, 18); ttl.size = Vector2(bw - 48, 34); box.add_child(ttl)
	var y = 66.0
	for ti in [1, 2, 3]:
		var d = str(host.Phase2Types.tier_desc(type_key, ti))
		if d.strip_edges() == "":
			continue
		var l = Label.new(); l.text = "档%d:  %s" % [ti, d]
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color("#ffd93d") if ti == cur_tier else Color("#9fb0c0"))
		l.position = Vector2(24, y); l.size = Vector2(bw - 48, 66); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(l)
		y += 72.0
	var ok = Button.new(); ok.text = "关闭"; ok.add_theme_font_size_override("font_size", 18)
	ok.position = Vector2(bw / 2.0 - 60, bh - 52); ok.size = Vector2(120, 40)
	ok.pressed.connect(func(): dim.queue_free())
	box.add_child(ok)


## 阵容玩法帮助弹窗 (把原来常驻的教程字收到这·按需看)
