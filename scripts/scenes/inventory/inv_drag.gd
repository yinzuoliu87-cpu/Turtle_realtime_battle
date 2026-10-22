class_name InvDrag
extends RefCounted
## 背包·卡片式拖动(用户 2026-10-22「做，最好要支持卡片式拖动的」· 方案书 docs/plans/20261022-背包重做.md)
##
## 拖动源: 背包格里的装备 / 单位卡上已装的装备。落点: 单位卡(装上 / 换人) / 背包区(卸下)。
## ★点选流程全部保留(点卡 → 点龟), 拖拽是快捷方式。
## ★背包区是滚动列表: 按下后竖着移 = 滚动(不拖), 横着或斜着移出 = 拖起(DIR_RATIO 判方向)。
## ★拖动中禁止重建(R5): 被拖的节点是 `_rebuild()` 要销毁的子节点; 落下由业务函数自己重建。
## 照 CLAUDE.md §5 拆分模板: RefCounted + 构造注入宿主(InventoryScene)。

const KIND_BENCH := "bench"     # 背包里的一件(bidx = persistent_bench 下标)
const KIND_WORN := "worn"       # 单位身上的一件(lane / idx / cell = _unit_equips 的真实下标)
const KIND_UNIT := "unit"       # 整张单位卡(拖到另一张 = 两张互换, 跨路 / 同路都行)
const LIFT_SCALE := 1.12        # 拿起来的卡片放大一点(「从桌上拿起一张卡」)
const LIFT_TILT := -0.08        # 微微歪着(弧度)
const PREVIEW_PX := 104.0       # 跟手那张卡的边长
const DIR_RATIO := 1.2          # 背包要滚动时: 竖向位移 > 横向 × 此值 ⇒ 当作滑动列表, 不拖
## ★按住这么久再动 = 拿起来(长按拖)。由来: 装备是往上拖到卡上的 —— 那一下本来就是竖的,
##   只认「横着拖」的话主手势直接被滚动吃掉。背包不用滚动时(手机上 22 件两排放得下)任何方向都直接拖。
const HOLD_MS := 200
const LIT := Color(1.18, 1.18, 1.12, 1.0)    # 能接: 抬亮
const DIM := Color(0.45, 0.45, 0.52, 1.0)    # 接不了: 压暗

var host
## 正在拖的东西(空 = 没在拖)。门禁读它。
var dragging: Dictionary = {}
## 本次拖动是否已经落下并处理过(落下处理里会重建; 拖动结束通知晚于它到)
var _dropped := false
var _src: Control = null


func _init(h) -> void:
	host = h


func active() -> bool:
	return not dragging.is_empty()


# ─────────── 拖动源 ───────────

## 背包格: 整格是拖动源。
func wire_bench_source(cell: Control, bidx: int, it: Dictionary) -> void:
	cell.set_drag_forwarding(func(at: Vector2) -> Variant:
		return _begin(cell, at, {"kind": KIND_BENCH, "bidx": bidx, "it": it}),
		Callable(), Callable())


## 单位卡: 按在某一件已装装备上 ⇒ 拖那一件; 按在卡的别处 ⇒ 拖整张卡(用户「把龟做成卡片」: 拖到另一张 = 换位)。
##   同时它也是落点(装上 / 换人)。worn_cells = [{rect(卡内坐标), cell(真实下标), it}]
func wire_unit(box: Control, lane: String, idx: int, unit: Dictionary, worn_cells: Array) -> void:
	box.set_drag_forwarding(
		func(at: Vector2) -> Variant:
			for wc in worn_cells:
				if (wc["rect"] as Rect2).has_point(at):
					return _begin(box, at, {"kind": KIND_WORN, "lane": lane, "idx": idx,
						"cell": int(wc["cell"]), "it": wc["it"], "unit": unit})
			return _begin(box, at, {"kind": KIND_UNIT, "lane": lane, "idx": idx, "unit": unit}),
		func(_at: Vector2, data: Variant) -> bool:
			return _can_take(lane, idx, unit, data),
		func(_at: Vector2, data: Variant) -> void:
			_drop_on_unit(lane, idx, data))


