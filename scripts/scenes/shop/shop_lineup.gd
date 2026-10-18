class_name ShopLineup
extends RefCounted
## 商店右侧【出战阵容】面板 + 底部【背包条】—— 买和装在同一屏(2026-10-18)。
##
## 玩家反馈 10-17「游戏的操作风格与道具装备的流程存在提升空间」。
## 实玩记录(方案书 docs/plans/20261018-商店背包合一.md「实玩记录」):
##   买一件再装上要 6 下 —— 点卡 → 购买 → 左上「背包」换页 → 点装备 → 点龟 → 点「商店」回来;
##   商店底部那两个弹层(背包 / 出战阵容)只能看不能动;
##   右侧详情框没选东西时整块空着;「装备 0/2」是什么, 屏上没有一个字解释。
## ⇒ 右侧常驻阵容(6 个单位 × 3 槽), 底部背包条可点:
##   点背包里一件 → 能装的单位亮起 → 点单位 = 装上;
##   不在「待装」时点一个单位 = 选中它, 面板底部操作条给出「卸下 X」。
##   买下的那件(没合成掉的话)自动成为「待装」, 于是 买 → 点龟 两下完成。
## ★装/卸/卖全走背包页同一套 `InvOps`(上限两条、自动合成、羁绊赠送件、存盘都在里面),
##   不在这里另写一份 —— 手抄的副本必然落后。
## ★触控尺寸(verify_ui_consistency「热区不足」= 短边 < 81px 且长边 < 200px):
##   能点的只有 ① 单位行(376 宽) ② 背包格(81) ③ 底部操作条按钮(81 高)。
##   装备槽不单独响应点击 —— 46px 的槽在手机上点不准, 点整行即可。
## ★照 CLAUDE.md §5 拆分模板: RefCounted + 构造注入宿主(ShopScene)。

const ROW_H := 54.0       # 单位行高
const ROW_STEP := 58.0
const SLOT := 46.0        # 装备槽边长(只显示, 不响应点击)
const SLOT_STEP := 50.0
const BAR_Y := 482.0      # 面板内底部操作条的 y(面板高 592, 框边 25 ⇒ 内容下界 567; 482+81=563)
const BAR_H := 81.0       # = 44pt 触控下限
const BENCH_CELL := 81.0  # = 44pt 触控下限
const BENCH_STEP := 89.0
const BENCH_PER_ROW := 8  # 8 × 89 = 712 ≤ 卡区宽 740
## 阵容行里龟名那一格(门禁 verify_shop_layout NAME_NOT_TRUNCATED 穷举 28 只龟名量它)
const NAME_W := 110.0
const NAME_FONT := 16
const Phase2Minion = preload("res://scripts/gamedata/phase2_minion.gd")

var host = null
## 选中的单位(不在「待装」时点一行): {lane, idx}。空 = 没选。
var pick_eq: Dictionary = {}


func _init(h) -> void:
	host = h


## 这个单位现在能不能接下背包里选中的那件。返回 "" = 能; 否则是不能的原因(短语)。
func refuse_reason(unit: Dictionary) -> String:
	if str(unit.get("kind", "")) == "leader" and str(unit.get("id", "")) == "":
		return "未选龟"
	var bench: Array = GameState.persistent_bench
	var bi: int = int(host._sel_bench)
	if bi < 0 or bi >= bench.size():
		return "没选装备"
	if GameState.is_synergy_grant(bench[bi]) or str((bench[bi] as Dictionary).get("kind", "")) == "item":
		return ""
	if GameState._cap_count(unit_equips(unit)) >= int(host.P2.UNIT_EQUIP_CAP):
		return "已满 3 件"
	if not GameState.team_has_equip_room():
		return "全队已满"
	return ""


func unit_equips(unit: Dictionary) -> Array:
	if str(unit.get("kind", "")) == "leader":
		var pe = GameState.persistent_equipped.get(str(unit.get("id", "")), []) if GameState.persistent_equipped is Dictionary else []
		return pe if pe is Array else []
	return unit.get("equips", []) if unit.get("equips", null) is Array else []


