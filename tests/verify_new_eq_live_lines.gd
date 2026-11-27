extends Node
## verify_new_eq_live_lines.gd —— 面具 / 长矛 / 筹码三批里有状态可看的装备, 信息面板「本局」与头顶徽章真的显示出来(2026-11-26 夜)
##
## 由来: 用户 11-26「物理护盾条呢…你这我随便一问，你这个就没做到啊？那你干啥呢？」——
##   纸面具的物理护盾血条上从来不画; 往下查, 新三批 30 件里有状态的(京剧当前哪张脸、骑枪冲势、盾矛存了多少、灰筹码层数…)
##   信息面板一样都不显示: 状态存在各批自己的 _mask_acc / _spear_acc 里, 面板只读 eq_state。
## 判据(每件都把状态推到该显示的样子, 再调面板同一个读法 InfoPanel.eq_live_lines):
##   ① 11 件逐件: 读出来的那一行含该有的字(数字对上)
##   ② 血条 HpBar 认物理护盾(_phys > 0)
##   ③ 头顶徽章: 灰筹码层数 / 黄金面具层数在叠层行, 金色护罩在状态行
## 反向验证(11-26 夜): 去掉面具批 tick_unit 里的 _live_mirror(u) ⇒ ① 面具那 6 件全红。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const IPANEL := preload("res://scripts/scenes/battle/info_panel.gd")
const HB := preload("res://scripts/scenes/hp_bar.gd")

var _n := 0
var _fail := 0
var _s


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, ids: Array, dx: float = 0.0) -> Dictionary:
	var c: Vector2 = _s._arena_center
	var u: Dictionary = _s._spawn._make_unit("green", side, c + Vector2((-150.0 if side == "left" else 150.0) + dx, 0.0))
	u["maxHp"] = 5000.0
	u["hp"] = 5000.0
	u["base_atk"] = 100.0
	u["buffs"] = []
	_s._recalc_stats(u)
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": 1})
	u["equips"] = eq
	return u


func _lines(u: Dictionary, eid: String) -> String:
	return " / ".join(IPANEL.eq_live_lines(u, _s._equip_sys.key_of(u, eid)))


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	_s._t = 3000.0
	print("=== 新三批: 信息面板「本局」/ 头顶徽章 ===")
	var me := _mk("left", ["p2eq_127", "p2eq_129", "p2eq_132", "p2eq_133", "p2eq_134", "p2eq_135"])
	var sp := _mk("left", ["p2eq_140", "p2eq_142", "p2eq_143"], 0.0)
	var ch := _mk("left", ["p2eq_153", "p2eq_154", "p2eq_155", "p2eq_156"], 0.0)
	var foe := _mk("right", [])
	_s._units.clear()
	_s._units.append_array([me, sp, ch, foe])
	for u in [me, sp, ch]:
		_s._equip_sys._stats.apply_unit(u)
	var mb = _s._equip_sys._mask_sys
	var sb = _s._equip_sys._spear_sys
	var cb = _s._equip_sys._chip_sys
	for u in [me, sp, ch]:
		for e in u["equips"]:
			match str(e["id"]):
				"p2eq_127", "p2eq_129", "p2eq_133", "p2eq_134", "p2eq_135", "p2eq_132":
					mb.on_spawn(u, str(e["id"]), 0)
				"p2eq_140":
					sb.on_spawn(u, "p2eq_140", 0)
				"p2eq_154", "p2eq_155":
					cb.on_spawn(u, str(e["id"]), 0)
	## 把状态推到该显示的样子
	me["hp"] = 2500.0                     # 防毒: 掉一半血 ⇒ 移速
	ch["_grey_stk"] = 12
	var gk: String = mb._gold_key(me, _s._equip_sys.key_of(me, "p2eq_135"))
	mb.gold_gain[gk] = 3
	sb._set_acc(sp, "lance:" + _s._equip_sys.key_of(sp, "p2eq_140"), 200.0)
	sb._set_acc(sp, "ftj:" + _s._equip_sys.key_of(sp, "p2eq_143"), 750.0)   # 5000 × 30% = 1500 ⇒ 50%
	for _i in range(3):
		_s._t += 0.05
		for u in [me, sp, ch]:
			mb.tick_unit(u, 0.05)
			sb.tick_unit(u, 0.05)
			cb.tick_unit(u, 0.05)

	## ① 逐件
	var want := {
		"p2eq_127": [me, "物理护盾剩余"],
		"p2eq_129": [me, "当前：红脸"],
		"p2eq_132": [me, "潜行中"],   # 上面把血压到一半 ⇒ 正好触发半血潜行
		"p2eq_133": [me, "移动速度"],
		"p2eq_134": [me, "复活：待命"],
		"p2eq_135": [me, "3 层：获得 60 最大生命值、6 攻击力"],
		"p2eq_140": [sp, "冲势 50%"],
		"p2eq_142": [sp, "秒后举盾"],
		"p2eq_143": [sp, "积攒进度 %d%%" % int(floor(750.0 / (float(sp["maxHp"]) * 0.30) * 100.0))],   # 最大生命含装备加的
		"p2eq_153": [ch, "本战场免疫控制"],
		"p2eq_154": [ch, "复活：待命"],
		"p2eq_155": [ch, "金色护罩：战斗开始 8 秒后触发"],
		"p2eq_156": [ch, "12 层：获得 24 攻击力、24 护甲和魔抗、240 最大生命值"],
	}
	var bad: Array = []
	for eid in want:
		var u: Dictionary = want[eid][0]
		var txt := _lines(u, eid)
		print("    %s: %s" % [eid, txt])
		if not txt.contains(str(want[eid][1])):
			bad.append("%s「%s」" % [eid, txt])
	_ok("① %d 件逐件: 信息面板「本局」读出该有的那一行" % want.size(), bad.is_empty(), str(bad))

	## ② 血条认物理护盾
	var bar = HB.new()
	bar.update_state(me)
	_ok("② 血条读到纸面具的物理护盾(%d)" % int(float(me.get("phys_shield", 0.0))), float(bar.get("_phys")) > 0.0 and float(me.get("phys_shield", 0.0)) > 0.0,
		"血条 %.0f" % float(bar.get("_phys")))
	bar.free()

	## ③ 头顶徽章
	me["_gold_guard_until"] = _s._t + 3.0
	var icons_stack: Array = []
	var icons_status: Array = []
	for u in [me, ch]:
		_s._layout_head_badges(u)
	for pair in [[me, "_hbrow_stack", icons_stack], [ch, "_hbrow_stack", icons_stack], [me, "_hbrow_status", icons_status]]:
		for b in (pair[0] as Dictionary).get(str(pair[1]), []):
			if is_instance_valid(b):
				var ic := (b as Control).get_node_or_null("icon") as TextureRect
				if ic != null and ic.texture != null:
					(pair[2] as Array).append(ic.texture.resource_path.get_file())
	_ok("③ 头顶徽章: 灰筹码层数 + 黄金面具层数在叠层行, 金色护罩在状态行",
		icons_stack.has("p2eq_156.png") and icons_stack.has("p2eq_135.png") and icons_status.has("p2eq_155.png"),
		"叠层 %s · 状态 %s" % [str(icons_stack), str(icons_status)])

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 新三批面板 / 徽章 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