## 背包区(滚动容器): 已装的拖回来 = 卸下。
func wire_bench_area(area: Control) -> void:
	area.set_drag_forwarding(Callable(),
		func(_at: Vector2, data: Variant) -> bool:
			return data is Dictionary and str((data as Dictionary).get("kind", "")) == KIND_WORN,
		func(_at: Vector2, data: Variant) -> void:
			_drop_on_bench(data))


func _begin(src: Control, at: Vector2, data: Dictionary) -> Variant:
	if host.has_method("_tut_on") and host._tut_on():
		return null        # 教程一步一步点着教, 不让拖乱了节奏(R2: 教程锚点只认点选)
	## 竖着移 ⇒ 是在滑列表, 不拖。at = 按下的点(卡内坐标), 鼠标现在的位置减它 = 这一下往哪移。
	var mv: Vector2 = src.get_local_mouse_position() - at
	if str(data.get("kind", "")) == KIND_BENCH and host.bench_scrolls() 			and Time.get_ticks_msec() - int(host._press_ms) < HOLD_MS and absf(mv.y) > absf(mv.x) * DIR_RATIO:
		return null        # 背包要滚动 + 没按住 + 竖着划 = 在滑列表
	dragging = data
	_dropped = false
	_src = src
	if str(data.get("kind", "")) == KIND_UNIT:
		src.set_drag_preview(_card_preview(src))
	else:
		src.set_drag_preview(_preview(data["it"]))
	if str(data.get("kind", "")) != KIND_WORN:
		src.modulate.a = 0.35     # 原位只剩个虚影 = 卡片被拿起来了
	_mark_targets(data)
	return data


## 跟手的那张卡: 图标装在一块卡片底上, 放大一点、歪一点、带投影; 摆在手指上方(手指不挡住它)。
func _preview(it: Dictionary) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := Control.new()
	card.size = Vector2(PREVIEW_PX, PREVIEW_PX)
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2.ONE * LIFT_SCALE
	card.rotation = LIFT_TILT
	card.position = Vector2(-PREVIEW_PX * 0.5, -PREVIEW_PX - 18.0)
	root.add_child(card)
	var sh := ColorRect.new()
	sh.color = Color(0, 0, 0, 0.35)
	sh.position = Vector2(6, 8); sh.size = card.size
	card.add_child(sh)
	var face := Panel.new()
	face.size = card.size
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(it.get("id", "")), {})
	face.add_theme_stylebox_override("panel", host.card_style(int(edef.get("cost", 1)), true))
	card.add_child(face)
	var ic := EquipIcon.make(edef, Vector2(72, 64)) if not edef.is_empty() else Control.new()
	ic.position = Vector2((PREVIEW_PX - 72.0) * 0.5, 30)
	card.add_child(ic)
	var st := Label.new()
	st.text = "★".repeat(maxi(1, int(it.get("star", 1))))
	st.add_theme_font_size_override("font_size", 20)
	st.add_theme_color_override("font_color", Color("#ffd93d"))
	st.position = Vector2(0, 4); st.size = Vector2(PREVIEW_PX, 26)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(st)
	return root


## 整张单位卡跟手: 复制这张卡(不带信号 = 不会被点), 放大一点、歪一点; 手指在卡的中间偏下。
func _card_preview(card: Control) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c: Control = card.duplicate(0) as Control
	c.position = Vector2(-card.size.x * 0.5, -card.size.y * 0.6)
	c.pivot_offset = card.size * 0.5
	c.scale = Vector2.ONE * 1.06
	c.rotation = LIFT_TILT
	c.modulate = Color(1, 1, 1, 0.92)
	root.add_child(c)
	return root


# ─────────── 落点 ───────────

