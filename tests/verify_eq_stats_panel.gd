extends Node
## verify_eq_stats_panel.gd — 局内详情面板: 点装备图标 → 描述下方贴「本局统计」(用户 2026-10-04 ①)
##
## 用户原话:「在信息栏内部点击任务后右侧面板点击装备图标展示装备效果时贴在描述的下面，你可以学学lol」
## 数据源 `u["_st_eq"][eid] = {phy, mag, tru, heal, shield}`(EquipTally)。
## 走产品自己的入口: `_show_unit_info_panel` 开面板 → 给装备槽喂一次真左键 → 读【面板左侧小卡】里的节点。
## ★2026-10-06 面板重做: 点装备不再在面板里盖 DetailOverlay, 而是在面板左侧弹独立小卡
##   (`battle._info_sys._card` · inspect_card.gd)。统计块 = 小卡里「本局」段那个 Label(live["extra"])。
##   ① 分母: 面板里真的有 2 个可点的装备槽, 点开后小卡在场且 key 是这件装备
##   ② 有统计的那件: 统计块在小卡里、排在描述【下面】(同一个 VBox 里下标更大), 可见,
##      每一行数字 == 独立从 _st_eq 算的
##   ③ 只列非零: 护盾为 0 ⇒ 不出现「护盾」; 两种伤害非零 ⇒ 括号拆开
##   ④ 实时: 改 _st_eq 后走一次 `_refresh_info_panel`(产品每帧那条路) ⇒ 文字跟着变
##   ⑤ 全零那件: ★2026-10-06 改为写一句「还没有产生效果」(小卡里「本局」段标题常在, 空着像坏了),
##      仍然【不印「0」】—— 一个数字都不许出现
## 反向验证见报告: 拿掉 `_refresh_eq_stats()` 调用 ⇒ ④ 红; 统计块不建 ⇒ ②③ 红。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EA := "p2eq_004"
const EB := "p2eq_021"

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", t, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", t, "  ", d)


