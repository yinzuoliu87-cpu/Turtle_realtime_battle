extends Node
## verify_axe_info_panel.gd — 局内点斧头看到的面板(2026-10-22)
##
## 用户 2026-10-22「我还需要看看在局内点击斧头，那里会显示什么」→ 实拍:
##   技能一格都没有、三个空装备格、选了余烬标题还写「钻石斧」、副标题「友军 · C · Lv 1」。
##   → 用户「可以」(照我的提议改):
##   ① 标题 = 显示名(选了造物就是造物名) ② 副标题只写友军 / 敌方
##   ③ 技能三格: 主动 / 窃取护盾 / 当前形态, 文字取小木斧定稿全文里的那几行 ④ 召唤物不画装备格
## ★走真召唤入口(axe_system.summon)造斧头, 走真点击打开每一格的说明卡, 量卡上的字。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _texts(root: Node) -> Array:
	var out: Array = []
	var q: Array = [root]
	while not q.is_empty():
		var n: Node = q.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			if n is Label:
				out.append(str((n as Label).text))
			elif n is RichTextLabel:
				out.append(str((n as RichTextLabel).get_parsed_text()))
		for c in n.get_children():
			q.append(c)
	return out


## 开一只带小木斧的龟, 走真召唤入口召出斧头, 打开斧头的面板。返回 [场景, 斧头]。
func _open(stage: int, total: int, fin: String) -> Array:
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	gs.axe_stage = stage
	gs.axe_exp_total = total
	gs.axe_exp_bar = 0
	gs.axe_final = fin
	var s = RB.new()
	add_child(s)
	await _frames(3)
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var carrier: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-120, 0))
	carrier["equips"] = [{"id": "p2eq_096", "star": 1}]
	s._units.clear()
	s._units.append(carrier)
	var ax = s._equip_sys._axe.summon(carrier)
	s._edit_mode = false
	s._over = false
	s.set_process(false)
	if ax is Dictionary:
		s._hud._show_unit_info_panel(ax)
		s._info_sys._refresh_info_panel()
	await _frames(4)
	return [s, ax]


## 真点技能行第 i 格, 返回弹出那张说明卡上的全部字。
func _card_text(s, i: int) -> String:
	var row = s._info_panel.find_child("AbilityRow", true, false)
	if row == null or i >= row.get_child_count():
		return ""
	var cell: Control = row.get_child(i)
	var slot = cell.get_meta("slot") if cell.has_meta("slot") else cell
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	(slot as Control).gui_input.emit(ev)
	await _frames(3)
	var card = s._info_sys.card().card
	return "\n".join(_texts(card)) if card != null and is_instance_valid(card) else ""


