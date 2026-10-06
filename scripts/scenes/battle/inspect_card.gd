class_name InspectCard
extends RefCounted
## 信息面板【左侧】弹出的独立小卡 —— 点装备 / 技能 / 属性图标时出现(2026-10-06 重做)。
##
## ★用户原话:「人家如果点击了技能图标或装备图标，人家是会弹新窗口来显示技能信息或装备信息的」
##   「比如人家点击图片后，就会弹这种小框」。参考图 docs/plans/ref/20261006-云顶装备弹窗/。
## ★版式照云顶(方案书 docs/plans/20261006-对局信息面板重做.md 第二节):
##   头部 = 图标 + 名字(+ 右侧小标签) → 属性行(图标+数字) → 细线 → 正文
##   → 特殊段/脚注(灰斜体) → [技能] 细线 + 数值拆解表 / [装备] 细线 + 本局统计。
## ★面板本身不动 —— 小卡是挂在 _ui_layer 上的独立节点, 贴着面板左沿。
## ★一次只开一张; 再点同一个图标 = 收起; 面板关了小卡跟着关(见 close())。

const HUD_TEX := "res://assets/sprites/battlehud/"
const CARD_W := 300.0
const GAP := 8.0                      # 小卡右沿与面板左沿的间距
const ICON := 44.0                    # 头部图标边长
const C_TITLE := Color("#f4ead8")
const C_BODY := Color("#d2c7b4")
const C_DIM := Color("#8c7f6c")
const C_LINE := Color(0.65, 0.47, 0.16, 0.55)   # 细线 = 面板黄铜边的淡色

var battle
var card: PanelContainer = null
var key: String = ""
## 每帧刷新要改的节点(技能正文 / 装备本局统计 / 属性数值), 由调用方按 key 取。
var live: Dictionary = {}


func _init(b) -> void:
	battle = b


func is_open(k: String) -> bool:
	return card != null and is_instance_valid(card) and key == k


func close() -> void:
	if card != null and is_instance_valid(card):
		var p := card.get_parent()
		if p != null:
			p.remove_child(card)
		card.queue_free()
	card = null
	key = ""
	live = {}


## 打开一张卡。spec:
##   icon: 贴图路径("" = 不画) · icon_tint: 白模板图标的染色(属性图标用)
##   title · title_col · tag(右上小字, 如「天生」「技能」「★★」) · tag_col
##   stats: [[图标路径, 文字, 颜色], ...] 头部下面那一行(装备加的属性 / 属性当前值)
##   body: bbcode 正文 · foot: bbcode 灰斜体脚注
##   table: [[左, 右], ...] 技能的数值拆解表(两列, bbcode)
##   extra_title + extra: 装备的「本局统计」(纯文本, 每行一项)
## anchor = 被点的那个控件(小卡顶边对齐它)。返回 live 字典。
func open(k: String, anchor: Control, spec: Dictionary) -> Dictionary:
	if is_open(k):
		close()                          # 再点一次 = 收起
		return {}
	close()
	if battle._ui_layer == null or battle._info_panel == null or not is_instance_valid(battle._info_panel):
		return {}
	key = k
	card = PanelContainer.new()
	card.name = "InspectCard"
	card.add_theme_stylebox_override("panel", _frame(spec.get("frame_col", null)))
	card.mouse_filter = Control.MOUSE_FILTER_STOP   # 点在卡上不穿到战场(否则会关掉面板)
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.size = Vector2(CARD_W, 0)
	battle._ui_layer.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)
	_head(vb, spec)
	var stats: Array = spec.get("stats", [])
	if not stats.is_empty():
		_stat_row(vb, stats)
	var body := str(spec.get("body", ""))
	if body != "":
		_line(vb)
		live["body"] = _rtl(vb, body, 14, C_BODY)
	var foot := str(spec.get("foot", ""))
	if foot != "":
		_rtl(vb, foot, 12, C_DIM)
	var table: Array = spec.get("table", [])
	if not table.is_empty():
		_line(vb)
		live["table"] = _table(vb, table)
	if spec.has("extra_title"):
		_line(vb)
		var et := _label(vb, str(spec["extra_title"]), 12, C_DIM)
		et.name = "ExtraTitle"
		var ex := _label(vb, str(spec.get("extra", "")), 13, C_BODY)
		ex.name = "Extra"
		ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		live["extra"] = ex
		live["extra_title"] = et
	_place(anchor)
	return live


## 九宫格框: insp-card.png(新画·深暖黑 + 细黄铜边), 缺图时退回纯色。
func _frame(col = null) -> StyleBox:
	## ★装备卡: 整个框按费用上色(用户 2026-10-06「装备详细窗口也是，名字也是」)。
	if col is Color:
		var cf := StyleBoxFlat.new()
		cf.bg_color = Color(0.07, 0.055, 0.04, 0.98)
		cf.set_border_width_all(2); cf.border_color = col
		cf.set_corner_radius_all(0)
		cf.shadow_color = Color(0, 0, 0, 1); cf.shadow_size = 2
		cf.content_margin_left = 14; cf.content_margin_right = 14
		cf.content_margin_top = 12; cf.content_margin_bottom = 12
		return cf
	var p := HUD_TEX + "insp-card.png"
	if ResourceLoader.exists(p):
		var t := StyleBoxTexture.new()
		t.texture = load(p)
		t.set_texture_margin_all(12)
		t.content_margin_left = 14; t.content_margin_right = 14
		t.content_margin_top = 12; t.content_margin_bottom = 12
		return t
	var f := StyleBoxFlat.new()
	f.bg_color = Color("#120e0a")
	f.set_border_width_all(2); f.border_color = Color("#a5751d")
	f.set_content_margin_all(12)
	return f