func _unit_at(lineup: Dictionary, lane: String, idx: int) -> Dictionary:
	var arr: Array = lineup.get(lane, [])
	return arr[idx] if idx >= 0 and idx < arr.size() and arr[idx] is Dictionary else {}


func _unit_name(unit: Dictionary) -> String:
	var kind := str(unit.get("kind", ""))
	var pid := str(unit.get("id", ""))
	if kind == "leader":
		if pid == "":
			return "统领%d" % (int(unit.get("slot", 0)) + 1)
		return str(DataRegistry.pet_by_id.get(pid, {}).get("name", pid))
	return "精英小将" if bool(unit.get("elite", false)) else "小将"


## 右侧面板。box = 已画好框的 Panel(PANEL 尺寸)。
func build_panel(box: Control, w: float) -> void:
	var lineup: Dictionary = GameState.get_dual_lineup()
	var used: int = int(GameState.team_equipped_count())
	var cap: int = int(GameState.team_equip_cap())
	var bench: Array = GameState.persistent_bench
	var bi: int = int(host._sel_bench)
	var sel_item: Dictionary = bench[bi] if bi >= 0 and bi < bench.size() else {}
	var pu: Dictionary = _unit_at(lineup, str(pick_eq.get("lane", "")), int(pick_eq.get("idx", -1)))
	if pu.is_empty():
		pick_eq = {}

	var t := Label.new(); t.text = "出战阵容"
	t.add_theme_font_size_override("font_size", 20); t.add_theme_color_override("font_color", Color("#e8f2ff"))
	t.position = Vector2(34, 28); t.size = Vector2(160, 28); box.add_child(t)
	var cnt := Label.new(); cnt.name = "TeamEquipCount"
	cnt.text = "装备 %d/%d" % [used, cap]
	cnt.add_theme_font_size_override("font_size", 20)
	cnt.add_theme_color_override("font_color", Color("#ffb454") if used >= cap else Color("#ffd93d"))
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.position = Vector2(w - 194, 28); cnt.size = Vector2(160, 28); box.add_child(cnt)

	## 第二行: 此刻该做什么。短指令(文案不许口语化·用户 10-07)。
	var hint := Label.new(); hint.name = "LineupHint"
	hint.add_theme_font_size_override("font_size", 15)
	hint.position = Vector2(34, 58); hint.size = Vector2(w - 68, 24)
	hint.clip_text = true; hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if not sel_item.is_empty():
		var ed: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(sel_item.get("id", "")), {})
		var _free: bool = GameState.is_synergy_grant(sel_item) or str(sel_item.get("kind", "")) == "item"
		if not _free and not GameState.team_has_equip_room():
			hint.text = "全队已满 · 升级或先卸下一件"
			hint.add_theme_color_override("font_color", Color("#ffb454"))
		else:
			hint.text = "点一只龟装上「%s」" % str(ed.get("name", "?"))
			hint.add_theme_color_override("font_color", Color("#ffd93d"))
	elif not pick_eq.is_empty():
		if unit_equips(pu).is_empty():
			hint.text = "%s · 还没有装备" % _unit_name(pu)
		else:
			hint.text = "%s · 点下方卸下" % _unit_name(pu)
		hint.add_theme_color_override("font_color", Color("#ffd93d"))
	else:
		hint.text = "全队已满 · 升级可多装" if used >= cap else "等级越高，全队可装越多"
		hint.add_theme_color_override("font_color", Color("#6f8aa0"))
	box.add_child(hint)

	var y := 88.0
	for lk in ["top", "bottom"]:
		var lh := Label.new(); lh.text = "上战场" if lk == "top" else "下战场"
		lh.add_theme_font_size_override("font_size", 14); lh.add_theme_color_override("font_color", Color("#8fb0c8"))
		lh.position = Vector2(34, y); lh.size = Vector2(120, 20); box.add_child(lh)
		y += 22.0
		var arr: Array = lineup.get(lk, [])
		for i in range(arr.size()):
			if arr[i] is Dictionary:
				_unit_row(box, Vector2(32, y), w - 64.0, lk, i, arr[i])
				y += ROW_STEP
		y += 4.0

	_action_bar(box, w, sel_item, pu)


