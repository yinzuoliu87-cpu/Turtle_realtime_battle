## 战中伤害统计浮层 (📊 按钮开关) — 从 RealtimeBattle3DScene.gd 抽出·2026-07-19
##
## 样式 1:1 回合制 DmgStatsPanel: 暗底+金棕边 / 4 Tab / 双列 rows / 0.4s 自刷。
## 与战斗场的耦合全部走【依赖注入】: 构造时传入 ui_layer 和「取某方单位列表」的回调,
## 本类不认识 _units / _world / 战斗状态。
##
## 注意: 结算统计表【不在此文件】—— 它在 battle_hud.gd 里
## (_build_stats_panel 建面板 / _stats_column 建一队一列), 是另一套 5 列样式
## (龟/造成伤害/承受伤害/治疗量/击杀)。★2026-08-02 更正: 原注释写"仍留在战斗场里"
## 且写"7列表格" —— 两处都过期了(表已搬进 HUD 层, 列也在 2026-08-02 从 7 列减到 5 列)。
class_name DmgStatsPanel
extends RefCounted

const UIPalette = preload("res://scripts/util/ui_palette.gd")
# 语义色引用 UIPalette 单一色表(2026-07-22); alpha 仍由本面板自己定 —— 色块要半透明
const COL_PHY := Color(UIPalette.PHYS, 0.6)
const COL_MAG := Color(UIPalette.MAGIC, 0.6)
const COL_TRU := Color(UIPalette.TRUE_DMG, 0.6)
const COL_HEAL := Color(UIPalette.HEAL, 0.65)
const COL_SHIELD := Color(UIPalette.SHIELD_VALUE, 0.6)
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
		_to_front()
		render()


## ★每次显示都把面板提到 _ui_layer 最前。
##
## 为什么必须这么做(探针实测, 不是防御性写法):
##   同一 CanvasLayer 内【树序 = 绘制层级】, 后 add_child 的画在上面。
##   而 _spawn_dual_lane 【每一路】都会重建左右队头像栏(battle_spawn.gd:180)、
##   摇杆、法术盘, 它们 add_child 后落到子节点列表末尾 →
##   本面板(首次点开时才建, 更早)就被压到下面去了。
##   探针数字: 开局 面板 index=21 / 左队栏 15(面板在上);
##             换一次路后 面板 19 / 左队栏 20(面板被盖住), 且两者几何真重叠。
##   用户 2026-07-30 报的正是「在下半战场统计面板还会被遮住」。
##   ★同一个根因也解释了"面板半透"的错觉 —— 底板其实 alpha 0.97 几乎不透明,
##     是【三路对阵总览幕布】后 add_child 画在了它上面。
func _to_front() -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var par := panel.get_parent()
	if par != null:
		par.move_child(panel, par.get_child_count() - 1)

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
	nm.add_theme_color_override("font_color", Color(UIPalette.SIDE_LEFT) if side == "left" else Color(UIPalette.SIDE_RIGHT))
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
	# ★y 56→100: 顶部 PK 条 2026-07-30 加宽加厚后占到 y≈67, 双路文字行到 94 ——
	#   原来的 56 会让面板标题栏钻到血条下面。100 是"贴着 HUD 下沿"。
	panel.position = Vector2(12, 100)
	# ★高度按内容自适应(见 render 末尾): 固定 430 时只有 5 行数据, 下半截一片空白(实拍看出来的)。
	#   这里给个初值, render 每次按真实行数收紧。
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
	# ★关闭按钮(用户 2026-07-30 报"交互很奇怪"): 原来只能【再点右上角那个统计按钮】关,
	#   而面板在左上角、按钮在右上角 —— 鼠标要横跨整屏才关得掉。这里就近放一个 ✕。
	# ★必须放在 TABS 循环【之后】—— 我第一版插在循环前, ✕ 跑到了 Tab 行最左边(实拍才看出来)。
	var close := Button.new()
	close.text = "✕"
	close.add_theme_font_size_override("font_size", 16)
	close.add_theme_color_override("font_color", Color("#c9d4e0"))
	close.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	close.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close.process_mode = Node.PROCESS_MODE_ALWAYS
	close.custom_minimum_size = Vector2(30, 26)
	close.pressed.connect(func() -> void: panel.visible = false)
	var sp := Control.new()                      # 弹性占位: 把 ✕ 顶到最右
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_child(sp)
	tabs.add_child(close)

	vb.add_child(cols)
	_cols = []
	for side_label in [["我方", "left"], ["敌方", "right"]]:
		var colv := VBoxContainer.new()
		colv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		colv.add_theme_constant_override("separation", 4)
		var hdr := Label.new()
		hdr.text = side_label[0]
		hdr.add_theme_font_size_override("font_size", 15)
		hdr.add_theme_color_override("font_color", Color(UIPalette.SIDE_LEFT) if side_label[1] == "left" else Color(UIPalette.SIDE_RIGHT))
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
	# ★每次自刷(0.4s)都重新提到最前 —— 只在"点开时"提是不够的:
	#   【面板开着的时候换路】, 新建的头像栏/摇杆/法术盘会盖上来, 而那时不会再调 toggle()。
	#   放在 render 里让它自愈, 最多 0.4 秒就回到最前。
	_to_front()
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

	# ★按内容收紧高度: 固定 430 时只有 5 行数据、下半截一片空白。
	#   Control 不会自己撑高/收缩, 得手算: 取两列里较高的一列 + 上下留白。
	var need := 0.0
	for c in _cols:
		var col := c as VBoxContainer
		if col == null:
			continue
		var hh := 0.0
		for ch in col.get_children():
			if ch is Control and (ch as Control).visible:
				hh += (ch as Control).get_combined_minimum_size().y + 4.0
		need = maxf(need, hh)
	if need > 0.0:
		panel.size.y = clampf(need + 96.0, 150.0, 430.0)   # +96 = Tab 行 + 列头 + 上下内边距