func _close(s) -> void:
	remove_child(s)
	s.queue_free()
	await _frames(2)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 局内点斧头的面板 ===")
	var gs = get_node("/root/GameState")
	var bak := [int(gs.axe_stage), int(gs.axe_exp_total), int(gs.axe_exp_bar), str(gs.axe_final)]

	## ── 铁斧 ──
	var r: Array = await _open(2, 300, "")
	var s = r[0]
	_ok("分母: 铁斧召唤成功、面板打开了", r[1] is Dictionary and s._info_panel != null and is_instance_valid(s._info_panel))
	var t: Array = _texts(s._info_panel)
	_ok("★标题是「铁斧」", t.has("铁斧"), str(t.slice(0, 6)))
	_ok("★副标题只写「友军」, 不再有稀有度 / 等级", t.has("友军") and not "".join(t).contains("Lv"), str(t.slice(0, 6)))
	var row = s._info_panel.find_child("AbilityRow", true, false)
	_ok("★技能行有 3 格(主动 / 窃取护盾 / 当前形态)", row != null and row.get_child_count() == 3,
		"%d 格" % (row.get_child_count() if row != null else -1))
	var c0: String = await _card_text(s, 0)
	_ok("★主动那格: 讲回复与护盾、龟能 %d" % int(AE.ACTIVE_ENERGY), c0.contains("回复") and c0.contains("护盾") and c0.contains("%d" % int(AE.ACTIVE_ENERGY)), c0.substr(0, 60))
	_ok("铁斧时主动那格还没有蓄力猛砸(钻石斧才有)", not c0.contains("蓄力猛砸"))
	var c1: String = await _card_text(s, 1)
	_ok("★窃取护盾那格", c1.contains("窃取"), c1.substr(0, 40))
	var c2: String = await _card_text(s, 2)
	_ok("★当前形态那格: 有石斧、铁斧, 没有金斧(只列已解锁的)", c2.contains("【石斧】") and c2.contains("【铁斧】") and not c2.contains("【金斧】"), c2.substr(0, 60))
	## ★局内按结果写(用户 10-15「对局内就是按结果的写法」, 与别的装备卡同一份换算): 用斧头自己的攻击力算出来
	var ax_i: Dictionary = r[1]
	var sm: int = roundi(float(ax_i.get("atk", 0.0)) * AE.SMASH_ATK)
	_ok("★★局内按结果写: 石斧那句是「额外造成 %d 物理伤害」(斧头攻击力 %.0f), 不是「%d%% 攻击力」" % [sm, float(ax_i.get("atk", 0.0)), roundi(AE.SMASH_ATK * 100)],
		sm > 0 and c2.contains("额外造成 %d 物理伤害" % sm), c2.substr(0, 80))
	_ok("★卡底有拆解行「物理伤害: %d = %d%% …」(与装备卡同一个样子)" % [sm, roundi(AE.SMASH_ATK * 100)],
		c2.contains("物理伤害: %d = %d%%" % [sm, roundi(AE.SMASH_ATK * 100)]), c2.substr(maxi(0, c2.find("物理伤害:")), 30))
	var eqrow = s._info_panel.find_child("EquipRow", true, false)
	_ok("★召唤物不画装备格", eqrow == null or not (eqrow as Control).is_visible_in_tree() or eqrow.get_child_count() == 0)
	await _close(s)

	## ── 余烬 ──
	r = await _open(AE.STAGES.size() - 1, 900, "ember")
	s = r[0]
	t = _texts(s._info_panel)
	_ok("★★选了余烬, 标题是「余烬」(原来写「钻石斧」)", t.has("余烬") and not t.has("钻石斧"), str(t.slice(0, 6)))
	c0 = await _card_text(s, 0)
	_ok("★钻石斧之后主动那格带蓄力猛砸", c0.contains("蓄力猛砸"), c0.substr(0, 60))
	var sl: int = roundi(float((r[1] as Dictionary).get("atk", 0.0)) * AE.SLAM_ATK)
	_ok("★★蓄力猛砸按结果写「造成 %d 物理伤害」" % sl, sl > 0 and c0.contains("造成 %d 物理伤害" % sl), c0.substr(maxi(0, c0.find("砸下")), 40))
	_ok("★★余烬替换了蓄力猛砸 ⇒ 主动那格写着余烬之光", c0.contains("余烬之光"), c0.substr(0, 80))
	c2 = await _card_text(s, 2)
	_ok("★当前形态那格有余烬那一行, 没有别的造物", c2.contains("【余烬】") and not c2.contains("【炽天使】"), c2.substr(0, 60))
	_ok("余烬之光只在主动那格出现一次(形态那格不重复)", not c2.contains("余烬之光"), c2.substr(maxi(0, c2.find("余烬之光") - 10), 40))
	await _close(s)

	## ── 亡灵之斧: 不替换蓄力猛砸 ⇒ 主动那格仍是蓄力猛砸, 亡灵那一行整行在形态那格 ──
	r = await _open(AE.STAGES.size() - 1, 900, "undead")
	s = r[0]
	c0 = await _card_text(s, 0)
	c2 = await _card_text(s, 2)
	_ok("亡灵之斧: 主动那格是蓄力猛砸、没有「替换为」", c0.contains("蓄力猛砸") and not c0.contains("替换为"), c0.substr(0, 60))
	_ok("亡灵之斧: 形态那格有复活那一句", c2.contains("【亡灵之斧】") and c2.contains("复活"), c2.substr(0, 60))
	await _close(s)

	## ── 小木斧(一档都没进化): 没有「当前形态」那格 ──
	r = await _open(0, 10, "")
	s = r[0]
	row = s._info_panel.find_child("AbilityRow", true, false)
	_ok("小木斧时只有主动 / 窃取护盾两格", row != null and row.get_child_count() == 2, "%d 格" % (row.get_child_count() if row != null else -1))
	t = _texts(s._info_panel)
	_ok("小木斧时标题是「小木斧」", t.has("小木斧"), str(t.slice(0, 6)))
	await _close(s)

	gs.axe_stage = int(bak[0]); gs.axe_exp_total = int(bak[1]); gs.axe_exp_bar = int(bak[2]); gs.axe_final = str(bak[3])
	_ok("分母: 断言条数 %d ≥ 21" % _n, _n >= 21)
	print("ALL PASS — 局内斧头面板" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
