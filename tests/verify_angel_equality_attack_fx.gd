extends Node
## verify_angel_equality_attack_fx.gd —— 天使龟【平等】: 90 龟能 + 每一段都算一次攻击(2026-11-19)
##
## 用户 11-19:「天使龟的平等技能…它现在是六十龟能对吧？需要削弱，削弱到九十龟能」
##   「它不是四段打击嘛，然后…还可能会触发额外一段打击对吧？每段打击都应该是能够触发攻击特效的。比如说能够触发三环，
##    或者有个二费叫钻孔螺，它应该能够触发这个魔法伤害的攻击特效的。同样，天使龟本身它的被动也是一个攻击特效，就是你把它归为一类」
## 实现: AngelSystem._equality_hit(出手 = _eq_on_basic_attack; 落地 = _hit_as_basic; 再结算 judge_hit)
##       + AngelSystem.judge_hit(审判被动只在这一处, 普攻命中与平等每一段共用)。
##   ① 龟能: SkillEnergy 与 pets.json 都是 90
##   ② 真入口 `_sk_angel_equality`, C 级目标(4 道圣光): 065 鲨肝油 +4 层(攻击时)、061 钻孔螺破损 +4 层(命中时按普攻)、
##      063 白鲸气环 4 下 = 满 3 引爆一次 + 剩 1 层
##   ③ A 级目标(4 道 + 审判光柱): 鲨肝油 +5、破损 +5
##   ④ 分母: 同一个目标挨一段不算攻击的技能伤害 ⇒ 破损不涨(钻孔螺「技能不触发」闸门真的在) ; 落地后「算作普攻」标记已清
##   ⑤ 审判被动每一段都结算一次(无装备的天使、按段逐步推算目标血量); 普攻命中仍正好一次
##   ⑥ 飞升的打包被动(每次普攻命中 +龟能 +攻击力)不跟着平等的每一段走(这次没改它)
##   ⑦ 源码: 主场景不再自己写审判系数(走 judge_hit); 审判伤害式子全仓只有一处; _equality_hit 不点剑士
## 结算从演出里抽出来直接调(CLAUDE.md §4.5)。
## 反向验证(11-19): 去掉出手钩子 ⇒ ②③ 鲨肝油红; 落地不带 _hit_as_basic ⇒ ②③ 破损 / 气环红;
##   光柱不走 _equality_hit ⇒ ③ 红; _equality_hit 里不调 judge_hit ⇒ ⑤ 红; 龟能写回 60 ⇒ ① 红。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ID_OIL := "p2eq_065"
const ID_DRILL := "p2eq_061"
const ID_RING := "p2eq_063"

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(id: String, px: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit(id, side, Vector2(px, 400.0))
	u["hp"] = 100000.0
	u["maxHp"] = 100000.0
	u["atk"] = 100.0
	u["base_atk"] = 100.0
	u["alive"] = true
	u["crit"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["shield"] = 0.0
	u["dodge"] = 0.0
	u["no_move"] = true
	u["atk_interval"] = 9999.0
	u["atk_cd"] = 9999.0
	return u


func _angel(equips: Array) -> Dictionary:
	var a: Dictionary = _mk("angel", 500.0, "left")
	a["equips"] = equips
	a["eq_state"] = {}
	return a


func _oil(u: Dictionary) -> int:
	return int((u["eq_state"].get(ID_OIL, {}) as Dictionary).get("oil_stacks", 0))


func _reset(units: Array) -> void:
	_s._units.clear()
	_s._pending_shots.clear()
	for x in units:
		_s._units.append(x)


func _run_pending() -> void:
	for _k in range(60):
		_s._ballistics._step_pending_shots(0.05)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 天使龟·平等: 90 龟能 + 每一段都算一次攻击 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false
	var asys = _s._angel_sys

	# ① 龟能
	var pets = JSON.parse_string(FileAccess.get_file_as_string("res://data/pets.json"))
	var pet_cost := -1.0
	for p in (pets if pets is Array else (pets as Dictionary).get("pets", [])):
		if str((p as Dictionary).get("id", "")) == "angel":
			for sk in p.get("skillPool", []):
				if str(sk.get("type", "")) == "angelEquality":
					pet_cost = float(sk.get("energyCost", -1))
	_ok("① ★平等龟能 = 90(SkillEnergy %.0f / pets.json %.0f)" % [_s.SkillEnergy.cost_of("angelEquality"), pet_cost],
		is_equal_approx(_s.SkillEnergy.cost_of("angelEquality"), 90.0) and is_equal_approx(pet_cost, 90.0))

	var eqs := [{"id": ID_OIL, "star": 1}, {"id": ID_DRILL, "star": 1}, {"id": ID_RING, "star": 1}]
	var trig: int = int(EqSpiritBatch.RING_TRIGGER)

	# ② C 级目标: 4 道圣光
	var a2 := _angel(eqs.duplicate(true))
	var t2: Dictionary = _mk("basic", 700.0, "right")
	t2["rarity"] = "C"
	_reset([a2, t2])
	asys._sk_angel_equality(a2, t2)
	var q2: int = _s._pending_shots.size()
	_run_pending()
	_ok("② 分母: C 级目标排进 %d 段(4 道圣光, 没有光柱)" % q2, q2 == AngelSystem.EQUAL_SEGMENTS)
	_ok("② ★4 道圣光各算一次攻击 ⇒ 鲨肝油正好 +4 层(攻击时的装备效果)", _oil(a2) == 4, str(_oil(a2)))
	_ok("② ★4 道圣光命中按普攻判 ⇒ 钻孔螺破损 +4 层(命中时的装备效果)", int(t2.get("breach_stacks", 0)) == 4, str(t2.get("breach_stacks", 0)))
	_ok("② ★白鲸气环: 4 下 = 满 %d 层引爆一次 + 剩 %d 层" % [trig, 4 - trig], int(t2.get("whale_rings", -1)) == 4 - trig, str(t2.get("whale_rings", -1)))
	_ok("② 落地之后「算作普攻」的标记已清掉(不串到下一次伤害)", not bool(a2.get("_hit_as_basic", false)))

	# ③ A 级目标: 4 道 + 审判光柱
	var a3 := _angel(eqs.duplicate(true))
	var t3: Dictionary = _mk("basic", 700.0, "right")
	t3["rarity"] = "A"
	_reset([a3, t3])
	asys._sk_angel_equality(a3, t3)
	var q3: int = _s._pending_shots.size()
	_run_pending()
	_ok("③ 分母: A 级目标排进 %d 段(4 道 + 光柱)" % q3, q3 == AngelSystem.EQUAL_SEGMENTS + 1)
	_ok("③ ★审判光柱也算一次攻击 ⇒ 鲨肝油 +5、破损 +5", _oil(a3) == 5 and int(t3.get("breach_stacks", 0)) == 5,
		"油 %d / 破损 %d" % [_oil(a3), int(t3.get("breach_stacks", 0))])

	# ④ 分母: 不算攻击的技能伤害不触发钻孔螺
	var b0: int = int(t3.get("breach_stacks", 0))
	_s._damage._apply_damage_from(a3, t3, 10, Color.WHITE)
	_ok("④ 分母: 同一目标挨一段不算攻击的技能伤害 ⇒ 破损不涨(闸门真的在)", int(t3.get("breach_stacks", 0)) == b0, "%d → %d" % [b0, int(t3.get("breach_stacks", 0))])

	# ⑤ 审判被动: 每一段一次; 普攻命中一次
	var a5 := _angel([])
	var t5: Dictionary = _mk("basic", 700.0, "right")
	t5["rarity"] = "C"
	_reset([a5, t5])
	var hp: float = float(t5["hp"])
	var exp_no_judge: float = hp
	for _k in range(AngelSystem.EQUAL_SEGMENTS):
		var d: int = _s._atk_dmg(a5, AngelSystem.EQUAL_SEG_COEF, t5, false)
		hp -= float(d)
		exp_no_judge -= float(d)
		hp -= float(_s._mitigate(a5, hp * AngelSystem.JUDGE_CURHP, t5, true))
	asys._sk_angel_equality(a5, t5)
	_run_pending()
	_ok("⑤ ★审判每一段都结算一次: 目标剩血 %.0f ≈ 推算 %.0f(不带审判会剩 %.0f)" % [float(t5["hp"]), hp, exp_no_judge],
		absf(float(t5["hp"]) - hp) <= 4.0 and absf(float(t5["hp"]) - exp_no_judge) > 1000.0)
	var h0: float = float(t5["hp"])
	var j: int = _s._mitigate(a5, h0 * AngelSystem.JUDGE_CURHP, t5, true)
	_s._on_basic_hit(a5, t5)
	_ok("⑤ 普攻命中: 审判正好结算一次(掉 %.0f = %d)" % [h0 - float(t5["hp"]), j], absf((h0 - float(t5["hp"])) - float(j)) <= 1.0)

	# ⑥ 飞升打包被动不跟平等每段走
	var a6 := _angel([])
	a6["_ascend_growth"] = true
	var t6: Dictionary = _mk("basic", 700.0, "right")
	t6["rarity"] = "A"
	_reset([a6, t6])
	var ba0: float = float(a6["base_atk"])
	asys._sk_angel_equality(a6, t6)
	_run_pending()
	_ok("⑥ 飞升的「每次普攻命中 +攻击力」不由平等的各段触发(这次没改)", is_equal_approx(float(a6["base_atk"]), ba0), "%.2f → %.2f" % [ba0, float(a6["base_atk"])])

	# ⑦ 源码
	var main_src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var ang_src := FileAccess.get_file_as_string("res://scripts/systems/skills/angel_system.gd").replace("\r\n", "\n")
	_ok("⑦ 主场景不再自己写审判系数(普攻命中走 _angel_sys.judge_hit)", main_src.find("AngelSystem.JUDGE_CURHP") < 0 and main_src.find("_angel_sys.judge_hit(u, tgt)") > 0)
	_ok("⑦ 审判伤害式子全文件只有一处(judge_hit)", ang_src.count("* JUDGE_CURHP") == 1, str(ang_src.count("* JUDGE_CURHP")))
	var i0 := ang_src.find("func _equality_hit(")
	var i1 := ang_src.find("\nfunc ", i0 + 5)
	var body := ang_src.substr(i0, i1 - i0) if i0 >= 0 and i1 > i0 else ""
	_ok("⑦ 分母: 找到 _equality_hit", body.length() > 100)
	_ok("⑦ _equality_hit 不点剑士(同赌神赌注的牌)", body.find("swordsman") < 0)
	_ok("⑦ 圣光与光柱都走 _equality_hit(两处)", ang_src.count("_equality_hit(u, tgt, func()") == 2)

	_s._units.clear()   # 不用 erase: 单位字典按内容比较会递归(CLAUDE.md §4.2)
	print("=== 共 %d 条, 失败 %d ===" % [_n, _fail])
	if _fail == 0 and _n >= 15:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)
