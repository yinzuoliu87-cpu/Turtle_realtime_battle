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

## 羁绊详情弹框：**该类型的全部档位**逐条列出，当前档高亮。点暗幕/关闭 关。
##
## ★★2026-08-04 重写。原来这里有两个都会让玩家【看不到已经写好的内容】的毛病：
##   ① `for ti in [1, 2, 3]` —— **档数写死成 3**。而奇械/法器/灵物/遗物是 `[2,5,8,10]`
##      四档 ⇒ **这四个类型的顶档在背包里根本不画**。
##   ② 每档一个**固定 66px** 的 Label（620 宽 · 14 号字 ≈ 每行 40 字 · 约容 3 行 = 120 字），
##      而逐类型评审后文案变长了：盾档1 209 字、弓箭三档 189/163/164、遗物 147/124/160…
##      ⇒ **10 个类型里 6 个被截断**。
##   ⇒ 现在：档数读 `TIER_DESCS` 的真实长度；文案放 RichTextLabel + 滚动，
##      框高按内容算并钳在视口内（同图鉴详情那边的做法）。
##
## ⚠ 别再写死任何"3 档" —— `TYPES` 里两种档制并存（`[3,6,9]` 与 `[2,5,8,10]`），
##   写死一个就等于把另一种的最后一档藏起来，而且【不报错、不留痕】。
func _show_synergy_popup(type_key: String, cur_tier: int) -> void:
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: dim.queue_free())
	host.add_child(dim)

	var descs: Array = host.Phase2Types.TIER_DESCS.get(type_key, [])
	var thresh: Array = (host.Phase2Types.TYPES.get(type_key, {}) as Dictionary).get("tiers", [])
	# 拼一段 bbcode：每档一小节，当前档高亮。★档数来自数据，不是写死的 [1,2,3]。
	var bb := ""
	for i in range(descs.size()):
		var txt: String = str(descs[i])
		if txt.strip_edges() == "":
			continue
		var th: int = int(thresh[i]) if i < thresh.size() else 0
		var col: String = "#ffd93d" if (i + 1) == cur_tier else "#9fb0c0"
		bb += ("" if bb == "" else "

") + "[color=%s][b]%d 件[/b][/color]  [color=%s]%s[/color]" % [col, th, col, txt]

	var bw := 620.0
	# 框高按内容估：每档标题 + 文案行数。估多了下面 minf 会钳住，估少了 RichTextLabel 自己能滚。
	var body_h: float = 0.0
	for d in descs:
		body_h += 26.0 + ceilf(float(str(d).length()) / 38.0) * 20.0
	# ⚠ 上限用设计框高 `host.H`（1280×720 的那个 720），**不是 `host._vh`** ——
	#   InventoryScene 上【没有 `_vh` 这个字段】（只有 `_vw`），写 `_vh` 会恒为 0
	#   ⇒ maxf 兜到 280、每个类型的框都一样矮，等于白改。
	#   本屏是"内容锁 1280×720 居中"的设计框口径（`_rebuild` 注释），所以按 H 算才对得上。
	var bh: float = clampf(body_h + 130.0, 260.0, host.H - 120.0)

	var box = Panel.new()
	var sb = StyleBoxFlat.new(); sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(host._vw / 2.0 - bw / 2.0, maxf(24.0, host.H / 2.0 - bh / 2.0))
	box.size = Vector2(bw, bh)
	box.mouse_filter = Control.MOUSE_FILTER_STOP   # 框内不穿透关闭
	dim.add_child(box)

	var ttl = Label.new()
	ttl.text = "%s %s   (当前 档%d / 共 %d 档)" % [host.Phase2Types.emoji_of(type_key),
		host.Phase2Types.display_name(type_key), cur_tier, descs.size()]
	ttl.add_theme_font_size_override("font_size", 24); ttl.add_theme_color_override("font_color", Color("#ffd93d"))
	ttl.position = Vector2(24, 18); ttl.size = Vector2(bw - 48, 34); box.add_child(ttl)

	# ★RichTextLabel + 滚动：文案再长也不会被吃掉（原来是固定 66px 的 Label，直接截断）
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = false
	rt.scroll_active = true
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.add_theme_font_size_override("bold_font_size", 15)
	rt.position = Vector2(24, 62)
	rt.size = Vector2(bw - 48, bh - 62 - 62)
	rt.text = bb
	box.add_child(rt)

	var ok = Button.new(); ok.text = "关闭"; ok.add_theme_font_size_override("font_size", 18)
	ok.position = Vector2(bw / 2.0 - 60, bh - 52); ok.size = Vector2(120, 40)
	ok.pressed.connect(func(): dim.queue_free())
	box.add_child(ok)


## 阵容玩法帮助弹窗 (把原来常驻的教程字收到这·按需看)