## 面板底部操作条(81 高): 选了背包里一件 → 详情 / 卖出; 选了一个单位 → 每件「卸下」。
func _action_bar(box: Control, w: float, sel_item: Dictionary, pu: Dictionary) -> void:
	var acts: Array = []   # [文字, Callable]
	if not sel_item.is_empty():
		acts.append(["详情", Callable(self, "_detail_bench")])
		if not GameState.is_synergy_grant(sel_item):
			acts.append(["卖出 +%d" % int(host._inv_ops._sell_value(sel_item)), Callable(self, "_sell_bench")])
	elif not pu.is_empty():
		var es: Array = unit_equips(pu)
		for ci in range(es.size()):
			if not (es[ci] is Dictionary):
				continue
			var ed: Dictionary = DataRegistry.phase2_equipment_by_id.get(str((es[ci] as Dictionary).get("id", "")), {})
			acts.append(["卸下\n%s" % str(ed.get("name", "?")), Callable(self, "_unequip_at").bind(ci)])
	if acts.is_empty():
		return
	var x0 := 32.0
	var bw: float = ((w - 64.0) - 8.0 * float(acts.size() - 1)) / float(acts.size())
	for k in range(acts.size()):
		var ab := Button.new(); ab.name = "LineupAct%d" % k
		ab.text = str(acts[k][0])
		ab.add_theme_font_size_override("font_size", 15)
		ab.position = Vector2(x0 + k * (bw + 8.0), BAR_Y); ab.size = Vector2(bw, BAR_H)
		ab.clip_text = true
		ab.pressed.connect(acts[k][1])
		host._skin_button(ab); box.add_child(ab)


func _unit_row(box: Control, pos: Vector2, rw: float, lane: String, idx: int, unit: Dictionary) -> void:
	var kind := str(unit.get("kind", ""))
	var pid := str(unit.get("id", ""))
	var is_ph: bool = kind == "leader" and pid == ""
	var arming: bool = int(host._sel_bench) >= 0
	var why: String = refuse_reason(unit) if arming else ""
	var ok: bool = arming and why == ""
	var picked: bool = not arming and str(pick_eq.get("lane", "")) == lane and int(pick_eq.get("idx", -1)) == idx

	var row := Panel.new(); row.name = "LineupRow_%s_%d" % [lane, idx]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1a2c3c") if (ok or picked) else Color("#122130")
	sb.border_color = Color("#ffd93d") if (ok or picked) else Color("#2a4256")
	sb.set_border_width_all(3 if (ok or picked) else 1); sb.set_corner_radius_all(0)
	row.add_theme_stylebox_override("panel", sb)
	row.position = pos; row.size = Vector2(rw, ROW_H)
	if arming and not ok:
		row.modulate = Color(1, 1, 1, 0.45)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_row(lane, idx))
	box.add_child(row)

	# 头像
	var img := ""
	if kind == "leader" and not is_ph:
		img = "res://assets/sprites/avatars/%s.png" % pid
	elif kind == "minion":
		img = "res://assets/sprites/%s" % Phase2Minion.minion_img(bool(unit.get("elite", false)), str(unit.get("role", "front")) == "back")
	if img != "" and ResourceLoader.exists(img):
		var a := TextureRect.new(); a.texture = load(img)
		a.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; a.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		a.position = Vector2(6, 5); a.size = Vector2(44, 44); a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(a)
	elif is_ph:
		var q := Label.new(); q.text = "?"
		q.add_theme_font_size_override("font_size", 30); q.add_theme_color_override("font_color", Color("#6f8aa0"))
		q.position = Vector2(6, 5); q.size = Vector2(44, 44)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(q)

	# 名字 + 身份 / 不能装的原因
	var nl := Label.new(); nl.name = "UnitName"; nl.text = _unit_name(unit)
	nl.add_theme_font_size_override("font_size", NAME_FONT); nl.add_theme_color_override("font_color", Color("#e8f2ff"))
	nl.position = Vector2(56, 4); nl.size = Vector2(NAME_W, 24)
	nl.clip_text = true; nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(nl)
	var tag := Label.new()
	if arming and not ok:
		tag.text = why
		tag.add_theme_color_override("font_color", Color("#ffb454"))
	elif is_ph:
		tag.text = "未选龟"
		tag.add_theme_color_override("font_color", Color("#6f8aa0"))
	else:
		tag.text = "统领" if kind == "leader" else ("前排" if str(unit.get("role", "front")) == "front" else "后排")
		tag.add_theme_color_override("font_color", Color("#8fb0c8"))
	tag.add_theme_font_size_override("font_size", 13)
	tag.position = Vector2(56, 28); tag.size = Vector2(NAME_W, 22)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(tag)

	# 3 个装备槽(只显示)
	var eqs: Array = unit_equips(unit)
	var sx := rw - 6.0 - 3.0 * SLOT_STEP + (SLOT_STEP - SLOT)
	for ci in range(int(host.P2.UNIT_EQUIP_CAP)):
		var cell := Panel.new(); cell.name = "Slot%d" % ci
		var csb := StyleBoxFlat.new(); csb.bg_color = Color("#0e1a26"); csb.set_corner_radius_all(0)
		var has_it: bool = ci < eqs.size() and eqs[ci] is Dictionary
		var ed: Dictionary = {}
		if has_it:
			ed = DataRegistry.phase2_equipment_by_id.get(str((eqs[ci] as Dictionary).get("id", "")), {})
			csb.border_color = host._cost_color(int(ed.get("cost", 1))); csb.set_border_width_all(2)
		else:
			csb.border_color = Color(1, 1, 1, 0.12); csb.set_border_width_all(1)
		cell.add_theme_stylebox_override("panel", csb)
		cell.position = Vector2(sx + ci * SLOT_STEP, 4); cell.size = Vector2(SLOT, SLOT)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(cell)
		if has_it:
			var ic := EquipIcon.make(ed, Vector2(32, 28))
			ic.position = Vector2(7, 3); ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(ic)
			var st := Label.new(); st.text = "★".repeat(int((eqs[ci] as Dictionary).get("star", 1)))
			st.add_theme_font_size_override("font_size", 10); st.add_theme_color_override("font_color", Color("#ffd93d"))
			st.position = Vector2(0, 31); st.size = Vector2(SLOT, 13); st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			st.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(st)