## 这只单位接不接得住(决定高亮; 落下时接不住的照样收下, 由业务函数说清原因)。
func can_hold(lane: String, idx: int, unit: Dictionary, data: Dictionary) -> bool:
	if unit.is_empty():
		return false
	if str(data.get("kind", "")) != KIND_UNIT and str(unit.get("kind", "")) == "leader" and str(unit.get("id", "")) == "":
		return false                                     # 占位统领: 没有真龟, 装不了东西
	var it: Dictionary = data.get("it", {})
	if str(data.get("kind", "")) != KIND_BENCH and str(data.get("lane", "")) == lane and int(data.get("idx", -1)) == idx:
		return false                                     # 拖回自己身上 = 什么都不做
	if str(data.get("kind", "")) == KIND_UNIT:
		return true                                      # 换位: 哪张都能换(占位统领也是一个位置)
	if str(it.get("kind", "")) == "item":
		return true                                      # 临时等级器: 谁都能用
	if GameState.is_synergy_grant(it):
		return true                                      # 羁绊赠送件不占容量
	if GameState._cap_count(host._unit_equips(unit)) >= host.P2.UNIT_EQUIP_CAP:
		return false
	## 从背包装上要占全队一格; 从别的单位挪过来不改全队件数
	if str(data.get("kind", "")) == KIND_BENCH and not GameState.team_has_equip_room():
		return false
	return true


func _can_take(lane: String, idx: int, unit: Dictionary, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	## 占位统领(装东西时)/ 拖回自己: 不收(光标显示「放不了」); 其余都收, 放不下的由业务函数弹原因
	var d: Dictionary = data
	if unit.is_empty():
		return false
	if str(d.get("kind", "")) != KIND_UNIT and str(unit.get("kind", "")) == "leader" and str(unit.get("id", "")) == "":
		return false
	return not (str(d.get("kind", "")) != KIND_BENCH and str(d.get("lane", "")) == lane and int(d.get("idx", -1)) == idx)


func _drop_on_unit(lane: String, idx: int, data: Variant) -> void:
	var d: Dictionary = data
	_finish()
	_dropped = true
	if str(d.get("kind", "")) == KIND_BENCH:
		host._equip_bench_to_unit(lane, idx, int(d.get("bidx", -1)))
	elif str(d.get("kind", "")) == KIND_UNIT:
		host._dl_sel = {}
		host._swap_units(str(d["lane"]), int(d["idx"]), lane, idx)
	else:
		host._inv_ops._move_worn(str(d["lane"]), int(d["idx"]), int(d["cell"]), lane, idx)


func _drop_on_bench(data: Variant) -> void:
	var d: Dictionary = data
	_finish()
	_dropped = true
	var u: Dictionary = d.get("unit", {})
	if str(u.get("kind", "")) == "leader":
		host._inv_ops._unequip_at(str(u.get("id", "")), int(d["cell"]))
	else:
		host._inv_ops._unequip_minion_at(str(d["lane"]), int(d["idx"]), int(d["cell"]))


# ─────────── 高亮 ───────────

func _mark_targets(data: Dictionary) -> void:
	for ub in host._unit_boxes:
		var b: Control = ub["box"]
		if not is_instance_valid(b):
			continue
		b.modulate = LIT if can_hold(str(ub["lane"]), int(ub["idx"]), ub["unit"], data) else DIM
	if host._bench_area != null and is_instance_valid(host._bench_area):
		host._bench_area.modulate = LIT if str(data.get("kind", "")) == KIND_WORN else Color(1, 1, 1, 1)


## 拖动结束(落下或放弃都会到): 收掉高亮、原位虚影复原。
func _finish() -> void:
	for ub in host._unit_boxes:
		var b: Control = ub["box"]
		if is_instance_valid(b):
			b.modulate = Color(1, 1, 1, 1)
	if host._bench_area != null and is_instance_valid(host._bench_area):
		host._bench_area.modulate = Color(1, 1, 1, 1)
	if _src != null and is_instance_valid(_src):
		_src.modulate.a = 1.0
	_src = null
	dragging = {}


## 宿主在 NOTIFICATION_DRAG_END 里调。落空(放在不收的地方)= 什么都不变。
func on_drag_end() -> void:
	if not dragging.is_empty():
		_finish()
	_dropped = false
