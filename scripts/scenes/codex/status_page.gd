extends RefCounted
## 图鉴·状态详情页(2026-10-10 重做)。
##
## 原来整页只有「图标 + 名字 + 一行效果」, 框下面一大片是背景; 4 个状态写着「数值由来源决定」
## 却不说是谁。现在:
##   头部   图标 / 名字 / 类别
##   效果   status.json 的说明(数字走 {C:类.常量}, 与龟 / 装备文案同一套渲染)
##   来源   龟(技能) / 小将 / 装备 / 羁绊 —— 来自 StatusSources(每条钉着代码位置, 门禁核对),
##          每格带该来源的数值; 点一格跳到那只龟 / 那件装备 / 那个羁绊的图鉴页
## 详情框恒为满高(DETAIL_MAX_H): 内容不够高时补一块透明垫底, 框不再缩成半截露出背景。

const StatusSources := preload("res://scripts/scenes/codex/status_sources.gd")

const CAT := {
	"dot": ["持续伤害", "#ef4444"], "cc": ["控制", "#c77dff"],
	"buff": ["增益", "#06d6a0"], "debuff": ["减益", "#fbbf24"],
}
const GROUPS := [["pet", "龟"], ["minion", "深海小将"], ["eq", "装备"], ["syn", "羁绊"]]
const TO_LABEL := {"self": "自身", "ally": "友军"}
const TILE_W := 421.0
const TILE_H := 60.0
const TILE_GAP := 18.0
const ICON := 40.0
## 数值字号 17: 像素字 m6x11 在 15px 下小数点那 1px 会被缩没(实拍「2.5 秒」印成「25 秒」), 17 与效果正文同号、点在。
const VAL_PX := 17
const TAP_SLOP := 14.0   # 按下→松开位移超过它算拖动(滚页), 不算点

var host
var _press := Vector2.ZERO


func _init(h) -> void:
	host = h


func show(st: Dictionary) -> void:
	host._clear_detail()
	var cat: Array = CAT.get(str(st.get("category", "")), [str(st.get("category", "")), "#58d3ff"])
	var icon_key: String = str(st.get("iconKey", ""))
	host._add_image(70, 72, "res://assets/sprites/status/%s-icon.png" % icon_key.replace("status-", ""), 96, 96, true)
	host._add_text(140, 46, str(st.get("name", "?")), 32, "#ffd93d", 0.0, 0.5, true)
	host._add_text(140, 90, str(cat[0]), 17, str(cat[1]), 0.0, 0.5, true)

	## 「效果」小标题与正文是 detail 的【直接子节点】(与龟 / 装备 / 羁绊页同一约定 ——
	##   多份门禁按 detail 的直接子节点找正文 RichTextLabel 量字号 / 读文字)。
	host._add_text(20, 150, "效果", 17, "#58d3ff", 0.0, 0.0, true)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, 176)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.mouse_filter = Control.MOUSE_FILTER_PASS
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_constant_override("line_separation", 5)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	## 状态说明里的数字走 `{C:类.常量}`(与龟 / 装备文案同一套渲染), 不在 json 里手抄。
	rt.text = SkillText.render_consts(str(st.get("desc", "")))
	host.detail.add_child(rt)

	## 「来源」一整块装进 VBox, 紧跟正文往下排。正文高度要排版后才定(fit_content),
	##   所以挂 resized: 正文每次定高都把来源块顶到它下面(不靠估字宽 / 行数)。
	var col := VBoxContainer.new()
	col.position = Vector2(20, 176 + 34)
	col.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	col.size = Vector2(host.DETAIL_W - 40, 0)
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.detail.add_child(col)
	rt.resized.connect(func() -> void:
		if is_instance_valid(col) and is_instance_valid(rt):
			col.position.y = rt.position.y + rt.size.y + 20.0)

	var srcs: Array = StatusSources.sources_of(str(st.get("id", "")))
	_section(col, "来源")
	if srcs.is_empty():
		col.add_child(_label("无", 17, "#8a93a0"))
	for g in GROUPS:
		var items: Array = srcs.filter(func(e): return str(e.get("k", "")) == str(g[0]))
		if items.is_empty():
			continue
		col.add_child(_label("%s  %d" % [str(g[1]), items.size()], 15, "#9fb3c8"))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", int(TILE_GAP))
		grid.add_theme_constant_override("v_separation", 8)
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(grid)
		for e in items:
			grid.add_child(_tile(e))

	## 垫底: 让内容底边至少到满高, 详情框不再缩成半截(CodexScene._fit_detail_frame 跟内容底边走)。
	var pad := Control.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.position = Vector2(0, 0)
	## 满高 = 与其它页签内容超长时同一个高度(DETAIL_MAX_H), 不另定一套。
	pad.size = Vector2(1, host.DETAIL_MAX_H - host.DETAIL_SCROLL_PAD)
	host.detail.add_child(pad)


