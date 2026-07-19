## 战中伤害统计浮层 (📊 按钮开关) — 从 RealtimeBattle3DScene.gd 抽出·2026-07-19
##
## 样式 1:1 回合制 DmgStatsPanel: 暗底+金棕边 / 4 Tab / 双列 rows / 0.4s 自刷。
## 与战斗场的耦合全部走【依赖注入】: 构造时传入 ui_layer 和「取某方单位列表」的回调,
## 本类不认识 _units / _world / 战斗状态。
##
## 注意: 结算统计表(_build_stats_panel / _stats_column)【不在此文件】——
## 它用了 await get_tree() 需要 Node 上下文, 且是另一套(7列表格)样式, 仍留在战斗场里。
class_name DmgStatsPanel
extends RefCounted

const COL_PHY := Color(1, 0.267, 0.267, 0.6)
const COL_MAG := Color(0.302, 0.671, 0.969, 0.6)
const COL_TRU := Color(1, 1, 1, 0.6)
const COL_HEAL := Color(0.024, 0.839, 0.627, 0.65)
const COL_SHIELD := Color(0.345, 0.827, 1, 0.6)
const TABS := [["dealt", "⚔ 造成"], ["taken", "🛡 承受"], ["heal", "💚 治疗"], ["shield", "🔵 护盾"]]

var panel: Control = null                 # 浮层本体(默认隐)
var _cols: Array = []                     # [左队 rows VBox, 右队 rows VBox]
var _tab: String = "dealt"                # 当前 Tab: dealt/taken/heal/shield
var _tab_btns: Array = []
var _ui_layer: CanvasLayer = null
var _units_of: Callable                   # func(side: String) -> Array

func setup(ui_layer: CanvasLayer, units_of: Callable) -> void:
	_ui_layer = ui_layer
	_units_of = units_of

## 📊 开关 (1:1 回合制 _on_dmg_stats_toggle)
func toggle() -> void:
	if panel == null:
		build()
	panel.visible = not panel.visible
	if panel.visible:
		render()

## 当前 Tab 的标量值 (排序/显示)
static func val(u: Dictionary, tab: String) -> int:
	match tab:
		"dealt": return int(u.get("_st_dealt", 0))
		"taken": return int(u.get("_st_taken", 0))
		"heal": return int(u.get("_st_heal", 0))
		"shield": return int(u.get("_st_shield", 0))
	return 0

## 当前 Tab 的分段条 [[值,色],...]: 造成/承受按类型三段, 治疗/护盾单段.
static func parts(u: Dictionary, tab: String) -> Array:
	if tab == "dealt" or tab == "taken":
		var bt: Dictionary = u.get("_st_dealt_by_type" if tab == "dealt" else "_st_taken_by_type", {})
		return [
			[int(bt.get("phy", 0)), COL_PHY],
			[int(bt.get("mag", 0)), COL_MAG],
			[int(bt.get("tru", 0)) + int(bt.get("dot", 0)), COL_TRU],
		]
	elif tab == "heal":
		return [[int(u.get("_st_heal", 0)), COL_HEAL]]
	return [[int(u.get("_st_shield", 0)), COL_SHIELD]]

## stacked bar: 高12/圆角4/裁切; 空轨 rgba(1,1,1,.05); 段按值 stretch_ratio; 余量透明露空轨.
static func make_bar(bar_parts: Array, col_max: int) -> Control:
	var wrap := Panel.new()
	wrap.custom_minimum_size = Vector2(0, 12)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.clip_contents = true
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(1, 1, 1, 0.05)
	wsb.set_corner_radius_all(4)
	wrap.add_theme_stylebox_override("panel", wsb)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 0)
	var used := 0
	for part in bar_parts:
		var v: int = int(part[0])
		if v <= 0:
			continue
		var seg := ColorRect.new()
		seg.color = part[1]
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = float(v)
		hb.add_child(seg)
		used += v
	var rem: int = maxi(0, col_max - used)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = maxf(0.0001, float(rem))
	hb.add_child(spacer)
	wrap.add_child(hb)
	return wrap

## 一行: 名(左绿/右红, 召唤体缩进)+值 / 下方分段条; 阵亡整行半透.
func make_row(u: Dictionary, side: String, col_max: int) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	if not bool(u.get("alive", true)):
		row.modulate.a = 0.4
	var top := HBoxContainer.new()
	var nm := Label.new()
	nm.text = ("↳ " if u.get("is_summon", false) else "") + str(u.get("name", u.get("id", "")))
	nm.add_theme_font_size_override("font_size", 15)
	nm.add_theme_color_override("font_color", Color("#06d6a0") if side == "left" else Color("#ff6b6b"))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var v := Label.new()
	v.text = str(val(u, _tab))
	v.add_theme_font_size_override("font_size", 14)
	v.add_theme_color_override("font_color", Color("#e6edf3"))
	top.add_child(v)
	row.add_child(top)
	row.add_child(make_bar(parts(u, _tab), col_max))
	return row

## 浮层骨架: 暗底+金棕边 / 4Tab / 双列 rows / 0.4s 自刷.
func build() -> void:
	panel = Panel.new()
	panel.position = Vector2(12, 56)
	panel.size = Vector2(540, 430)
	panel.visible = false
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.055, 0.075, 0.11, 0.97)
	psb.border_color = Color("#6b5430")
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", psb)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 14; vb.offset_top = 12; vb.offset_right = -14; vb.offset_bottom = -12
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	_tab_btns = []
	for pair in TABS:
		var b := Button.new()
		b.text = pair[1]
		b.add_theme_font_size_override("font_size", 15)
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var key: String = pair[0]
		b.pressed.connect(func() -> void: _tab = key; render())
		tabs.add_child(b)
		_tab_btns.append({"btn": b, "key": key})
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(cols)
	_cols = []
	for side_label in [["我方", "left"], ["敌方", "right"]]:
		var colv := VBoxContainer.new()
		colv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		colv.add_theme_constant_override("separation", 4)
		var hdr := Label.new()
		hdr.text = side_label[0]
		hdr.add_theme_font_size_override("font_size", 15)
		hdr.add_theme_color_override("font_color", Color("#06d6a0") if side_label[1] == "left" else Color("#ff6b6b"))
		colv.add_child(hdr)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 6)
		colv.add_child(rows)
		cols.add_child(colv)
		_cols.append(rows)
	_ui_layer.add_child(panel)
	var t := Timer.new()
	t.wait_time = 0.4
	t.autostart = true
	t.timeout.connect(func() -> void:
		if panel != null and panel.visible:
			render())
	panel.add_child(t)

## 重建两列 rows: 各列按当前 Tab 值降序; Tab active 高亮.
func render() -> void:
	if _cols.size() < 2:
		return
	for tb in _tab_btns:
		var active: bool = tb["key"] == _tab
		(tb["btn"] as Button).add_theme_color_override("font_color", Color("#ffffff") if active else Color("#8b949e"))
	var sides := ["left", "right"]
	for ci in range(2):
		var side: String = sides[ci]
		var rows_vb: VBoxContainer = _cols[ci]
		for c in rows_vb.get_children():
			rows_vb.remove_child(c)
			c.queue_free()
		var list: Array = _units_of.call(side)
		var tab := _tab
		list.sort_custom(func(a, b): return val(a, tab) > val(b, tab))
		var col_max := 1
		for u in list:
			col_max = maxi(col_max, val(u, tab))
		for u in list:
			rows_vb.add_child(make_row(u, side, col_max))