func _click(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	c.gui_input.emit(ev)


func _eq_slots(root: Node) -> Array:
	var out: Array = []
	var q: Array = [root]
	while not q.is_empty():
		var n: Node = q.pop_front()
		if n is PanelContainer and not (n as Control).gui_input.get_connections().is_empty():
			out.append(n)
		q.append_array(n.get_children())
	return out


## 左侧小卡(InspectCard)。没开 / 已释放 ⇒ null。
func _card(s):
	var c = s._info_sys._card
	if c == null or c.card == null or not is_instance_valid(c.card) or c.key == "":
		return null
	return c


func _card_key(s) -> String:
	var c = _card(s)
	return "-" if c == null else str(c.key)


## 统计块在小卡里排在描述【下面】: 两者同在小卡的内容 VBox 里, 统计块的下标更大。
## ★不要求"紧挨着" —— 新版式里描述与本局之间夹着灰斜体脚注和一道细线(照云顶装备卡),
##   用户要的是「贴在描述的下面」, 守的是上下关系, 不是中间不许有东西。
func _below_desc(s) -> bool:
	var c = _card(s)
	if c == null or not c.live.has("body") or not c.live.has("extra"):
		return false
	var b: Node = c.live["body"]
	var e: Node = c.live["extra"]
	if not is_instance_valid(b) or not is_instance_valid(e) or b.get_parent() != e.get_parent():
		return false
	return e.get_index() > b.get_index()


func _stats_lbl(s) -> Label:
	var c = _card(s)
	if c == null or not c.live.has("extra"):
		return null
	var l = c.live["extra"]
	if l is Label and is_instance_valid(l) and not (l as Node).is_queued_for_deletion():
		return l
	return null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 装备本局统计: 描述下方 ===")
	var s = RTScene.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("basic", "left", c)
	u["equips"] = [{"id": EA, "star": 2}, {"id": EB, "star": 1}]
	u["_st_eq"] = {
		EA: {"phy": 1233.6, "mag": 0.0, "tru": 30.2, "heal": 566.5, "shield": 0.0},
		EB: {"phy": 0.0, "mag": 0.0, "tru": 0.0, "heal": 0.0, "shield": 0.0},
	}
	s._units.clear()
	s._units.append(u)
	s._edit_mode = false
	s._over = false
	s.set_process(false)
	s._hud._show_unit_info_panel(u)
	s._info_sys._refresh_info_panel()
	for _i in range(4):
		await get_tree().process_frame

	var slots: Array = _eq_slots(s._info_equip_box)
	_ok("① 分母: 装备区有 2 个可点的槽", slots.size() == 2, "n=%d" % slots.size())
	if slots.size() != 2:
		_end(s); return

	## ── A: 有统计 ──
	_click(slots[0])
	for _i in range(2):
		await get_tree().process_frame
	_ok("① 分母: 点了之后左侧小卡在场、key = eq:" + EA,
		_card(s) != null and (_card(s).card as Control).is_visible_in_tree() and _card_key(s) == "eq:" + EA,
		"key=%s" % _card_key(s))
	var sl: Label = _stats_lbl(s)
	_ok("② 统计块在小卡里、排在描述下面且可见",
		sl != null and _below_desc(s) and sl.is_visible_in_tree(),
		"stats=%s below=%s" % [str(sl), str(_below_desc(s))])
	var st: Dictionary = u["_st_eq"][EA]
	var want_dmg: int = int(round(float(st["phy"]))) + int(round(float(st["mag"]))) + int(round(float(st["tru"])))
	var want_heal: int = int(round(float(st["heal"])))
	var tx: String = "" if sl == null else sl.text
	_ok("② 造成伤害 == _st_eq 三类之和(%d)" % want_dmg, tx.contains("造成伤害 %d" % want_dmg), tx.replace("\n", " ⏎ "))
	_ok("③ 两种伤害非零 ⇒ 括号拆开 物理/真实", tx.contains("物理 %d" % int(round(float(st["phy"])))) and tx.contains("真实 30") and not tx.contains("魔法"), tx.replace("\n", " ⏎ "))
	_ok("② 治疗 == _st_eq.heal(%d)" % want_heal, tx.contains("治疗 %d" % want_heal), tx.replace("\n", " ⏎ "))
	_ok("③ 护盾为 0 ⇒ 不出现「护盾」", not tx.contains("护盾"), tx.replace("\n", " ⏎ "))

	## ── ④ 实时 ──
	st["shield"] = 400.0
	st["heal"] = 666.4
	s._info_sys._refresh_info_panel()
	tx = "" if sl == null or not is_instance_valid(sl) else sl.text
	_ok("④ 实时: 改 _st_eq 后刷新一次, 治疗 666 / 护盾 400 跟着变", tx.contains("治疗 666") and tx.contains("护盾 400"), tx.replace("\n", " ⏎ "))

	## ── ⑤ B: 全零 ──
	_click(slots[1])
	for _i in range(2):
		await get_tree().process_frame
	_ok("⑤ 分母: 小卡换成了 eq:" + EB, _card(s) != null and _card_key(s) == "eq:" + EB, "key=%s" % _card_key(s))
	var sl2: Label = _stats_lbl(s)
	## ★全零: 写一句「还没有产生效果」, 而且【一个数字都没有】(不印「0」那条老要求不变)。
	var _t2: String = "" if sl2 == null else sl2.text
	var _digit := false
	for _ch in _t2:
		if _ch >= "0" and _ch <= "9":
			_digit = true
	_ok("⑤ 全零那件: 统计块写「还没有产生效果」, 不印任何数字",
		sl2 != null and sl2.is_visible_in_tree() and _t2 == "暂无效果" and not _digit,
		"" if sl2 == null else "visible=%s text=%s" % [str(sl2.is_visible_in_tree()), _t2])
	## ⑤b 全零 → 后来有了数 ⇒ 统计块换成真数字(刷新路径能把那句占位换掉)
	(u["_st_eq"][EB] as Dictionary)["mag"] = 88.0
	s._info_sys._refresh_info_panel()
	_ok("⑤b 全零那件之后有了魔法伤害 ⇒ 统计块出现「造成伤害 88」", sl2 != null and is_instance_valid(sl2) and sl2.is_visible_in_tree() and sl2.text == "造成伤害 88",
		"" if sl2 == null else sl2.text)
	## ⑥ 再点同一个槽 = 收起(小卡是独立节点, 不收就一直压在战场上)
	_click(slots[1])
	for _i in range(2):
		await get_tree().process_frame
	_ok("⑥ 再点同一件 ⇒ 小卡收起", _card(s) == null, "key=%s" % _card_key(s))
	_end(s)


func _end(s) -> void:
	s.queue_free()
	print("")
	if _fail == 0 and _n >= 12:
		print("ALL PASS (%d 条)" % _n)
		get_tree().quit(0)
	else:
		print("FAILED %d / %d" % [_fail, _n])
		get_tree().quit(1)
