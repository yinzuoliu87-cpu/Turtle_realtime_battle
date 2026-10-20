extends RefCounted
## blocklist_panel.gd —— 设置 → 账号 →「黑名单」(2026-10-20 · App Store 审核指南 1.2)。
##
## 名单本体在 `scripts/util/blocklist.gd`(只存在本机)。这里只管看与移出: 一行 = 拉黑时看到的昵称 + 玩家 ID +「移出」。
## 拉黑的入口不在这里, 在各屏的玩家菜单(`scripts/scenes/social/player_menu.gd`)。
## ★皮照抄问题反馈弹框(压暗底 + `panel-frame` 九宫格 + `UISkin.pixel_button`)。

const BL := preload("res://scripts/util/blocklist.gd")

const BOX := Vector2(620.0, 460.0)
const ROW_H := 64.0

## 【门禁按名字找的节点】
const LAYER := "BlocklistLayer"
const LIST := "BlocklistList"
const EMPTY := "BlocklistEmpty"
const ROW_PREFIX := "BlocklistRow"
const BTN_REMOVE := "BlocklistRemove"
const BTN_CLOSE := "BlocklistClose"

const TITLE := "黑名单"
const NOTE := "黑名单中的玩家昵称显示为默认昵称。名单仅保存在本设备。"
const MSG_EMPTY := "黑名单为空"
const L_REMOVE := "移出"
const L_CLOSE := "关闭"


static func open(host: Control) -> Control:
	var old := host.get_node_or_null(LAYER)
	if old != null:
		return old as Control
	var dim := ColorRect.new()
	dim.name = LAYER
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(dim)

	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#5aa0ff")
	sb.set_border_width_all(3); sb.set_corner_radius_all(0)
	var rtex := UISkin.nine("panel-frame.png", 20, sb)
	if rtex is StyleBoxTexture:
		(rtex as StyleBoxTexture).modulate_color = UISkin.tint_of(Color("#5aa0ff"))
	box.add_theme_stylebox_override("panel", rtex)
	var vs: Vector2 = host.get_viewport_rect().size
	box.position = (vs - BOX) * 0.5
	box.size = BOX
	dim.add_child(box)

	var ttl := Label.new()
	ttl.text = TITLE
	ttl.add_theme_font_size_override("font_size", 24)
	ttl.add_theme_color_override("font_color", Color("#cfe3ff"))
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)
	ttl.position = Vector2(0, 18); ttl.size = Vector2(BOX.x, 32)
	var nt := Label.new()
	nt.text = NOTE
	nt.add_theme_font_size_override("font_size", 13)
	nt.add_theme_color_override("font_color", Color("#8fa6bd"))
	nt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nt.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	box.add_child(nt)
	nt.position = Vector2(30, 54); nt.size = Vector2(BOX.x - 60.0, 22)

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	sc.position = Vector2(30, 88); sc.size = Vector2(BOX.x - 60.0, 270)
	var list := VBoxContainer.new()
	list.name = LIST
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var empty := Label.new()
	empty.name = EMPTY
	empty.text = MSG_EMPTY
	empty.add_theme_font_size_override("font_size", 17)
	empty.add_theme_color_override("font_color", Color("#8a9bb0"))
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(empty)
	empty.position = Vector2(30, 200); empty.size = Vector2(BOX.x - 60.0, 30)
	_fill(list, empty)

	var cl := Button.new()
	cl.name = BTN_CLOSE
	cl.text = L_CLOSE
	cl.focus_mode = Control.FOCUS_NONE
	cl.add_theme_font_size_override("font_size", 18)
	UISkin.pixel_button(cl, UISkin.PX_SLATE, 4)
	box.add_child(cl)
	cl.position = Vector2(BOX.x / 2.0 - 125.0, 376); cl.size = Vector2(250, 56)
	cl.pressed.connect(func() -> void: dim.queue_free())
	return dim


static func _fill(list: VBoxContainer, empty: Label) -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var es: Array = BL.entries()
	empty.visible = es.is_empty()
	var i := 0
	for e in es:
		var row := HBoxContainer.new()
		row.name = ROW_PREFIX + str(i)
		row.set_meta("tag", str(e["tag"]))
		row.custom_minimum_size = Vector2(0, ROW_H)
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		var nv := VBoxContainer.new()
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.alignment = BoxContainer.ALIGNMENT_CENTER
		nv.add_theme_constant_override("separation", 0)
		row.add_child(nv)
		var nl := Label.new()
		nl.text = str(e["name"]) if str(e["name"]) != "" else str(e["tag"])
		nl.add_theme_font_size_override("font_size", 18)
		nl.add_theme_color_override("font_color", Color("#e8eef5"))
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nv.add_child(nl)
		var tl := Label.new()
		tl.text = str(e["tag"])
		tl.add_theme_font_size_override("font_size", 13)
		tl.add_theme_color_override("font_color", Color("#8796a6"))
		nv.add_child(tl)
		var rb := Button.new()
		rb.name = BTN_REMOVE
		rb.text = L_REMOVE
		rb.focus_mode = Control.FOCUS_NONE
		rb.add_theme_font_size_override("font_size", 16)
		rb.custom_minimum_size = Vector2(200, 52)
		UISkin.pixel_button(rb, UISkin.PX_SLATE, 3)
		row.add_child(rb)
		var tag := str(e["tag"])
		rb.pressed.connect(func() -> void:
			BL.remove(tag)
			_fill(list, empty))
		i += 1
