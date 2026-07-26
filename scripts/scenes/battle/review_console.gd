class_name ReviewConsole
extends RefCounted
## 评审台控制台(REVIEW·dev-only: 面板+切龟/切技/切装/星级按钮)
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

# 🛠 调试面板(评审demo顶部一排按钮·技能0-3/装备开关/星级1-3·点即改静态变量+重开·用户2026-07-11)
func _build_debug_panel() -> void:
	if not battle._review_demo() or battle._is_dual_lane_mode() or battle._ui_layer == null or battle.DEBUG_EDIT:
		return
	var bar = HBoxContainer.new()
	bar.position = Vector2(12, 44)
	bar.add_theme_constant_override("separation", 3)
	battle._ui_layer.add_child(bar)
	var lbl = Label.new()
	lbl.text = "🛠 "
	lbl.add_theme_font_size_override("font_size", 18)
	bar.add_child(lbl)
	var tprev = _dbg_btn("◀龟")
	tprev.pressed.connect(_dbg_turtle_cycle.bind(-1))
	bar.add_child(tprev)
	var tname = str(battle._data_by_id.get(battle._review_turtle(), {}).get("name", battle._review_turtle()))
	var tlbl = _dbg_btn(tname)
	tlbl.pressed.connect(_dbg_turtle_cycle.bind(1))
	bar.add_child(tlbl)
	var tnext = _dbg_btn("▶")
	tnext.pressed.connect(_dbg_turtle_cycle.bind(1))
	bar.add_child(tnext)
	var cur_sk: int = battle._review_skill_idx()
	for si in range(4):
		var b = _dbg_btn("技%d%s" % [si, ("•" if si == cur_sk else "")])
		b.pressed.connect(_dbg_set_skill.bind(si))
		bar.add_child(b)
	var _eqnm = "关"
	if battle._dbg_equip_idx >= 0:
		var _eids = _dbg_equip_ids()
		if battle._dbg_equip_idx < _eids.size():
			_eqnm = str(DataRegistry.phase2_equipment_by_id.get(_eids[battle._dbg_equip_idx], {}).get("name", _eids[battle._dbg_equip_idx]))
	var eqprev = _dbg_btn("◀装")
	eqprev.pressed.connect(_dbg_equip_cycle.bind(-1))
	bar.add_child(eqprev)
	var eqlbl = _dbg_btn(_eqnm)
	eqlbl.pressed.connect(_dbg_equip_cycle.bind(1))
	bar.add_child(eqlbl)
	var eqnext = _dbg_btn("▶")
	eqnext.pressed.connect(_dbg_equip_cycle.bind(1))
	bar.add_child(eqnext)
	var cur_star: int = battle._dbg_star if battle._dbg_star > 0 else battle.REVIEW_EQUIP_STAR
	for st in [1, 2, 3]:
		var b = _dbg_btn("★%d%s" % [st, ("•" if st == cur_star else "")])
		b.pressed.connect(_dbg_set_star.bind(st))
		bar.add_child(b)

func _dbg_btn(t: String) -> Button:
	var b = Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	return b

func _dbg_set_skill(si: int) -> void:
	battle._dbg_skill = si
	battle.get_tree().reload_current_scene()

func _dbg_turtle_ids() -> Array:
	return battle.STATS.keys()

func _dbg_turtle_cycle(dir: int) -> void:
	var ids = _dbg_turtle_ids()
	var i = ids.find(battle._review_turtle())
	if i < 0: i = 0
	battle._dbg_turtle = str(ids[wrapi(i + dir, 0, ids.size())])
	battle._dbg_skill = -99   # 换龟→重置技能覆盖(不同龟技能不同)
	battle.get_tree().reload_current_scene()

func _dbg_equip_ids() -> Array:
	var ids: Array = DataRegistry.phase2_equipment_by_id.keys()
	ids.sort()
	return ids

func _dbg_equip_cycle(dir: int) -> void:
	var n = _dbg_equip_ids().size()
	battle._dbg_equip_idx = wrapi(battle._dbg_equip_idx + dir + 1, 0, n + 1) - 1   # [-1, n-1] 循环(-1=关)
	battle.get_tree().reload_current_scene()

func _dbg_set_star(st: int) -> void:
	battle._dbg_star = st
	battle.get_tree().reload_current_scene()


# ============================================================================
#  ⏸ 暂停期相机输入中继 (2026-07-22, 测试人员「点暂停键鼠标似乎也无法拖动」)
# ============================================================================
# 主场景 process_mode=INHERIT → 跟 root 的 PAUSABLE → battle.get_tree().paused 时
# can_process()=false, _unhandled_input 一次都不会被调用。整场改 ALWAYS 会让
# _process 里的战斗 tick 在暂停中照跑(等于取消暂停), 所以只让这个空壳节点常驻,
# 暂停期间把事件转给主场景的 _cam_handle_input。
#
# ★只在 paused 时转发: 未暂停时主场景自己收得到, 两边都转会让平移变 2 倍速
#   (与 _touch_seen 那个模拟鼠标 2× 坑同源, 那次是 InventoryScene.gd:639 记过的)。