func _head(vb: VBoxContainer, spec: Dictionary) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hb)
	var ip := str(spec.get("icon", ""))
	if ip != "" and ResourceLoader.exists(ip):
		var box := PanelContainer.new()
		var bsb: StyleBox = _slot_box()
		if spec.has("icon_border"):          # 装备: 图标框按费用上色(与面板里的槽同色)
			var fb := StyleBoxFlat.new()
			fb.bg_color = Color("#0c0907")
			fb.set_border_width_all(2); fb.border_color = spec["icon_border"]
			fb.set_corner_radius_all(0); fb.set_content_margin_all(3)
			bsb = fb
		box.add_theme_stylebox_override("panel", bsb)
		box.custom_minimum_size = Vector2(ICON, ICON)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(box)
		var tr := TextureRect.new()
		tr.texture = load(ip)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if spec.has("icon_tint"):
			tr.modulate = spec["icon_tint"]
		box.add_child(tr)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(col)
	var tl := _label(col, str(spec.get("title", "")), 17, spec.get("title_col", C_TITLE))
	tl.name = "Title"
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tag := str(spec.get("tag", ""))
	if tag != "":
		_label(col, tag, 12, spec.get("tag_col", C_DIM)).name = "Tag"


## 头部下那一行: 图标 + 数字横排(云顶的 ❤+250 ⚔+25%)。
func _stat_row(vb: VBoxContainer, stats: Array) -> void:
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 12)
	fl.add_theme_constant_override("v_separation", 2)
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.name = "StatRow"
	vb.add_child(fl)
	for s in stats:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 3)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fl.add_child(hb)
		var ip := str(s[0])
		if ip != "" and ResourceLoader.exists(ip):
			var tr := TextureRect.new()
			tr.texture = load(ip)
			tr.modulate = SkillText.stat_icon_color_of(ip)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.custom_minimum_size = Vector2(18, 18)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(tr)
		var l := _label(hb, str(s[1]), 15, s[2] if s.size() > 2 else C_TITLE)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not live.has("stat_lbls"):
			live["stat_lbls"] = []
		(live["stat_lbls"] as Array).append(l)


func _line(vb: VBoxContainer) -> void:
	var r := ColorRect.new()
	r.color = C_LINE
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(r)


func _rtl(vb: Control, bb: String, px: int, col: Color) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("normal_font_size", px)
	t.add_theme_font_size_override("bold_font_size", px)
	t.add_theme_font_size_override("italics_font_size", px)
	t.add_theme_color_override("default_color", col)
	t.custom_minimum_size = Vector2(CARD_W - 28.0, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.text = bb
	vb.add_child(t)
	return t


func _label(parent: Control, txt: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## 技能拆解表: 每行 [左(项目: 当前值 = 系数), 右(补充)]。两列各一个 RichTextLabel。
func _table(vb: VBoxContainer, rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(hb)
		var l := _rtl(hb, str(r[0]), 13, C_BODY)
		l.custom_minimum_size = Vector2(0, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		var rr := _rtl(hb, str(r[1]) if r.size() > 1 else "", 13, C_DIM)
		rr.custom_minimum_size = Vector2(0, 0)
		rr.autowrap_mode = TextServer.AUTOWRAP_OFF
		rr.fit_content = true
		out.append(l)
	return out


func _slot_box() -> StyleBox:
	var p := HUD_TEX + "insp-slot.png"
	if ResourceLoader.exists(p):
		var t := StyleBoxTexture.new()
		t.texture = load(p)
		t.set_texture_margin_all(6)
		t.set_content_margin_all(3)
		return t
	var f := StyleBoxFlat.new()
	f.bg_color = Color("#0c0907")
	return f


## 摆位: 右沿贴面板左沿(留 GAP), 顶边对齐被点的控件; 超出视口就往上收。
## ★高度要等一帧排完版才准(RichTextLabel fit_content) ⇒ 先摆一次, 下一帧再按真实高收一次。
func _place(anchor: Control) -> void:
	_place_now(anchor)
	var c := card
	await battle.get_tree().process_frame
	if c == card and is_instance_valid(c):
		c.size = Vector2(CARD_W, 0)          # 让容器按内容重算高度
		_place_now(anchor)


func _place_now(anchor: Control) -> void:
	if card == null or not is_instance_valid(card):
		return
	var vp: Vector2 = Vector2(battle.get_viewport().get_visible_rect().size)
	var pr: Rect2 = (battle._info_panel as Control).get_global_rect()
	var h: float = maxf(card.get_combined_minimum_size().y, card.size.y)
	var y: float = 54.0
	if anchor != null and is_instance_valid(anchor):
		y = anchor.get_global_rect().position.y - 6.0
	y = clampf(y, 50.0, maxf(50.0, vp.y - h - 8.0))
	card.position = Vector2(pr.position.x - GAP - CARD_W, y)