func _on_row(lane: String, idx: int) -> void:
	var lineup: Dictionary = GameState.get_dual_lineup()
	var unit: Dictionary = _unit_at(lineup, lane, idx)
	if unit.is_empty():
		return
	if int(host._sel_bench) < 0:
		var same: bool = str(pick_eq.get("lane", "")) == lane and int(pick_eq.get("idx", -1)) == idx
		pick_eq = {} if same else {"lane": lane, "idx": idx}
		host._sel = -1
		host._sel_own = ""
		host._rebuild()
		return
	var why := refuse_reason(unit)
	if why != "":
		host._toast(why)
		return
	var n0: int = int(GameState.team_equipped_count())
	var bench_n0: int = GameState.persistent_bench.size()
	if str(unit.get("kind", "")) == "leader":
		host._inv_ops._equip_to(str(unit.get("id", "")), int(host._sel_bench))
	else:
		host._inv_ops._equip_minion(lane, idx, int(host._sel_bench))
	if int(GameState.team_equipped_count()) > n0 or GameState.persistent_bench.size() < bench_n0:
		host._toast("已装上")


func _unequip_at(ci: int) -> void:
	var lane := str(pick_eq.get("lane", ""))
	var idx: int = int(pick_eq.get("idx", -1))
	var u: Dictionary = _unit_at(GameState.get_dual_lineup(), lane, idx)
	if u.is_empty():
		pick_eq = {}
		host._rebuild(); return
	if str(u.get("kind", "")) == "leader":
		host._inv_ops._unequip_at(str(u.get("id", "")), ci)
	else:
		host._inv_ops._unequip_minion_at(lane, idx, ci)
	host._toast("已放回背包")


