extends Node
## verify_onhit_order_independent.gd —— 命中效果不许因为「前面那件装备只认普攻」而整批跳过(2026-10-11 全项目通读第三条)
##
## ★读码疑点: `_eq_on_hit` 的 for 循环里, 002 辣椒 / 023 火珊瑚 / 026 雷电法杖遇到非普攻写的是 `return`
##   (其余只认普攻的件写的是 `continue`) ⇒ 技能命中时, 排在它们**后面**的装备(004 处决 / 003 溅射 / 009 充能…)
##   一件都不触发, 触不触发取决于槽位顺序。而且 `return` 还跳过函数末尾的收尾。
## ★判据走产品函数: 同一套装备、同一次技能命中, 只换槽位顺序 ⇒ 004 处决必须两种顺序都触发。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 摆一对单位: 攻击者带 equips(按给定顺序), 目标血量压在 004 斩杀线以下; 调一次产品的 _eq_on_hit。
## 返回目标是否被处决。
func _executed(order: Array, first_id: String, basic: bool) -> bool:
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var a: Dictionary = _s._spawn._make_unit("basic", "left", c)
	var b: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(60, 0))
	a["crit"] = 0.0
	var eqs: Array = []
	for id in order:
		eqs.append({"id": id, "star": 1})
	a["equips"] = eqs
	a["eq_state"] = {}
	b["maxHp"] = 10000.0
	b["hp"] = 100.0          # 1% < 004 一星斩杀线 4%
	_s._units.append(a)
	_s._units.append(b)
	_s._over = false
	_s._equip_sys._eq_on_hit(a, b, 10, basic, false)
	return not bool(b.get("alive", true))


func _ready() -> void:
	await get_tree().process_frame
	print("=== 命中效果与槽位顺序无关 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s._edit_mode = false

	_ok("★分母: 只带 004, 技能命中 ⇒ 处决", _executed(["p2eq_004"], "p2eq_004", false))
	for gate in ["p2eq_002", "p2eq_023", "p2eq_026"]:
		_ok("★★%s 在前、004 在后, 技能命中 ⇒ 004 照样处决" % gate, _executed([gate, "p2eq_004"], gate, false))
		_ok("对照: %s 在后 ⇒ 处决" % gate, _executed(["p2eq_004", gate], gate, false))
		_ok("对照: %s 在前、普攻命中 ⇒ 处决" % gate, _executed([gate, "p2eq_004"], gate, true))

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
