class_name InvCandyJar
extends RefCounted
## 背包·糖果罐(打碎领奖)
## 类内名不变;外部名加 battle.

var host

func _init(b) -> void:
	host = b

## ★旧的「右上角独立小面板」已删(2026-08-14)。
##   用户:「点击装备, 下面把出售和什么按钮换成打碎就好了啊」——
##   糖果罐现在是背包格子里的一张卡, 选中后走底部同一条操作栏(InventoryScene._build_jar_op_bar)。
##   这个函数删掉而不是留着不调 —— GDScript 鸭子类型, 留着的死函数照样能被门禁"断言存在"保护住。


func _on_break_jar() -> void:
	var r: Dictionary = GameState.break_candy_jar()
	if r.is_empty():
		return
	_show_jar_reward(r)


func _show_jar_reward(r: Dictionary) -> void:
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(dim)

	var box = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(host.W / 2.0 - 260, host.H / 2.0 - 150); box.size = Vector2(520, 300)
	dim.add_child(box)

	var ttl = Label.new()
	ttl.text = "🍬 糖果罐碎了！  (档%d)" % int(r.get("tier", 1))
	ttl.add_theme_font_size_override("font_size", 26)
	ttl.add_theme_color_override("font_color", Color("#ffd93d"))
	ttl.position = Vector2(0, 20); ttl.size = Vector2(520, 36)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)

	var lines: Array = ["💠 深海币  +%d" % int(r.get("coins", 0))]
	var eid = str(r.get("equip", ""))
	if eid != "":
		var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
		lines.append("🗡 装备  %s  %s  → 进背包" % [str(edef.get("name", eid)), "★".repeat(int(r.get("star", 1)))])
	if bool(r.get("leveler", false)):
		lines.append("🔼 临时等级器 ×1  → 进背包 (点它再点一只龟/小将, 本大轮 +1 级)")

	var y = 80.0
	for t in lines:
		var l = Label.new()
		l.text = str(t)
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color("#e8f2ff"))
		l.position = Vector2(40, y); l.size = Vector2(440, 30)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
		y += 46.0

	var ok = Button.new()
	ok.text = "收下"
	ok.add_theme_font_size_override("font_size", 20)
	ok.position = Vector2(200, 234); ok.size = Vector2(120, 44)
	ok.pressed.connect(func(): dim.queue_free(); host._rebuild())
	box.add_child(ok)


# 消耗品格子 (临时等级器): 不是装备 → 不查装备表/不显星/不参与3合1