func _detail_bench() -> void:
	var bench: Array = GameState.persistent_bench
	var bi: int = int(host._sel_bench)
	if bi < 0 or bi >= bench.size():
		return
	host._on_select_own(str(bench[bi].get("id", "")), int(bench[bi].get("star", 1)))


func _sell_bench() -> void:
	var bench: Array = GameState.persistent_bench
	var bi: int = int(host._sel_bench)
	if bi < 0 or bi >= bench.size():
		return
	var sv: int = int(host._inv_ops._sell_value(bench[bi]))
	host._inv_ops._sell_selected()
	host._toast("已卖出 +%d" % sv)


## 底部背包条: 没装上的装备。点一件 = 选为「待装」(再点 = 取消)。
func build_bench(parent: Control, x0: float, y0: float) -> void:
	var bench: Array = GameState.persistent_bench
	var hd := Label.new(); hd.name = "BenchHeader"
	hd.text = ("背包 %d 件" % bench.size()) if bench.size() > 0 else "背包为空"
	hd.add_theme_font_size_override("font_size", 15); hd.add_theme_color_override("font_color", Color("#9fb6c9"))
	hd.position = Vector2(x0, y0); hd.size = Vector2(300, 22); parent.add_child(hd)
	var overflow: bool = bench.size() > BENCH_PER_ROW
	var shown: int = (BENCH_PER_ROW - 1) if overflow else bench.size()
	for j in range(shown):
		var it: Dictionary = bench[j]
		var ed: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(it.get("id", "")), {})
		var sel: bool = j == int(host._sel_bench)
		var cell := Panel.new(); cell.name = "BenchCell%d" % j
		var csb := StyleBoxFlat.new(); csb.bg_color = Color("#162230")
		csb.border_color = Color("#ffd93d") if sel else host._cost_color(int(ed.get("cost", 1)))
		csb.set_border_width_all(3 if sel else 2); csb.set_corner_radius_all(0)
		cell.add_theme_stylebox_override("panel", UISkin.slot(csb, UISkin.tint_of(csb.border_color)))
		cell.position = Vector2(x0 + j * BENCH_STEP, y0 + 24.0); cell.size = Vector2(BENCH_CELL, BENCH_CELL)
		parent.add_child(cell)
		if sel:
			var ring := Panel.new()
			var rsb := StyleBoxFlat.new(); rsb.bg_color = Color(1, 0.85, 0.24, 0.12)
			rsb.border_color = Color("#ffd93d"); rsb.set_border_width_all(3); rsb.set_corner_radius_all(0)
			ring.add_theme_stylebox_override("panel", rsb)
			ring.position = Vector2.ZERO; ring.size = Vector2(BENCH_CELL, BENCH_CELL)
			ring.mouse_filter = Control.MOUSE_FILTER_IGNORE; ring.z_index = 1
			cell.add_child(ring)
		var ic := EquipIcon.make(ed, Vector2(44, 38))
		ic.position = Vector2(18, 13); cell.add_child(ic)
		var st := Label.new(); st.text = "★".repeat(int(it.get("star", 1)))
		st.add_theme_font_size_override("font_size", 12); st.add_theme_color_override("font_color", Color("#ffd93d"))
		st.position = Vector2(16, 51); st.size = Vector2(BENCH_CELL - 32.0, 16); st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(st)
		cell.tooltip_text = "%s ★%d" % [str(ed.get("name", "?")), int(it.get("star", 1))]
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var _j := j
		cell.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_bench(_j))
	if overflow:
		var mb := Button.new(); mb.name = "BenchMore"
		mb.text = "+%d" % (bench.size() - shown)
		mb.add_theme_font_size_override("font_size", 18)
		mb.position = Vector2(x0 + shown * BENCH_STEP, y0 + 24.0); mb.size = Vector2(BENCH_CELL, BENCH_CELL)
		mb.pressed.connect(func(): host._go_inventory())
		host._skin_button(mb); parent.add_child(mb)


func _on_bench(j: int) -> void:
	host._sel_bench = -1 if int(host._sel_bench) == j else j
	pick_eq = {}
	host._sel = -1
	host._sel_own = ""
	host._rebuild()