func _section(parent: Control, text: String) -> void:
	parent.add_child(_label(text, 17, "#58d3ff"))


func _label(text: String, size: int, color: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(color))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 一个来源格: [图标] 名字 / 技能·对象 …… 数值。整格可点。
func _tile(e: Dictionary) -> Control:
	var info: Dictionary = describe(e)
	var p := Panel.new()
	p.custom_minimum_size = Vector2(TILE_W, TILE_H)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1a2740"); sb.bg_color.a = 0.85
	sb.border_color = Color(str(info["color"])); sb.set_border_width_all(2)
	var box := UISkin.nine_if_big(TILE_W, TILE_H, "slot-frame.png", 12, sb)
	if box is StyleBoxTexture:
		(box as StyleBoxTexture).modulate_color = UISkin.tint_of(Color(str(info["color"])))
	p.add_theme_stylebox_override("panel", box)

	## 内部用 HBox 排: [图标][名字 / 副行(撑满, 超长省略)][数值(按真实字宽)]。
	##   宽度交给容器在树里量 —— 离树的 Label 问不到项目字体链, 自己估字宽会估错。
	var row := HBoxContainer.new()
	row.position = Vector2(10, 0)
	row.size = Vector2(TILE_W - 24, TILE_H)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var ic: Control = info["icon"]
	if ic == null:
		ic = Control.new()
	ic.custom_minimum_size = Vector2(ICON, ICON)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var nm := _label(str(info["name"]), 17, "#ffffff")
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(nm)
	var sub: String = str(info["sub"])
	if sub != "":
		var sl := _label(sub, 14, "#9fb3c8")
		sl.clip_text = true
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(sl)
	var val: String = StatusSources.render_value(str(e.get("v", "")))
	if val != "":
		var vl := _label(val, VAL_PX, "#ffd93d")
		vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(vl)
	p.set_meta("status_src", e)
	p.gui_input.connect(func(ev: InputEvent) -> void: _on_tile_input(ev, e))
	return p


func _on_tile_input(ev: InputEvent, e: Dictionary) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			_press = mb.global_position
		elif mb.global_position.distance_to(_press) <= TAP_SLOP:
			open(e)


