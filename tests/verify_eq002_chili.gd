extends Node
## verify_eq002_chili.gd — 辣椒(002): 流血【只跟携带者的普攻走】 (2026-08-31)
##
## ★需求原文(用户 2026-08-31):
##   「海带卷刃改名为辣椒，图标重新生成，效果变为携带者的普攻施加流血而不是每段伤害了」
##
## ★这条门禁的核心是【反面断言】: 技能伤害命中**不许**再叠流血。
##   只验"普攻能叠"是守不住的 —— 改之前普攻本来就能叠, 那条改前改后都绿。
##   真正变了的是"别的段不能叠", 所以判据必须落在那一半。
##
## ★判据落在【目标身上真实的 bleed 层数】, 不是"函数被调过"
##   ([[fb-gate-must-measure-requirement-not-my-hook]])。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _mk(side: String, off: Vector2) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", side, c + off)
	for k in ["shield", "def", "mr", "base_def", "base_mr", "dodge_bonus",
			"damage_reduction", "damage_amp", "crit"]:
		u[k] = 0.0
	u["maxHp"] = 1.0e6
	u["hp"] = 1.0e6
	u["dots"] = []
	_s._units.append(u)
	return u


## 目标身上的 bleed 层数
func _bleed(o: Dictionary) -> int:
	## ★流血层数存在 `dot_stacks` 这个字典里, 不是 `dots` 数组 ——
	##   我第一版读错字段, 结果"普攻能叠"那条报 0 层, 差点当成产品 bug 去查。
	return int((o.get("dot_stacks", {}) as Dictionary).get("bleed", 0))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 辣椒(002): 流血只跟普攻走 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0

	## ── ① 普攻命中 → 施加流血 ──
	_s._units.clear()
	var a: Dictionary = _mk("left", Vector2(-120.0, 0.0))
	var d: Dictionary = _mk("right", Vector2(-40.0, 0.0))
	a["equips"] = [{"id": "p2eq_002", "star": 3}]
	a["eq_state"] = {"p2eq_002": {}}
	_s._equip_sys._stats._eq_apply_all_stats()
	a["atk"] = 100.0
	_ok("★分母: 开打之前目标身上没有流血(不然下面恒真)", _bleed(d) == 0, "%d 层" % _bleed(d))
	_s._equip_sys._eq_on_hit(a, d, 100, true)      # basic = true
	var after_basic: int = _bleed(d)
	_ok("① ★★普攻命中 → 施加流血", after_basic > 0, "%d 层" % after_basic)

	## ── ② 技能伤害命中 → 不施加流血(**本次需求的核心**) ──
	_s._units.clear()
	var a2: Dictionary = _mk("left", Vector2(-120.0, 0.0))
	var d2: Dictionary = _mk("right", Vector2(-40.0, 0.0))
	a2["equips"] = [{"id": "p2eq_002", "star": 3}]
	a2["eq_state"] = {"p2eq_002": {}}
	_s._equip_sys._stats._eq_apply_all_stats()
	a2["atk"] = 100.0
	for _k in range(10):
		_s._equip_sys._eq_on_hit(a2, d2, 100, false)   # basic = false: 技能/DoT/追击段
	_ok("② ★★技能等【非普攻】命中 10 次 → 一层流血都不许有(改之前这里会叠满)",
		_bleed(d2) == 0, "%d 层" % _bleed(d2))

	## ── ③ 逐星层数没被顺手改(用户:「不用补」) ──
	var src := FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	_ok("③ ★分母: 源码读得到", src.length() > 10000, "%d 字" % src.length())
	_ok("③ 系数仍是 [0.075, 0.1, 0.15] —— 用户明确说【不用补】强度",
		src.contains('[0.075, 0.1, 0.15][si] * src["atk"]'))
	## ★★判据只许看【代码行】—— 我在产品文件里写的说明注释里也有 `0.5 if is_aoe else 1.0`
	##   这串字, 直接 contains 会永远红。今天第三次踩这个形状(前两次: `_b4_all()` / `SKIP_MARK`)。
	var code_only := ""
	for ln in src.split("
"):
		if not str(ln).strip_edges().begins_with("#"):
			code_only += str(ln) + "
"
	_ok("③ ★分母: 剔注释后代码仍占大头(剔过头 = 空检查)",
		float(code_only.length()) > float(src.length()) * 0.4,
		"%d / %d 字" % [code_only.length(), src.length()])
	_ok("③ ★★「范围技能减半」那一支已删干净(未决①定的 (a))",
		not code_only.contains("0.5 if is_aoe else 1.0"))

	## ── ④ 改名与换图真的落地 ──
	var eq: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_002", {})
	_ok("④ 名字 = 辣椒", str(eq.get("name", "")) == "辣椒", str(eq.get("name", "")))
	_ok("④ 图标换成专属图(不再借 phase1 的 dungeon-blade)",
		str(eq.get("img", "")) == "equip/chili-pepper.png", str(eq.get("img", "")))
	_ok("④ 图标文件真的在盘上",
		ResourceLoader.exists("res://assets/sprites/%s" % str(eq.get("img", ""))))
	var eq4: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_004", {})
	_ok("④ 暴君之牙换了新图, 且【名字与效果一个字没动】",
		str(eq4.get("img", "")) == "equip/tyrant-fang-new.png"
		and str(eq4.get("name", "")) == "暴君之牙"
		and ResourceLoader.exists("res://assets/sprites/%s" % str(eq4.get("img", ""))),
		"%s / %s" % [str(eq4.get("name", "")), str(eq4.get("img", ""))])

	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 11:
		print("  [FAIL] ★分母: 断言只有 %d 条(<11)" % _n)
		_fail += 1
	print("ALL PASS — 辣椒只跟普攻走" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