## 一条来源 → {name, sub, color, icon(Control 或 null)}。纯查表, 不碰场景树(门禁也调它)。
func describe(e: Dictionary) -> Dictionary:
	var k := str(e.get("k", ""))
	var id := str(e.get("id", ""))
	var to_lbl: String = str(TO_LABEL.get(str(e.get("to", "")), ""))
	var out := {"name": id, "sub": to_lbl, "color": "#7a8a96", "icon": null}
	match k:
		"pet":
			var pet: Dictionary = DataRegistry.pet_by_id.get(id, {})
			out["name"] = str(pet.get("name", id))
			out["color"] = "#4cc9f0"
			var sk := skill_of(pet, str(e.get("sk", "")))
			var bits: PackedStringArray = []
			if not sk.is_empty():
				bits.append("%s · %s" % [str(sk.get("name", "")), _role(pet, sk)])
			if to_lbl != "":
				bits.append(to_lbl)
			out["sub"] = "  ".join(bits)
			out["icon"] = _tex("res://assets/sprites/avatars/%s.png" % id)
		"minion":
			for mk in MinionCodex.MINION_KINDS:
				if str(mk.get("kind", "")) == id:
					out["name"] = str(mk.get("name", id))
					out["icon"] = _tex("res://assets/sprites/pets/%s" % str(mk.get("img", "")))
			var info: Dictionary = MinionCodex.MINION_INFO.get(id, {})
			var bits2: PackedStringArray = []
			if str(e.get("sk", "")) != "" and str(info.get("skill_name", "")) != "":
				bits2.append("%s · 技能" % str(info.get("skill_name", "")))
			elif str(e.get("pv", "")) != "":
				bits2.append("%s · 被动" % str(e["pv"]))
			if to_lbl != "":
				bits2.append(to_lbl)
			out["sub"] = "  ".join(bits2)
			out["color"] = "#cdd9c2"
		"eq":
			var ed: Dictionary = DataRegistry.phase2_equipment_by_id.get(id, {})
			out["name"] = str(ed.get("name", id))
			out["color"] = str(host.COST_COLOR.get(int(ed.get("cost", 1)), "#94a3b8")) if host != null else "#94a3b8"
			out["sub"] = ("属性" + ("  " + to_lbl if to_lbl != "" else "")) if e.has("derived") else to_lbl
			out["icon"] = EquipIcon.make(ed, Vector2(ICON, ICON), true) if not ed.is_empty() else null
		"syn":
			out["name"] = id + "羁绊"
			out["color"] = str(host._type_color(id)) if host != null else "#7a8a96"
			out["sub"] = ("属性" + ("  " + to_lbl if to_lbl != "" else "")) if e.has("derived") else to_lbl
			var tp: String = str(host._type_icon(id)) if host != null else ""
			out["icon"] = _tex(tp, true)
	return out


## 龟身上 type == sk 的那一张技能卡(普通技能组 / 形态技组 / 被动)。
static func skill_of(pet: Dictionary, sk: String) -> Dictionary:
	if sk == "":
		return {}
	var pas = pet.get("passive", {})
	if pas is Dictionary and str((pas as Dictionary).get("type", "")) == sk:
		return pas
	for key in pet.keys():
		var arr = pet[key]
		if (str(key) == "skillPool" or str(key).ends_with("Skills")) and arr is Array:
			for s in arr:
				if s is Dictionary and str((s as Dictionary).get("type", "")) == sk:
					return s
	return {}


func _role(pet: Dictionary, sk: Dictionary) -> String:
	var pas = pet.get("passive", {})
	if pas is Dictionary and is_same(pas, sk):
		return "被动"
	if host == null:
		return "技能"
	match str(host.skill_role_of(pet, sk)):
		"basic": return "攻击"
		"passive": return "被动"
	return "技能"


func _tex(path: String, native: bool = false) -> Control:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED if native else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return tr


## 跳到来源自己的图鉴页(与点左栏那一行走同一个入口 _switch_tab + _select)。
func open(e: Dictionary) -> void:
	var k := str(e.get("k", ""))
	var id := str(e.get("id", ""))
	var tab := ""
	match k:
		"pet", "minion": tab = "pets"
		"eq": tab = "equips"
		"syn": tab = "synergies"
	if tab == "":
		return
	host._switch_tab(tab)
	## ★_switch_tab 会先把第 0 条画出来; 龟页在下一帧还要回头量技能卡(_fit_skill_cards),
	##   同一帧里立刻 _select 换页会把那批卡释放掉 ⇒ 它下一帧读到已释放节点报 SCRIPT ERROR。
	##   等两帧让第 0 条走完再换(龟页那个函数不在本页地盘, 不改它)。
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if not is_instance_valid(host) or str(host.current_tab) != tab:
		return
	var items: Array = host._items
	for i in range(items.size()):
		var it = items[i]
		if not (it is Dictionary):
			continue
		var d := it as Dictionary
		var hit := false
		match k:
			"pet", "eq": hit = str(d.get("id", "")) == id and not d.has("_minion")
			"minion": hit = str(d.get("_minion", "")) == id
			"syn": hit = str(d.get("_type", "")) == id
		if hit:
			host._select(i)
			return
